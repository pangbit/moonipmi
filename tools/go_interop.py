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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client")
    parser.add_argument("server")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--expect-address-rejection", action="store_true",
                       help="assert the pinned server's known response-address mismatch; not successful interoperability")
    modes.add_argument("--ipmitool-address-probe", action="store_true",
                       help="observe ipmitool's permissive address handling against the same unmodified server")
    args = parser.parse_args()
    with tempfile.TemporaryFile(mode="w+") as errors:
        server = subprocess.Popen([args.server], stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            with selectors.DefaultSelector() as poll:
                poll.register(server.stdout, selectors.EVENT_READ)
                if not poll.select(timeout=5):
                    raise RuntimeError("go-ipmi simulator did not start within five seconds")
            port = json.loads(server.stdout.readline())["port"]
            if not isinstance(port, int) or not 1 <= port <= 65535:
                raise RuntimeError("invalid loopback simulator port")
            command = [args.client, str(port)]
            if args.ipmitool_address_probe:
                command = [args.client, "-vvv", "-I", "lanplus", "-C", "17", "-L", "USER",
                           "-U", "tester", "-P", "synthetic-password", "-H", "127.0.0.1",
                           "-p", str(port), "-N", "1", "-R", "0", "mc", "info"]
            client = subprocess.run(command, capture_output=True, text=True, timeout=10)
            if server.poll() is not None:
                raise RuntimeError("go-ipmi simulator exited before cleanup")
            if args.ipmitool_address_probe:
                if client.returncode or not re.search(r">>\s+Rq Addr\s*:\s*81\b", client.stderr) or not re.search(r"<<\s+Rq Addr\s*:\s*20\b", client.stderr):
                    raise RuntimeError("ipmitool did not show the expected request 0x81 / response 0x20 behaviour")
                fields = dict(line.split(":", 1) for line in client.stdout.splitlines() if ":" in line)
                fields = {key.strip(): value.strip() for key, value in fields.items()}
                if fields.get("Manufacturer ID") != "343" or fields.get("Product ID") != "4660 (0x1234)":
                    raise RuntimeError("unexpected synthetic Device ID from go-ipmi")
                print(subprocess.check_output([args.client, "-V"], text=True).strip())
                print("OBSERVED: ipmitool accepted rqAddr 0x20 in responses to requester 0x81")
                print("LIMIT: permissive client behaviour is not evidence of a conforming response address")
            elif args.expect_address_rejection:
                if client.returncode == 0 or client.stdout.strip() != "FAIL: IPMI response address mismatch":
                    raise RuntimeError("expected the pinned server's address mismatch, got:\n" + client.stdout + client.stderr)
                print("PASS: pinned go-ipmi response-address mismatch rejected after authenticated handshake")
                print("LIMIT: full go-ipmi interoperability is NOT verified; no checks were relaxed")
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
