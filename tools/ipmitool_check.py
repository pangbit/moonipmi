#!/usr/bin/env python3
"""Cross-check the Python fixture with ipmitool, on loopback with synthetic data.
This verifies the fixture independently; it does not connect moonipmi to a BMC.
"""
import shutil
import socket
import subprocess

import interop as fixture


def serve(server):
    first, peer = server.recvfrom(2048)
    # ipmitool first discovers v2 support using a session-zero capability query.
    # This fixture does not implement or allow authenticated IPMI 1.5 sessions.
    assert first[:14] == bytes.fromhex("0600ff0700000000000000000009")
    request = first[14:]
    assert request[0:2] == b"\x20\x18" and request[3] == 0x81
    assert request[5:8] == bytes.fromhex("388e02")
    assert sum(request[:3]) % 256 == 0 and sum(request[3:]) % 256 == 0
    capabilities = bytes.fromhex("0180040200000000")  # non-anonymous, v2 only
    response = fixture.reply(6, 0x38, request[4] >> 2, capabilities)
    server.sendto(bytes.fromhex("0600ff07") + bytes(9) + bytes([len(response)]) + response, peer)

    def receive():
        packet, sender = server.recvfrom(2048)
        assert sender == peer
        return packet

    opened = fixture.unpack(receive(), 0x10)
    tag, console = opened[0], fixture.read32(opened, 4)
    assert len(opened) == 32 and opened[1:4] == bytes([2, 0, 0]) and console
    assert opened[8:] == fixture.ALGORITHMS
    server.sendto(fixture.envelope(0x11, bytes([tag, 0, 2, 0]) + fixture.u32(console)
                                  + fixture.u32(fixture.BMC_ID) + fixture.ALGORITHMS), peer)
    rakp1 = fixture.unpack(receive(), 0x12)
    assert rakp1[1:8] == bytes(3) + fixture.u32(fixture.BMC_ID)
    assert rakp1[24] in (2, 0x12)  # User privilege, with/without name-only lookup
    assert rakp1[25:] == bytes([0, 0, len(fixture.USER)]) + fixture.USER
    rc = rakp1[8:24]
    role_name = bytes([rakp1[24], len(fixture.USER)]) + fixture.USER
    rakp2 = fixture.mac(fixture.KEY, fixture.u32(console) + fixture.u32(fixture.BMC_ID)
                        + rc + fixture.RAND + fixture.GUID + role_name)
    server.sendto(fixture.envelope(0x13, bytes([rakp1[0], 0, 0, 0]) + fixture.u32(console)
                                  + fixture.RAND + fixture.GUID + rakp2), peer)
    rakp3 = fixture.unpack(receive(), 0x14)
    assert rakp3[1:8] == bytes(3) + fixture.u32(fixture.BMC_ID)
    assert fixture.hmac.compare_digest(rakp3[8:], fixture.mac(
        fixture.KEY, fixture.RAND + fixture.u32(console) + role_name))
    sik = fixture.mac(fixture.KEY, rc + fixture.RAND + role_name)
    k1, k2 = fixture.mac(sik, b"\x01" * 20), fixture.mac(sik, b"\x02" * 20)[:16]
    rakp4 = fixture.mac(sik, rc + fixture.u32(fixture.BMC_ID) + fixture.GUID)[:16]
    server.sendto(fixture.envelope(0x15, bytes([rakp3[0], 0, 0, 0]) + fixture.u32(console) + rakp4), peer)

    previous = 0
    reads = 0
    for index in range(12):  # Bound automatic discovery plus one requested read.
        previous, request = fixture.unprotect(receive(), previous, k1, k2)
        assert request[0] == 0x20 and request[3] == 0x81
        netfn, command, sequence = request[1] >> 2, request[5], request[4] >> 2
        assert request[1] & 3 == 0 and request[4] & 3 == 0
        data, completion = b"", 0
        if (netfn, command) == (6, 0x3b):
            assert request[6:-1] == b"\x02"
            data = b"\x02"
        elif (netfn, command) == (6, 1):
            assert not request[6:-1]
            data = bytes.fromhex("1203012302015701003412")
            reads += 1
        elif (netfn, command) == (6, 0x3c):
            assert request[6:-1] == fixture.u32(fixture.BMC_ID) and reads
        elif (netfn, command) in ((0x2c, 0), (0x2c, 0x3e)):
            completion = 0xc1  # Unsupported automatic PICMG/VITA discovery.
        else:
            raise AssertionError("unexpected ipmitool command in read-only fixture")
        response = bytearray(fixture.reply(netfn, command, sequence, data))
        response[6] = completion
        response[-1] = -sum(response[3:-1]) % 256
        server.sendto(fixture.protect(response, console, index + 1, k1, k2), peer)
        if (netfn, command) == (6, 0x3c):
            return
    raise AssertionError("ipmitool did not close within the bounded exchange")


def main():
    executable = shutil.which("ipmitool")
    if not executable:
        raise SystemExit("ipmitool is required for this optional fixture cross-check")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(5)
        # Public synthetic credentials, never operator-supplied secrets.
        args = [executable, "-I", "lanplus", "-C", "17", "-L", "USER", "-U", "tester",
                "-P", "synthetic-password", "-H", "127.0.0.1", "-p", str(server.getsockname()[1]),
                "-N", "1", "-R", "0", "mc", "info"]
        client = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            serve(server)
            out, err = client.communicate(timeout=5)
            if client.returncode:
                raise RuntimeError(out + err)
            fields = dict(line.split(":", 1) for line in out.splitlines() if ":" in line)
            fields = {key.strip(): value.strip() for key, value in fields.items()}
            assert fields.get("Manufacturer ID") == "343"
            assert fields.get("Product ID") == "4660 (0x1234)"
            assert fields.get("IPMI Version") == "2.0"
            print("PASS: ipmitool verified the Python fixture (suite 17, Device ID, graceful close)")
        finally:
            if client.poll() is None:
                client.terminate()
                try:
                    client.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    client.kill()
                    client.communicate(timeout=5)


if __name__ == "__main__":
    main()
