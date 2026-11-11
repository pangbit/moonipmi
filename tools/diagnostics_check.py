#!/usr/bin/env python3
"""Compare bounded read-only diagnostics with ipmitool 1.8.19, no real BMC."""
import argparse
import json
import socket
import subprocess
import threading
import time

import diagnostics_fixture as fixture
import shared_bmc
import reference_profile


def execute(executable, mode, *, moon=False, fault=None, word=False, cwd=None):
    trace = {"authenticated": False, "closed": False, "commands": []}
    model = fixture.Diagnostics(fault, word)
    errors = []
    stop = threading.Event()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(0.1)
        port = server.getsockname()[1]

        def worker():
            try:
                shared_bmc.serve(server, stop, trace, command_handler=model.command, max_exchanges=192)
            except shared_bmc.Stopped:
                pass
            except Exception as error:
                errors.append(f"{type(error).__name__}: {error}")

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        args = [executable, str(port), mode] if moon else [executable, "-I", "lanplus", "-C", "17",
            "-L", "USER", "-U", "tester", "-P", "synthetic-password", "-H", "127.0.0.1",
            "-p", str(port), "-N", "1", "-R", "1", *mode.split()]
        start = time.monotonic()
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=15, cwd=cwd, stdin=subprocess.DEVNULL,
                                    env=reference_profile.environment())
        finally:
            stop.set()
            thread.join(timeout=2)
        elapsed = time.monotonic() - start
        assert not thread.is_alive() and not errors, (errors, result.stdout, result.stderr)
    assert trace["authenticated"], (result.returncode, result.stdout, result.stderr)
    return result, trace, elapsed


def parsed(result):
    return [json.loads(line) for line in result.stdout.splitlines()]


def fields(output):
    pairs = [line.split(":", 1) for line in output.splitlines() if ":" in line]
    result = {key.strip(): value.strip() for key, value in pairs}
    assert len(result) == len(pairs), "duplicate labels must not be silently discarded"
    return result


def chassis_fields(value):
    result = {
        "System Power": "on" if value["power_on"] else "off",
        "Power Overload": str(value["power_overload"]).lower(),
        "Power Interlock": "active" if value["power_interlock"] else "inactive",
        "Main Power Fault": str(value["power_fault"]).lower(),
        "Power Control Fault": str(value["power_control_fault"]).lower(),
        "Power Restore Policy": ["always-off", "previous", "always-on", "unknown"][value["restore_policy"]],
        "Last Power Event": " ".join(label for bit, label in enumerate(
            ["ac-failed", "overload", "interlock", "fault", "command"]) if value["last_power_event"] & (1 << bit)),
    }
    for bit, label in enumerate(["Chassis Intrusion", "Front-Panel Lockout", "Drive Fault", "Cooling/Fan Fault"]):
        enabled = bool(value["misc_status"] & (1 << bit))
        result[label] = ("active" if enabled else "inactive") if bit < 2 else str(enabled).lower()
    buttons = value["front_panel_buttons"]
    if buttons == 0:
        result["Front Panel Control"] = "none"
    elif buttons is not None:
        for bit, label in enumerate(["Power", "Reset", "Diag", "Sleep"]):
            result[label + " Button Disable"] = "allowed" if buttons & (16 << bit) else "not allowed"
            result[label + " Button Disabled"] = str(bool(buttons & (1 << bit))).lower()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output")
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    version = reference["version"]
    results = []
    comparisons = []

    def compare(case_id, actual, expected, scope):
        assert actual == expected, (case_id, actual, expected)
        comparisons.append({"id": case_id, "status": "PASS_PROJECTION", "scope": scope,
                            "actual": actual.hex() if isinstance(actual, bytes) else actual,
                            "expected": expected.hex() if isinstance(expected, bytes) else expected})

    def success(mode, *, moon=False, word=False, fault=None):
        result, trace, elapsed = execute(args.moon_client if moon else ipmitool, mode,
                                        moon=moon, word=word, fault=fault)
        assert result.returncode == 0 and trace["closed"], (mode, result.stdout, result.stderr)
        if moon:
            allowed = {(6, 0x3b), (6, 0x3c), (0, 0), (0, 1), (0, 7), (10, 0x10), (10, 0x11), (10, 0x40), (10, 0x43)}
            assert all((c["netfn"], c["command"]) in allowed for c in trace["commands"])
            fru_reads = [bytes.fromhex(c["request_data"]) for c in trace["commands"] if (c["netfn"], c["command"]) == (10, 0x11)]
            assert all(0 < read[3] <= 16 for read in fru_reads)
        results.append({"client": "moonipmi" if moon else "ipmitool", "mode": mode, "word_access": word,
                        "fault": fault, "argv": result.args, "exit_code": result.returncode,
                        "output": result.stdout, "stderr": result.stderr, "trace": trace, "elapsed_seconds": elapsed})
        print(f"PASS: {'moonipmi' if moon else 'ipmitool'} {mode} word={word} fault={fault}")
        return result

    for variant in fixture.CHASSIS_VARIANTS:
        chassis = parsed(success("chassis", moon=True, fault=variant))[0]
        compare("C05.status." + variant, chassis_fields(chassis),
                fields(success("chassis status", fault=variant).stdout), "all printed chassis status fields; typed API projection")
    capabilities = bytes.fromhex(success("raw 0x00 0x00").stdout)
    compare("C05.capabilities.raw", [chassis[key] for key in ("flags", "fru_address", "sdr_address", "sel_address",
            "system_management_address", "bridge_address")], list(capabilities), "all six capability bytes via reference raw")
    for cause in range(12):
        variant = f"restart-{cause}"
        value = parsed(success("chassis", moon=True, fault=variant))[0]
        assert value["restart_cause"] == cause and value["restart_channel"] == 1
        compare(f"C05.restart-cause.{cause}", "System restart cause: " + value["restart_description"] + "\n",
                success("chassis restart_cause", fault=variant).stdout, "complete reference stdout versus documented description projection")
    for word in (False, True):
        inventory = parsed(success("fru", moon=True, word=word))
        assert [r["fields"] for r in inventory] == [fixture.CHASSIS_FIELDS, fixture.BOARD_FIELDS, fixture.PRODUCT_FIELDS]
        assert all(r["size_bytes"] == len(fixture.FRU) for r in inventory)
        assert inventory[0]["chassis_type"] == 23 and inventory[1]["manufacturing_minutes"] == 0
        output = success("fru print 0", word=word).stdout
        expected = {"Chassis Type": "Rack Mount Chassis", "Chassis Part Number": inventory[0]["fields"][0],
                    "Chassis Serial": inventory[0]["fields"][1], "Board Mfg Date": "Unspecified"}
        expected.update(zip(["Board Mfg", "Board Product", "Board Serial", "Board Part Number"], inventory[1]["fields"][:4]))
        expected.update(zip(["Product Manufacturer", "Product Name", "Product Part Number", "Product Version",
                             "Product Serial", "Product Asset Tag"], inventory[2]["fields"][:6]))
        compare("C12.print." + ("word" if word else "byte"), fields(output), expected,
                "all printed labels and values for the basic ASCII inventory; raw size and manufacturing epoch checked separately")
    for word in (False, True):
        assert parsed(success("fru", moon=True, word=word, fault="fru-short"))[2]["fields"] == fixture.PRODUCT_FIELDS
    records = parsed(success("sel", moon=True))
    assert records[0] == {"id": 1, "type": 2, "timestamp": 1700000000, "generator_id": 32,
        "revision": 4, "sensor_type": 1, "sensor_number": 48, "event_type": 1, "deassertion": False,
        "event_data": [9, 0, 0], "threshold": "Upper Critical going high"}
    assert records[1]["timestamp"] == 0xffffffff and records[1]["deassertion"] is True and records[1]["threshold"] is None
    assert bytes(records[2]["raw"]) == fixture.SEL_RECORDS[2]
    info = parsed(success("sel-info", moon=True))[0]
    assert info == {"version": 81, "entries": 3, "free_space": 65535, "last_addition": 1700000000,
                    "last_erase": 4294967295, "operations": 2}
    reference_info = fields(success("sel info").stdout)
    compare("C14.info.basic", reference_info, {
        "Version": "1.5 (v1.5, v2 compliant)", "Entries": str(info["entries"]),
        "Free Space": str(info["free_space"]) + " bytes or more", "Percent Used": "unknown",
        "Last Add Time": "11/14/23 22:13:20 UTC", "Last Del Time": "Not Available", "Overflow": "false", "Supported Cmds": "'Reserve'"},
        "all printed SEL info fields for fixed UTC fixture")
    info2 = parsed(success("sel-info", moon=True, fault="sel-version-2"))[0]
    assert info2 == {**info, "version": 2}
    compare("C14.info.version-2", fields(success("sel info", fault="sel-version-2").stdout), {
        **reference_info, "Version": "2.0 (v1.5, v2 compliant)"},
        "both accepted reference SEL version encodings; all other info fields unchanged")
    listing = success("sel list").stdout
    assert listing == (
        "   1 | 11/14/23 | 22:13:20 UTC | Temperature #0x30 | Upper Critical going high | Asserted\n"
        "   3 | Unspecified | Unspecified | Physical Security #0x3a | General Chassis intrusion | Deasserted\n"
        "   5 |  Pre-Init  |0000000000| OEM record c0 | 000157 | 010203040506\n")
    for record in fixture.SEL_RECORDS:
        response = bytes.fromhex(success(f"raw 0x0a 0x43 0 0 {record[0]} 0 0 255").stdout)
        compare(f"C14.get.raw.{record[0]}", response[2:], record, "complete record bytes via reference raw; typed fields checked against independent fixture")
    assert parsed(success("sel", moon=True, fault="sel-empty")) == []
    faults = {
        "fru-limit": "FRU inventory exceeds byte limit", "fru-zero": "FRU returned count",
        "fru-count": "FRU returned count", "fru-checksum": "FRU area checksum",
        "sel-limit": "SEL repository exceeds record limit", "sel-cycle": "SEL record identity",
        "sel-early": "SEL chain ended", "sel-id": "SEL record identity", "sel-short": "complete record",
        "sel-changed": "SEL repository changed", "sel-completion": "Get SEL Entry failed",
        "fru-timeout": "operation did not complete", "sel-timeout": "operation did not complete",
    }
    for fault, expected in faults.items():
        mode = fault if fault.endswith("timeout") else fault.split("-")[0]
        result, trace, elapsed = execute(args.moon_client, mode, moon=True, fault=fault)
        assert result.returncode != 0 and expected in result.stdout + result.stderr, (fault, result.stdout, result.stderr)
        assert not any(line.startswith("{") for line in result.stdout.splitlines()), "no partial inventory"
        if fault.endswith("limit"):
            assert not any((c["netfn"], c["command"]) in ((10, 0x11), (10, 0x43)) for c in trace["commands"])
        if fault.endswith("timeout"):
            assert elapsed < 1.5 and len(trace["commands"]) < 7, "overall deadline must stop traversal"
        results.append({"fault": fault, "result": "rejected", "argv": result.args, "exit_code": result.returncode,
                        "output": result.stdout, "stderr": result.stderr, "trace": trace, "elapsed_seconds": elapsed})
        print(f"PASS: {fault}: rejected without partial inventory")
    if args.output:
        with open(args.output, "w") as out:
            json.dump({"scope": "synthetic suite-17 loopback only; semantic projections are not full CLI/wire parity; no hardware validation",
                       "implementation": reference_profile.implementation(args.moon_client), "reference": reference, "baseline": version, "comparisons": comparisons, "results": results}, out, indent=2)
            out.write("\n")
    print(f"PASS: {len(comparisons)} differential projections; {len(results)} total executions including moon-only boundaries; no hardware contacted")


if __name__ == "__main__":
    main()
