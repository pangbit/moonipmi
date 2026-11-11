#!/usr/bin/env python3
"""Compare bounded read-only diagnostics with ipmitool 1.8.19, no real BMC."""
import argparse
import json
import os
import shutil
import socket
import subprocess
import threading
import time

import diagnostics_fixture as fixture
import shared_bmc


def execute(executable, mode, *, moon=False, fault=None, word=False):
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
            result = subprocess.run(args, capture_output=True, text=True, timeout=15,
                                    env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
        finally:
            stop.set()
            thread.join(timeout=2)
        elapsed = time.monotonic() - start
        assert not thread.is_alive() and not errors, (errors, result.stdout, result.stderr)
    assert trace["authenticated"]
    return result, trace, elapsed


def parsed(result):
    return [json.loads(line) for line in result.stdout.splitlines()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    ipmitool = shutil.which("ipmitool")
    assert ipmitool, "ipmitool is required"
    version = subprocess.check_output([ipmitool, "-V"], text=True).strip()
    assert version == "ipmitool version 1.8.19"
    results = []

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
                        "fault": fault, "output": result.stdout, "trace": trace, "elapsed_seconds": elapsed})
        print(f"PASS: {'moonipmi' if moon else 'ipmitool'} {mode} word={word} fault={fault}")
        return result

    chassis = parsed(success("chassis", moon=True))[0]
    assert chassis == {"flags": 15, "fru_address": 32, "sdr_address": 32, "sel_address": 32,
                       "system_management_address": 32, "bridge_address": 0, "power_on": True,
                       "restart_cause": 4, "restart_channel": 1}
    assert bytes.fromhex(success("raw 0x00 0x00").stdout) == fixture.CAPABILITIES
    assert "System Power" in success("chassis status").stdout
    assert "watchdog" in success("chassis restart_cause").stdout.lower()
    for word in (False, True):
        inventory = parsed(success("fru", moon=True, word=word))
        assert [r["fields"] for r in inventory] == [fixture.CHASSIS_FIELDS, fixture.BOARD_FIELDS, fixture.PRODUCT_FIELDS]
        assert all(r["size_bytes"] == len(fixture.FRU) for r in inventory)
        assert inventory[0]["chassis_type"] == 23 and inventory[1]["manufacturing_minutes"] == 0
        output = success("fru print 0", word=word).stdout
        for field in fixture.CHASSIS_FIELDS + fixture.BOARD_FIELDS + fixture.PRODUCT_FIELDS:
            if field:
                assert field in output, (field, output)
    for word in (False, True):
        assert parsed(success("fru", moon=True, word=word, fault="fru-short"))[2]["fields"] == fixture.PRODUCT_FIELDS
    records = parsed(success("sel", moon=True))
    assert records[0] == {"id": 1, "type": 2, "timestamp": 1700000000, "generator_id": 32,
        "revision": 4, "sensor_type": 1, "sensor_number": 48, "event_type": 1, "deassertion": False,
        "event_data": [9, 0, 0], "threshold": "Upper Critical going high"}
    assert records[1]["timestamp"] == 0xffffffff and records[1]["deassertion"] is True and records[1]["threshold"] is None
    assert bytes(records[2]["raw"]) == fixture.SEL_RECORDS[2]
    info = success("sel info").stdout
    assert "3" in info and "1.5" in info
    listing = success("sel list").stdout
    assert "Upper Critical going high" in listing and "Chassis" in listing
    for record in fixture.SEL_RECORDS:
        response = bytes.fromhex(success(f"raw 0x0a 0x43 0 0 {record[0]} 0 0 255").stdout)
        assert response[2:] == record
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
        results.append({"fault": fault, "result": "rejected", "trace": trace, "elapsed_seconds": elapsed})
        print(f"PASS: {fault}: rejected without partial inventory")
    if args.output:
        with open(args.output, "w") as out:
            json.dump({"scope": "synthetic suite-17 loopback only; no hardware validation", "baseline": version, "results": results}, out, indent=2)
            out.write("\n")
    print(f"PASS: {len(results)} focused diagnostics comparisons/boundaries; no hardware contacted")


if __name__ == "__main__":
    main()
