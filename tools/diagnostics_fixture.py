"""Synthetic chassis/FRU/SEL data for the existing suite-17 loopback BMC."""
import struct
import time

import shared_bmc


def area(prefix, fields):
    data = bytearray(prefix)
    for field in fields:
        raw = field.encode("ascii")
        assert len(raw) != 1  # 0xc1 is the end marker, not a one-character field.
        data.extend(bytes([0xc0 | len(raw)]) + raw)
    data.append(0xc1)
    data.extend(bytes((-len(data) - 1) % 8))
    data.append(0)
    data[1] = len(data) // 8
    data[-1] = -sum(data) % 256
    return bytes(data)


CHASSIS_FIELDS = ["CH-42", "CH-SYNTH"]
BOARD_FIELDS = ["Example", "Board", "BD-SYNTH", "BD-42", ""]
PRODUCT_FIELDS = ["Example", "Server", "SRV-42", "v2", "SYNTH-0001", "LAB", ""]
CHASSIS_AREA = area([1, 0, 23], CHASSIS_FIELDS)
BOARD_AREA = area([1, 0, 0, 0, 0, 0], BOARD_FIELDS)
PRODUCT_AREA = area([1, 0, 0], PRODUCT_FIELDS)
HEADER = bytearray([1, 0, 1, (8 + len(CHASSIS_AREA)) // 8,
                    (8 + len(CHASSIS_AREA) + len(BOARD_AREA)) // 8, 0, 0, 0])
HEADER[-1] = -sum(HEADER) % 256
FRU = bytes(HEADER) + CHASSIS_AREA + BOARD_AREA + PRODUCT_AREA
SEL_RECORDS = [
    struct.pack("<HBIHBBBBBBB", 1, 2, 1700000000, 0x20, 4, 1, 0x30, 1, 9, 0, 0),
    struct.pack("<HBIHBBBBBBB", 3, 2, 0xffffffff, 0x20, 4, 5, 0x3a, 0xef, 0, 0, 0),
    struct.pack("<HBI", 5, 0xc0, 0) + bytes.fromhex("570100010203040506"),
]
CAPABILITIES = bytes.fromhex("0f2020202000")
CHASSIS_VARIANTS = {
    "chassis-basic": bytes.fromhex("01000000"),
    "chassis-faults": bytes.fromhex("5e1f0f"),
    "chassis-buttons": bytes.fromhex("3f1005a5"),
    "chassis-reserved-policy": bytes.fromhex("600000"),
}


class Diagnostics:
    def __init__(self, fault=None, word=False):
        self.fault = fault
        self.word = word
        self.info_reads = 0
        self.fru = FRU
        if fault == "fru-checksum":
            self.fru = FRU[:-1] + bytes([FRU[-1] ^ 1])

    def command(self, netfn, command, data):
        if (netfn, command) == (6, 1):
            device = bytearray(shared_bmc.DEVICE)
            device[5] |= 0x0c
            return bytes(device), 0
        if (netfn, command) == (0, 0):
            assert not data
            return CAPABILITIES, 0
        if (netfn, command) == (0, 1) and self.fault in CHASSIS_VARIANTS:
            assert not data
            return CHASSIS_VARIANTS[self.fault], 0
        if (netfn, command) == (0, 7):
            assert not data
            if self.fault and self.fault.startswith("restart-"):
                return bytes([int(self.fault.split("-")[1]), 1]), 0
            return b"\x04\x01", 0
        if (netfn, command) == (0x0a, 0x10):
            assert data == b"\x00"
            size = 2048 if self.fault == "fru-limit" else len(self.fru)
            return struct.pack("<HB", size, self.word), 0
        if (netfn, command) == (0x0a, 0x11):
            assert len(data) == 4 and data[0] == 0
            offset = int.from_bytes(data[1:3], "little") * (2 if self.word else 1)
            count = data[3]  # Requested count is bytes, returned count is access units.
            assert count and offset < len(self.fru)
            if self.fault == "fru-timeout":
                time.sleep(0.12)
            if self.fault == "fru-short":
                count = min(count, 4)
            chunk = self.fru[offset:offset + count]
            returned = len(chunk) // (2 if self.word else 1)
            if self.fault == "fru-zero":
                return b"\x00", 0
            if self.fault == "fru-count":
                returned += 1
            return bytes([returned]) + chunk, 0
        if (netfn, command) == (0x0a, 0x40):
            assert not data
            self.info_reads += 1
            count = 0 if self.fault == "sel-empty" else 9 if self.fault == "sel-limit" else len(SEL_RECORDS)
            added = 1700000000 + (self.fault == "sel-changed" and self.info_reads > 1)
            version = 0x02 if self.fault == "sel-version-2" else 0x51
            return struct.pack("<BHHIIB", version, count, 0xffff, added, 0xffffffff, 2), 0
        if (netfn, command) == (0x0a, 0x42):
            assert not data
            return b"\x34\x12", 0
        if (netfn, command) == (0x0a, 0x43):
            reservation, record_id, offset, count = struct.unpack("<HHBB", data)
            assert reservation in (0, 0x1234) and offset == 0 and count == 0xff
            if self.fault == "sel-timeout":
                time.sleep(0.12)
            if self.fault == "sel-completion":
                return b"", 0xcb
            ids = [1, 3, 5]
            record_id = ids[0] if record_id == 0 else record_id
            index = ids.index(record_id)
            next_id = ids[index + 1] if index + 1 < len(ids) else 0xffff
            record = SEL_RECORDS[index]
            if self.fault == "sel-cycle":
                next_id = record_id
            if self.fault == "sel-early":
                next_id = 0xffff
            if self.fault == "sel-id" and index == 1:
                record = b"\x66\x00" + record[2:]
            if self.fault == "sel-short":
                record = record[:-1]
            return struct.pack("<H", next_id) + record, 0
        return None
