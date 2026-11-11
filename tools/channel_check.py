#!/usr/bin/env python3
"""Compare channel information/access and cipher-list reads on loopback only."""
import argparse
import json
import time

from diagnostics_check import execute
import reference_profile

MEDIUM = ["reserved", "IPMB (I2C)", "ICMB v1.0", "ICMB v0.9", "802.3 LAN", "Serial/Modem",
          "Other LAN", "PCI SMBus", "SMBus v1.0/v1.1", "SMBus v2.0", "USB 1.x", "USB 2.x", "System Interface"]
PROTOCOL = {0: "reserved", 1: "IPMB-1.0", 2: "ICMB-1.0", 3: "reserved", 4: "IPMI-SMBus", 5: "KCS",
            6: "SMIC", 7: "BT-10", 8: "BT-15", 9: "TMode", 28: "OEM 1", 29: "OEM 2", 30: "OEM 3", 31: "OEM 4"}
AUTH = ["none", "hmac_sha1", "hmac_md5", "hmac_sha256"]
INTEGRITY = ["none", "hmac_sha1_96", "hmac_md5_128", "md5_128", "sha256_128"]
CRYPT = ["none", "aes_cbc_128", "xrc4_128", "xrc4_40"]
HEADER = "ID   IANA    Auth Alg        Integrity Alg   Confidentiality Alg\n"


def standard(number=17, auth=3, integrity=4, crypt=1):
    return bytes([0xc0, number, auth, 0x40 | integrity, 0x80 | crypt])


def oem(number=128, iana=0x123456):
    return bytes([0xc1, number]) + iana.to_bytes(3, "little") + bytes([3, 0x44, 0x81])


class Channel:
    def __init__(self, kind="info", *, channel=14, info=bytes.fromhex("f184e5bf563412aa55"),
                 active=b"\x02\xf4", persistent=b"\x39\xf2", data=b"", payload="ipmi", fault=None, completion=0xd4):
        self.kind, self.channel, self.info = kind, channel, info
        self.active, self.persistent = active, persistent
        self.data, self.payload, self.fault, self.completion = data, payload, fault, completion
        self.requests = []

    def command(self, netfn, command, request):
        if netfn != 6 or command not in (0x41, 0x42, 0x54):
            return None
        self.requests.append((command, request.hex()))
        if command == 0x42:
            assert self.kind == "info" and request == bytes([self.channel]) and len(self.requests) == 1
            return (b"", self.completion) if self.fault == "info-error" else (self.info, 0)
        if command == 0x41:
            expected_channel = self.info[0] & 15 if self.kind == "info" else self.channel
            assert request[0] == expected_channel and len(request) == 2 and request[1] in (0x40, 0x80)
            if self.kind == "info":
                assert request[1] == (0x80 if len(self.requests) == 2 else 0x40)
            if self.fault == ("active-error" if request[1] == 0x80 else "persistent-error"):
                return b"", self.completion
            return self.active if request[1] == 0x80 else self.persistent, 0
        assert self.kind == "ciphers"
        index = len(self.requests) - 1
        assert index < 64 and request == bytes([self.channel, 0 if self.payload == "ipmi" else 1, 0x80 | index])
        if self.fault == "first-error" or self.fault == "second-error" and index == 1:
            return b"", self.completion
        if self.fault == "slow":
            time.sleep(0.12)
        header = 0xf1 if self.fault != "channel-change" or index == 0 else 0xf2
        response = bytes([header]) + self.data[index * 16:(index + 1) * 16]
        if self.fault == "empty-page":
            response = b""
        elif self.fault == "oversized-page":
            response = bytes(18)
        return response, 0


def label(table, number):
    return table[number] if number < len(table) else f"Unknown (0x{number:02X})"


def access_value(raw):
    return {"raw": list(raw), "mode": raw[0] & 7, "alerting": not bool(raw[0] & 32),
            "per_message_auth": not bool(raw[0] & 16), "user_level_auth": not bool(raw[0] & 8),
            "privilege_limit": raw[1] & 15}


def info_value(model):
    d = model.info
    return {"raw": list(d), "channel": d[0] & 15, "medium": d[1] & 127, "protocol": d[2] & 31,
            "session_support": d[3] >> 6, "active_sessions": d[3] & 63,
            "vendor_id": int.from_bytes(d[4:7], "little"), "auxiliary": list(d[7:]),
            "settings": [access_value(model.active), access_value(model.persistent)] if d[1] & 127 in (4, 6) else []}


def info_projection(v):
    text = (f"Channel 0x{v['channel']:x} info:\n"
            f"  Channel Medium Type   : {label(MEDIUM, v['medium'])}\n"
            f"  Channel Protocol Type : {PROTOCOL.get(v['protocol'], 'Unknown (0x%02X)' % v['protocol'])}\n"
            f"  Session Support       : {['session-less', 'single-session', 'multi-session', 'session-based'][v['session_support']]}\n"
            f"  Active Session Count  : {v['active_sessions']}\n  Protocol Vendor ID    : {v['vendor_id']}\n")
    for title, access in zip(("Volatile(active) Settings", "Non-Volatile Settings"), v["settings"]):
        text += "  " + title + "\n"
        for name, field in [("Alerting", "alerting"), ("Per-message Auth", "per_message_auth"), ("User Level Auth", "user_level_auth")]:
            text += f"    {name:<20}: {'enabled' if access[field] else 'disabled'}\n"
        text += "    Access Mode         : " + ["disabled", "pre-boot only", "always available", "shared", *["unknown"] * 4][access["mode"]] + "\n"
    return text


def suites_value(data):
    records, offset = [], 0
    while offset < len(data):
        size = 5 if data[offset] == 0xc0 else 8
        raw = data[offset:offset + size]
        assert len(raw) == size and raw[0] in (0xc0, 0xc1)
        records.append({"id": raw[1], "iana": int.from_bytes(raw[2:5], "little") if size == 8 else None,
                        "authentication": raw[-3] & 63, "integrity": raw[-2] & 63,
                        "confidentiality": raw[-1] & 63, "raw": list(raw)})
        offset += size
    return records


def cipher_projection(records, csv=False, unknown_alias=None):
    text = "" if csv else HEADER
    for record in records:
        iana = f"{record['iana']:06x}" if record["iana"] else "N/A"
        names = [label(table, record[field]) for table, field in
                 [(AUTH, "authentication"), (INTEGRITY, "integrity"), (CRYPT, "confidentiality")]]
        if unknown_alias is not None:
            names = [f"Unknown (0x{unknown_alias:02X})" if name.startswith("Unknown") else name for name in names]
        text += f"{record['id']},{iana},{','.join(names)}\n" if csv else f"{record['id']:<4} {iana:<7} {names[0]:<15} {names[1]:<15} {names[2]:<15}\n"
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    executions, leaves = [], []

    def run(model, moon, *, setting="volatile", csv=False, limit=1024, timeout=10000):
        if model.kind == "info":
            command = f"channel-info:{model.channel}" if moon else f"channel info {model.channel}"
        elif model.kind == "access":
            command = f"channel-access:{model.channel}:{setting}" if moon else f"raw 6 0x41 {model.channel} {128 if setting == 'volatile' else 64}"
        else:
            command = f"ciphers:{model.channel}:{model.payload}:{limit}:{timeout}" if moon else f"{'-c ' if csv else ''}channel getciphers {model.payload} {model.channel}"
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, command, moon=moon, model=model)
        allowed = {(6, c) for c in (0x3b, 0x3c, 0x41, 0x42, 0x54)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"])
        reads = [r for r in trace["commands"] if r["netfn"] == 6 and r["command"] in (0x41, 0x42, 0x54)]
        assert [(r["command"], r["request_data"]) for r in reads] == model.requests
        execution_id = len(executions)
        executions.append({"id": execution_id, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode,
                           "trace": trace, "elapsed_seconds": elapsed})
        if result.returncode == 0:
            assert trace["closed"]
        return result, execution_id

    def record(name, status, ids, **details):
        leaves.append({"id": "C20." + name, "status": status, "executions": ids, **details})
        print(status + ": C20." + name, flush=True)

    protocols = [*PROTOCOL, 10, 27]
    for index, protocol in enumerate(protocols):
        medium = index if index <= 12 else 127
        info = bytes([0xf1, medium | 128, protocol | 224, (index % 4) * 64 + (63 if index % 2 else 0), 0xff, 0xff, 0xff, 0xa5, 0x5a])
        kwargs = {"info": info, "channel": [0, 1, 11, 14, 15][index % 5]}
        moon, mid = run(Channel(**kwargs), True)
        assert moon.returncode == 0 and not moon.stderr
        value = json.loads(moon.stdout)
        assert value == info_value(Channel(**kwargs))
        ref, rid = run(Channel(**kwargs), False)
        assert ref.returncode == 0 and not ref.stderr and ref.stdout == info_projection(value), (ref.stdout, info_projection(value))
        assert executions[mid]["trace"]["commands"][1]["request_data"] == f"{kwargs['channel']:02x}"
        record(f"info.fields-{index}", "PASS_PROJECTION", [mid, rid], typed_value=value)

    for mode in range(8):
        kwargs = {"active": bytes([mode | (mode << 3) | 0xc0, 0xf0 | mode]),
                  "persistent": bytes([(7 - mode) | ((7 - mode) << 3), 15 - mode])}
        moon, mid = run(Channel(**kwargs), True)
        assert moon.returncode == 0 and not moon.stderr
        value = json.loads(moon.stdout)
        assert value == info_value(Channel(**kwargs))
        ref, rid = run(Channel(**kwargs), False)
        assert ref.returncode == 0 and not ref.stderr and ref.stdout == info_projection(value)
        record(f"info.access-mode-{mode}", "PASS_PROJECTION", [mid, rid], typed_value=value)
    for setting in ("volatile", "persistent"):
        moon, mid = run(Channel("access"), True, setting=setting)
        ref, rid = run(Channel("access"), False, setting=setting)
        assert moon.returncode == ref.returncode == 0 and not moon.stderr and not ref.stderr
        value = json.loads(moon.stdout)
        assert value == access_value(bytes.fromhex(ref.stdout))
        record("access.raw-" + setting, "PASS_RAW_PROJECTION", [mid, rid], typed_value=value)

    cases = [("empty", b""), ("suite-17", standard()), ("two-oem-exact-page", oem() + oem(129, 0)),
             ("split-records", standard() + oem() + standard(3)), ("twelve", b"".join(standard(i) for i in range(12))),
             ("thirteen", b"".join(standard(i) for i in range(13))),
             ("all-standard-ids", b"".join(standard(i) for i in range(18))),
             ("max-standard", b"".join(standard(i) for i in range(204))), ("max-pages", oem() * 128),
             ("unknown-auth", standard(auth=63)), ("unknown-integrity", standard(integrity=62)),
             ("unknown-crypt", standard(crypt=61)), ("unknown-three", standard(auth=63, integrity=62, crypt=61)),
             ("algorithm-flags", bytes.fromhex("c011c3c4c1"))]
    for name, data in cases:
        for payload in ("ipmi", "sol"):
            moon, mid = run(Channel("ciphers", data=data, payload=payload), True)
            assert moon.returncode == 0 and not moon.stderr
            value = json.loads(moon.stdout)
            records = suites_value(data)
            assert value["raw"] == list(data) and value["suites"] == records
            assert value["terminated"] == (len(data) < 1024)
            assert len(value["pages"]) == min(64, len(data) // 16 + 1)
            for index, page in enumerate(value["pages"]):
                assert page == {"channel": 1, "raw_channel": 0xf1, "data": list(data[index * 16:(index + 1) * 16])}
            for csv in (False, True):
                ref, rid = run(Channel("ciphers", data=data, payload=payload), False, csv=csv)
                assert ref.returncode == 0 and not ref.stderr
                for execution_id in (mid, rid):
                    pages = [r for r in executions[execution_id]["trace"]["commands"] if r["netfn"] == 6 and r["command"] == 0x54]
                    assert len(pages) == min(64, len(data) // 16 + 1)
                    assert b"".join(bytes.fromhex(page["response_data"])[1:] for page in pages) == data
                expected = cipher_projection(records[:12], csv)
                status = "DIVERGENT_REFERENCE_RECORD_LIMIT" if len(records) > 12 else "PASS_PROJECTION"
                if name == "unknown-three":
                    assert ref.stdout in [cipher_projection(records, csv, alias) for alias in (61, 62, 63)]
                    status = "DIVERGENT_UNKNOWN_ALGORITHM_DISPLAY"
                else:
                    assert ref.stdout == expected, (name, ref.stdout, expected)
                record(f"getciphers.{payload}.{name}.{'csv' if csv else 'text'}", status, [mid, rid],
                       typed_value=value, projected_stdout=cipher_projection(records, csv), reference_stdout=ref.stdout)

    # Reference ignores the page channel header. Preserve it without silently discarding it.
    data = standard() * 4
    moon, mid = run(Channel("ciphers", data=data, fault="channel-change"), True)
    ref, rid = run(Channel("ciphers", data=data, fault="channel-change"), False)
    value = json.loads(moon.stdout)
    assert moon.returncode == ref.returncode == 0 and not moon.stderr and not ref.stderr
    assert [p["channel"] for p in value["pages"]] == [1, 2] and value["raw"] == list(data)
    assert ref.stdout == cipher_projection(value["suites"])
    record("getciphers.reported-channel-change", "PASS_PROJECTION", [mid, rid], typed_value=value,
           scope="reported metadata retained; reference does not validate it; authenticated packet checks unchanged")

    for name, data in [("bad-tag", standard() + b"\xc2"), ("short-standard", standard() + b"\xc0\x01"),
                       ("short-oem", standard() + oem()[:-1])]:
        moon, mid = run(Channel("ciphers", data=data), True)
        ref, rid = run(Channel("ciphers", data=data), False)
        assert moon.returncode > 0 and not moon.stdout.startswith("{")
        assert ("unknown cipher" if name == "bad-tag" else "incomplete cipher") in moon.stdout + moon.stderr
        assert ref.returncode == 0 and ref.stdout == cipher_projection(suites_value(standard()))
        record("getciphers." + name, "DIVERGENT_PARTIAL_PARSE", [mid, rid])

    for name, kwargs in [("info-short", {"info": bytes(8)}), ("info-extra", {"info": bytes(10)}),
                         ("access-short", {"active": b"\x02"}), ("access-extra", {"persistent": bytes(3)}),
                         ("info-completion", {"fault": "info-error"}), ("access-completion", {"fault": "persistent-error"})]:
        moon, mid = run(Channel(**kwargs), True)
        ref, rid = run(Channel(**kwargs), False)
        assert moon.returncode > 0 and ref.returncode > 0 and not moon.stdout.startswith("{")
        expected = "completion code 212" if name.endswith("completion") else "must contain 9" if name.startswith("info") else "must contain 2"
        assert expected in moon.stdout + moon.stderr
        partial = name.startswith("access")
        assert bool(ref.stdout) == partial
        record("info." + name, "DIVERGENT_PARTIAL_OUTPUT" if partial else "PASS_REJECTION_PROJECTION", [mid, rid])
    for fault in ("empty-page", "oversized-page", "first-error", "second-error"):
        for completion in ((0xc1, 0xd4) if fault.endswith("error") else (0,)):
            moon, mid = run(Channel("ciphers", data=standard() * 5, fault=fault, completion=completion), True)
            ref, rid = run(Channel("ciphers", data=standard() * 5, fault=fault, completion=completion), False)
            assert moon.returncode > 0 and ref.returncode > 0 and not moon.stdout.startswith("{") and not ref.stdout
            if completion:
                assert f"completion code {completion}" in moon.stdout + moon.stderr
            record(f"getciphers.{fault}-{completion:02x}", "PASS_REJECTION_PROJECTION", [mid, rid])

    for name, kwargs, options, reads in [
        ("byte-limit", {}, {"limit": 15}, 1), ("negative-limit", {}, {"limit": -1}, 0),
        ("oversized-limit", {}, {"limit": 1025}, 0), ("zero-timeout", {}, {"timeout": 0}, 0),
        ("oversized-timeout", {}, {"timeout": 60001}, 0), ("whole-deadline", {"fault": "slow"}, {"timeout": 200}, 2),
        *[(f"channel-{ch}", {"channel": ch}, {}, 0) for ch in (-1, 12, 13, 16)],
    ]:
        model = Channel("ciphers", data=standard() * 10, **kwargs)
        moon, mid = run(model, True, **options)
        assert moon.returncode > 0 and not moon.stdout.startswith("{") and len(model.requests) == reads
        if name == "whole-deadline":
            assert executions[mid]["elapsed_seconds"] < 2
            expected = "operation did not complete"
        elif name.startswith("channel-"):
            expected = "channel must be"
        elif "timeout" in name:
            expected = "overall timeout"
        elif name == "byte-limit":
            expected = "exceeds byte limit"
        else:
            expected = "cipher byte limit"
        assert expected in moon.stdout + moon.stderr
        record("getciphers." + name, "PASS_MOON_BOUNDARY_ONLY", [mid])

    assert len({row["id"] for row in leaves}) == len(leaves)
    summary = {s: sum(row["status"] == s for row in leaves) for s in sorted({row["status"] for row in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "read-only channel APIs, synthetic suite17/User; no auth selection, activation or policy changes; output projections are not full CLI parity",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; differences retained; no real device contacted")


if __name__ == "__main__":
    main()
