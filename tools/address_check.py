#!/usr/bin/env python3
"""Compare requester-address tolerance and retained checks with ipmitool 1.8.19.

Loopback-only authenticated suite-17 Device ID responses, synthetic data only.
Other than the MAC case, all mutations carry a valid session HMAC. No raw logs
or cryptographic material are written to the report.
"""
import argparse
import json
import socket
import subprocess
import threading

from compare_clients import EXPECTED, ipmitool_command, normalize_ipmitool
import shared_bmc
import reference_profile

CASES = (None, "requester-20", "requester-00", "requester-ff", "responder", "netfn",
         "requester-lun", "responder-lun", "sequence", "command", "checksum", "mac")
MOON_ERRORS = {
    "responder": "IPMI response address mismatch",
    "netfn": "IPMI response does not match request",
    "requester-lun": "IPMI response does not match request",
    "responder-lun": "IPMI response does not match request",
    "sequence": "IPMI response does not match request",
    "command": "IPMI response does not match request",
    "checksum": "invalid IPMI checksum",
    "mac": "packet integrity check failed",
}


def probe(name, executable, fault):
    trace = {"authenticated": False, "closed": False, "commands": []}
    errors = []
    stop = threading.Event()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("127.0.0.1", 0))
        server.settimeout(0.1)
        port = server.getsockname()[1]

        def worker():
            try:
                shared_bmc.serve(server, stop, trace, wire_fault=fault)
            except shared_bmc.Stopped:
                pass
            except Exception as error:
                errors.append(f"{type(error).__name__}: {error}")

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        command = (ipmitool_command(executable, port, "device") if name == "ipmitool"
                   else [executable, str(port), "device"])
        if name == "ipmitool":
            # lanplus treats -R 0 as the default retry count, not zero retries.
            command[command.index("-R") + 1] = "1"
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=8,
                                    env=reference_profile.environment())
        finally:
            stop.set()
            thread.join(timeout=2)
        assert not thread.is_alive(), "fixture failed to stop"
        assert not errors, f"{name}/{fault}: fixture error {errors}"
    assert trace["authenticated"], "probe failed before authentication"
    reads = [c for c in trace["commands"] if (c["netfn"], c["command"]) == (6, 1)]
    assert reads and all(c["requester_address"] == 0x81 for c in reads), "expected Device ID requester 0x81"
    if fault:
        assert trace.get("wire_fault") == fault, "fault was not injected"
    if fault in {"requester-20", "requester-00", "requester-ff"}:
        assert trace["response_requester"] == int(fault.split("-")[1], 16), "wrong requester mutation"
    return result, trace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon-client", required=True)
    parser.add_argument("--output", help="optional synthetic JSON report path")
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    ipmitool, reference = reference_profile.resolve(args)
    version = reference["version"]
    rows = []
    for name, executable in (("moonipmi", args.moon_client), ("ipmitool", ipmitool)):
        for fault in CASES:
            result, trace = probe(name, executable, fault)
            rejected = (fault in MOON_ERRORS if name == "moonipmi"
                        else fault in {"sequence", "command", "mac"})
            assert (result.returncode > 0 if rejected else result.returncode == 0), f"{name}/{fault}: unexpected outcome"
            if rejected:
                if name == "moonipmi":
                    assert f"FAIL: {MOON_ERRORS[fault]}" in result.stdout, f"{fault}: wrong rejection"
                elif fault == "mac":
                    assert "invalid authcode" in result.stderr, "wrong MAC rejection"
                else:
                    assert "Get Device ID command failed" in result.stderr, "wrong command rejection"
            else:
                value = (normalize_ipmitool("device", result.stdout) if name == "ipmitool"
                         else json.loads(result.stdout))
                assert value == EXPECTED["device"], f"{name}/{fault}: wrong Device ID"
                assert trace["closed"], "successful client did not close"
            row = {"id": "X01.response." + (fault or "normal"), "client": name, "case": fault or "normal",
                   "outcome": "rejected" if rejected else "accepted", "argv": result.args,
                   "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "trace": trace}
            rows.append(row)
            print(f"PASS: {name}/{row['case']}: {row['outcome']}")
    if args.output:
        with open(args.output, "w") as output:
            json.dump({"implementation": reference_profile.implementation(args.moon_client), "reference": reference, "ipmitool_version": version, "scope": "synthetic loopback, not hardware", "cases": rows}, output, indent=2)
            output.write("\n")
    print(f"PASS: {len(rows)} response-policy comparisons; no hardware contacted")


if __name__ == "__main__":
    main()
