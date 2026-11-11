"""Synthetic SDR records for the shared authenticated loopback BMC.

The data models temperature, voltage, fan, power and intrusion sensors, not a
specific vendor or real machine. No client-dependent responses or hardware I/O.
"""
import struct

import shared_bmc


def full(record_id, number, name, unit=1, sensor_type=1, m=1, b=0, exp=0, fmt=0):
    body = bytearray(43)
    body[0:5] = bytes([0x20, 0, number, 7, 1])
    body[5:9] = bytes([0x67, 0x68, sensor_type, 1])
    body[9:15] = bytes.fromhex("ff7fff7f3f00")
    body[15:18] = bytes([fmt << 6, unit, 0])
    body[19:25] = bytes([m & 255, (m >> 2) & 0xc0, b & 255, (b >> 2) & 0xc0, 0, exp])
    body[29:31] = bytes([255, 0])
    body[42] = 0xc0 | len(name)
    body.extend(name.encode("ascii"))
    return struct.pack("<HBBB", record_id, 0x51, 1, len(body)) + body


def compact(record_id, number):
    name = b"Intrusion"
    body = bytearray(27)
    body[0:5] = bytes([0x20, 0, number, 7, 1])
    body[5:9] = bytes([0x63, 0x40, 5, 0x6f])
    body[9:15] = bytes.fromhex("7f007f007f00")
    body[15] = 0xc0
    body[26] = 0xc0 | len(name)
    body.extend(name)
    return struct.pack("<HBBB", record_id, 0x51, 2, len(body)) + body


RECORDS = [
    full(1, 0x30, "Temp"),
    full(3, 0x31, "Voltage", unit=4, sensor_type=2, exp=0xf0),
    full(5, 0x32, "Fan", unit=18, sensor_type=4, m=60),
    full(7, 0x33, "Power", unit=6, sensor_type=0x0b, m=2, b=-10),
    full(9, 0x34, "Signed", fmt=2),
    full(11, 0x35, "Ones", fmt=1),
    full(13, 0x36, "Unavailable"),
    full(15, 0x37, "Disabled"),
    full(17, 0x38, "EventsOff"),
    full(19, 0x39, "Critical"),
    compact(21, 0x3a),
]
READINGS = {
    0x30: bytes([42, 0xc0, 0, 0]), 0x31: bytes([120, 0xc0, 0, 0]),
    0x32: bytes([100, 0xc0, 0, 0]), 0x33: bytes([80, 0xc0, 0, 0]),
    0x34: bytes([246, 0xc0, 0, 0]), 0x35: bytes([245, 0xc0, 0, 0]),
    0x36: bytes([238, 0xe0, 0, 0]), 0x37: bytes([238, 0x80, 0, 0]),
    0x38: bytes([42, 0x40, 0, 0]), 0x39: bytes([80, 0xc0, 0x10, 0]),
    0x3a: bytes([0, 0xc0, 1, 0]),
}


class Repository:
    def __init__(self, fault=None):
        self.fault = fault
        self.records = {int.from_bytes(record[:2], "little"): record for record in RECORDS}
        self.ids = list(self.records)
        self.partial_reads = 0

    def command(self, netfn, command, data):
        if (netfn, command) == (6, 1):
            device = bytearray(shared_bmc.DEVICE)
            device[5] |= 2  # Advertise the SDR repository, not Device SDRs.
            return bytes(device), 0
        if (netfn, command) == (0x0a, 0x20):
            assert not data
            count = 0 if self.fault == "empty" else 65 if self.fault == "limit" else len(self.ids)
            flags = 0 if self.fault == "no-reservation" else 2
            return struct.pack("<BHHIIB", 0x51, count, 0xffff, 0, 0, flags), 0
        if (netfn, command) == (0x0a, 0x22):
            assert not data
            return b"\x34\x12", 0
        if (netfn, command) == (0x0a, 0x23):
            assert len(data) == 6
            reservation, record_id, offset, count = struct.unpack("<HHBB", data)
            assert reservation == 0x1234
            if self.fault == "lost-reservation" and offset:
                return b"", 0xc5
            record_id = self.ids[0] if record_id == 0 else record_id
            assert record_id in self.records
            record = self.records[record_id]
            position = self.ids.index(record_id)
            next_id = self.ids[position + 1] if position + 1 < len(self.ids) else 0xffff
            if self.fault == "cycle":
                next_id = record_id
            if self.fault == "early-end":
                next_id = 0xffff
            if self.fault == "changed-next" and offset:
                next_id = 0xffff
            assert 0 < count <= 0xff and offset < len(record)
            if count == 0xff:
                count = len(record) - offset
            chunk = record[offset:offset + count]
            if offset:
                self.partial_reads += 1
            if self.fault == "short-chunk":
                chunk = chunk[:-1]
            if self.fault == "wrong-id" and record_id != self.ids[0] and offset == 0:
                chunk = b"\x66\x00" + chunk[2:]
            return struct.pack("<H", next_id) + chunk, 0
        if (netfn, command) == (4, 0x2d):
            assert len(data) == 1 and data[0] in READINGS
            return READINGS[data[0]], 0
        if (netfn, command) == (4, 0x27):
            assert len(data) == 1 and data[0] in READINGS
            # No dynamic thresholds advertised. Comparisons do not claim threshold
            # settings support; threshold *status* comes from Get Sensor Reading.
            return bytes(7), 0
        return None
