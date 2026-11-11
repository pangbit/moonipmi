# Full ipmitool parity acceptance matrix

[简体中文](IPMITOOL_PARITY_MATRIX.md)

Status: **P1 and selected read-only implementation work in progress; no row has passed full-parity acceptance.** See the [plan](IPMITOOL_PARITY_PLAN.en.md) for the pinned reference, stages, K01–K10 conflicts and completion rules.
The [machine-readable inventory](ipmitool-parity-inventory.json) contains all 38 registered commands and 12 interfaces. C39 is generic `help`; D rows cover the separate `ipmievd` executable.
Every registered entry has a row, including aliases, OEM commands and conditional features.

## Reading and execution rules

- `N` = NOT_IMPLEMENTED; `P` = PARTIAL; `U` = UNVERIFIED; `D` = DIVERGENT. None means PASS.
- Every group requires P1 leaf expansion and pinned-build evidence. Add `BLOCKED_ENV` or `BLOCKED_DECISION` where needed; do not turn blockers into “not applicable.”
- `R` = device read; `W` = device/configuration/event mutation; `F` = file; `T` = terminal; `L` = local driver/service; `V` = vendor/extension hardware. Reads can still log, reserve or consume resources. W does not imply execution authorization. Determine minimum privileges from target policy/reference cases and test all denial paths.
- Every row-specific criterion includes G0–G7. Each subcommand/parameter group inside a cell needs separate leaf IDs; one representative case cannot pass the group.
- Use stable leaf IDs such as `C12.print.word.short-count`, with build/interface/privilege/fixture dimensions. Existing evidence only fills the leaves it actually covered.
- **P1 executes reference/help and existing read-only leaves only against synthetic loopback peers. W-class development and real-device actions remain prohibited.** Selected P3 read leaves now use the existing session; remaining P2–P7 work stays open.

## Common acceptance dimensions

| ID | Record and compare for each applicable leaf |
|---|---|
| G0 | Exact reference/implementation SHA, binary/data hashes, build profile, environment, raw argv/stdin and initial state; reset each client's fixture separately |
| G1 | Default invocation, every valid branch, aliases/case/prefix rules, optional argument order/combinations, help; missing/extra/invalid/minimum/maximum/out-of-range inputs |
| G2 | stdout, stderr, exit code, CSV/verbosity, byte order, lengths, units/precision, text/order, files; process success or selected fields alone are insufficient |
| G3 | Complete discovery/authentication/privilege/request sequence, payloads, chunks, completion codes, retries/timeouts and cleanup; reviewed relations for random fields only |
| G4 | Present/absent capability, empty/full, unknown/OEM/reserved values, completion failures, truncation/length errors, malformed fields, duplication/reordering/loss/late responses |
| G5 | User/channel/payload denial, failed authentication and local ACL denial; no real-secret exposure; match failure stage and side effects |
| G6 | Resettable simulations for every write step, duplicate request, partial failure/disconnect/uncertain result; also compare file, terminal and daemon cleanup/residual state |
| G7 | Applicable platform/interface/firmware combinations; hardware semantics eventually require separately authorized real-environment evidence, recorded separately from synthetic passes |

## Command families

Links pin the reference commit. Groups were cross-checked against dispatchers, configuration tables and the manual; **this is not an exhaustive enumeration of parameter boundaries**.
G1 includes help, empty invocation and argument-error behavior for every entry. State-changing branches require P4 or later and removal of the current development restriction.

| ID / entry | Subcommands and feature groups | Current moonipmi gap | Specific acceptance | Resources / stage |
|---|---|---|---|---|
| C01 `raw` [source][raw] | Arbitrary netfn/cmd/data, target LUN/address, response/completion | P: offline encoder only; no generic send API/CLI | Byte and length boundaries, response hex, command-specific timeout/attempts; separate read/write leaves | R/W; P2/P4; K03–K05 |
| C02 `i2c` [source][raw] | Master Write-Read, bus/channel/public/address/read count/write bytes | N | Bus selection, mixed read/write, length/NACK/errors/output; a read with a write prefix is not effect-free | R/W, I2C target; P3/P4 |
| C03 `spd` [source][raw] | I2C SPD read and memory interpretation | N | Each reference-recognized SPD type/field, missing/truncated data, output and bus errors | R, SPD fixture/hardware; P3/P7 |
| C04 `lan` [source][lanp] | print/printconf; set IP/netmask/MAC/gateway/ARP/VLAN/auth/access/user/password/SNMP/alert/cipher_privs/bad_pass_thresh; alert print/set; stats get/clear | N | Every parameter/default channel, readback, set/commit order, disconnected state and counter clearing | R/W, channel policy; P3/P4 |
| C05 `chassis` [source][chassis] | status/power/selftest/identify/poh/restart_cause/policy; bootparam get/set, bootdev, bootmbox | P/D: status/capabilities/restart/self-test/POH APIs; POH precision differs; other reads, controls and CLI missing | Optional bits, power aliases, boot/mailbox blocks/persistence, identify durations, policy and interrupted failures | R/W, general BMC; P3/P4 |
| C06 `power` [source][chassis] | chassis power shortcut: status, on/up, off/down, cycle/reset/diag/soft/acpi | P: state through chassis API only | Match corresponding C05 output/status/requests; sharing a success return is insufficient | R/W; P2/P4 |
| C07 `event` [source][event] | Predefined events, sensor/event states, event files | N | Every send mode, assertion/deassertion, file syntax, record side effects, invalid states and duplicates | W/F; P4 |
| C08 `mc` [source][mc] | info; guid auto/ipmi/smbios/rfc/dump; getenables/setenables/selftest; reset cold/warm; watchdog get/set/off/reset; getsysinfo/setsysinfo | P: Device ID/self-test/global-enables/watchdog-get APIs; GUID/system-info, controls and CLI missing | GUID modes/manual alias discrepancies, system-info chunks/encoding, enables/watchdog state, post-reset session | R/W; P3/P4 |
| C09 `bmc` [source][mc] | Compatibility alias of mc | N: no CLI alias | Repeat every C08 leaf through alias, including error text/exit codes | R/W; P2/P4 |
| C10 `sdr` [source][sdr] | list/elist all/full/compact/event/mcloc/fru/generic; type/entity/info/get/dump; fill sensors/nosat/file/range | P: repository and partial Full/Compact; Device SDR/shared/bridged/full encodings/types/CLI/cache/dump/fill missing | Every type/route/shared expansion, reservation/retry, cache/files, fill/mutation; single/multiple/empty/changing records | R/W/F; P3/P4 |
| C11 `sensor` [source][sensor] | list/get/reading; thresh individual/lower/upper groups | P: raw and partial linear values/state; complete threshold reads, accuracy, nonlinear/dynamic factors and writes missing | Actual reference conversion branches, units/precision, unavailable/discrete readings, SDR lookup, threshold request order/errors | R/W; P3/P4 |
| C12 `fru` [source][fru] | Default discovery, print/list/read/write; internaluse info/print/read/write; get/edit OEM multirecord and edit field; upgEkey | P: explicit ID, byte/word/basic validation/limited text; discovery/full encodings/multirecord/OEM/files/writes missing | Access units/short reads/reference chunk retries, discovery/bridging, all areas/types/languages, bad checksum/partial output, edited layout/checksum/export | R/W/F/V; P3/P4/P6; K08 |
| C13 `gendev` [source][gendev] | list/read/write, Generic Device Locator EEPROM/device files | N | Locator/bus/page boundaries, file length, read/write/verification failures and exit codes | R/W/F, device fixture; P3/P4 |
| C14 `sel` [source][sel] | info/list/elist/get, first/last/count; time get/set; clear/delete/add; save/readraw/ereadraw/writeraw/interpret | P: bounded enumeration, standard metadata/partial thresholds/time classes/raw OEM; full interpretation/filter/files/time changes/mutations missing | Event/OEM meanings, SDR joins, IDs/time/timezones, repository changes/overflow/clear/delete; distinguish writeraw file export from BMC writes | R/W/F/V; P3/P4/P6 |
| C15 `pef` [source][pef] | capabilities/event/info/status/timer/pet; filter/policy list/enable/disable/create/delete | N | Filter/policy masks, destinations/alerts, timer, deletion/disabling/errors; simulated PET receiver records effects | R/W, PEF/PET fixture; P3/P4 |
| C16 `sol` [source][sol] | info/set, payload enable/disable/status, activate/deactivate, looptest, keepalive options | N | Configuration/privilege/payload, ACK/retry/flow control/disconnect, escape/break, tty recovery, keepalive/looptest | R/W/T, PTY+SOL peer; P3/P5 |
| C17 `tsol` [source][tsol] | Tyan IPMI 1.5 SOL; IP/port, ro/rw, rows/cols, altterm | N | Destination/port, read-only/input modes, terminal size/escapes, start/stop/loss/exit recovery | W/T/V, Tyan fixture; P5/P7 |
| C18 `isol` [source][isol] | Intel IPMI 1.5 SOL info/set/activate | N | Configuration, legacy session, terminal bytes, escapes/close and reference unsupported-interface outcomes | R/W/T/V; P3/P5 |
| C19 `user` [source][user] | summary/list/test, set name/password/priv, enable/disable | N | ID/channel bounds, 16/20-byte passwords, disabled/privilege matrix, test versus set, partial-failure state | R/W, synthetic users; P3/P4 |
| C20 `channel` [source][channel] | authcap/info/getaccess/setaccess/getciphers ipmi/sol | N: internal fixed handshake is not this command | Channels/access bits/persistence, suite pagination, privilege denial/invalid payload, effective changed privileges | R/W; P3/P4 |
| C21 `session` [source][session] | info active/all/id/handle | N: internal session state is not this command | Active/missing/multiple sessions, address fields, ID/handle selectors, short responses/limits | R; P3 |
| C22 `dcmi` [source][dcmi] | discover/oob_discover/sensors; asset_tag/set_asset_tag; get/set_mc_id_string; get_temp_reading; get/set_conf_param; thermalpolicy get/set; power reading/get_limit/set_limit/activate/deactivate | N | Capability pages/temp entities/string chunks, power actions/sampling, DHCP, Ping/Pong; every table-driven parameter | R/W/V, DCMI peer; P3/P6 |
| C23 `nm` [source][dcmi] | discover/capability/control; policy add/get/remove/limiting; statistics/power range/suspend/reset/alert/threshold | N | Domains/policy IDs/triggers/volatile/cores_off, statistics modes, thresholds/suspend arrays, alerts/removal/reset and version capabilities | R/W/V, Intel NM; P3/P6 |
| C24 `sunoem` [source][sunoem] | cli force/wait; led/sbled; sshkey set/del; ping/version/nacname/getval/setval/getfile/getbehavior | N | Property/sensor mappings, interactive CLI, LED groups, file/key chunks, version capability/vendor errors | R/W/F/T/V; P3/P6 |
| C25 `kontronoem` [source][kontronoem] | setsn/setmfgdate/nextboot | N | Generated/written FRU identifiers/date, boot selection, success/failure; no production serials in fixtures | W/V, Kontron; P6 |
| C26 `picmg` [source][picmg] | properties/addrinfo/busres summary/frucontrol/activate/deactivate/policy; portstate/amcportstate, LED/power/clk queries/settings/filters | N | ATCA/AMC/FRU routing, links/clocks, granted/denied/all, colors/power/activation locks, extension capabilities/failures | R/W/V, PICMG; P3/P6 |
| C27 `fwum` [source][fwum] | info/status/download/upgrade/rollback/tracelog | N | Image validation/chunks/sequence/retry, upgrade/rollback state, communication failures/recovery; lawful images/recoverable target | R/W/F/V, Kontron; P6 |
| C28 `firewall` [source][firewall] | info/enable/disable/reset; channel/lun/netfn/command/subfn/force | N | Every mask level, supported/configurable bits, protected commands/force/partial settings; not output alone | R/W; P3/P4 |
| C29 `delloem` [source][delloem] | lcd/mac/lan/setled/powermonitor/vFlash; mode/line/status, LOM/failover, counters/budgets/powercap | N | Dell-generation capabilities, NIC/display/drive LEDs, units/counter clearing/budgets/vFlash; unknown vendor records are not support | R/W/V, Dell; P3/P6 |
| C30 `shell` [source][shell] | Conditional readline entry, interaction/history/TAB insertion, dispatch, help/?, quit/exit | N | With/without readline, PTY editing/quotes/keepalive, post-error session, EOF/signals/history/secrets; reference disables completion, so adding it changes behavior | T/R/W; P2/P5; K06 |
| C31 `exec` [source][shell] | Command sequences from files | N | Comments/blank lines/length/tokenization, file failure, continuation after errors, final status, runtime settings/session reuse | F/R/W; P2/P5 |
| C32 `set` [source][shell] | host/hostname, user/username, pass/password, privlvl/authtype/localaddr/targetaddr/port/csv/verbose | N | Each field/alias, missing/invalid values, effect on following commands, reconnect/session boundaries | T/R/W; P2/P5 |
| C33 `echo` [source][shell] | Script echo with zero/multiple arguments | N | Separators/newlines/empty strings/exit code; missing help description is not exclusion | F/T; P2 |
| C34 `hpm` [source][hpm] | check; upgrade component/activate/force/debug; compare component/debug; activate/norollback; targetcap/compprop/abort/upgstatus/rollback/rollbackstatus/selftestresult | N | HPM.1 images/components/upload/activation, progress/retries/rollback/interruption; measure manual download/all versus dispatcher discrepancies | R/W/F/V, PICMG HPM; P6 |
| C35 `ekanalyzer` [source][ekanalyzer] | FRU-file frushow, print carrier/power/all, summary match/unmatch/all | N | File roles/topology/link matching/power budgets, malformed/truncated FRU, output order/errors; offline output also requires parity | F/V formats; P3 |
| C36 `ime` [source][ime] | info/update/rollback | N | Intel ME image/state/modes/chunks/failure recovery/rollback and hardware-version restrictions | R/W/F/V, Intel ME; P6 |
| C37 `vita` [source][vita] | properties/frucontrol/addrinfo/activate/deactivate/policy get/set/LED prop/cap/get/set | N | VITA 46.11 group/FRU/site, policy masks, LEDs/activation/effects/unsupported completion codes | R/W/V; P3/P6 |
| C38 `lan6` [source][lan6] | print/save/set nolock/lock/commit/discard; support/enables/traffic_class/hops/flow_label/address/DUID/DHCPv6/router tables | N | Every configuration parameter/set/block selector, IPv6 byte order, read-only fields, transaction locks/commit/discard, save scripts/post-failure state | R/W/F; P3/P4 |
| C39 `help` [source][main] | Generic help, command list, unknown commands | N | Conditional entries/hidden descriptions/aliases, no command, output channels/status; do not hardcode manual examples | F; P2 |

## Interfaces and platforms

Each interface needs normal round trips, request/response sizes, timeout/cancellation, denied access, disconnection and cleanup, followed by its applicable command/privilege cases.
Matching a name is not a port. Record buildability and hardware availability separately.

| ID / `-I` | Pinned source | Dependencies and specific acceptance | Current / stage |
|---|---|---|---|
| T01 `bmc` | [bmc][tbmc] | Solaris BMC driver, STREAMS/ABI, paths, permissions/completion codes | N + environment missing; P2/P7 |
| T02 `dbus` | [dbus][tdbus] | OpenBMC/libsystemd, service/method signatures, error mapping/policy denial | N + environment missing; P2/P7 |
| T03 `dummy` | [dummy][tdummy] | Actual Linux DummyIPMI local-socket protocol/lifecycle; not an alias of the UDP fixture | N; P1/P2 |
| T04 `free` | [free][tfree] | libfreeipmi, supported OS drivers/devices, version branches, probing/error mapping | N + dependencies/devices missing; P2/P7 |
| T05 `imb` | [imb][timb] | Intel IMB driver ABI, send/receive/timeout/permissions | N + environment missing; P2/P7 |
| T06 `lan` | [lan][tlan] | IPMI 1.5/RMCP, authentication capabilities/activation/types, ASF, bridging, sequence/retry/OEM quirks | N + K01/K04; P2/P7 |
| T07 `lanplus` | [lanplus][tlanplus] | RMCP+, actual suite 0..17 success/failure, automatic selection, Kg/privilege, SOL/bridging/cache/retry/size adaptation | P/D: suite 17/User/read-only subset; P2/P5/P7; K01–K04 |
| T08 `lipmi` | [lipmi][tlipmi] | Solaris 9 headers/driver, legacy ABI/errors | N + environment missing; P2/P7 |
| T09 `open` | [open][topen] | Linux OpenIPMI and source FreeBSD branch, multiple devices/ioctl/events/bridging differences | N + OS/devices missing; P2/P5/P7 |
| T10 `serial-basic` | [basic][tserialbasic] | POSIX tty Basic framing/escaping/checksum, baud/system-interface mode, terminal restoration | N + serial peer required; P2/P7 |
| T11 `serial-terminal` | [terminal][tserialterminal] | POSIX tty Terminal encoding/line boundaries/fragments, baud/system mode/restoration | N + serial peer required; P2/P7 |
| T12 `usb` | [usb][tusb] | AMI OEM USB, OS driver/device, encapsulation/polling/access/disconnection | N + AMI environment missing; P2/P7 |

## Global CLI options

Use [OPTION_STRING and its branches][main] for the inventory and cover full/restricted builds.
Compare CLI/environment/file/default/repeated-option precedence. Requiring a library caller to implement an option is not completion of that CLI feature.

| ID | Options | Specific acceptance and current gap | Stage / conflict |
|---|---|---|---|
| O01 | `-h -V` | N: help/version/program identity/exit and full/restricted lists | P2; K10 |
| O02 | `-I -d -D` | N: interfaces/default/device index/tty/baud/system mode/dependency errors | P2/P7; K09 |
| O03 | `-H -p -4 -6` | P: explicit Addr only; DNS, IP-family selection/default port/invalid and special addresses missing | P2; K07 |
| O04 | `-U -P -a -E -f` | N/P: no CLI credential sources; empty/length/prompt/environment precedence/files/argv hiding | P2; K01/K06 |
| O05 | `-L -A` | P/D: fixed User; other roles/default Administrator, lookup + and IPMI 1.5 auth types missing | P2; K01/K02 |
| O06 | `-C -k -K -y -Y` | P/D: suite 17 only; explicit/automatic selection, text/hex/env/prompt Kg and invalid input | P2; K01 |
| O07 | `-t -T -b -B -l -m` | N: single/dual bridges, destination/transit channel/address/LUN/defaults/forced privileges | P2; K02/K07 |
| O08 | `-N -R -z` | P/D: different timeout semantics; retries/zero/defaults/command-specific overrides/communication size limits/probing | P2; K04 |
| O09 | `-v -c` | N: per-command verbosity/CSV support, error routing/format/precision/packet logs | P2/P3; K06/K10 |
| O10 | `-S` | N: SDR cache load/validation, online missing/stale cache, lookup/read effects | P3; K08/K09 |
| O11 | `-O` | N: OEM SEL descriptions, syntax/lookup/precedence/parse errors | P3/P6; K08/K09 |
| O12 | `-o -g -s` | N: eight OEM profiles/list/help/deprecated shortcuts/protocol changes | P2/P6; K01/K09 |
| O13 | `-e` | N: SOL escapes/repetition/no TTY/nested shell or SSH | P5 |
| O14 | `-Z` | N: UTC/local time/sentinels/DST/invalid time/multiple outputs | P3; K08/K10 |

## Daemon and cross-cutting behavior

| ID | Scope and source | Current gap and specific acceptance | Resources / stage |
|---|---|---|---|
| D01 | `ipmievd open` [source][evd] | N: kernel asynchronous events, receiver configuration, decoding/duplicates/loss; record setting effects | L/R/W, driver event source; P5/P7 |
| D02 | `ipmievd sel` [source][evd] | N: intervals/initial baseline, clearing/rotation/overflow, duplication/failure recovery, SDR interpretation | R/W, event fixture; P5/P7 |
| D03 | daemon/nodaemon/pidfile/timeout, signals/logs [manual][evdman] | N: daemonization/PID/syslog facility/stderr/permissions/duplicate startup/abnormal exit | L/F, isolated processes; P5 |
| X01 | Authenticated packet correlation/validation | D: [24-case comparison](COMPARISON.md) demonstrates responder/netfn/LUN/checksum differences; extend to other transports/all boundaries | P1/P2; K03 |
| X02 | RAKP/HMAC/AES, session identity/sequence/replay/padding | P/U: existing positive/negative tests are not complete differential coverage; algorithms/fields/random relations/failure stages | P2; K01/K03 |
| X03 | Deadlines/retry/backoff/cancel/close/abort, concurrency/session reuse | D: no-retry/local-abort versus reference close/wait; inject faults at each exchange/multichunk step and compare cleanup/total duration | P2/P5; K04 |
| X04 | Completion codes/errors/exit/partial output/missing capabilities | P/U: typed errors are not CLI error parity; every command's output/status/continuation, including unknown/OEM codes | P2–P6 |
| X05 | Text/numbers/time/binary exports | P/D: existing comparisons normalize fields; exact POH API minutes differ from reference float display; add encodings/vendor names/units/precision/order/empty/locale/DST; do not skip differences | P3; K08/K10 |
| X06 | Automatic OEM detection/profiles [source][oem] | N: supermicro/intelwv2/intelplus/icts/ibm/i82571spt/kontron/quanta; manufacturer/product branches, IBM data, PICMG/VITA probes | V; P2/P6 |
| X07 | Files/scripts/install [directory][contrib] | N: enterprise-numbers, OEM maps, manuals, services, bmclanconf, bmc-snmp-proxy, exchange-bmc-os-info, collect/log/RRD/web examples; call contracts/paths/permissions/dependencies | F/R/W, isolated shell/SNMP/RRD; P3–P7 |
| X08 | Crypto/driver/runtime dependencies/build variants [configure][configure] | P/U: native/OpenSSL 3 does not cover libcrypto/internal MD5/readline/FreeIPMI/libsystemd combinations; pin supported/failing profiles | P1/P2/P7; K09 |
| X09 | CLI signals/TTY/pipes/redirection/batches | N: SIGINT/EOF/broken pipe/exit, prompts/history/terminal recovery/session closure | T/F; P2/P5; K06 |
| X10 | File security/permissions/symlinks/overwrite | N: both ENABLE_FILE_SECURITY builds, missing/unreadable/length/format errors, cache/script/image import/export; separate defect blockers | F; P1/P3/P6; K09/K10 |
| X11 | Chunks/size negotiation/reservations/repository changes | P/D: current 16-byte FRU chunks, bounded traversal and SEL-change rejection; compare adaptive sizing/retry/partial/total behavior | P3; K04/K08 |
| X12 | Platform/device-capability/role combinations | U: two-platform subset CI only; substantiate each T row/resource requirement with model/firmware/channel/role records; missing resources cannot pass | P7 |
| X13 | Manual/help/source disagreements and unstable behavior | U: cipher defaults, HPM download, GUID spelling, undescribed subcommands; retain actual P1 reference outputs and decide each case | P1; K10 |

## Executed P1 leaf seeds

See [reference profiles and leaf evidence](IPMITOOL_REFERENCE.md): 71 reference states (70 observed, one build-blocked) and 24 diagnostic projections across 62 executions. Scripts emit stable per-leaf IDs, stdout/stderr/exit and traces. These are partial G1/semantic seeds; every family status above remains unchanged. Additional subcommands, parameters, privileges, builds and failures still need expansion.

## Implemented management reads

[Four actual client APIs](MANAGEMENT.md) add self-test results, global enables, watchdog status and POH. Their report has 56 output projections, eight completion-error projections, 11 moon-only length checks and one `DIVERGENT_DISPLAY_PRECISION` leaf, across 127 executions. `C05.poh.unit-1-count-16777217` retains exact raw/API minutes while reference display loses one minute (K10 decision). Self-test projections preserve the different MC/chassis outputs and exits. C05/C08 remain partial; no full CLI/default/privilege/hardware equivalence is claimed.

## Example leaf records for review

These are future test designs, not results from this task. Every record also needs G0–G7 evidence.

| Proposed leaf ID | Input/fault | Required comparisons | Current status |
|---|---|---|---|
| C12.print.word.short-count | Same word-access FRU with a valid short read | Offset/count units, progress, all areas/output, subsequent requests/retries/close; extend the fixture beyond field sets | PARTIAL |
| C14.elist.oem.relative-time | Standard/OEM SEL, relative/unspecified times, absent SDR | Order/time text/OEM interpretation/stderr/exit/extra SDR requests/empty-result semantics | NOT_IMPLEMENTED |
| C10.fill.file.mid-failure | Resettable repository; fail chunk N | Before/after records, reservation/clear/commit, retries, partial writes/exit; no assumed rollback | NOT_IMPLEMENTED; development prohibited now |
| T07.auto-cipher.no-17 | Isolated suite-3-only peer; separately fail capability query | Reference selection/fallback/handshake/error; decide K01 before changing moonipmi policy | BLOCKED_DECISION |
| X01.response.checksum | Valid HMAC with deliberately wrong IPMI checksum | Acceptance/rejection, continued waiting/output/close; retain the known difference | DIVERGENT |
| O04.password.sources | Synthetic env/file/argv/prompt combinations and empty values | Precedence/prompt/TTY/length/errors/logs; public synthetic secrets only | NOT_IMPLEMENTED |
| D02.poll.sel-cleared | Clear/add/reuse IDs while polling a simulated SEL | Lost/duplicate reports, syslog/period, recovery/cleanup | NOT_IMPLEMENTED |
| C34.upgrade.interrupted | Lawful synthetic HPM image; disconnect during upload/activation | Accepted components/state/retry/query/failure/rollback; later real hardware must be recoverable and separately authorized | NOT_IMPLEMENTED; development prohibited now |

Actual reports must add both commits, profile, date, evidence paths, differences and reviewer fields.
Unexecuted examples are designs, not passing results; actual P1 evidence is separately linked above. The [completion rules](IPMITOOL_PARITY_PLAN.en.md) govern the overall conclusion.

[raw]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_raw.c
[lanp]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_lanp.c
[chassis]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_chassis.c
[event]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_event.c
[mc]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c
[sdr]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sdr.c
[sensor]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sensor.c
[fru]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_fru.c
[gendev]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_gendev.c
[sel]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sel.c
[pef]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_pef.c
[sol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sol.c
[tsol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_tsol.c
[isol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_isol.c
[user]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_user.c
[channel]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_channel.c
[session]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_session.c
[dcmi]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_dcmi.c
[sunoem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sunoem.c
[kontronoem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_kontronoem.c
[picmg]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_picmg.c
[fwum]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_fwum.c
[firewall]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_firewall.c
[delloem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_delloem.c
[shell]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmishell.c
[hpm]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_hpmfwupg.c
[ekanalyzer]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_ekanalyzer.c
[ime]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_ime.c
[vita]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_vita.c
[lan6]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_lanp6.c
[main]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_main.c
[evd]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmievd.c
[evdman]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/doc/ipmievd.8.in
[oem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_oem.c
[contrib]: https://github.com/ipmitool/ipmitool/tree/19d78782d795d0cf4ceefe655f616210c9143e62/contrib
[configure]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/configure.ac
[tbmc]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/bmc/bmc.c
[tdbus]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/dbus/dbus.c
[tdummy]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/dummy/dummy.c
[tfree]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/free/free.c
[timb]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/imb/imb.c
[tlan]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lan/lan.c
[tlanplus]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c
[tlipmi]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lipmi/lipmi.c
[topen]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/open/open.c
[tserialbasic]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/serial/serial_basic.c
[tserialterminal]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/serial/serial_terminal.c
[tusb]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/usb/usb.c
