#!/usr/bin/env python3
"""Run the existing MoonBit loopback example against pinned go-ipmi.
Only loopback and synthetic credentials are possible; no real BMC is contacted.
"""
import json
import selectors
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python3 tools/go_interop.py <loopback-client> <reference-bmc>")
    with tempfile.TemporaryFile(mode="w+") as errors:
        server = subprocess.Popen([sys.argv[2]], stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            with selectors.DefaultSelector() as poll:
                poll.register(server.stdout, selectors.EVENT_READ)
                if not poll.select(timeout=5):
                    raise RuntimeError("go-ipmi simulator did not start within five seconds")
            port = json.loads(server.stdout.readline())["port"]
            if not isinstance(port, int) or not 1 <= port <= 65535:
                raise RuntimeError("invalid loopback simulator port")
            client = subprocess.run([sys.argv[1], str(port)], capture_output=True, text=True, timeout=10)
            if client.returncode:
                raise RuntimeError(client.stderr)
            if server.poll() is not None:
                raise RuntimeError("go-ipmi simulator exited before cleanup")
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
