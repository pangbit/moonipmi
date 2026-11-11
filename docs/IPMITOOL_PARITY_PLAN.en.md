# Full ipmitool parity plan

[简体中文](IPMITOOL_PARITY_PLAN.md)

Status: **P1 reference/case work and selected read-only implementation are authorized and in progress; no complete-parity claim or authorization for state-changing stages.**

This plan tracks the full scope. Authorized work now includes reference-build identification, leaf cases, differential validation and unambiguous read-only corrections. It does not operate real devices, develop state-changing controls, relax authentication/packet checks, or publish to Mooncakes.
The requested goal includes every reference feature and observable behavior. Current moonipmi is a read-only subset with substantial omissions and known differences; it is not a complete ipmitool replacement.

## 1. Fixed reference and scope

| Item | Baseline or rule |
|---|---|
| Reference | `ipmitool/ipmitool` **1.8.19**, continuing the existing comparison baseline; do not follow an upstream branch or silently upgrade distribution packages |
| Tag | `IPMITOOL_1_8_19`, annotated-tag object `259e69af5d72fd57cddf8f3aa9783e4acc406dc0` |
| Resolved source commit | **`19d78782d795d0cf4ceefe655f616210c9143e62`** |
| moonipmi inventory baseline | `355682ea7fdaa8355747c901601a41569570f33f`; future implementations need their own exact commit and acceptance evidence |
| Full inventory | **38 registered command entries**, special `help`, **12 conditional transport interfaces**, global options/OEM profiles, separate `ipmievd`, related files/data and companion-script behavior |
| Build conditions | Retain the union of all build variants. A command missing from a macOS or minimal-build help screen is not globally out of scope |
| Reference upgrades | Review changes, update the inventory, and rerun affected acceptance cases. Do not extrapolate 1.8.19 evidence to another version |

The tag object and resolved commit were checked through read-only GitHub access. See the [source inventory](ipmitool-parity-inventory.json) and [acceptance matrix](IPMITOOL_PARITY_MATRIX.en.md).
The 38 entries include alias `bmc`, shortcut `power`, undescribed `echo`, and `shell` under `HAVE_READLINE`. Generic `help` is handled outside that table; neither the registration table alone nor an example help listing is sufficient.

**Pinning source does not freeze every reference build.** The first unpatched local reference executable and CI recipe are now identified in [P1 evidence](IPMITOOL_REFERENCE.md); full dependency/platform and all-interface builds remain incomplete.
P1 must record source/patch and binary hashes, OS/architecture, compiler, configure arguments, `config.h`, OpenSSL/FreeIPMI/readline/libsystemd versions, default/enabled interfaces, `ENABLE_ALL_OPTIONS`, `HAVE_CRYPTO_SHA256`, and `ENABLE_FILE_SECURITY`.
Distribution patches, IANA enterprise data, OEM description files and environment variables affect behavior. Existing reports of `ipmitool -V = 1.8.19` are not substitutes for these records.

The reference has documentation/implementation differences. For example, the manual describes default cipher suite 17, but the [lanplus selection function](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c#L3366) prefers 17 and includes fallback paths to 3.
The mappings for suites 0..17 do not prove every combination works with every crypto build. Measure the fixed binary and retain discrepancies between source, help and manual.

## 2. Observable equivalence contract

The full target needs a compatible CLI as well as library capabilities. Matching selected typed API fields is insufficient.
Expand each matrix group into leaf cases across `entry × subcommand × arguments/defaults × interface/build × privilege × device capability × success/failure path`.
The groups are review and tracking units, not claims that every argument value has been enumerated or exhaustively tested.

Each leaf checks:

1. **Invocation/output:** argument ordering, aliases, defaults, case/prefix matching, help, stdout/stderr separation, exit status, CSV, precision, text, ordering, empty values, errors and warnings.
2. **Communication:** discovery, authentication/privilege negotiation, address/LUN/bridging, command payloads, chunking, completion codes, retry counts/intervals, timeouts, duplicate responses, session closure and cancellation.
3. **Side effects:** device state, extra requests, file creation/overwrite, terminal modes, signals, logging, background processes and residual resources.
4. **Platforms:** actual interfaces, defaults, options, missing dependencies and inaccessible-device errors for each build. One platform does not validate another.

Use `LC_ALL=C`, `TZ=UTC`, a controlled clock, pinned data files and equal initial device states for deterministic comparisons.
Also test non-default timezone, `-Z`, locale, environment variables, and TTY/non-TTY behavior; freezing the primary environment must not hide those features.
Compare stdout/stderr/exported files byte for byte where deterministic. Apply explicitly reviewed relational checks only to nonce/session-ID/random-IV fields, never discard an entire response or output line.
Use justified timing tolerances while checking retry/wait state transitions precisely; two runs cannot have identical wall-clock durations.

Any normalization, program identity/version difference or retained protection needs a recorded decision. A retained observable difference permits only a specifically qualified compatibility claim, not “no omissions or differences.”
Unreproducible undefined behavior, crashes or incidental environmental effects are blockers to investigate, not promises to reproduce memory errors.
Finite tests cannot prove equivalence for every unknown device or input. Final statements must identify the reference commit, builds, environments and validated scenarios.

## 3. Current implementation and evidence

| Existing capability | Existing evidence | What it does not establish |
|---|---|---|
| Native/OpenSSL 3; suite 17 RMCP+; User privilege; authentication/integrity/replay checks; single-flight UDP | Native tests, independent synthetic Python handshake/exchanges, existing Linux/macOS CI | Other authentication, transports, privileges, defaults and retries |
| Device ID, Chassis Status, raw Sensor Reading | 30-case three-client common-Python-fixture matrix; [comparison](COMPARISON.md) | All commands or full CLI-output parity |
| SDR repository and partial Full/Compact interpretation | 33 output comparisons and nine repository boundaries; [SDR](SDR.md) | Nonlinear/dynamic factors, Device SDR, shared/bridged records, reading configured thresholds and other omitted fields |
| Chassis capabilities/restart cause, basic FRU, SEL | Historical stage: 41 native test groups in total; separately 30 mixed diagnostic executions/boundary cases, not 30 direct client comparisons; [diagnostics](DIAGNOSTICS.md) | Historical text assertions were limited; [P1](IPMITOOL_REFERENCE.md) adds 24 field/description/raw projections across 62 executions. Still no complete semantics, CLI, writes or hardware validation; counts are not a coverage percentage |
| Self-test/global-enables/watchdog/POH reads | 46 native groups in total; [127 management executions](MANAGEMENT.md), including 56 output projections, eight completion-error projections, 11 moon-only boundaries and one display difference | Typed APIs only; full CLI, controls and hardware still missing; POH float display differs |
| GUID and six System Info string reads | 50 native groups in total; [180 identity executions / 94 leaves](IDENTITY.md): locally 62 output, 5 rejection, 8 moon-only boundaries, 19 differences | Typed APIs; GUID time/System Info text, lengths, validation and error exits differ; full CLI and hardware absent |
| Requester-address tolerance | 24 packet-policy comparisons | Responder, netfn/LUN and IPMI-checksum acceptance still differs |

Implementation commit `81a7728` passed [exact-commit CI](https://github.com/pangbit/moonipmi/actions/runs/42971333879) on Ubuntu 24.04 and macOS 15.
Both run native checks/tests/build and loopback exchange. ipmitool/Go/SDR/diagnostic/address comparisons run in Linux CI; local macOS comparison evidence is separate.
The pinned go-ipmi BMC lacks Get Sensor Reading and did not pass the complete three-read exchange. It is not the full-feature reference.
There is no real-BMC validation, comprehensive platform certification or external security audit. P1 reran the listed local subset checks with a hash-bound reference; exact-commit CI evidence is kept separately.

## 4. Proposed stages

**P0 is delivered; P1 and selected reads on the existing suite-17/User session are authorized and in progress. Security/major compatibility choices await review; state-changing development remains prohibited.**
P2/P3 must not use raw access, diagnostics or reservation operations to introduce arbitrary write support.

| Stage | Deliverables and dependencies | Exit gate |
|---|---|---|
| P0: inventory and contract | This plan, pinned source, inventory, matrix, resource/conflict register and review decisions | Map 38/38 registered entries and 12/12 interfaces; no full-parity passes claimed; documentation only |
| P1: reference builds and differential harness | In progress: first profile, 71 reference leaf states and 24 diagnostic projections; complete reference/dependency profiles; independent fixtures and argv/output/trace/state records; expand all groups into leaves | Run the actual reference for every leaf; reconcile help, dispatcher branches and configuration tables; explain every unknown/skip; no production evidence gathering |
| P2: CLI, sessions and transports | P1 and K01–K10 decisions; CLI/configuration/identity/errors, transport abstraction, bridging, authentication/retry; simulate local drivers first | Differential O/T/X cases; unresolved safety choices stay blocked; reproduce reference failure for unsupported combinations instead of inventing success |
| P3: complete reads and offline processing | Selected [management reads](MANAGEMENT.md) and [identity reads](IDENTITY.md) implemented on the existing transport; remaining work needs the required P2 transports; complete SDR/sensor/FRU/SEL, MC/channel/user/session, network configuration reads, DCMI/NM/OEM reads and file parsing | Every read leaf includes malformed/boundary/missing-capability/permission cases; retained raw bytes are not interpreted support; compare files and text too |
| P4: standard state-changing controls | **Currently prohibited**; separate approval, then P1–P3; power/boot/reset, accounts/channels/LAN, thresholds, SDR/FRU/SEL writes, events/PEF/firewall | Resettable simulators first; compare each effect, failure point, duplicate, disconnect and uncertain outcome. Real devices need separate authorization; do not assume rollback is possible |
| P5: interactive and long-lived operations | Separate approval; SOL/ISOL/TSOL, complete shell/exec session behavior, ipmievd | PTY/escape/retransmission/flow-control/keepalive, signal and terminal recovery, duplicate/lost events and daemon lifecycle; record notification-enabling side effects |
| P6: platform extensions and firmware | Separate approval; PICMG/VITA, DCMI/NM controls, Sun/Dell/Kontron OEM, HPM/FWUM/IME | Specific simulators, lawful image samples and vendor state machines; separately test upload/activation/rollback/interruption. Generic raw is not feature completion |
| P7: platform and hardware closure | Platform builds may be prepared earlier; device work needs explicit target/account/operation authorization and relevant simulator passes | Evidence for each transport/device-family/privilege combination. Missing functionality, differences, devices and builds stay visible; apply the completion rules below |

Do not promise calendar estimates before platform/device resources are identified. Estimate batches after P1 reveals leaf counts, vendor documentation and hardware availability.
Mooncakes publication remains a separate manual maintainer decision, never an automatic stage action.

## 5. Platform, hardware and privilege requirements

| Environment | Required investigation | Current state |
|---|---|---|
| Ubuntu 24.04/macOS 15 native | Reproducible reference/MoonBit builds, CLI, LAN transports, crypto/readline differences | First four-interface profile recipe added to both CI platforms; broader profiles remain unfrozen; macOS cannot validate Linux local drivers |
| Linux/FreeBSD plus applicable OpenIPMI/FreeIPMI/IMB | Driver/ioctl ABI, device selection, permissions, kernel event delivery | Full builds/device evidence missing; simulation cannot close hardware acceptance |
| Relevant Solaris 9/10 environments | lipmi/bmc headers/drivers/ABI and potentially restricted default option sets | Toolchain, OS and devices unavailable; retain blockers |
| Cygwin, AIX and other configure branches | Determine actual upstream buildability and MoonBit native portability | Unverified; Cygwin is not native Windows support; blocks a global claim |
| OpenBMC | D-Bus service, libsystemd, identity/policy/errors | No evidence; private mock service first, separately authorized devices later |
| Serial and AMI USB hardware | Basic/Terminal framing, baud/system modes; OEM USB transport and permissions | No evidence; UDP simulation cannot stand in for transport validation |
| IPMI 1.5/2.0 BMCs and bridges/satellite MCs | Negotiation, suites, Kg, quirks and changing device state | No real hardware evidence; record firmware even within one model |
| Sun/Oracle, Dell, Kontron, Intel NM/ME, PICMG/ATCA, VITA | OEM/extensions, firmware formats and recovery procedures | Models, images, authorization, maintenance windows and recovery equipment unresolved |

Remote cases must cover NULL/anonymous scenarios and CALLBACK, USER, OPERATOR, ADMINISTRATOR, channel/user/payload restrictions and denial paths.
This inventory does not authorize anonymous or privileged access now. Determine command privileges from reference requests and target policy; do not assume every read permits User or every write needs only Operator.
Local devices depend on OS nodes/groups/ACLs or D-Bus policy rather than remote Administrator privilege; do not unconditionally use root.
Firmware/OEM actions may require vendor roles, jumpers or particular device states; record these separately.

## 6. Behavior conflicts requiring review

These conflicts describe the existing implementation and safety policy versus full equivalence. They do not authorize changing security behavior now.
A retained difference is `DIVERGENT`, remains in the denominator, and prevents a full-parity claim.

| ID | Reference behavior or branch to measure | Current conflict and required decision |
|---|---|---|
| K01 | LAN 1.5, NONE/weaker authentication, suite selection/fallback, Kg, NULL credentials | Current suite-17-only, nonempty credentials and no fallback. Decide compatibility policy; measure weak modes only with isolated synthetic peers first |
| K02 | Default Administrator, `-L`/`+` lookup, elevated privilege for bridging | Fixed User/role 0x02 versus reference role 0x12 in existing tests. Defaults and privilege changes require explicit testing/review |
| K03 | More permissive acceptance of some authenticated malformed IPMI fields | Existing 24-case comparison shows stricter responder/netfn/LUN/checksum rejection. Retain protection or reproduce reference acceptance; “stricter” is not “equal” |
| K04 | Retries, command-specific timeouts, continued waiting after discards, close requests | Per-exchange timeout, single-flight/fail-closed/no-retry and whole-FRU/SEL limits differ. Repetition may repeat a state change; test uncertain outcomes |
| K05 | raw/I2C and account/LAN/power/log/inventory/firmware mutations | Current read-only allowlist. Distinguish implementing a capability from authorizing its use. Added prompts/default refusals/switches are observable differences |
| K06 | argv/environment/file/prompt passwords, verbose packet dumps, history | Current secret/packet logging restrictions. Decide exposure boundaries; evidence uses synthetic secrets only and excludes real credentials |
| K07 | IPv4/IPv6/DNS/selection, bridging, paths and discovery | Current Addr/single-peer and address exclusions. Measure reference acceptance; compatibility testing must not become network scanning |
| K08 | Complete interpretation/formatting/export, changing repositories | Raw retention, ASCII subset, bounded non-atomic traversal, failure without partial output differ. Compare reference partial/error semantics; do not drop differing fields |
| K09 | `--enable-file-security`, default interfaces, shell and conditional options | Freeze multiple profiles; do not change build flags to eliminate failing cases or mistake host-platform absence for global absence |
| K10 | Program/version/help identity, dependency errors, time/randomness and upstream defects | Recommend honest moonipmi identity and relational random-field checks; this can conflict with literal equality and needs a decision. Record memory-corruption/unreproducible behavior as blockers rather than copying defects |

## 7. Acceptance records and completion

Each leaf report needs its stable ID, source branch, both exact commits/builds, command/input, fixture version/initial state, privilege, stdout/stderr/exit status, sanitized trace, before/after state, differences, date and evidence links.
Reset fixtures separately for each client. Writes, clocks, counters and events must not let the first client change the second client's inputs.
Independent fixtures must not recognize the client and change responses accordingly. Keep minimal reproducers for failures and execute the real reference, not just assertions against locally invented expectations.

Use `NOT_IMPLEMENTED`, `PARTIAL`, `UNVERIFIED`, `BLOCKED_ENV`, `BLOCKED_DECISION`, `DIVERGENT`, and `PASS`.
`REFERENCE_UNAVAILABLE` can describe a particular unsupported reference build combination and its matching failure, but does not remove supported combinations elsewhere.
Unavailable hardware is blocked, not PASS/N/A. A group passes only when its leaves and dependencies pass; code, help entries or a single simulation do not suffice.

Full completion requires:

- A mapping for all source entries, options, subcommand branches, configuration tables, conditional interfaces and companion tools, including later discoveries; no unexplained/unexpanded items.
- Execution of the reviewed complete platform/transport/device matrix, with no unresolved omissions, differences, resource or decision blockers; narrowing scope cannot substitute for implementation.
- Matching deterministic observable behavior, explicit decisions on randomness/timing/identity, and disclosure of every retained difference.
- Specific model/firmware/privilege/interface evidence for hardware claims; one BMC cannot establish all-BMC compatibility and simulation is not hardware validation.
- Focused review of authentication, FFI/drivers, files, long sessions and firmware paths. Such review does not automatically constitute an external audit or authorize release.

Review must settle the 1.8.19/full-build-union baseline; CLI/library/ipmievd/companion-script deliverables; K01–K10; available resources; and the remaining P1 work/later-stage boundaries. P1 and selected independent read-only implementation are authorized; see the [progress and recommendations](IPMITOOL_REFERENCE.md).
The existing restrictions on state-changing development, real-device operations and release remain in force.
**Recommendation:** continue reference evidence and independent read-only functionality; keep unresolved K01–K10 implementation changes blocked. Do not reduce acceptance scope by removing legacy interfaces, weak authentication or OEM features.
Full equivalence requires actually addressing those capabilities and differences. Do not directly reproduce memory errors, real-secret exposure or uncontrolled effects; retain blockers and submit concrete reproducible evidence for review rather than silently changing the goal.

## 8. Pinned primary sources

- [Annotated tag](https://api.github.com/repos/ipmitool/ipmitool/git/tags/259e69af5d72fd57cddf8f3aa9783e4acc406dc0), [command registry](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmitool.c#L86), [transport registry](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/ipmi_intf.c#L58), [configure](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/configure.ac).
- [CLI implementation](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_main.c), [manual](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/doc/ipmitool.1.in), [OEM profiles](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_oem.c).
- [ipmievd implementation](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmievd.c), [manual](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/doc/ipmievd.8.in), [companion scripts](https://github.com/ipmitool/ipmitool/tree/19d78782d795d0cf4ceefe655f616210c9143e62/contrib).
- moonipmi [public API](../pkg.generated.mbti), [scope/evidence](STATUS.md), [packet differences](COMPARISON.md), [SDR limitations](SDR.md), and [FRU/SEL limitations](DIAGNOSTICS.md).
