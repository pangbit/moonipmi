#!/usr/bin/env python3
"""Compare actual read-only management APIs with a fixed ipmitool build on loopback."""
import argparse
import json
import struct

from diagnostics_check import execute
import reference_profile

COMMANDS = {"self-test": (6, 4, 2), "enables": (6, 0x2f, 1),
            "watchdog": (6, 0x25, 8), "poh": (0, 0x0f, 5)}
REFERENCE_COMMAND = {"self-test": "mc selftest", "enables": "mc getenables",
                     "watchdog": "mc watchdog get", "poh": "chassis poh"}
GROUPS = {"self-test": "C08.selftest", "enables": "C08.getenables", "watchdog": "C08.watchdog.get", "poh": "C05.poh"}
ENABLE_FIELDS = [(0, "receive_message_queue_interrupt", "Receive Message Queue Interrupt"),
                 (1, "event_message_buffer_full_interrupt", "Event Message Buffer Full Interrupt"),
                 (2, "event_message_buffer", "Event Message Buffer"), (3, "system_event_logging", "System Event Logging"),
                 (5, "oem0", "OEM 0"), (6, "oem1", "OEM 1"), (7, "oem2", "OEM 2")]
USES = ["Reserved", "BIOS FRB2", "BIOS/POST", "OS Load", "SMS/OS", "OEM", "Reserved", "Reserved"]
MC_FAILURES = ["controller operational firmware corrupted", "Controller update boot block corrupted",
               "Internal Use Area corrupted", "SDR repository empty", "IPMB signal lines do not respond",
               "FRU device not accessible", " -> SDR repository not accessible", " -> SEL device not accessible"]
CHASSIS_FAILURES = ["firmware corrupted", "boot block corrupted", "FRU Internal Use Area corrupted",
                    "SDR Repository empty", "IPMB not responding", "cannot access BMC FRU",
                    "cannot access SDR Repository", "cannot access SEL Device"]


class Management:
    def __init__(self, mode, data, completion=0):
        self.command_id = COMMANDS[mode][:2]
        self.data, self.completion = data, completion

    def command(self, netfn, command, request):
        if (netfn, command) == self.command_id:
            assert request == b"", "management reads have no request parameters"
            return self.data, self.completion
        return None


def selftest_projection(value, chassis=False):
    code, detail = value["code"], value["detail"]
    assert value["status"] == {0x55: "passed", 0x56: "not-implemented", 0x57: "corrupted",
                               0x58: "fatal", 0xff: "reserved"}.get(code, "device-specific")
    assert value["corruption_flags"] == (detail if code == 0x57 else None)
    if chassis:
        text = "Self Test Results    : "
        if code in (0x55, 0x56):
            text += "passed\n" if code == 0x55 else "not implemented\n"
        elif code == 0x57:
            text += "device error\n" + "".join(" " * 23 + f"[{label}]\n" for bit, label in enumerate(CHASSIS_FAILURES) if detail & (1 << bit))
        elif code == 0x58:
            text += f"Fatal hardware error: {detail:02x}h\n"
        else:
            text += f"Device-specific failure {code:02x}h:{detail:02x}h\n"
        return text, 0
    if code == 0x55:
        return "Selftest: passed\n", 0
    if code == 0x56:
        return "Selftest: not implemented\n", 1
    if code == 0x57:
        return "Selftest: device corrupted\n" + "".join(MC_FAILURES[bit] + "\n" for bit in range(7, -1, -1) if detail & (1 << bit)), 1
    if code == 0x58:
        return f"Selftest     : fatal error\nFailure code : {detail:02x}\n", 1
    if code == 0xff:
        return "Selftest: N/A", 1
    return f"Selftest     : device specific ({code:02X}h)\nFailure code : {detail:02X}h\n", 0


def watchdog_projection(value):
    raw = bytes(value["raw"])
    reconstructed = struct.pack("<BBBBHH", value["timer_use"] | (0x40 if value["running"] else 0) |
        (0 if value["logging_enabled"] else 0x80) | (raw[0] & 0x38),
        value["timeout_action"] | (value["pre_timeout_interrupt"] << 4) | (raw[1] & 0x88),
        value["pre_timeout_seconds"], value["expiration_flags"], value["initial_countdown_tenths"], value["present_countdown_tenths"])
    assert reconstructed == raw
    assert value["initial_countdown_seconds"] == value["initial_countdown_tenths"] / 10
    assert value["present_countdown_seconds"] == value["present_countdown_tenths"] / 10
    text = (f"Watchdog Timer Use:     {value['timer_use_description']} (0x{raw[0]:02x})\n"
            f"Watchdog Timer Is:      {'Started/Running' if value['running'] else 'Stopped'}\n"
            f"Watchdog Timer Logging: {'On' if value['logging_enabled'] else 'Off'}\n"
            f"Watchdog Timer Action:  {value['timeout_action_description']} (0x{raw[1]:02x})\n"
            f"Pre-timeout interrupt:  {value['pre_timeout_interrupt_description']}\n"
            f"Pre-timeout interval:   {value['pre_timeout_seconds']} seconds\n"
            f"Timer Expiration Flags: {'' if value['expiration_flags'] else 'None '}(0x{value['expiration_flags']:02x})\n")
    text += "".join(" " * 24 + f"* {USES[bit]}\n" for bit in range(8) if value["expiration_flags"] & (1 << bit))
    return text + f"Initial Countdown:      {value['initial_countdown_seconds']:.1f} sec\nPresent Countdown:      {value['present_countdown_seconds']:.1f} sec\n"


def poh_projection(value):
    days, remainder = divmod(value["total_minutes"], 1440)
    hours, minutes = divmod(remainder, 60)
    text = f"POH Counter  : {days} days, {hours} hours"
    return text + (f", {minutes} minutes" if value["minutes_per_count"] < 60 else "") + "\n"


def valid_cases():
    for code, detail in [(0x55, 0), (0x56, 0), (0x58, 0xa5), (0xff, 0xa5), (0x99, 0xa5)] + [
            (0x57, flag) for flag in [0, *[1 << bit for bit in range(8)], 255]]:
        yield "self-test", f"{code:02x}-{detail:02x}", bytes([code, detail])
    for flags in [0, 255, *[1 << bit for bit in range(8)]]:
        yield "enables", f"flags-{flags:02x}", bytes([flags])
    for index in range(8):
        yield "watchdog", f"fields-{index}", struct.pack("<BBBBHH", index | (0x40 if index % 2 else 0) |
            (0x80 if index % 3 else 0), index | ((7-index) << 4), index * 30, 1 << index, 1000 + index, 257 + index)
    yield "watchdog", "zero", bytes(8)
    yield "watchdog", "maximum-reserved", bytes([255]) * 8
    for unit, count in [(0, 0xffffffff), (1, 0), (1, 1501), (15, 12345), (60, 50), (255, 17), (1, 16777217)]:
        yield "poh", f"unit-{unit}-count-{count}", struct.pack("<BI", unit, count)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", required=True)
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    executions, leaves = [], []

    def run(mode, data, *, moon, command=None, completion=0):
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool,
            mode if moon else command or REFERENCE_COMMAND[mode], moon=moon, model=Management(mode, data, completion))
        target = COMMANDS[mode][:2]
        allowed = {target, (6, 0x3b), (6, 0x3c)}
        if not moon:
            allowed |= {(6, 1), (0x2c, 0), (0x2c, 0x3e)}
        assert all((r["netfn"], r["command"]) in allowed for r in trace["commands"]), trace
        reads = [r for r in trace["commands"] if (r["netfn"], r["command"]) == target]
        assert len(reads) == 1 and reads[0]["request_data"] == "" and reads[0]["completion"] == completion
        execution_id = len(executions)
        executions.append({"id": execution_id, "client": "moonipmi" if moon else "ipmitool", "argv": result.args,
                           "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode,
                           "trace": trace, "elapsed_seconds": elapsed})
        return result, trace, execution_id

    for mode, name, data in valid_cases():
        moon, trace, moon_id = run(mode, data, moon=True)
        assert moon.returncode == 0 and trace["closed"] and not moon.stderr
        value = json.loads(moon.stdout)
        if mode == "self-test":
            assert bytes([value["code"], value["detail"]]) == data
            projections = [("mc selftest", *selftest_projection(value)), ("chassis selftest", *selftest_projection(value, True))]
        elif mode == "enables":
            assert value["flags"] == data[0]
            projections = [("mc getenables", "".join(f"{label:<40} : {'enabled' if value[field] else 'disabled'}\n"
                                                    for _, field, label in ENABLE_FIELDS), 0)]
        elif mode == "watchdog":
            assert bytes(value["raw"]) == data
            projections = [("mc watchdog get", watchdog_projection(value), 0)]
        else:
            assert struct.pack("<BI", value["minutes_per_count"], value["count"]) == data
            assert value["total_minutes"] == value["minutes_per_count"] * value["count"]
            projections = [("chassis poh", poh_projection(value), 0)]
        for command, projected, expected_exit in projections:
            result, trace, ref_id = run(mode, data, moon=False, command=command)
            assert trace["closed"] and result.returncode == expected_exit and not result.stderr
            group = "C05.selftest" if command == "chassis selftest" else GROUPS[mode]
            row = {"id": group + "." + name, "status": "PASS_PROJECTION", "executions": [moon_id, ref_id],
                   "typed_value": value, "projected_stdout": projected, "reference_stdout": result.stdout,
                   "reference_exit_code": result.returncode}
            if mode == "poh" and value["count"] == 16777217:
                assert result.stdout == "POH Counter  : 11650 days, 20 hours, 16 minutes\n"
                assert projected == "POH Counter  : 11650 days, 20 hours, 17 minutes\n"
                raw, _, raw_id = run(mode, data, moon=False, command="raw 0x00 0x0f")
                assert raw.returncode == 0 and bytes.fromhex(raw.stdout) == data
                row.update(status="DIVERGENT_DISPLAY_PRECISION", raw_reference_execution=raw_id,
                           reason="Reference float32 display loses one minute; API retains exact raw counter and UInt64 minutes. K10 review remains open.")
            else:
                assert result.stdout == projected, (row["id"], repr(result.stdout), repr(projected))
            leaves.append(row)
            print(row["status"] + ": " + row["id"], flush=True)

    for mode, (netfn, command, size) in COMMANDS.items():
        for completion in (0xc1, 0xd4):
            ids = []
            for moon in (True, False):
                result, _, execution_id = run(mode, b"", moon=moon, completion=completion)
                assert result.returncode > 0 and not any(line.startswith("{") for line in result.stdout.splitlines())
                if moon:
                    assert f"completion code {completion}" in result.stdout + result.stderr
                ids.append(execution_id)
            leaves.append({"id": GROUPS[mode] + f".completion-{completion:02x}", "status": "PASS_REJECTION_PROJECTION",
                           "executions": ids, "scope": "same completion failure; errors/cleanup remain distinct API versus CLI behavior"})
        for length in sorted({0, size - 1, size + 1}):
            result, _, execution_id = run(mode, bytes(length), moon=True)
            assert result.returncode > 0 and "must contain" in result.stdout + result.stderr
            assert not any(line.startswith("{") for line in result.stdout.splitlines())
            leaves.append({"id": GROUPS[mode] + f".length-{length}", "status": "PASS_MOON_BOUNDARY_ONLY",
                           "executions": [execution_id], "scope": "reference unchecked short-buffer reads are not executed or treated as parity"})
    summary = {status: sum(row["status"] == status for row in leaves) for status in sorted({row["status"] for row in leaves})}
    with open(args.output, "w") as out:
        json.dump({"scope": "four read-only library APIs; synthetic suite17/User loopback; projections do not establish compatible CLI, defaults or hardware behavior",
                   "reference": reference, "implementation": reference_profile.implementation(args.moon_client),
                   "summary": summary, "leaves": leaves, "executions": executions}, out, indent=2)
        out.write("\n")
    print(f"RESULT: {summary}; {len(executions)} executions; known divergence retained; no hardware contacted")


if __name__ == "__main__":
    main()
