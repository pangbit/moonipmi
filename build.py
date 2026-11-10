#!/usr/bin/env python3
"""Read-only OpenSSL 3 discovery for MoonBit's native build configuration.
No downloads, installation, environment dumps or machine-specific committed files.
"""
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys

json.load(sys.stdin)  # Consume Moon's build context; do not log environment values.
env = os.environ.copy()
if not shutil.which("pkg-config"):
    raise SystemExit("moonipmi requires pkg-config and OpenSSL 3 development files")

def query(option):
    return subprocess.check_output(["pkg-config", option, "libcrypto"], env=env, text=True, stderr=subprocess.DEVNULL).strip()

try:
    version = query("--modversion")
except subprocess.CalledProcessError:
    version = ""
if not version.startswith("3.") and platform.system() == "Darwin" and shutil.which("brew"):
    prefix = subprocess.check_output(["brew", "--prefix", "openssl@3"], text=True).strip()
    env["PKG_CONFIG_PATH"] = str(Path(prefix) / "lib/pkgconfig") + os.pathsep + env.get("PKG_CONFIG_PATH", "")
    version = query("--modversion")
if not version.startswith("3."):
    raise SystemExit("moonipmi requires OpenSSL major version 3 (macOS: openssl@3; Debian/Ubuntu: libssl-dev)")
include, library = query("--variable=includedir"), query("--variable=libdir")
if not (Path(include) / "openssl/evp.h").is_file():
    raise SystemExit("OpenSSL development headers are missing")
print(json.dumps({
    "vars": {"OPENSSL_CFLAGS": shlex.join(["-I" + include])},
    "link_configs": [{
        "package": "pangbit/moonipmi/native_crypto",
        "link_libs": ["crypto"],
        "link_search_paths": [library],
    }],
}))
