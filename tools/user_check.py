#!/usr/bin/env python3
"""Byte-accurate read-only user/access comparison against a fixed loopback reference."""
import argparse
import json
import time

from diagnostics_check import execute
import reference_profile

PRIVILEGES = {1: b"CALLBACK", 2: b"USER", 3: b"OPERATOR", 4: b"ADMINISTRATOR", 5: b"OEM", 15: b"NO ACCESS"}
ENABLE = [b"unknown", b"enabled", b"disabled", b"reserved"]
LIST_HEADER = b"ID  Name\t     Callin  Link Auth\tIPMI Msg   Channel Priv Limit\n"


class Users:
    def __init__(self, *, count=3, channel=14, accesses=None, names=None, fault=None, delay=0):
        self.count, self.channel = count, channel
        self.accesses, self.names = accesses or {}, names or {}
        self.fault, self.delay, self.requests = fault, delay, []

    def access(self, uid):
        return self.accesses.get(uid, bytes([self.count | 0xc0, min(self.count, 2) | ((uid % 4) << 6),
                                           min(self.count, 1) | 0xc0, 0x80 | ((uid * 16) & 0x70) | (uid % 16)]))

    def name(self, uid):
        return self.names.get(uid, f"fixture-{uid:02d}".encode().ljust(16, b"\0"))

    def command(self, netfn, command, request):
        if netfn != 6 or command not in (0x44, 0x46):
            return None
        if command == 0x44:
            assert len(request) == 2 and request[0] == self.channel
            uid = request[1]
        else:
            assert len(request) == 1
            uid = request[0]
        assert 1 <= uid <= 63
        self.requests.append((command, uid))
        if self.delay:
            time.sleep(self.delay)
        if self.fault and (command, uid) == self.fault[:2]:
            return b"", self.fault[2]
        value = self.access(uid) if command == 0x44 else self.name(uid)
        return (b"", 0xcc) if value is None else (value, 0)


def access_value(raw):
    return {"maximum": raw[0] & 63, "enabled": raw[1] & 63, "fixed": raw[2] & 63,
            "enable_status": raw[1] >> 6, "call_in_allowed": not bool(raw[3] & 64),
            "link_authentication": bool(raw[3] & 32), "ipmi_messaging": bool(raw[3] & 16),
            "privilege_limit": raw[3] & 15, "raw": list(raw)}


def name_value(raw):
    if raw is None:
        return None
    data = raw.split(b"\0", 1)[0]
    return {"raw": list(raw), "data": list(data), "ascii_text": data.decode("ascii") if all(c < 128 for c in data) else None}


def record_value(model, uid):
    return {"id": uid, "access": access_value(model.access(uid)), "name": name_value(model.name(uid))}


def expected_records(model, mode):
    records, initial = [], model.access(1)[0] & 63
    uid = 1
    while uid <= 63:
        record = record_value(model, uid)
        records.append(record)
        maximum = record["access"]["maximum"] if mode == "follow" else initial
        uid += 1
        if uid > maximum:
            return records
    return records


def privilege(value):
    return PRIVILEGES.get(value, f"Unknown (0x{value:02X})".encode())


def name_bytes(record):
    return bytes(record["name"]["data"]) if record["name"] is not None else b""


def summary_projection(value, csv=False):
    if csv:
        return f"{value['maximum']},{value['enabled']},{value['fixed']}\n".encode()
    return (f"Maximum IDs\t    : {value['maximum']}\nEnabled User Count  : {value['enabled']}\n"
            f"Fixed Name Count    : {value['fixed']}\n").encode()


def list_projection(records, csv=False):
    output = b"" if csv or not records else LIST_HEADER
    for record in records:
        access, uid, name = record["access"], record["id"], name_bytes(record)
        flags = [access["call_in_allowed"], access["link_authentication"], access["ipmi_messaging"]]
        if csv:
            output += str(uid).encode() + b"," + name + b"," + b",".join(b"true" if f else b"false" for f in flags) + b"," + privilege(access["privilege_limit"]) + b"\n"
        else:
            output += str(uid).encode().ljust(4) + name.ljust(17)
            output += b"".join((b"true " if flag else b"false").ljust(width) for flag, width in zip(flags, [8, 11, 11]))
            output += privilege(access["privilege_limit"]) + b"\n"
    return output


def detail_projection(records):
    if not records:
        return b""
    first = records[0]["access"]
    output = f"Maximum User IDs     : {first['maximum']}\nEnabled User IDs     : {first['enabled']}\n".encode()
    for record in records:
        access, uid = record["access"], record["id"]
        output += f"\nUser ID              : {uid}\nUser Name            : ".encode() + name_bytes(record) + b"\n"
        output += b"Fixed Name           : " + (b"Yes" if uid <= access["fixed"] else b"No") + b"\n"
        output += b"Access Available     : " + (b"call-in / callback" if access["call_in_allowed"] else b"callback") + b"\n"
        output += b"Link Authentication  : " + (b"enabled" if access["link_authentication"] else b"disabled") + b"\n"
        output += b"IPMI Messaging       : " + (b"enabled" if access["ipmi_messaging"] else b"disabled") + b"\n"
        output += b"Privilege Level      : " + privilege(access["privilege_limit"]) + b"\n"
        output += b"Enable Status        : " + ENABLE[access["enable_status"]] + b"\n"
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    leaves, executions = [], []

    def run(model, moon, *, operation="list", uid=1, mode="follow", csv=False, limit=63, timeout=10000):
        channel = model.channel
        if moon:
            command = {"list": f"users:{channel}:{mode}:{limit}:{timeout}", "record": f"user-record:{channel}:{uid}:{timeout}",
                       "access": f"user-access:{channel}:{uid}", "name": f"user-name:{uid}"}[operation]
        else:
            command = {"list": f"user list {channel}" if mode == "follow" else f"channel getaccess {channel}",
                       "record": f"channel getaccess {channel} {uid}", "access": f"user summary {channel}" if uid == 1 else f"raw 6 0x44 {channel} {uid}",
                       "name": f"raw 6 0x46 {uid}"}[operation]
            command = ("-c " if csv else "") + command
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, command, moon=moon, model=model, binary=True)
        allowed = {(6, c) for c in (0x3b, 0x3c, 0x44, 0x46)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"])
        reads = [r for r in trace["commands"] if r["netfn"] == 6 and r["command"] in (0x44, 0x46)]
        assert [(r["command"], bytes.fromhex(r["request_data"])[-1]) for r in reads] == model.requests
        execution_id = len(executions)
        executions.append({"id": execution_id, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout_hex": result.stdout.hex(), "stderr_hex": result.stderr.hex(),
                           "stdout_utf8_escaped": result.stdout.decode("utf-8", "backslashreplace"),
                           "stderr_utf8_escaped": result.stderr.decode("utf-8", "backslashreplace"),
                           "exit_code": result.returncode, "trace": trace, "elapsed_seconds": elapsed})
        if result.returncode == 0:
            assert trace["closed"] and not result.stderr
        return result, execution_id

    def record(name, status, ids, **details):
        leaves.append({"id": name, "status": status, "executions": ids, **details})
        print(status + ": " + name, flush=True)

    for count in (0, 1, 63):
        model = Users(count=count)
        moon, mid = run(model, True, operation="access")
        value = json.loads(moon.stdout)
        assert moon.returncode == 0 and value == access_value(model.access(1)) and model.requests == [(0x44, 1)]
        for csv in (False, True):
            model = Users(count=count)
            ref, rid = run(model, False, operation="access", csv=csv)
            assert ref.returncode == 0 and ref.stdout == summary_projection(value, csv) and model.requests == [(0x44, 1)]
            record(f"C19.summary.count-{count}.{'csv' if csv else 'text'}", "PASS_PROJECTION", [mid, rid], typed_value=value)

    for bits in range(16):
        uid = [1, 2, 63][bits % 3]
        raw = bytes([0xc0 | [0, 1, 63][bits % 3], (bits % 4) * 64 + (63 - bits), 0xff,
                     0x80 | ((bits % 8) << 4) | bits])
        kwargs = {"channel": [0, 1, 11, 14, 15][bits % 5], "accesses": {uid: raw}}
        model = Users(**kwargs)
        moon, mid = run(model, True, operation="record", uid=uid)
        value = json.loads(moon.stdout)
        assert moon.returncode == 0 and value == record_value(model, uid) and model.requests == [(0x44, uid), (0x46, uid)]
        model = Users(**kwargs)
        ref, rid = run(model, False, operation="record", uid=uid)
        assert ref.returncode == 0 and ref.stdout == detail_projection([value]) and model.requests == [(0x44, uid), (0x46, uid)]
        record(f"C20.getaccess.fields-{bits}", "PASS_PROJECTION", [mid, rid], typed_value=value)

    for name, raw in [("empty", bytes(16)), ("completion-cc", None)]:
        model = Users(names={63: raw})
        moon, mid = run(model, True, operation="record", uid=63)
        value = json.loads(moon.stdout)
        assert moon.returncode == 0 and value == record_value(model, 63)
        model = Users(names={63: raw})
        ref, rid = run(model, False, operation="record", uid=63)
        assert ref.returncode == 0 and ref.stdout == detail_projection([value])
        assert model.requests == [(0x44, 63), (0x46, 63)]
        record("C20.getaccess.name-" + name, "PASS_PROJECTION", [mid, rid], typed_value=value,
               scope="same empty reference name; typed result preserves successful empty versus completion 0xcc")

    profiles = [
        ("basic", {}), ("zero-maximum", {"count": 0}), ("maximum-63", {"count": 63}),
        ("empty-name", {"names": {1: bytes(16)}}), ("unsupported-name", {"names": {1: None}}),
        ("full-name", {"names": {1: b"1234567890abcdef"}}),
        ("nul-and-padding", {"names": {1: b"abc\0tail\xff".ljust(16, b"\0")}}),
        ("binary-name", {"names": {1: b"\xff\x80x".ljust(16, b"\0"), 2: "é".encode().ljust(16, b"\0")}}),
        ("unescaped-name", {"names": {1: b'a,b"c'.ljust(16, b"\0"), 2: b"line\nname".ljust(16, b"\0")}}),
        ("growing-maximum", {"count": 4, "accesses": {1: b"\x02\x42\x01\x32"}}),
        ("shrinking-maximum", {"count": 4, "accesses": {2: b"\x01\x81\x00\x42"}}),
        ("changing-counts", {"count": 3, "accesses": {2: b"\x03\x00\x03\x03", 3: b"\x03\xc3\x02\x7f"}}),
    ]
    for name, kwargs in profiles:
        for mode in ("follow", "initial"):
            model = Users(**kwargs)
            moon, mid = run(model, True, mode=mode)
            value = json.loads(moon.stdout)
            assert moon.returncode == 0 and value == expected_records(model, mode)
            requests = [(cmd, row["id"]) for row in value for cmd in (0x44, 0x46)]
            assert model.requests == requests
            for csv in ((False, True) if mode == "follow" else (False,)):
                model = Users(**kwargs)
                ref, rid = run(model, False, mode=mode, csv=csv)
                projected = list_projection(value, csv) if mode == "follow" else detail_projection(value)
                assert ref.returncode == 0 and ref.stdout == projected and model.requests == requests, (name, mode, ref.stdout, projected)
                group = "C19.list" if mode == "follow" else "C20.getaccess.all"
                record(f"{group}.{name}.{'csv' if csv else 'text'}",
                       "OBSERVED_REFERENCE_UNESCAPED_NAME" if name == "unescaped-name" else "PASS_PROJECTION", [mid, rid],
                       typed_value=value, projected_stdout_hex=projected.hex())

    for name, raw in [("empty", bytes(16)), ("full", b"1234567890abcdef"), ("binary", b"\xff\x80".ljust(16, b"\0")),
                      ("nul-padding", b"abc\0suffix".ljust(16, b"\0"))]:
        moon, mid = run(Users(names={63: raw}), True, operation="name", uid=63)
        ref, rid = run(Users(names={63: raw}), False, operation="name", uid=63)
        assert moon.returncode == ref.returncode == 0
        value = json.loads(moon.stdout)
        assert value == name_value(raw) and bytes.fromhex(ref.stdout.decode()) == raw
        record("C19.name.raw-" + name, "PASS_RAW_PROJECTION", [mid, rid], typed_value=value)
    moon, mid = run(Users(), True, operation="access", uid=63)
    ref, rid = run(Users(), False, operation="access", uid=63)
    assert moon.returncode == ref.returncode == 0 and json.loads(moon.stdout) == access_value(bytes.fromhex(ref.stdout.decode()))
    record("C20.getaccess.raw-id-63", "PASS_RAW_PROJECTION", [mid, rid])

    failures = [(f"access-length-{n}", {"accesses": {1: bytes(n)}}, b"must contain 4") for n in (0, 3, 5)]
    failures += [(f"name-length-{n}", {"names": {1: bytes(n)}}, b"must contain 16") for n in (0, 15, 17)]
    failures += [(f"{cmd:02x}-completion-{cc:02x}", {"fault": (cmd, 1, cc)}, f"completion code {cc}".encode())
                 for cmd, codes in [(0x44, (0xc1, 0xcc, 0xd4)), (0x46, (0xc1, 0xd4))] for cc in codes]
    for name, kwargs, message in failures:
        moon, mid = run(Users(**kwargs), True, operation="record")
        ref, rid = run(Users(**kwargs), False, operation="record")
        assert moon.returncode > 0 and ref.returncode > 0 and message in moon.stdout + moon.stderr
        assert not moon.stdout.startswith(b"{") and not ref.stdout
        record("C20.getaccess." + name, "PASS_REJECTION_PROJECTION", [mid, rid])
    moon, mid = run(Users(names={1: None}), True, operation="name")
    ref, rid = run(Users(names={1: None}), False, operation="name")
    assert moon.returncode > 0 and ref.returncode > 0 and b"completion code 204" in moon.stdout + moon.stderr
    record("C19.name.raw-completion-cc", "PASS_REJECTION_PROJECTION", [mid, rid], scope="direct name read raises; compound user readers explicitly preserve 0xcc as absent")

    for name, kwargs, message in [
        ("access-error", {"fault": (0x44, 2, 0xd4)}, b"completion code 212"),
        ("name-error", {"fault": (0x46, 2, 0xc1)}, b"completion code 193"),
        ("access-short", {"accesses": {2: bytes(3)}}, b"must contain 4"),
        ("name-short", {"names": {2: bytes(15)}}, b"must contain 16"),
    ]:
        for mode in ("follow", "initial"):
            moon, mid = run(Users(**kwargs), True, mode=mode)
            assert moon.returncode > 0 and not moon.stdout.startswith(b"[") and message in moon.stdout + moon.stderr
            for csv in ((False, True) if mode == "follow" else (False,)):
                ref, rid = run(Users(**kwargs), False, mode=mode, csv=csv)
                prefix = [record_value(Users(**kwargs), 1)]
                projected = list_projection(prefix, csv) if mode == "follow" else detail_projection(prefix)
                assert ref.returncode > 0 and ref.stdout == projected
                record(f"{'C19.list' if mode == 'follow' else 'C20.getaccess.all'}.{name}.{'csv' if csv else 'text'}",
                       "DIVERGENT_PARTIAL_OUTPUT", [mid, rid], reference_prefix_hex=projected.hex())

    boundaries = [
        ("user-limit", {}, {"limit": 2}, 1, b"exceeds user limit"),
        ("growing-limit", {"count": 4, "accesses": {1: b"\x02\x42\x01\x32"}}, {"limit": 2}, 3, b"exceeds user limit"),
        ("zero-limit", {}, {"limit": 0}, 0, b"user limit"), ("oversized-limit", {}, {"limit": 64}, 0, b"user limit"),
        ("zero-timeout", {}, {"timeout": 0}, 0, b"overall timeout"), ("oversized-timeout", {}, {"timeout": 60001}, 0, b"overall timeout"),
        ("whole-deadline", {"delay": 0.12}, {"timeout": 200}, 2, b"operation did not complete"),
        ("record-deadline", {"delay": 0.12}, {"operation": "record", "timeout": 200}, 2, b"operation did not complete"),
        *[(f"user-id-{uid}", {}, {"operation": "record", "uid": uid}, 0, b"user ID must be") for uid in (-1, 0, 64)],
        *[(f"channel-{channel}", {"channel": channel}, {}, 0, b"channel must be") for channel in (-1, 12, 13, 16)],
    ]
    for name, kwargs, options, count, message in boundaries:
        model = Users(**kwargs)
        moon, mid = run(model, True, **options)
        assert moon.returncode > 0 and message in moon.stdout + moon.stderr and not moon.stdout.startswith((b"[", b"{"))
        assert len(model.requests) == count
        if "deadline" in name:
            assert executions[mid]["elapsed_seconds"] < 2
        record("C19.users." + name, "PASS_MOON_BOUNDARY_ONLY", [mid])

    assert len({row["id"] for row in leaves}) == len(leaves)
    summary = {s: sum(row["status"] == s for row in leaves) for s in sorted({row["status"] for row in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "user/access read APIs on synthetic suite17/User loopback; no passwords, account writes or privilege changes; byte projections do not establish full CLI or hardware parity",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; partial-output differences retained; no real device contacted")


if __name__ == "__main__":
    main()
