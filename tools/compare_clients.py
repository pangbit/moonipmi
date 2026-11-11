#!/usr/bin/env python3
"""Compare explicitly supplied clients against the same synthetic loopback BMC."""
import argparse
import json
import re
import socket
import subprocess
import threading

import shared_bmc
import reference_profile

CASES = ("device", "device-extended", "chassis", "chassis-faults", "sensor", "sensor-unavailable",
         "sensor-disabled", "sensor-events-disabled", "bad-password", "completion")
EXPECTED = {
    "device": {"device_id": 18, "device_revision": 3, "firmware_major": 1,
               "firmware_minor": 23, "ipmi_major": 2, "ipmi_minor": 0,
               "manufacturer_id": 343, "product_id": 4660, "firmware_available": True,
               "provides_device_sdrs": False, "additional_device_support": 1, "auxiliary_firmware": None},
    "chassis": {"power_on": True, "power_overload": False, "power_interlock": False,
                "power_fault": False, "power_control_fault": False, "restore_policy": 0,
                "intrusion_active": False, "front_panel_lockout": False, "drive_fault": False, "cooling_fan_fault": False},
    "sensor": {"raw_reading": 42, "reading_available": True, "scanning_enabled": True,
               "events_enabled": True, "status_bits": [1], "usable_raw_reading": 42},
}

EXPECTED.update({
    "device-extended": {**EXPECTED["device"], "firmware_available": False, "provides_device_sdrs": True,
                        "additional_device_support": 255, "auxiliary_firmware": [1, 35, 69, 103]},
    "chassis-faults": {**EXPECTED["chassis"], "power_on": False, "power_overload": True, "power_fault": True,
                       "restore_policy": 2, "intrusion_active": True, "front_panel_lockout": True,
                       "drive_fault": True, "cooling_fan_fault": True},
    "sensor-unavailable": {**EXPECTED["sensor"], "raw_reading": 238, "reading_available": False,
                           "status_bits": [2], "usable_raw_reading": None},
    "sensor-disabled": {**EXPECTED["sensor"], "raw_reading": 238, "scanning_enabled": False,
                        "status_bits": [2], "usable_raw_reading": None},
    "sensor-events-disabled": {**EXPECTED["sensor"], "events_enabled": False},
})


def ipmitool_command(executable, port, case):
    password = "wrong-synthetic-key" if case == "bad-password" else "synthetic-password"
    args = [executable, "-I", "lanplus", "-C", "17", "-L", "USER", "-U", "tester", "-P", password,
            "-H", "127.0.0.1", "-p", str(port), "-N", "1", "-R", "0"]
    if case in ("device", "device-extended", "bad-password"):
        return args + ["mc", "info"]
    if case.startswith("chassis"):
        return args + ["chassis", "status"]
    return args + ["raw", "0x04", "0x2d", "0xfe" if case == "completion" else "0x2a"]


def normalize_ipmitool(case, out):
    if case.startswith("sensor"):
        data = bytes.fromhex(out)
        assert len(data) == 3
        return {"raw_reading": data[0], "reading_available": not bool(data[1] & 0x20),
                "scanning_enabled": bool(data[1] & 0x40), "events_enabled": bool(data[1] & 0x80),
                "status_bits": list(data[2:]),
                # Derived flag semantics, not an invocation of ipmitool sensor/SDR output.
                "usable_raw_reading": data[0] if (data[1] & 0x60) == 0x40 else None}
    fields = dict(line.split(":", 1) for line in out.splitlines() if ":" in line)
    fields = {key.strip(): value.strip() for key, value in fields.items()}
    if case.startswith("device"):
        major, minor = fields["Firmware Revision"].split(".")
        ipmi_major, ipmi_minor = fields["IPMI Version"].split(".")
        return {"device_id": int(fields["Device ID"]), "device_revision": int(fields["Device Revision"]),
                "firmware_major": int(major), "firmware_minor": int(minor),
                "ipmi_major": int(ipmi_major), "ipmi_minor": int(ipmi_minor),
                "manufacturer_id": int(fields["Manufacturer ID"]),
                "product_id": int(fields["Product ID"].split()[0]),
                "firmware_available": fields["Device Available"] == "yes",
                "provides_device_sdrs": fields["Provides Device SDRs"] == "yes",
                "additional_device_support": sum(1 << bit for bit, label in enumerate((
                    "Sensor Device", "SDR Repository Device", "SEL Device", "FRU Inventory Device",
                    "IPMB Event Receiver", "IPMB Event Generator", "Bridge", "Chassis Device"))
                    if label in {line.strip() for line in out.splitlines()}),
                "auxiliary_firmware": [int(value, 16) for value in re.findall(r"^\s+0x([0-9a-fA-F]{2})\s*$", out, re.MULTILINE)] or None}
    return {"power_on": fields["System Power"] == "on", "power_overload": fields["Power Overload"] == "true",
            "power_interlock": fields["Power Interlock"] == "active", "power_fault": fields["Main Power Fault"] == "true",
            "power_control_fault": fields["Power Control Fault"] == "true",
            "restore_policy": {"always-off": 0, "previous": 1, "always-on": 2}[fields["Power Restore Policy"]],
            "intrusion_active": fields["Chassis Intrusion"] == "active",
            "front_panel_lockout": fields["Front-Panel Lockout"] == "active",
            "drive_fault": fields["Drive Fault"] == "true", "cooling_fan_fault": fields["Cooling/Fan Fault"] == "true"}


def run_case(name, executable, case):
    trace = {"authenticated": False, "closed": False, "commands": []}
    errors = []
    stop = threading.Event()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(0.1)
        port = server.getsockname()[1]

        def worker():
            try:
                shared_bmc.serve(server, stop, trace, case)
            except shared_bmc.Stopped:
                pass
            except Exception as error:
                errors.append(f"{type(error).__name__}: {error}")

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        args = ipmitool_command(executable, port, case) if name == "ipmitool" else [executable, str(port), case]
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=8,
                                    env=reference_profile.environment())
        finally:
            stop.set()
            thread.join(timeout=2)
        assert not thread.is_alive(), "fixture did not stop"
        assert not errors, f"{name}/{case}: fixture error {errors}"
    if case == "bad-password":
        assert result.returncode > 0 and trace.get("rakp2_sent") and not trace["authenticated"], (
            f"{name}: wrong password must fail before session activation\n{result.stdout}\n{result.stderr}")
        assert re.search(r"rakp|hmac|authenticat|RMCP\+ session", result.stdout + result.stderr, re.IGNORECASE), "unrelated authentication failure"
        classification = "authentication-rejected"
        normalized = None
    elif case == "completion":
        assert result.returncode > 0 and trace["authenticated"]
        assert any(c["netfn"] == 4 and c["command"] == 0x2d and c["request_data"] == "fe" and c["completion"] == 0xcb for c in trace["commands"])
        marker = r"rsp=0xcb\b" if name == "ipmitool" else r"completion code 203\b"
        assert re.search(marker, result.stdout + result.stderr), f"{name}: client did not expose completion 0xcb"
        classification = "completion-rejected"
        normalized = {"completion_code": 0xcb}
    else:
        assert result.returncode == 0 and trace["authenticated"] and trace["closed"], (
            f"{name}/{case}: failed or did not close\n{result.stdout}\n{result.stderr}")
        target = {"device": (6, 1, ""), "chassis": (0, 1, ""), "sensor": (4, 0x2d, "2a")}[case.split("-")[0]]
        assert any((c["netfn"], c["command"], c["request_data"]) == target for c in trace["commands"])
        normalized = normalize_ipmitool(case, result.stdout) if name == "ipmitool" else json.loads(result.stdout)
        assert normalized == EXPECTED[case], f"{name}/{case}: field mismatch: {normalized}"
        classification = "matched"
    return {"client": name, "case": case, "classification": classification, "result": normalized,
            "trace": trace}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--go-client")
    parser.add_argument("--output", help="optional synthetic JSON report path")
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    ipmitool_version = reference["version"]
    clients = [("moonipmi", args.moon_client), ("ipmitool", ipmitool)]
    if args.go_client:
        clients.append(("go-ipmi", args.go_client))
    rows = []
    for name, executable in clients:
        for case in CASES:
            row = run_case(name, executable, case)
            rows.append(row)
            print(f"PASS: {name}/{case}: {row['classification']}")
    report = {"scope": "synthetic loopback, suite 17, three reads, representative status boundaries and two error cases; not hardware validation",
              "go_ipmi_revision": "d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6" if args.go_client else None,
              "implementation": reference_profile.implementation(args.moon_client), "reference": reference, "ipmitool_version": ipmitool_version, "cases": rows}
    if args.output:
        with open(args.output, "w") as output:
            json.dump(report, output, indent=2)
            output.write("\n")
    print(f"PASS: {len(rows)} comparisons across {len(clients)} clients; no hardware contacted")


if __name__ == "__main__":
    main()
