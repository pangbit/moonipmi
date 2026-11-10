#!/usr/bin/env python3
"""Run the existing MoonBit loopback example against pinned go-ipmi.
Only loopback and synthetic credentials are possible; no real BMC is contacted.
"""
import argparse
import json
import selectors
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client")
    parser.add_argument("server")
    parser.add_argument("--expect-address-rejection", action="store_true",
                        help="assert the pinned server's known response-address mismatch; not successful interoperability")
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
            client = subprocess.run([args.client, str(port)], capture_output=True, text=True, timeout=10)
            if server.poll() is not None:
                raise RuntimeError("go-ipmi simulator exited before cleanup")
            if args.expect_address_rejection:
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
