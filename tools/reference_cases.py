#!/usr/bin/env python3
"""Record pinned reference dispatch/help leaves; never count them as parity passes."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from diagnostics_check import execute
import reference_profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    reference_profile.add_arguments(parser)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not args.reference_profile:
        parser.error("a verified --reference-profile is required for the leaf catalogue")
    executable, reference = reference_profile.resolve(args)
    inventory = json.loads((Path(__file__).resolve().parents[1] / "docs/ipmitool-parity-inventory.json").read_text())
    profile = json.loads(args.reference_profile.read_text())
    rows = []
    with tempfile.TemporaryDirectory(prefix="moonipmi-reference-cases-") as scratch:
        for entry in inventory["commands"]:
            case_id = entry["id"] + ".dispatch-help"
            if entry["name"] == "shell" and profile["defines"]["HAVE_READLINE"] is None:
                rows.append({"id": case_id, "status": "BLOCKED_BUILD", "reason": "readline disabled in this profile",
                             "moonipmi_status": "NOT_IMPLEMENTED"})
                continue
            result, trace, elapsed = execute(executable, entry["name"] + " help", cwd=scratch)
            assert trace["closed"], (case_id, result.stdout, result.stderr)
            # All command help observations are allowed only the common discovery,
            # authentication and closure sequence, never a control command.
            allowed = {(6, 0x3b), (6, 1), (6, 0x3c), (0x2c, 0), (0x2c, 0x3e)}
            assert all((c["netfn"], c["command"]) in allowed for c in trace["commands"]), case_id
            rows.append({"id": case_id, "status": "REFERENCE_OBSERVED", "moonipmi_status": "NOT_IMPLEMENTED",
                         "argv": result.args, "stdin": "EOF", "stdout": result.stdout, "stderr": result.stderr,
                         "exit_code": result.returncode, "trace": trace, "elapsed_seconds": elapsed,
                         "note": "Literal 'help' dispatch; echo/exec/set and unsupported-interface branches may not display help."})
            print(f"OBSERVED: {case_id}, exit {result.returncode}", flush=True)
        offline = [("C39.help", ["help"]), ("O01.help", ["-h"]), ("O01.version", ["-V"]),
                              ("O01.invalid-option", ["-?"]), ("O02.invalid-interface", ["-I", "moonipmi-invalid-interface"]),
                              ("D03.help", ["-h"]), ("D03.version", ["-V"])]
        groups = {"O02": "IdD", "O03": "Hp", "O04": "UPf", "O05": "LA", "O06": "Cky",
                  "O07": "tTblmB", "O08": "NRz", "O10": "S", "O11": "O", "O12": "o", "O13": "e"}
        flag_groups = {flag: group for group, flags in groups.items() for flag in flags}
        required = re.findall(r"(.):", inventory["option_strings"]["all"])
        assert set(required) == set(flag_groups), "review option inventory/group mapping before adding leaves"
        offline += [(flag_groups[flag] + ".missing-" + flag, ["-" + flag]) for flag in required]
        for case_id, argv in offline:
            binary = str(Path(executable).with_name("ipmievd")) if case_id.startswith("D") else executable
            result = subprocess.run([binary, *argv], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                    timeout=5, cwd=scratch, env=reference_profile.environment())
            if ".missing-" in case_id:
                assert result.returncode != 0 and "requires an argument" in result.stderr, case_id
            rows.append({"id": case_id, "status": "REFERENCE_OBSERVED", "moonipmi_status": "NOT_IMPLEMENTED",
                         "argv": result.args, "stdin": "EOF", "stdout": result.stdout, "stderr": result.stderr,
                         "exit_code": result.returncode, "trace": None, "scope": "pre-session CLI branch"})
    assert len({row["id"] for row in rows}) == len(rows)
    args.output.write_text(json.dumps({"reference": reference, "cases": rows,
        "scope": "Reference-only G1 seed leaves; no moonipmi CLI exists. Not full subcommand/argument enumeration or a parity pass."}, indent=2) + "\n")
    print(f"Recorded {len(rows)} leaf states; no hardware contacted or full-parity acceptance claimed")


if __name__ == "__main__":
    main()
