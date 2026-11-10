#!/usr/bin/env python3
"""Independent loopback-only suite-17 BMC emulator for the example client.
Standard-library framing/HMAC; system OpenSSL for raw AES. Synthetic data only.
This is not go-ipmi or evidence of a real hardware BMC test.
"""
import hashlib
import hmac
import shutil
import socket
import struct
import subprocess
import sys

USER = b"tester"
KEY = b"synthetic-password".ljust(20, b"\0")
BMC_ID = 0x55667788
RAND = bytes(range(16, 32))
GUID = bytes(range(32, 48))
ALGORITHMS = bytes.fromhex("000000080300000001000008040000000200000801000000")
u32 = lambda n: struct.pack("<I", n)
read32 = lambda data, pos=0: struct.unpack_from("<I", data, pos)[0]
mac = lambda key, data: hmac.new(key, data, hashlib.sha256).digest()
OPENSSL = shutil.which("openssl")


def aes(data, key, iv, decrypt=False):
    args = [OPENSSL, "enc", "-aes-128-cbc", "-nopad", "-K", key.hex(), "-iv", iv.hex()]
    if decrypt:
        args.append("-d")
    return subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def envelope(kind, payload):
    return bytes.fromhex("0600ff0706") + bytes([kind]) + bytes(8) + struct.pack("<H", len(payload)) + payload


def unpack(data, kind):
    assert data[:14] == bytes.fromhex("0600ff0706") + bytes([kind]) + bytes(8)
    assert len(data) == 16 + int.from_bytes(data[14:16], "little")
    return data[16:]


def protect(payload, session, sequence, k1, k2):
    pad = (-(len(payload) + 1)) % 16
    iv = bytes([sequence]) * 16  # Deliberately deterministic emulator fixture.
    cipher = aes(payload + bytes(range(1, pad + 1)) + bytes([pad]), k2, iv)
    packet = bytes.fromhex("0600ff0706c0") + u32(session) + u32(sequence) + struct.pack("<H", 16 + len(cipher)) + iv + cipher
    pad = (-(len(packet) - 4 + 2)) % 4
    packet += b"\xff" * pad + bytes([pad, 7])
    return packet + mac(k1, packet[4:])[:16]


def unprotect(packet, previous, k1, k2):
    assert packet[:6] == bytes.fromhex("0600ff0706c0")
    assert read32(packet, 6) == BMC_ID
    sequence = read32(packet, 10)
    assert sequence > previous
    assert hmac.compare_digest(packet[-16:], mac(k1, packet[4:-16])[:16])
    length = int.from_bytes(packet[14:16], "little")
    end = 16 + length
    pad = packet[-18]
    assert pad <= 3 and end + pad + 18 == len(packet) and packet[-17] == 7
    assert packet[end:end + pad] == b"\xff" * pad
    plain = aes(packet[32:end], k2, packet[16:32], decrypt=True)
    pad = plain[-1]
    assert pad <= 15 and plain[-1-pad:-1] == bytes(range(1, pad + 1))
    plain = plain[:-pad-1]
    assert sum(plain[:3]) % 256 == 0 and sum(plain[3:]) % 256 == 0
    return sequence, plain


def reply(netfn, command, sequence, payload):
    first = bytes([0x81, (netfn + 1) << 2])
    first += bytes([-sum(first) % 256])
    second = bytes([0x20, sequence << 2, command, 0]) + payload
    return first + second + bytes([-sum(second) % 256])


def serve(server):
    first, peer = server.recvfrom(2048)
    opened = unpack(first, 0x10)
    tag, console = opened[0], read32(opened, 4)
    assert len(opened) == 32 and opened[1:4] == bytes([2, 0, 0]) and console
    assert opened[8:] == ALGORITHMS
    server.sendto(envelope(0x11, bytes([tag, 0, 2, 0]) + u32(console) + u32(BMC_ID) + ALGORITHMS), peer)

    def receive():
        packet, sender = server.recvfrom(2048)
        assert sender == peer
        return packet

    rakp1 = unpack(receive(), 0x12)
    assert rakp1[:8] == bytes([tag, 0, 0, 0]) + u32(BMC_ID)
    assert rakp1[24:] == bytes([2, 0, 0, len(USER)]) + USER
    rc = rakp1[8:24]
    role_name = bytes([2, len(USER)]) + USER
    rakp2 = mac(KEY, u32(console) + u32(BMC_ID) + rc + RAND + GUID + role_name)
    server.sendto(envelope(0x13, bytes([tag, 0, 0, 0]) + u32(console) + RAND + GUID + rakp2), peer)
    rakp3 = unpack(receive(), 0x14)
    assert rakp3 == bytes([tag, 0, 0, 0]) + u32(BMC_ID) + mac(KEY, RAND + u32(console) + role_name)
    sik = mac(KEY, rc + RAND + role_name)
    k1, k2 = mac(sik, b"\x01" * 20), mac(sik, b"\x02" * 20)[:16]
    rakp4 = mac(sik, rc + u32(BMC_ID) + GUID)[:16]
    server.sendto(envelope(0x15, bytes([tag, 0, 0, 0]) + u32(console) + rakp4), peer)
    commands = [
        (6, 0x3b, b"\x02", b"\x02"),
        (6, 1, b"", bytes.fromhex("1203012302015701003412")),
        (0, 1, b"", bytes.fromhex("010000")),
        (4, 0x2d, b"\x2a", bytes.fromhex("2ac001")),
        (6, 0x3c, u32(BMC_ID), b""),
    ]
    previous = 0
    for index, (netfn, command, request_data, response_data) in enumerate(commands):
        previous, request = unprotect(receive(), previous, k1, k2)
        assert request[0] == 0x20 and request[1] == netfn << 2 and request[3] == 0x81
        assert request[4] == index << 2 and request[5] == command and request[6:-1] == request_data
        response = reply(netfn, command, index, response_data)
        server.sendto(protect(response, console, index + 1, k1, k2), peer)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tools/interop.py <built loopback example>")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(5)
        client = subprocess.Popen([sys.argv[1], str(server.getsockname()[1])], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            serve(server)
            out, err = client.communicate(timeout=5)
            if client.returncode:
                raise RuntimeError(err)
            print(out.strip())
            print("PASS: independent Python emulator verified RAKP, packet integrity and all five commands")
        finally:
            if client.poll() is None:
                client.terminate()
                client.communicate(timeout=5)


if __name__ == "__main__":
    main()
