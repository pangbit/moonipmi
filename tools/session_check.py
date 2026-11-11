#!/usr/bin/env python3
"""Compare bounded session reads with pinned ipmitool using synthetic localhost only."""
import argparse
import json
import time

from diagnostics_check import execute
import reference_profile

PRIVILEGES = {1: "CALLBACK", 2: "USER", 3: "OPERATOR", 4: "ADMINISTRATOR", 5: "OEM", 15: "NO ACCESS"}
ACTIVITIES = {0: "IPMI Messaging session active", 1: "Callback Messaging session active",
              2: "Dial-out Alert active", 3: "TAP Page Active"}


def lan(*, slots=3, active=2, handle=1, uid=1, privilege=2, auxiliary=1, channel=14, port=623):
    return bytes([handle, slots | 0xc0, active | 0xc0, uid | 0xc0, privilege | 0xf0,
                  auxiliary << 4 | channel, 192, 0, 2, 1, 2, 0xaa, 0xbb, 0xcc, 0xdd, 0xee]) + port.to_bytes(2, "little")


def serial(*, port=None, activity=0, destination=7, **kwargs):
    return lan(**kwargs)[:6] + bytes([activity, destination | 0xf0, 198, 51, 100, 2]) + (b"" if port is None else port.to_bytes(2, "little"))


class Sessions:
    def __init__(self, *, count=3, records=None, direct=None, delay=0):
        self.count, self.records, self.direct, self.delay = count, records or {}, direct, delay
        self.requests = []

    def response(self, slot):
        return self.records.get(slot, (lan(slots=self.count, handle=slot), 0))

    def command(self, netfn, command, request):
        if (netfn, command) != (6, 0x3d):
            return None
        assert request and ((request[0] <= 63 and len(request) == 1) or
                            (request[0] == 0xfe and len(request) == 2) or
                            (request[0] == 0xff and len(request) == 5)), request.hex()
        self.requests.append(request.hex())
        if self.delay:
            time.sleep(self.delay)
        return self.response(request[0]) if 1 <= request[0] <= 63 else (self.direct or (lan(), 0))


def value(raw):
    result = {"handle": raw[0], "slots": raw[1] & 63, "active": raw[2] & 63, "details": None, "raw": list(raw)}
    if len(raw) == 3:
        return result
    connection = {"kind": "header-only"}
    if len(raw) == 18:
        connection = {"kind": "lan", "ip": list(raw[6:10]), "mac": list(raw[10:16]), "port": int.from_bytes(raw[16:18], "little")}
    elif len(raw) in (12, 14):
        connection = {"kind": "serial", "activity": raw[6], "destination": raw[7] & 15, "ip": list(raw[8:12]),
                      "port": int.from_bytes(raw[12:14], "little") if len(raw) == 14 else None}
    result["details"] = {"user_id": raw[3] & 63, "privilege": raw[4] & 15, "channel": raw[5] & 15,
                         "auxiliary": raw[5] >> 4, "connection": connection}
    return result


def label(table, number):
    return table.get(number, f"Unknown (0x{number:02X})")


def projection(info, csv=False):
    fields = [("session handle", str(info["handle"])), ("slot count", str(info["slots"])),
              ("active sessions", str(info["active"]))]
    d = info["details"]
    if d is not None:
        fields += [("user id", str(d["user_id"])), ("privilege level", label(PRIVILEGES, d["privilege"])),
                   ("session type", "IPMIv2/RMCP+" if d["auxiliary"] else "IPMIv1.5"),
                   ("channel number", f"0x{d['channel']:02x}")]
        c = d["connection"]
        if c["kind"] == "serial":
            fields += [("Session/Channel Activity Type", label(ACTIVITIES, c["activity"])),
                       ("Destination selector", str(c["destination"]))]
        if c["kind"] != "header-only":
            fields.append(("console ip", ".".join(map(str, c["ip"]))))
            if c["kind"] == "lan":
                fields.append(("console mac", ":".join(f"{b:02x}" for b in c["mac"])))
            if c["port"] is not None:
                fields.append(("console port", str(c["port"])))
    text = ",".join(v for _, v in fields) + "\n" if csv else "".join(f"{k:30}: {v}\n" for k, v in fields) + "\n"
    return text.encode()


def reference_projection(raw, csv=False, previous=b"\0" * 18):
    # Model the observed bounded memcpy, reused union and wrong PPP port offset.
    # This is an evidence projection only, never the client decoder's contract.
    copied = raw[:18] + previous[min(len(raw), 18):]
    n = min(len(raw), 18)
    canonical = copied[:n] if n in (3, 6, 12, 14, 18) else copied[:6]
    info = value(canonical)
    if n == 14:
        info["details"]["connection"]["port"] = int.from_bytes(copied[16:18], "little")
    return projection(info, csv), copied


def scan(model):
    entries, slot = [], 1
    while slot <= 63:
        raw, code = model.response(slot)
        info = value(raw)
        entries.append({"slot": slot, "completion": code, "info": info})
        slot += 1
        if slot > info["slots"]:
            break
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    leaves, executions = [], []

    def run(model, moon, *, mode="active", selector=0, csv=False, limit=63, timeout=10000):
        if moon:
            command = f"sessions:{limit}:{timeout}" if mode == "all" else f"session-info:{mode}:{selector}"
        else:
            command = f"raw 6 0x3d {selector}" if mode == "slot" else "session info " + mode + (f" {selector}" if mode in ("id", "handle") else "")
            command = ("-c " if csv else "") + command
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, command, moon=moon, model=model, binary=True)
        allowed = {(6, 0x3b), (6, 0x3c), (6, 0x3d)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"])
        requests = [r["request_data"] for r in trace["commands"] if (r["netfn"], r["command"]) == (6, 0x3d)]
        assert requests == model.requests
        index = len(executions)
        executions.append({"id": index, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout_hex": result.stdout.hex(), "stderr_hex": result.stderr.hex(),
                           "stdout_utf8_escaped": result.stdout.decode("utf-8", "backslashreplace"),
                           "stderr_utf8_escaped": result.stderr.decode("utf-8", "backslashreplace"),
                           "exit_code": result.returncode, "trace": trace, "elapsed_seconds": elapsed})
        if result.returncode == 0:
            assert trace["closed"] and not result.stderr, (command, result.stderr)
        return result, index

    def record(suffix, status, ids, **detail):
        leaf = {"id": "C21." + suffix, "status": status, "executions": ids, **detail}
        leaves.append(leaf)
        print(status, leaf["id"], flush=True)

    cases = [("counts-only", bytes([0, 0xc0, 0xff])), ("header-only", lan()[:6]), ("lan", lan()),
             ("lan-zero-port", lan(port=0)), ("lan-max", lan(slots=63, active=63, handle=255, uid=63, port=65535)),
             ("serial", serial()), ("serial-destination-max", serial(destination=15))]
    cases += [(f"privilege-{p}", lan(privilege=p)) for p in range(16)]
    cases += [(f"auxiliary-{a}", lan(auxiliary=a, channel=a)) for a in range(16)]
    cases += [(f"serial-activity-{a}", serial(activity=a)) for a in (1, 2, 3, 4, 255)]
    cases += [(f"ppp-port-{p}", serial(port=p)) for p in (0, 623, 65535)]
    for name, raw in cases:
        model = Sessions(direct=(raw, 0))
        moon, mid = run(model, True)
        assert moon.returncode == 0 and model.requests == ["00"]
        typed = json.loads(moon.stdout)
        assert typed == value(raw)
        for csv in (False, True):
            model = Sessions(direct=(raw, 0))
            ref, rid = run(model, False, csv=csv)
            assert ref.returncode == 0 and model.requests == ["00"]
            actual, _ = reference_projection(raw, csv)
            assert ref.stdout == actual, (name, csv, ref.stdout, actual)
            status = "PASS_PROJECTION" if ref.stdout == projection(typed, csv) else "DIVERGENT_PPP_PORT"
            record(f"active.{name}.{'csv' if csv else 'text'}", status, [mid, rid])

    for mode, selectors in [("id", (0, 0x12345678, 0xffffffff)), ("handle", (0, 1, 255)), ("slot", (1, 63))]:
        for selector in selectors:
            expected = (b"\xff" + selector.to_bytes(4, "little") if mode == "id" else
                        bytes([0xfe, selector]) if mode == "handle" else bytes([selector])).hex()
            model = Sessions()
            moon, mid = run(model, True, mode=mode, selector=selector)
            assert moon.returncode == 0 and model.requests == [expected]
            typed = json.loads(moon.stdout)
            model = Sessions()
            ref, rid = run(model, False, mode=mode, selector=selector)
            assert ref.returncode == 0 and model.requests == [expected]
            if mode == "slot":
                assert bytes(typed["raw"]) == bytes.fromhex(ref.stdout.decode())
            else:
                assert projection(typed) == ref.stdout
            record(f"{mode}.{selector}", "PASS_RAW_PROJECTION" if mode == "slot" else "PASS_PROJECTION", [mid, rid])

    scan_cases = [("basic", {}), ("zero-slots", {"count": 0}), ("full-slots", {"count": 63}),
                  ("grow", {"count": 4, "records": {1: (lan(slots=2), 0)}}),
                  ("shrink", {"count": 1, "records": {1: (lan(slots=3), 0)}}),
                  ("changing-active", {"records": {2: (lan(active=63), 0)}}),
                  ("absent-cb", {"records": {2: (bytes([0, 3, 1]), 0xcb)}}),
                  ("absent-cc", {"records": {2: (bytes([0, 3, 1]), 0xcc)}}),
                  ("cc-with-full-data", {"records": {2: (lan(), 0xcc)}}),
                  ("mixed-layouts", {"records": {1: (serial(), 0), 2: (lan()[:6], 0), 3: (b"\x00\x03\x01", 0)}}),
                  ("ppp-after-lan", {"records": {1: (lan(port=4321), 0), 2: (serial(port=623), 0)}})]
    for name, kwargs in scan_cases:
        model = Sessions(**kwargs)
        moon, mid = run(model, True, mode="all")
        typed = scan(model)
        assert moon.returncode == 0 and json.loads(moon.stdout) == typed
        requests = [bytes([e["slot"]]).hex() for e in typed]
        assert model.requests == requests
        for csv in (False, True):
            model = Sessions(**kwargs)
            ref, rid = run(model, False, mode="all", csv=csv)
            assert ref.returncode == 0 and model.requests == requests
            output, previous = b"", b"\0" * 18
            for entry in typed:
                part, previous = reference_projection(bytes(entry["info"]["raw"]), csv, previous)
                output += part
            assert ref.stdout == output, (name, csv, ref.stdout, output)
            correct = b"".join(projection(entry["info"], csv) for entry in typed)
            record(f"all.{name}.{'csv' if csv else 'text'}", "PASS_PROJECTION" if correct == output else "DIVERGENT_PPP_PORT", [mid, rid])

    for code in (0xc1, 0xcb, 0xcc, 0xd4):
        for mode in ("active", "id", "handle"):
            moon, mid = run(Sessions(direct=(b"\x00\x03\x00", code)), True, mode=mode, selector=1)
            ref, rid = run(Sessions(direct=(b"\x00\x03\x00", code)), False, mode=mode, selector=1)
            assert moon.returncode > 0 and ref.returncode > 0 and not ref.stdout
            assert f"completion code {code}".encode() in moon.stdout + moon.stderr
            record(f"{mode}.completion-{code:02x}", "PASS_REJECTION_PROJECTION", [mid, rid])

    for size in (0, 1, 2, 4, 5, 7, 11, 13, 15, 17, 19):
        raw = (lan() + b"\xaa")[:size]
        moon, mid = run(Sessions(direct=(raw, 0)), True)
        assert moon.returncode > 0 and b"Session Info must contain" in moon.stdout + moon.stderr
        for csv in (False, True):
            ref, rid = run(Sessions(direct=(raw, 0)), False, csv=csv)
            expected, _ = reference_projection(raw, csv)
            assert ref.returncode == 0 and ref.stdout == expected
            record(f"active.length-{size}.{'csv' if csv else 'text'}", "DIVERGENT_RESPONSE_LENGTH", [mid, rid])

    for name, response in [("completion-c1", (b"", 0xc1)), ("completion-d4", (b"", 0xd4)),
                           ("cb-no-data", (b"", 0xcb)), ("cc-short", (b"\x00\x03", 0xcc)), ("short", (b"\x00", 0))]:
        kwargs = {"records": {2: response}}
        model = Sessions(**kwargs)
        moon, mid = run(model, True, mode="all")
        assert moon.returncode > 0 and not moon.stdout.startswith(b"[") and model.requests == ["01", "02"]
        for csv in (False, True):
            model = Sessions(**kwargs)
            ref, rid = run(model, False, mode="all", csv=csv)
            assert ref.returncode > 0 and model.requests == ["01", "02"]
            assert ref.stdout == projection(value(lan()), csv)
            record(f"all.{name}.{'csv' if csv else 'text'}", "DIVERGENT_PARTIAL_OUTPUT", [mid, rid])

    # A short accepted response reuses earlier union bytes in the reference scan.
    for raw in (lan()[:4], lan()[:13]):
        kwargs = {"count": 2, "records": {2: (raw[:1] + bytes([2]) + raw[2:], 0)}}
        model = Sessions(**kwargs)
        moon, mid = run(model, True, mode="all")
        assert moon.returncode > 0 and b"Session Info must contain" in moon.stdout + moon.stderr
        for csv in (False, True):
            model = Sessions(**kwargs)
            ref, rid = run(model, False, mode="all", csv=csv)
            first, previous = reference_projection(model.response(1)[0], csv)
            second, _ = reference_projection(model.response(2)[0], csv, previous)
            assert ref.returncode == 0 and ref.stdout == first + second
            record(f"all.length-{len(raw)}.{'csv' if csv else 'text'}", "DIVERGENT_RESPONSE_LENGTH", [mid, rid])

    for selector in (256, 0xffffffff):
        model = Sessions()
        # The typed API's signed Int32 still rejects 256; the CLI accepts uint32
        # then truncates to one byte. The full uint32 case is reference-only evidence.
        ids = []
        if selector == 256:
            moon, mid = run(Sessions(), True, mode="handle", selector=selector)
            assert moon.returncode > 0 and b"session handle must" in moon.stdout + moon.stderr
            ids.append(mid)
        ref, rid = run(model, False, mode="handle", selector=selector)
        assert ref.returncode == 0 and model.requests == [bytes([0xfe, selector & 255]).hex()]
        record(f"handle.truncation-{selector}",
               "DIVERGENT_HANDLE_RANGE" if ids else "OBSERVED_REFERENCE_HANDLE_TRUNCATION", ids + [rid],
               scope="256 compared against bounded API; uint32 maximum is reference-only evidence outside the API handle type")

    boundaries = [("zero-limit", {}, {"mode": "all", "limit": 0}, [], b"slot limit"),
                  ("oversized-limit", {}, {"mode": "all", "limit": 64}, [], b"slot limit"),
                  ("slot-limit", {}, {"mode": "all", "limit": 2}, ["01"], b"exceeds slot limit"),
                  ("growing-limit", {"count": 4, "records": {1: (lan(slots=2), 0)}}, {"mode": "all", "limit": 2}, ["01", "02"], b"exceeds slot limit"),
                  ("zero-timeout", {}, {"mode": "all", "timeout": 0}, [], b"overall timeout"),
                  ("oversized-timeout", {}, {"mode": "all", "timeout": 60001}, [], b"overall timeout"),
                  ("negative-handle", {}, {"mode": "handle", "selector": -1}, [], b"session handle"),
                  *[(f"slot-{s}", {}, {"mode": "slot", "selector": s}, [], b"session slot must") for s in (-1, 0, 64)]]
    for name, kwargs, options, requests, message in boundaries:
        model = Sessions(**kwargs)
        result, mid = run(model, True, **options)
        assert result.returncode > 0 and message in result.stdout + result.stderr and model.requests == requests
        assert not result.stdout.startswith((b"[", b"{"))
        record("boundary." + name, "PASS_MOON_BOUNDARY_ONLY", [mid])
    for delay in (0.12, 0.22):
        model = Sessions(delay=delay)
        result, mid = run(model, True, mode="all", timeout=200)
        assert result.returncode > 0 and b"operation did not complete" in result.stdout + result.stderr
        assert not result.stdout.startswith(b"[") and not executions[mid]["trace"]["closed"]
        assert 1 <= len(model.requests) <= 2 and model.requests == ["01", "02"][:len(model.requests)]
        assert 0.15 <= executions[mid]["elapsed_seconds"] < 2
        record(f"boundary.deadline-{delay}", "PASS_MOON_BOUNDARY_ONLY", [mid])

    assert len({leaf["id"] for leaf in leaves}) == len(leaves)
    summary = {s: sum(row["status"] == s for row in leaves) for s in sorted({row["status"] for row in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "session read APIs over synthetic suite17/User loopback; no session control; projections are not full CLI/hardware parity",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; differences retained; no real device contacted")


if __name__ == "__main__":
    main()
