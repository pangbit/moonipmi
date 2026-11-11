#!/usr/bin/env python3
"""Run real ipmitool sdr/sensor commands and moonipmi against one synthetic BMC."""
import argparse
import csv
import json
import os
import shutil
import socket
import subprocess
import threading

import sdr_fixture
import shared_bmc


def execute(executable, mode, fault=None):
    trace = {"authenticated": False, "closed": False, "commands": []}
    repository = sdr_fixture.Repository(fault)
    errors = []
    stop = threading.Event()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(0.1)
        port = server.getsockname()[1]

        def worker():
            try:
                shared_bmc.serve(server, stop, trace, command_handler=repository.command, max_exchanges=256)
            except shared_bmc.Stopped:
                pass
            except Exception as error:
                errors.append(f"{type(error).__name__}: {error}")

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        args = [executable, str(port)] if mode == "moonipmi" else [
            executable, "-I", "lanplus", "-C", "17", "-L", "USER", "-U", "tester",
            "-P", "synthetic-password", "-H", "127.0.0.1", "-p", str(port),
            "-N", "1", "-R", "1", "-c", *mode.split(),
        ]
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=20,
                                    env={**os.environ, "LC_ALL": "C"})
        finally:
            stop.set()
            thread.join(timeout=2)
        assert not thread.is_alive(), "fixture did not stop"
        assert not errors, f"{mode}/{fault}: fixture error {errors}\n{result.stdout}\n{result.stderr}"
    return result, trace, repository


EXPECTED = {
    "Temp": {"value": 42.0, "unit": "degrees C", "status": "ok"},
    "Voltage": {"value": 12.0, "unit": "Volts", "status": "ok"},
    "Fan": {"value": 6000.0, "unit": "RPM", "status": "ok"},
    "Power": {"value": 150.0, "unit": "Watts", "status": "ok"},
    "Signed": {"value": -10.0, "unit": "degrees C", "status": "ok"},
    "Ones": {"value": -10.0, "unit": "degrees C", "status": "ok"},
    "Unavailable": {"value": None, "unit": None, "status": "unavailable"},
    "Disabled": {"value": None, "unit": None, "status": "unavailable"},
    "EventsOff": {"value": 42.0, "unit": "degrees C", "status": "ok"},
    "Critical": {"value": 80.0, "unit": "degrees C", "status": "cr"},
    "Intrusion": {"value": None, "unit": None, "status": "discrete-bit-0"},
}
FAULTS = {
    "limit": "SDR repository exceeds record limit",
    "no-reservation": "SDR reservation support is required",
    "lost-reservation": "Get SDR failed (completion code 197)",
    "cycle": "SDR record identity mismatch or repeated record",
    "early-end": "SDR chain ended before advertised record count",
    "changed-next": "SDR next-record ID changed during read",
    "short-chunk": "Get SDR chunk length mismatch",
    "wrong-id": "SDR record identity mismatch or repeated record",
}


def normalize(mode, output):
    normalized = {}
    for line in output.splitlines():
        if mode == "moonipmi":
            row = json.loads(line)
            name, value, unit, status = (row[k] for k in ("name", "value", "unit", "status"))
            if name == "Intrusion":
                assert row["record_type"] == 2 and row["state_bits"] == 1 and row["value_kind"] == "discrete"
                status = "discrete-bit-0"
            elif name == "Critical":
                assert row["state_bits"] == 16
            elif name in ("Unavailable", "Disabled"):
                assert row["state_bits"] is None
                assert row["value_kind"] == {"Unavailable": "unavailable", "Disabled": "scanning-disabled"}[name]
            else:
                assert row["record_type"] == 1 and row["state_bits"] == 0 and row["value_kind"] == "numeric"
            if value is None:
                unit = None
        else:
            row = next(csv.reader([line]))
            name = row[0]
            if name == "Intrusion":
                if mode == "sdr list all":
                    assert row == ["Intrusion", "3Ah", "ok", "7.1", "General Chassis intrusion"]
                else:
                    # ipmitool prints data2 then data3 as hex, not a LE integer.
                    assert row[:4] == ["Intrusion", "0x0", "discrete", "0x0100"]
                value, unit, status = None, None, "discrete-bit-0"
            elif row[1] in ("", "na"):
                assert row[3] in ("na", "ns")
                value, unit, status = None, None, "unavailable"
            else:
                value, unit, status = float(row[1]), row[2], row[3]
            if mode == "sensor list":
                assert len(row) == 10 and row[4:] == ["na"] * 6, "threshold settings are outside this comparison"
        assert name not in normalized, "duplicate sensor name in fixture output"
        normalized[name] = {"value": value, "unit": unit, "status": status}
    return normalized


def verify_trace(trace, repository, mode):
    assert trace["authenticated"] and trace["closed"]
    commands = trace["commands"]
    assert any((c["netfn"], c["command"]) == (0x0a, 0x20) for c in commands)
    assert any((c["netfn"], c["command"]) == (0x0a, 0x22) for c in commands)
    reads = [c for c in commands if (c["netfn"], c["command"]) == (0x0a, 0x23)]
    ids = {int.from_bytes(bytes.fromhex(c["request_data"])[2:4], "little") for c in reads}
    assert ids - {0} == set(repository.ids), "every record must actually be retrieved"
    assert repository.partial_reads > len(repository.ids)
    sensors = [c["request_data"] for c in commands if (c["netfn"], c["command"]) == (4, 0x2d)]
    assert sensors == [f"{number:02x}" for number in sdr_fixture.READINGS]
    assert all(c["completion"] == 0 for c in commands if c["netfn"] != 0x2c)
    if mode == "moonipmi":
        assert all(bytes.fromhex(c["request_data"])[5] <= 16 for c in reads)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    executable = shutil.which("ipmitool")
    assert executable, "ipmitool is required"
    version = subprocess.check_output([executable, "-V"], text=True).strip()
    assert version == "ipmitool version 1.8.19", "review another version before changing the baseline"
    rows = []
    for mode, client in [("moonipmi", args.moon_client), ("sdr list all", executable), ("sensor list", executable)]:
        result, trace, repository = execute(client, mode)
        assert result.returncode == 0, f"{mode}: {result.stdout} {result.stderr}"
        verify_trace(trace, repository, mode)
        normalized = normalize(mode, result.stdout)
        assert normalized == EXPECTED, f"{mode}: field mismatch: {normalized}"
        rows.append({"mode": mode, "result": normalized, "observed_output": result.stdout, "trace": trace})
        print(f"PASS: {mode}: {len(normalized)} SDR-backed readings, authenticated traversal and close")
    faults = []
    for fault, expected_error in FAULTS.items():
        result, trace, _ = execute(args.moon_client, "moonipmi", fault)
        assert result.returncode != 0 and expected_error in result.stdout + result.stderr, (fault, result.stdout, result.stderr)
        assert trace["authenticated"]
        assert not any((c["netfn"], c["command"]) == (4, 0x2d) for c in trace["commands"]), "must not return a partial inventory"
        if fault in ("limit", "no-reservation"):
            assert not any(c["command"] in (0x22, 0x23) and c["netfn"] == 0x0a for c in trace["commands"])
        faults.append({"fault": fault, "classification": "rejected", "trace": trace})
        print(f"PASS: moonipmi/{fault}: rejected without partial inventory")
    result, trace, _ = execute(args.moon_client, "moonipmi", "empty")
    assert result.returncode == 0 and not result.stdout.strip() and trace["closed"]
    assert not any(c["netfn"] == 0x0a and c["command"] != 0x20 for c in trace["commands"]), "empty repository must not be rebuilt or reserved"
    print("PASS: moonipmi/empty: empty inventory, no rebuild or reservation")
    report = {"scope": "synthetic suite-17 loopback; not real BMC validation",
              "ipmitool_version": version, "readings": rows, "faults": faults, "empty_repository": "passed"}
    if args.output:
        with open(args.output, "w") as output:
            json.dump(report, output, indent=2)
            output.write("\n")
    print("PASS: 33 SDR-backed output comparisons and 9 repository boundary scenarios; no hardware contacted")


if __name__ == "__main__":
    main()
