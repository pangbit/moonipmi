#!/usr/bin/env python3
"""Compare capability queries and non-clearing LAN statistics on synthetic localhost."""
import argparse
import json
import time

from diagnostics_check import execute
import reference_profile

COUNTERS = ["ip_received", "ip_header_errors", "ip_address_errors", "ip_fragmented", "ip_transmitted",
            "udp_received", "rmcp_received", "udp_proxy_received", "udp_proxy_dropped"]
COUNTER_LABELS = ["IP Rx Packet", "IP Rx Header Errors", "IP Rx Address Errors", "IP Rx Fragmented",
                  "IP Tx Packet", "UDP Rx Packet", "RMCP Rx Valid", "UDP Proxy Packet Received", "UDP Proxy Packet Dropped"]
AUTH = bytes.fromhex("0ebf2703570100a5")
STATS = bytes.fromhex("00000001010012348000ffff00ff0102abcd")


def channel_info(channel, medium=4):
    return bytes([channel, medium, 1, 0x81, 0x57, 1, 0, 0, 0])


class NetworkStatus:
    def __init__(self, *, channel=14, privilege=2, auth=None, infos=None, stats=(STATS, 0), delay=0):
        self.channel, self.privilege = channel, privilege
        self.auth = auth if auth is not None else [(AUTH, 0)]
        # Invalid CLI arguments must reach client validation without constructing
        # an invalid fixture byte; this default reply is never used in those cases.
        self.infos = infos if infos is not None else [(channel_info(channel & 15), 0)]
        self.stats, self.delay = stats, delay
        self.requests, self.auth_index, self.info_index = [], 0, 0

    def command(self, netfn, command, request):
        if (netfn, command) not in ((6, 0x38), (6, 0x42), (12, 4)):
            return None
        self.requests.append((netfn, command, request.hex()))
        if self.delay:
            time.sleep(self.delay)
        if command == 0x38:
            assert request in (bytes([self.channel | 128, self.privilege]), bytes([self.channel, self.privilege]))
            result = self.auth[min(self.auth_index, len(self.auth) - 1)]
            self.auth_index += 1
            return result
        if command == 0x42:
            assert request == bytes([self.channel])
            result = self.infos[min(self.info_index, len(self.infos) - 1)]
            self.info_index += 1
            return result
        assert request == bytes([self.channel, 0]), "clearing statistics is prohibited"
        return self.stats


def auth_value(raw):
    return {"channel": raw[0], "auth_types": raw[1] & 63, "v20_data_available": bool(raw[1] & 128),
            "kg_nonzero": bool(raw[2] & 32), "per_message_auth_enabled": not bool(raw[2] & 16),
            "user_level_auth_enabled": not bool(raw[2] & 8), "non_null_usernames": bool(raw[2] & 4),
            "null_usernames": bool(raw[2] & 2), "anonymous_login": bool(raw[2] & 1),
            "ipmi15_supported": bool(raw[3] & 1), "ipmi20_supported": bool(raw[3] & 2),
            "oem_id": int.from_bytes(raw[4:7], "little"), "oem_auxiliary": raw[7], "raw": list(raw)}


def auth_projection(c):
    yes = lambda b: "yes" if b else "no"
    enabled = lambda b: "enabled" if b else "disabled"
    names = "".join(name + " " for bit, name in [(1, "NONE"), (2, "MD2"), (4, "MD5"), (16, "PASSWORD"), (32, "OEM")] if c["auth_types"] & bit)
    out = f"Channel number             : {c['channel']}\nIPMI v1.5  auth types      : {names}\n"
    if c["v20_data_available"]:
        out += "KG status                  : " + ("non-zero" if c["kg_nonzero"] else "default (all zeroes)") + "\n"
    out += "Per message authentication : " + enabled(c["per_message_auth_enabled"]) + "\n"
    out += "User level authentication  : " + enabled(c["user_level_auth_enabled"]) + "\n"
    out += "Non-null user names exist  : " + yes(c["non_null_usernames"]) + "\n"
    out += "Null user names exist      : " + yes(c["null_usernames"]) + "\n"
    out += "Anonymous login enabled    : " + yes(c["anonymous_login"]) + "\n"
    if c["v20_data_available"]:
        out += "Channel supports IPMI v1.5 : " + yes(c["ipmi15_supported"]) + "\n"
        out += "Channel supports IPMI v2.0 : " + yes(c["ipmi20_supported"]) + "\n"
    if c["auth_types"] & 32:
        out += f"IANA Number for OEM        : {c['oem_id']}\nOEM Auxiliary Data         : 0x{c['oem_auxiliary']:x}\n"
    return out.encode()


def stats_value(raw):
    return {**{key: int.from_bytes(raw[2*i:2*i+2], "big") for i, key in enumerate(COUNTERS)}, "raw": list(raw)}


def stats_projection(value):
    return "".join(f"{label:26}: {value[key]}\n" for key, label in zip(COUNTERS, COUNTER_LABELS)).encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    leaves, executions = [], []

    def run(model, moon, *, operation="authcap", version2=True, csv=False, timeout=10000):
        if moon:
            command = f"authcap:{model.channel}:{model.privilege}:{'v2' if version2 else 'v1'}" if operation == "authcap" else f"lan-stats:{model.channel}:{timeout}"
        elif operation == "authcap":
            command = f"channel authcap {model.channel} {model.privilege}" if version2 else f"raw 6 0x38 {model.channel} {model.privilege}"
        else:
            command = f"lan stats get {model.channel}"
        if not moon and csv:
            command = "-c " + command
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, command, moon=moon, model=model, binary=True)
        allowed = {(6, 0x3b), (6, 0x3c), (6, 0x38), (6, 0x42), (12, 4)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"])
        reads = [(r["netfn"], r["command"], r["request_data"]) for r in trace["commands"] if (r["netfn"], r["command"]) in ((6, 0x38), (6, 0x42), (12, 4))]
        assert reads == model.requests
        assert trace["rakp_role"] == (2 if moon else 0x12), "query privilege must not alter the authenticated role"
        index = len(executions)
        executions.append({"id": index, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout_hex": result.stdout.hex(), "stderr_hex": result.stderr.hex(),
                           "stdout_utf8_escaped": result.stdout.decode("utf-8", "backslashreplace"),
                           "stderr_utf8_escaped": result.stderr.decode("utf-8", "backslashreplace"),
                           "exit_code": result.returncode, "trace": trace, "elapsed_seconds": elapsed})
        if result.returncode == 0:
            assert trace["closed"] and not result.stderr, (command, result.stderr)
        return result, index

    def record(id, status, ids, **detail):
        leaves.append({"id": id, "status": status, "executions": ids, **detail})
        print(status, id, flush=True)

    cases = [(f"auth-mask-{n}", bytes([14, n | 128, 7, 3, 0x57, 1, 0, 0])) for n in range(64)]
    cases += [(f"flags-{n:02x}", bytes([14, 0xbf, n, 3, 0x56, 0x34, 0x12, 255])) for n in (0, 1, 2, 4, 8, 16, 32, 64, 128, 255)]
    cases += [(f"support-{n}", bytes([254, 0xff, 255, n, 255, 255, 255, 255])) for n in (0, 1, 2, 3, 0xfc, 255)]
    cases += [("v15-layout", bytes.fromhex("0e3f3fff01020304")), ("all-zero", bytes(8))]
    for name, raw in cases:
        model = NetworkStatus(auth=[(raw, 0)])
        moon, mid = run(model, True)
        assert moon.returncode == 0 and json.loads(moon.stdout) == auth_value(raw)
        expected_requests = [(6, 0x38, "8e02")]
        assert model.requests == expected_requests
        for csv in ((False, True) if name in ("v15-layout", "all-zero", "flags-ff") else (False,)):
            model = NetworkStatus(auth=[(raw, 0)])
            ref, rid = run(model, False, csv=csv)
            assert ref.returncode == 0 and ref.stdout == auth_projection(json.loads(moon.stdout))
            assert model.requests == expected_requests
            record(f"C20.authcap.{name}.{'csv' if csv else 'text'}", "PASS_PROJECTION", [mid, rid])

    for channel, privilege in [(0, 1), (1, 2), (11, 3), (14, 4), (15, 5), (14, 15)]:
        for version2 in (True, False):
            moon_model, ref_model = NetworkStatus(channel=channel, privilege=privilege), NetworkStatus(channel=channel, privilege=privilege)
            moon, mid = run(moon_model, True, version2=version2)
            ref, rid = run(ref_model, False, version2=version2)
            expected = [(6, 0x38, bytes([channel | (128 if version2 else 0), privilege]).hex())]
            assert moon_model.requests == ref_model.requests == expected
            assert moon.returncode == ref.returncode == 0
            if version2:
                assert ref.stdout == auth_projection(json.loads(moon.stdout))
            else:
                assert bytes.fromhex(ref.stdout.decode()) == bytes(json.loads(moon.stdout)["raw"])
            record(f"C20.authcap.channel-{channel}.privilege-{privilege}.v{2 if version2 else 1}",
                   "PASS_PROJECTION" if version2 else "PASS_RAW_PROJECTION", [mid, rid])

    for first_code in (0xc1, 0xcc, 0xd4):
        for fallback_code in (0, 0xd4):
            responses = [(b"", first_code), (AUTH if fallback_code == 0 else b"", fallback_code)]
            moon_model, ref_model = NetworkStatus(auth=responses), NetworkStatus(auth=responses)
            moon, mid = run(moon_model, True)
            ref, rid = run(ref_model, False)
            assert moon.returncode > 0 and f"completion code {first_code}".encode() in moon.stdout + moon.stderr
            assert moon_model.requests == [(6, 0x38, "8e02")]
            assert ref_model.requests == [(6, 0x38, "8e02"), (6, 0x38, "0e02")]
            assert (ref.returncode == 0) == (fallback_code == 0)
            assert ref.stdout == (auth_projection(auth_value(AUTH)) if fallback_code == 0 else b"")
            record(f"C20.authcap.fallback-{first_code:02x}-{fallback_code:02x}", "DIVERGENT_QUERY_FALLBACK", [mid, rid],
                   scope="extended-data query retry only; both clients remain suite17/User; no authentication downgrade")

    stats_cases = [("distinct", STATS, 4), ("all-zero", bytes(18), 4), ("all-max", b"\xff"*18, 6),
                   ("byte-order", bytes(range(18)), 4), ("reserved-medium-bits", STATS, 0x84)]
    for name, raw, medium in stats_cases:
        model = NetworkStatus(infos=[(channel_info(1, medium), 0)], stats=(raw, 0))
        moon, mid = run(model, True, operation="stats")
        assert moon.returncode == 0 and json.loads(moon.stdout) == stats_value(raw)
        expected = [(6, 0x42, "0e"), (6, 0x42, "0e"), (12, 4, "0e00")]
        assert model.requests == expected
        for csv in (False, True):
            model = NetworkStatus(infos=[(channel_info(1, medium), 0)], stats=(raw, 0))
            ref, rid = run(model, False, operation="stats", csv=csv)
            assert ref.returncode == 0 and ref.stdout == stats_projection(json.loads(moon.stdout))
            assert model.requests == expected
            record(f"C04.stats.{name}.{'csv' if csv else 'text'}", "PASS_PROJECTION", [mid, rid])
    for channel in (1, 11, 12, 13):
        models = [NetworkStatus(channel=channel), NetworkStatus(channel=channel)]
        moon, mid = run(models[0], True, operation="stats")
        ref, rid = run(models[1], False, operation="stats")
        assert moon.returncode == ref.returncode == 0 and ref.stdout == stats_projection(json.loads(moon.stdout))
        assert models[0].requests == models[1].requests == [(6, 0x42, f"{channel:02x}"), (6, 0x42, f"{channel:02x}"), (12, 4, f"{channel:02x}00")]
        record(f"C04.stats.channel-{channel}", "PASS_PROJECTION", [mid, rid])

    failures = [("non-lan-first", {"infos": [(channel_info(14, 5), 0)]}, 1, b"not a LAN channel"),
                ("non-lan-second", {"infos": [(channel_info(14), 0), (channel_info(14, 1), 0)]}, 2, b"not a LAN channel")]
    for index in (1, 2):
        prefix = [(channel_info(14), 0)] * (index-1)
        for n in (0, 8, 10):
            failures.append((f"info-{index}-length-{n}", {"infos": prefix + [(bytes(n), 0)]}, index, b"Channel Info must contain"))
        for code in (0xc1, 0xcc, 0xd4):
            failures.append((f"info-{index}-completion-{code:02x}", {"infos": prefix + [(b"", code)]}, index, f"completion code {code}".encode()))
    for code in (0x80, 0xc1, 0xcc, 0xd4):
        failures.append((f"completion-{code:02x}", {"stats": (b"", code)}, 3, f"completion code {code}".encode()))
    for name, kwargs, count, message in failures:
        models = [NetworkStatus(**kwargs), NetworkStatus(**kwargs)]
        moon, mid = run(models[0], True, operation="stats")
        ref, rid = run(models[1], False, operation="stats")
        assert moon.returncode > 0 and ref.returncode > 0 and not ref.stdout
        assert message in moon.stdout + moon.stderr and not moon.stdout.startswith(b"{")
        assert len(models[0].requests) == count and models[0].requests == models[1].requests
        record("C04.stats." + name, "PASS_REJECTION_PROJECTION", [mid, rid])

    for operation, original in (("authcap", AUTH), ("stats", STATS)):
        for size in (0, len(original)-1, len(original)+1):
            raw = (original + b"\xaa")[:size]
            kwargs = {"auth": [(raw, 0)]} if operation == "authcap" else {"stats": (raw, 0)}
            moon, mid = run(NetworkStatus(**kwargs), True, operation=operation)
            ref, rid = run(NetworkStatus(**kwargs), False, operation=operation)
            assert moon.returncode > 0 and b"must contain" in moon.stdout + moon.stderr
            assert ref.returncode == 0 and ref.stdout
            if size > len(original):
                expected = auth_projection(auth_value(original)) if operation == "authcap" else stats_projection(stats_value(original))
                assert ref.stdout == expected
            record(f"{'C20.authcap' if operation == 'authcap' else 'C04.stats'}.length-{size}",
                   "DIVERGENT_EXTRA_RESPONSE_BYTES" if size > len(original) else "OBSERVED_REFERENCE_SHORT_RESPONSE", [mid, rid],
                   scope="reference short-response values beyond supplied bytes are recorded, not assumed stable; library rejects the incomplete layout")

    boundaries = [("C20.authcap", "authcap", {"channel": c}, {}, b"channel must") for c in (-1, 12, 13, 16)]
    boundaries += [("C20.authcap", "authcap", {"privilege": p}, {}, b"capability query privilege") for p in (-1, 0, 6, 14, 16)]
    boundaries += [("C04.stats", "stats", {"channel": c}, {}, b"LAN statistics channel") for c in (-1, 0, 15, 256)]
    boundaries += [("C04.stats", "stats", {}, {"timeout": n}, b"overall timeout") for n in (0, 60001)]
    for prefix, operation, kwargs, options, message in boundaries:
        model = NetworkStatus(**kwargs)
        moon, mid = run(model, True, operation=operation, **options)
        assert moon.returncode > 0 and message in moon.stdout + moon.stderr and not model.requests
        record(prefix + ".boundary." + "-".join(f"{k}-{v}" for k,v in {**kwargs, **options}.items()), "PASS_MOON_BOUNDARY_ONLY", [mid])
    for delay in (0.12, 0.22):
        model = NetworkStatus(delay=delay)
        result, mid = run(model, True, operation="stats", timeout=200)
        assert result.returncode > 0 and b"operation did not complete" in result.stdout + result.stderr
        assert not result.stdout.startswith(b"{") and not executions[mid]["trace"]["closed"]
        expected = [(6, 0x42, "0e"), (6, 0x42, "0e")]
        assert 1 <= len(model.requests) <= 2 and model.requests == expected[:len(model.requests)]
        assert 0.15 <= executions[mid]["elapsed_seconds"] < 2
        record(f"C04.stats.boundary.deadline-{delay}", "PASS_MOON_BOUNDARY_ONLY", [mid])

    assert len({r["id"] for r in leaves}) == len(leaves)
    summary = {s: sum(r["status"] == s for r in leaves) for s in sorted({r["status"] for r in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "explicit read-only capability/statistics queries on synthetic suite17/User loopback; no auth fallback, statistics clearing, CLI or hardware parity",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; no real device contacted")


if __name__ == "__main__":
    main()
