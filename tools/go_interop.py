#!/usr/bin/env python3
"""Run the existing MoonBit loopback example against pinned go-ipmi.
Only loopback and synthetic credentials are possible; no real BMC is contacted.
"""
import argparse
import json
import re
import selectors
import subprocess
import sys
import tempfile

from compare_clients import EXPECTED, ipmitool_command, normalize_ipmitool
import reference_profile


def compare_reads(client, port, ipmitool):
    """Do not mistake the reference BMC's unsupported sensor command for success."""
    for case in ("device", "chassis", "sensor"):
        for name, executable in (("moonipmi", client), ("ipmitool", ipmitool)):
            command = (ipmitool_command(executable, port, case) if name == "ipmitool"
                       else [executable, str(port), case])
            if name == "ipmitool":
                command[command.index("-R") + 1] = "1"
            result = subprocess.run(command, capture_output=True, text=True, timeout=8,
                                    env=reference_profile.environment())
            if case == "sensor":
                marker = "rsp=0xc1" if name == "ipmitool" else "FAIL: Get Sensor Reading failed (completion code 193)"
                if result.returncode <= 0 or marker not in result.stdout + result.stderr:
                    raise RuntimeError(f"{name}: expected reference sensor completion 0xc1")
                print(f"PASS: {name}/sensor: reference reports unsupported command 0xc1")
            else:
                if result.returncode:
                    raise RuntimeError(f"{name}/{case}: reference read failed")
                value = normalize_ipmitool(case, result.stdout) if name == "ipmitool" else json.loads(result.stdout)
                expected = dict(EXPECTED[case])
                if case == "device":
                    expected["additional_device_support"] = 0
                if value != expected:
                    raise RuntimeError(f"{name}/{case}: unexpected reference data")
                print(f"PASS: {name}/{case}: matched reference data")
    print("LIMIT: the unmodified reference BMC does not implement Get Sensor Reading; no full three-read claim")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client")
    parser.add_argument("server")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--compare-reads", action="store_true",
                       help="compare the MoonBit comparison example and ipmitool, including the reference sensor limitation")
    modes.add_argument("--ipmitool-address-probe", action="store_true",
                       help="observe ipmitool's permissive address handling against the same unmodified server")
    reference_profile.add_arguments(parser)
    args = parser.parse_args()
    if args.compare_reads or args.ipmitool_address_probe:
        if args.ipmitool_address_probe and not args.reference_profile and not args.ipmitool:
            args.ipmitool = args.client
        ipmitool, reference = reference_profile.resolve(args)
        print("REFERENCE:", json.dumps(reference, sort_keys=True))
    with tempfile.TemporaryFile(mode="w+") as errors:
        server = subprocess.Popen([args.server], stdout=subprocess.PIPE, stderr=errors, text=True,
                                  env=reference_profile.environment())
        try:
            with selectors.DefaultSelector() as poll:
                poll.register(server.stdout, selectors.EVENT_READ)
                if not poll.select(timeout=5):
                    raise RuntimeError("go-ipmi simulator did not start within five seconds")
            port = json.loads(server.stdout.readline())["port"]
            if not isinstance(port, int) or not 1 <= port <= 65535:
                raise RuntimeError("invalid loopback simulator port")
            if args.compare_reads:
                compare_reads(args.client, port, ipmitool)
                if server.poll() is not None:
                    raise RuntimeError("go-ipmi simulator exited before cleanup")
                return
            command = [args.client, str(port)]
            if args.ipmitool_address_probe:
                command = [ipmitool, "-vvv", "-I", "lanplus", "-C", "17", "-L", "USER",
                           "-U", "tester", "-P", "synthetic-password", "-H", "127.0.0.1",
                           "-p", str(port), "-N", "1", "-R", "0", "mc", "info"]
            client = subprocess.run(command, capture_output=True, text=True, timeout=10,
                                    env=reference_profile.environment())
            if server.poll() is not None:
                raise RuntimeError("go-ipmi simulator exited before cleanup")
            if args.ipmitool_address_probe:
                if client.returncode or not re.search(r">>\s+Rq Addr\s*:\s*81\b", client.stderr) or not re.search(r"<<\s+Rq Addr\s*:\s*20\b", client.stderr):
                    raise RuntimeError("ipmitool did not show the expected request 0x81 / response 0x20 behaviour")
                fields = dict(line.split(":", 1) for line in client.stdout.splitlines() if ":" in line)
                fields = {key.strip(): value.strip() for key, value in fields.items()}
                if fields.get("Manufacturer ID") != "343" or fields.get("Product ID") != "4660 (0x1234)":
                    raise RuntimeError("unexpected synthetic Device ID from go-ipmi")
                print(reference["version"])
                print("OBSERVED: ipmitool accepted rqAddr 0x20 in responses to requester 0x81")
                print("LIMIT: permissive client behaviour is not evidence of a conforming response address")
            else:
                if client.returncode:
                    raise RuntimeError(client.stdout + client.stderr)
                print(client.stdout.strip())
                print("PASS: MoonBit client interoperated with pinned go-ipmi over loopback (suite 17, three reads, close)")
        except Exception:
            errors.seek(0)
            diagnostics = errors.read()
            if diagnostics:
                print(diagnostics, file=sys.stderr)
            raise
        finally:
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)
            server.stdout.close()


if __name__ == "__main__":
    main()
