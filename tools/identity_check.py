#!/usr/bin/env python3
"""Compare GUID and bounded System Info reads on synthetic loopback peers only."""
import argparse
from datetime import datetime, timezone
import json
import time
import uuid

from diagnostics_check import execute
import reference_profile

PARAMETERS = {1: "system_fw_version", 2: "system_name", 3: "primary_os_name",
              4: "os_name", 0xe4: "delloem_os_version", 0xde: "delloem_url"}
VERSIONS = ["Unknown/unsupported", "Time-based", "DCE Security with POSIX UIDs (not for IPMI)",
            "Name-based using MD5", "Random or pseudo-random", "Name-based using SHA-1"]


class Identity:
    def __init__(self, kind, data, *, parameter=2, encoding=0, completion=0, fault=None):
        self.kind, self.data = kind, data
        self.parameter, self.encoding, self.completion, self.fault = parameter, encoding, completion, fault
        self.reads = 0

    def command(self, netfn, command, request):
        if (netfn, command) != (6, 0x37 if self.kind == "guid" else 0x59):
            return None
        selector = self.reads
        self.reads += 1
        if self.kind == "guid":
            assert request == b"" and self.reads == 1
            return self.data, self.completion
        assert request == bytes([0, self.parameter, selector, 0]), request
        assert selector <= 16, "bounded read exceeded 255-byte wire range"
        if self.completion:
            return b"", self.completion
        if self.fault == "second-error" and selector == 1:
            return b"", 0xc1
        if self.fault == "slow":
            time.sleep(0.12)
        if selector == 0:
            payload = bytes([self.encoding, len(self.data)]) + self.data[:14].ljust(14, b"\0")
        else:
            start = 14 + (selector - 1) * 16
            payload = self.data[start:start + 16].ljust(16, b"\0")
        revision = 0x12 if self.fault == "revision" and selector == 1 else 0x11
        echo = selector + 1 if self.fault == "selector" else selector
        response = bytes([revision, echo]) + payload
        if self.fault == "short":
            response = response[:17]
        elif self.fault == "extra":
            response += b"x"
        elif self.fault == "padding" and selector == 0:
            response = response[:7] + b"X" + response[8:]
        return response, 0


def encoded(canonical, mode):
    if mode == "ipmi":
        return canonical[::-1]
    if mode == "smbios":
        return uuid.UUID(bytes=canonical).bytes_le
    return canonical


def decoded(raw, mode):
    canonical = raw[::-1] if mode == "ipmi" else uuid.UUID(bytes_le=raw).bytes if mode == "smbios" else raw
    guid = uuid.UUID(bytes=canonical)
    version = canonical[6] >> 4
    return {"encoding": mode, "value": str(guid), "raw_version": version,
            "version": version if version <= 5 else 0,
            "unix_seconds": guid.time // 10000000 - 12219292800 if version == 1 else None}


def expected_guid(raw, mode, year):
    dump = {"encoding": "dump", "value": raw.hex().upper(), "raw_version": None,
            "version": None, "unix_seconds": None}
    if mode == "dump":
        return dump
    if mode != "auto":
        return decoded(raw, mode)
    result = dump
    for encoding in ("rfc", "ipmi", "smbios"):
        candidate = decoded(raw, encoding)
        if 1 <= candidate["version"] <= 5:
            result = candidate
            seconds = candidate["unix_seconds"]
            if seconds is not None and 1970 <= datetime.fromtimestamp(seconds, timezone.utc).year <= year:
                break
    return result


def guid_projection(value, auto):
    text = "System GUID   : " + value["value"] + "\n"
    if value["encoding"] == "dump":
        return text
    if auto:
        label = {"ipmi": "IPMI", "rfc": "RFC4122", "smbios": "SMBIOS"}[value["encoding"]]
        text += "GUID Encoding : " + label
        text += " (WARNING: IPMI Specification violation!)" if value["encoding"] != "ipmi" else ""
        text += "\n"
    text += "GUID Version  : " + VERSIONS[value["version"]]
    text += f" ({value['raw_version']})" if value["version"] == 0 else ""
    text += "\n"
    if value["unix_seconds"] is not None:
        # Reconstruct the reference CLI's separate uint32/SEL-time presentation.
        stamp = value["unix_seconds"] & 0xffffffff
        if stamp == 0xffffffff:
            timestamp = "Unspecified"
        else:
            date = datetime.fromtimestamp(stamp, timezone.utc)
            fmt = "S+ %H:%M:%S" if stamp < 86400 else "S+ %y/%j %H:%M:%S" if stamp < 0x20000000 else "%m/%d/%y %H:%M:%S UTC"
            timestamp = date.strftime(fmt)
        text += "Timestamp     : " + timestamp + "\n"
    return text


def time_guid(seconds):
    ticks = (seconds + 12219292800) * 10000000
    return uuid.UUID(fields=(ticks & 0xffffffff, (ticks >> 32) & 0xffff,
        ((ticks >> 48) & 0xfff) | 0x1000, 0x9a, 0x3c, 0x123456789abc)).bytes


def guid_cases(year):
    base = uuid.UUID("00112233-4455-4677-8899-aabbccddeeff").bytes
    for wire in ("rfc", "ipmi", "smbios"):
        for mode in ("rfc", "ipmi", "smbios", "dump", "auto"):
            yield wire + "-as-" + mode, encoded(base, wire), mode
    for version in range(16):
        raw = bytearray(base)
        raw[6] = (version << 4) | 6
        yield f"version-{version}", bytes(raw), "rfc"
    for name, raw in [("zeros", bytes(16)), ("ff", bytes([255]) * 16),
                      ("last-valid-wins", bytes.fromhex("00112233445546578839aabbccddeeff"))]:
        yield name, raw, "auto"
    for name, seconds in [("gregorian", -12219292800), ("before-epoch", -1), ("epoch", 0),
                          ("2020", 1577836800), ("current-year-end", int(datetime(year, 12, 31, tzinfo=timezone.utc).timestamp())),
                          ("next-year", int(datetime(year + 1, 1, 1, tzinfo=timezone.utc).timestamp())),
                          ("2200", 7258118400)]:
        for mode in ("rfc", "auto"):
            yield name + "-" + mode, time_guid(seconds), mode
    for wire in ("ipmi", "smbios"):
        for mode in (wire, "auto"):
            yield "time-" + wire + "-" + mode, encoded(time_guid(1577836800), wire), mode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    year = datetime.now(timezone.utc).year
    executions, leaves = [], []

    def run(model, moon, mode="auto", limit=255, timeout=10000):
        if model.kind == "guid":
            command = f"guid:{mode}:{year}" if moon else "mc guid " + mode
            target = (6, 0x37)
        else:
            command = f"sysinfo:{model.parameter}:{limit}:{timeout}" if moon else "mc getsysinfo " + PARAMETERS[model.parameter]
            target = (6, 0x59)
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, command, moon=moon, model=model)
        allowed = {target, (6, 0x3b), (6, 0x3c)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"]), trace
        reads = [r for r in trace["commands"] if (r["netfn"], r["command"]) == target]
        assert len(reads) == model.reads
        execution_id = len(executions)
        executions.append({"id": execution_id, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode,
                           "trace": trace, "read_count": len(reads), "elapsed_seconds": elapsed})
        if result.returncode == 0:
            assert trace["closed"]
        return result, execution_id

    def record(name, status, ids, **extra):
        leaves.append({"id": "C08." + name, "status": status, "executions": ids, **extra})
        print(status + ": C08." + name, flush=True)

    for name, raw, mode in guid_cases(year):
        moon, moon_id = run(Identity("guid", raw), True, mode)
        assert moon.returncode == 0 and not moon.stderr, moon
        value = json.loads(moon.stdout)
        assert value == {"raw": list(raw), **expected_guid(raw, mode, year)}, value
        ref, ref_id = run(Identity("guid", raw), False, mode)
        projected = guid_projection(value, mode == "auto")
        assert ref.returncode == 0 and not ref.stderr and ref.stdout == projected, (name, ref, projected)
        seconds = value["unix_seconds"]
        difference = seconds is not None and (seconds < 0x20000000 or seconds >= 0xffffffff)
        record("guid." + name, "DIVERGENT_TIMESTAMP_DISPLAY" if difference else "PASS_PROJECTION", [moon_id, ref_id],
               typed_value=value, projected_stdout=projected,
               scope="raw and UUID fields checked independently; reference timestamp projection is not an API/CLI equivalence claim")

    for length in (0, 15, 17):
        ids = []
        for moon in (True, False):
            result, execution_id = run(Identity("guid", bytes(length)), moon)
            assert result.returncode > 0 and not result.stdout.startswith("{")
            ids.append(execution_id)
        record(f"guid.length-{length}", "PASS_REJECTION_PROJECTION", ids)

    def sys_case(name, data, parameter=2, encoding=0, fault=None, moon_only=False):
        model = Identity("sysinfo", data, parameter=parameter, encoding=encoding, fault=fault)
        moon, moon_id = run(model, True)
        assert moon.returncode == 0 and not moon.stderr, moon
        value = json.loads(moon.stdout)
        assert value["data"] == list(data) and value["parameter"] == parameter
        assert value["revision"] == 0x11 and value["encoding_byte"] == encoding and value["encoding"] == encoding & 15
        assert value["ascii_text"] == (data.decode("ascii") if encoding & 15 == 0 and all(c < 128 for c in data) else None)
        assert model.reads == max(1, (len(data) + 17) // 16)
        reads = [r for r in executions[moon_id]["trace"]["commands"] if r["command"] == 0x59 and r["netfn"] == 6]
        assert len(value["blocks"]) == len(reads)
        for selector, (block, read) in enumerate(zip(value["blocks"], reads)):
            assert bytes([block["revision"], block["selector"], *block["data"]]).hex() == read["response_data"]
            assert block["selector"] == selector
        if moon_only:
            record("getsysinfo." + name, "PASS_MOON_BOUNDARY_ONLY", [moon_id], typed_value=value,
                   scope="no reference execution: high-bit text or 255-byte buffer boundary; no differential pass claimed")
            return
        model = Identity("sysinfo", data, parameter=parameter, encoding=encoding, fault=fault)
        ref, ref_id = run(model, False)
        assert ref.returncode == 0 and not ref.stderr, ref
        status = "PASS_PROJECTION"
        if len(data) == 128 and model.reads == 1:
            expected = data[:14].decode("ascii") + "\n"
            status = "DIVERGENT_REFERENCE_CHAR_LENGTH"
        elif fault == "padding":
            expected = "abcX\n"
            status = "DIVERGENT_DECLARED_LENGTH"
        else:
            expected = data.split(b"\0")[0].decode("ascii") + "\n"
            if b"\0" in data:
                status = "DIVERGENT_NUL_DISPLAY"
            elif encoding & 15:
                status = "DIVERGENT_ENCODING_READS"
        expected_reads = (2 if parameter == 0xde else 4) if encoding & 15 else max(1, (len(data) + 17) // 16)
        if status == "DIVERGENT_REFERENCE_CHAR_LENGTH":
            expected_reads = 1
        assert model.reads == expected_reads and ref.stdout == expected, (name, model.reads, ref.stdout, expected)
        record("getsysinfo." + name, status, [moon_id, ref_id], typed_value=value,
               reference_read_count=model.reads, reference_stdout=ref.stdout)

    for parameter in PARAMETERS:
        sys_case("parameter-" + str(parameter), b"synthetic-system-value", parameter)
    for length in (0, 1, 14, 15, 30, 31, 62, 63, 127, 128):
        sys_case("length-" + str(length), bytes(65 + i % 26 for i in range(length)))
    sys_case("encoding-upper-bits", b"synthetic", encoding=0xf0)
    sys_case("embedded-nul", b"abc\0def")
    sys_case("nonzero-padding", b"abc", fault="padding")
    sys_case("encoding-1", b"synthetic", encoding=1)
    sys_case("encoding-2-url", b"synthetic", parameter=0xde, encoding=2)
    sys_case("maximum-255", b"X" * 255, moon_only=True)
    sys_case("non-ascii", b"\xff\x80", moon_only=True)

    for kind in ("guid", "sysinfo"):
        for completion in ((0xc1, 0xd4) if kind == "guid" else (0x80, 0xc1, 0xd4)):
            ids = []
            for moon in (True, False):
                result, execution_id = run(Identity(kind, b"", completion=completion), moon)
                assert not result.stdout.startswith("{")
                if moon:
                    assert result.returncode > 0
                    assert f"completion code {completion}" in result.stdout + result.stderr
                elif kind == "sysinfo":
                    assert result.returncode == 0 and result.stdout == "\n"
                    expected_error = "parameter not supported" if completion == 0x80 else "command failed:"
                    assert expected_error in result.stderr
                else:
                    assert result.returncode > 0
                ids.append(execution_id)
            record(f"{'getsysinfo' if kind == 'sysinfo' else kind}.completion-{completion:02x}",
                   "DIVERGENT_COMPLETION_EXIT" if kind == "sysinfo" else "PASS_REJECTION_PROJECTION", ids,
                   scope=("System Info positive completion errors produce reference exit zero and stderr; API raises, CLI policy unresolved"
                          if kind == "sysinfo" else "GUID completion rejection only; error text and cleanup remain API/CLI contracts"))

    for fault in ("selector", "revision", "short", "extra", "second-error"):
        ids = []
        data = b"X" * 31
        for moon in (True, False):
            result, execution_id = run(Identity("sysinfo", data, fault=fault), moon)
            if moon:
                assert result.returncode > 0 and not result.stdout.startswith("{")
                expected = {"selector": "selector mismatch", "revision": "revision changed", "short": "must contain 18",
                            "extra": "must contain 18", "second-error": "completion code 193"}[fault]
                assert expected in result.stdout + result.stderr
            else:
                assert result.returncode == 0
                assert bool(result.stderr) == (fault == "second-error")
                assert result.stdout == ("X" * 14 if fault == "second-error" else "X" * 13 if fault == "short" else "X" * 31) + "\n"
            ids.append(execution_id)
        record("getsysinfo." + fault, "DIVERGENT_PARTIAL_FAILURE" if fault == "second-error" else "DIVERGENT_VALIDATION", ids)

    for name, limit, timeout, fault, expected, reads in [
        ("byte-limit", 13, 10000, None, "exceeds byte limit", 1),
        ("negative-limit", -1, 10000, None, "byte limit", 0),
        ("oversized-limit", 256, 10000, None, "byte limit", 0),
        ("zero-timeout", 255, 0, None, "overall timeout", 0),
        ("oversized-timeout", 255, 60001, None, "overall timeout", 0),
        ("whole-deadline", 255, 200, "slow", "operation did not complete", 2),
    ]:
        model = Identity("sysinfo", b"X" * 63, fault=fault)
        result, execution_id = run(model, True, limit=limit, timeout=timeout)
        assert result.returncode > 0 and expected in result.stdout + result.stderr
        assert not result.stdout.startswith("{") and model.reads <= reads
        if fault != "slow":
            assert model.reads == reads
        else:
            assert 1 <= model.reads <= 2 and executions[execution_id]["elapsed_seconds"] < 2
        record("getsysinfo." + name, "PASS_MOON_BOUNDARY_ONLY", [execution_id])

    assert datetime.now(timezone.utc).year == year, "UTC year changed; repeat to freeze GUID auto-detection inputs"
    assert len({row["id"] for row in leaves}) == len(leaves), "leaf identifiers must be unique"
    summary = {status: sum(row["status"] == status for row in leaves) for status in sorted({row["status"] for row in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "GUID and six string reads on loopback suite17/User; output projections do not establish CLI/default/hardware equivalence",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "guid_detection_utc_year": year, "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; known differences retained; no hardware contacted")


if __name__ == "__main__":
    main()
