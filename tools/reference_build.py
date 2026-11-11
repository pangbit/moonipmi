#!/usr/bin/env python3
"""Build an unpatched, pinned ipmitool reference without installing it."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tarfile

COMMIT = "19d78782d795d0cf4ceefe655f616210c9143e62"
PROFILE = "lanplus-readonly-v1"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="upstream Git checkout containing the pinned commit")
    parser.add_argument("--output", required=True, type=Path, help="new, empty build directory")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise SystemExit("output must be empty; retain previous profiles rather than overwrite evidence")
    # Export the exact object, not the checkout's potentially edited working files.
    archive = subprocess.check_output(["git", "-C", str(args.source), "archive", COMMIT])
    source = output / "source"
    source.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        for member in tree.getmembers():
            target = source / member.name
            if not target.resolve().is_relative_to(source) or not (member.isfile() or member.isdir()):
                raise SystemExit("unexpected archive member")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tree.extractfile(member).read())
                target.chmod(member.mode)
    data = output / "data"
    data.mkdir()
    # A nonempty synthetic registry is required by this upstream version.
    # This is fixture data, not an authoritative IANA registry snapshot.
    (data / "enterprise-numbers").write_bytes(b"343\n  Synthetic fixture vendor\n")
    env = {"PATH": os.environ["PATH"], "LC_ALL": "C", "TZ": "UTC",
           "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "GIT_CEILING_DIRECTORIES": str(output)}

    def capture(argv):
        return subprocess.check_output(argv, env=env, text=True).strip()

    cflags = capture(["pkg-config", "--cflags", "openssl"])
    ldflags = capture(["pkg-config", "--libs-only-L", "openssl"])
    if platform.system() == "Darwin":
        # The upstream packed Dell table has unaligned pointers. Use classic
        # relocations rather than chained fixups; do not patch the reference.
        ldflags += " -Wl,-no_fixup_chains"
    env.update(CC="cc", CFLAGS="-O2 -g0", CPPFLAGS=cflags, LDFLAGS=ldflags,
               DEFAULT_INTF="lan", IANADIR=str(data), IANAUSERDIR=".moonipmi-reference-unused")
    configure = ["./configure", "--prefix=" + str(output / "install"),
                 "--enable-intf-lan", "--enable-intf-lanplus", "--enable-intf-serial",
                 *["--disable-intf-" + name for name in ("open", "imb", "lipmi", "bmc", "free", "dbus", "dummy", "usb")],
                 "--disable-ipmishell", "--disable-file-security"]
    steps = [["sh", "-e", "bootstrap"], configure, ["make", "-j2"]]
    for index, command in enumerate(steps):
        print("Building reference:", command[0], flush=True)
        with (output / f"build-{index}.log").open("w") as log:
            subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = source / "src/ipmitool"
    daemon = source / "src/ipmievd"
    config = (source / "config.h").read_text()
    defines = dict(re.findall(r"^#define (\w+)(?: (.*))?$", config, re.MULTILINE))
    selected = {key: defines.get(key) for key in sorted(set(
        ["ENABLE_ALL_OPTIONS", "HAVE_CRYPTO_SHA256", "HAVE_READLINE", "ENABLE_FILE_SECURITY"] +
        ["IPMI_INTF_" + x.upper() for x in ("lan", "lanplus", "serial", "open", "imb", "lipmi", "bmc", "free", "dbus", "dummy", "usb")]))}
    assert all(selected[key] == "1" for key in ("ENABLE_ALL_OPTIONS", "HAVE_CRYPTO_SHA256", "IPMI_INTF_LANPLUS"))
    version = capture([str(binary), "-V"])
    assert version == "ipmitool version 1.8.19", version
    tools = {name: capture([name, "--version"]).splitlines()[0]
             for name in ("cc", "autoconf", "automake", "make", "pkg-config")}
    linker = ["otool", "-L"] if platform.system() == "Darwin" else ["ldd"]
    linked = capture([*linker, str(binary)])
    dependencies = {}
    for line in linked.splitlines()[1:]:
        match = re.search(r"(?:=>\s+)?(/[^\s]+)", line)
        if match and Path(match[1]).is_file():
            path = Path(match[1])
            dependencies[path.name] = {"path": str(path), "sha256": sha256(path)}
    manifest = {
        "schema_version": 1, "profile": PROFILE, "source_commit": COMMIT,
        "source_archive_sha256": hashlib.sha256(archive).hexdigest(), "patches": [],
        "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine(),
                     "macos": platform.mac_ver()[0] or None},
        "tools": tools, "openssl": capture(["pkg-config", "--modversion", "openssl"]),
        "optional_dependencies": {"readline": "disabled", "freeipmi": "disabled", "libsystemd": "disabled"},
        "configure": configure, "build_environment": env, "defines": selected,
        "default_interface": "lan", "enabled_interfaces": ["lan", "lanplus", "serial-basic", "serial-terminal"],
        "version": version, "binary": "source/src/ipmitool", "binary_sha256": sha256(binary),
        "daemon_sha256": sha256(daemon), "config_sha256": sha256(source / "config.h"),
        "data_file": "data/enterprise-numbers", "data_sha256": sha256(data / "enterprise-numbers"),
        "linked_libraries": dependencies,
        "scope": "Recorded local build; dependencies are fingerprinted, not a hermetic toolchain lock. No hardware validation.",
    }
    (output / "profile.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"PASS: {PROFILE}; source {COMMIT}; binary SHA-256 {manifest['binary_sha256']}")


if __name__ == "__main__":
    main()
