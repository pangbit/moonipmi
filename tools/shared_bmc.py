"""One loopback-only suite-17 fixture for all comparison clients.
Synthetic data, fixed User ceiling, bounded exchanges; no hardware-control API.
"""
import socket

import interop as wire

DEVICE = bytes.fromhex("1203012302015701003412")
CHASSIS = bytes.fromhex("01000000")
SENSOR = bytes.fromhex("2ac001")


class Stopped(Exception):
    pass


def response(request, data=b"", completion=0):
    # Echo the actual requester address. Do not special-case any client.
    first = bytes([request[3], request[1] | 4])
    second = bytes([request[0], request[4], request[5], completion]) + data
    return first + bytes([-sum(first) % 256]) + second + bytes([-sum(second) % 256])


def serve(server, stop, trace):
    peer = None
    count = 0

    def receive():
        nonlocal peer, count
        while not stop.is_set():
            try:
                packet, sender = server.recvfrom(2048)
            except socket.timeout:
                continue
            if peer is None:
                peer = sender
            assert sender == peer, "unexpected fixture peer"
            count += 1
            assert count <= 24, "bounded fixture exchange exceeded"
            return packet
        raise Stopped

    def send(packet):
        server.sendto(packet, peer)

    first = receive()
    if first[:5] == bytes.fromhex("0600ff0700"):
        # Session-zero Get Channel Authentication Capabilities only; no v1.5 session.
        assert len(first) == 14 + first[13] and wire.read32(first, 9) == 0
        req = first[14:]
        assert len(req) == 9 and req[0:2] == b"\x20\x18" and req[5:8] == b"\x38\x8e\x02"
        assert sum(req[:3]) % 256 == 0 and sum(req[3:]) % 256 == 0
        trace["capability_discovery"] = True
        reply = response(req, bytes.fromhex("0180040200000000"))
        send(bytes.fromhex("0600ff07") + bytes(9) + bytes([len(reply)]) + reply)
        first = receive()
    opened = wire.unpack(first, 0x10)
    tag, console = opened[0], wire.read32(opened, 4)
    assert len(opened) == 32 and opened[1] in (0, 2) and opened[2:4] == bytes(2) and console
    assert opened[8:] == wire.ALGORITHMS, "only suite 17 is supported"
    trace["open_privilege"] = opened[1]
    send(wire.envelope(0x11, bytes([tag, 0, 2, 0]) + wire.u32(console)
                       + wire.u32(wire.BMC_ID) + wire.ALGORITHMS))
    rakp1 = wire.unpack(receive(), 0x12)
    assert rakp1[1:8] == bytes(3) + wire.u32(wire.BMC_ID)
    assert rakp1[24] in (2, 0x12)  # Same User privilege; name-only lookup is optional.
    assert rakp1[25:] == bytes([0, 0, len(wire.USER)]) + wire.USER
    trace["rakp_role"] = rakp1[24]
    rc = rakp1[8:24]
    role_name = bytes([rakp1[24], len(wire.USER)]) + wire.USER
    rakp2 = wire.mac(wire.KEY, wire.u32(console) + wire.u32(wire.BMC_ID)
                     + rc + wire.RAND + wire.GUID + role_name)
    send(wire.envelope(0x13, bytes([rakp1[0], 0, 0, 0]) + wire.u32(console)
                       + wire.RAND + wire.GUID + rakp2))
    trace["rakp2_sent"] = True
    rakp3 = wire.unpack(receive(), 0x14)
    assert rakp3[2:8] == bytes(2) + wire.u32(wire.BMC_ID)
    if rakp3[1] != 0:
        trace["client_rakp_rejection"] = rakp3[1]
        return
    expected = wire.mac(wire.KEY, wire.RAND + wire.u32(console) + role_name)
    assert wire.hmac.compare_digest(rakp3[8:], expected), "client RAKP3 authentication mismatch"
    sik = wire.mac(wire.KEY, rc + wire.RAND + role_name)
    k1, k2 = wire.mac(sik, b"\x01" * 20), wire.mac(sik, b"\x02" * 20)[:16]
    rakp4 = wire.mac(sik, rc + wire.u32(wire.BMC_ID) + wire.GUID)[:16]
    send(wire.envelope(0x15, bytes([rakp3[0], 0, 0, 0]) + wire.u32(console) + rakp4))
    trace["authenticated"] = True
    previous = 0
    for index in range(16):
        previous, req = wire.unprotect(receive(), previous, k1, k2)
        assert len(req) >= 7 and req[0] == 0x20 and req[3] in (0x81, 0x20)
        assert req[1] & 3 == 0 and req[4] & 3 == 0
        netfn, cmd, data = req[1] >> 2, req[5], req[6:-1]
        reply, completion = b"", 0
        if (netfn, cmd) == (6, 0x3b):
            assert data == b"\x02"
            reply = b"\x02"
        elif (netfn, cmd) == (6, 1):
            assert not data
            reply = DEVICE
        elif (netfn, cmd) == (0, 1):
            assert not data
            reply = CHASSIS
        elif (netfn, cmd) == (4, 0x2d):
            assert len(data) == 1
            if data == b"\x2a":
                reply = SENSOR
            else:
                completion = 0xcb  # Requested sensor is not present.
        elif (netfn, cmd) == (6, 0x3c):
            assert data == wire.u32(wire.BMC_ID)
        elif (netfn, cmd) in ((0x2c, 0), (0x2c, 0x3e)):
            completion = 0xc1  # Unsupported read-only PICMG/VITA discovery.
        else:
            raise AssertionError(f"unexpected command in read-only fixture: {netfn:02x}/{cmd:02x}")
        trace["commands"].append({"netfn": netfn, "command": cmd, "request_data": data.hex(),
                                  "completion": completion, "response_data": reply.hex(),
                                  "requester_address": req[3]})
        send(wire.protect(response(req, reply, completion), console, index + 1, k1, k2))
        if (netfn, cmd) == (6, 0x3c):
            trace["closed"] = True
            return
    raise AssertionError("no close within the bounded fixture exchange")
