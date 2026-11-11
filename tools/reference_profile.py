"""Bind comparison reports to a verified reference build, or label them unfrozen."""
import json
import os
from pathlib import Path
import shutil
import subprocess

from reference_build import COMMIT, PROFILE, sha256


def environment():
    # Do not inherit passwords, user IANA registries, locale or loader overrides.
    return {"PATH": os.environ["PATH"], "LC_ALL": "C", "TZ": "UTC"}


def add_arguments(parser):
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--reference-profile", type=Path, help="profile.json from reference_build.py")
    group.add_argument("--ipmitool", help="explicit unprofiled binary (version-only evidence)")


def resolve(args):
    if args.reference_profile:
        path = args.reference_profile.resolve()
        manifest = json.loads(path.read_text())
        assert manifest["source_commit"] == COMMIT and manifest["profile"] == PROFILE
        assert manifest["patches"] == []
        root = path.parent
        executable = str(root / manifest["binary"])
        checks = [(executable, manifest["binary_sha256"]),
                  (root / "source/src/ipmievd", manifest["daemon_sha256"]),
                  (root / "source/config.h", manifest["config_sha256"]),
                  (root / manifest["data_file"], manifest["data_sha256"])]
        checks += [(row["path"], row["sha256"]) for row in manifest["linked_libraries"].values()]
        for target, expected in checks:
            assert sha256(target) == expected, f"reference changed: {target}"
        # The embedded IANA directory is absolute; moving a build requires rebuilding.
        assert manifest["build_environment"]["IANADIR"] == str(root / "data")
        evidence = {"status": "PROFILE_VERIFIED", "profile": PROFILE, "source_commit": COMMIT,
                    "manifest_sha256": sha256(path), "binary_sha256": manifest["binary_sha256"],
                    "config_sha256": manifest["config_sha256"], "data_sha256": manifest["data_sha256"],
                    "platform": manifest["platform"], "openssl": manifest["openssl"]}
    else:
        executable = args.ipmitool or shutil.which("ipmitool")
        assert executable, "ipmitool is required"
        evidence = {"status": "UNFROZEN_VERSION_ONLY", "binary_sha256": sha256(executable)}
    version = subprocess.check_output([executable, "-V"], text=True, env=environment()).strip()
    assert version == "ipmitool version 1.8.19", "review another version before changing the baseline"
    evidence["version"] = version
    return executable, evidence


def implementation(executable):
    root = Path(__file__).resolve().parents[1]
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root))
    return {"source_commit": commit, "working_tree_dirty": dirty, "binary_sha256": sha256(executable),
            "note": "A dirty working tree is not exact-commit evidence; use clean CI artifacts for that claim."}
