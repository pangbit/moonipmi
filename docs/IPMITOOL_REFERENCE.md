# P1 reference builds and leaf evidence / P1 参考构建与叶用例

P1 is **in progress**. The source/configuration below and each measured executable are identified; the complete platform/dependency matrix is not frozen. No family has passed full parity. This work uses synthetic loopback peers and does not authorize hardware operations, state-changing development or publication.

P1 **进行中**。下列源码、配置及每次实际使用的二进制均有身份记录；全平台和依赖矩阵尚未冻结。没有任何功能族通过完整一致验收。本轮仅用本机模拟器，不授权真实设备操作、有状态控制开发或发布。

## Build contract / 构建合同

`tools/reference_build.py` exports Git object `19d78782d795d0cf4ceefe655f616210c9143e62` from the supplied upstream checkout, ignoring working-tree edits. It builds both `ipmitool` and `ipmievd` without source patches or installation. It does not download IANA data. `lanplus-readonly-v1` enables `lan`, `lanplus`, `serial-basic` and `serial-terminal`, defaults to `lan`, enables all CLI options and SHA256, and disables readline, file-security and other interfaces. The name describes the test scope: the reference executable still contains upstream control commands.

脚本从指定上游仓库导出确切 Git 对象，忽略工作区改动；构建两个程序，不修改上游源码、不安装、不下载 IANA 数据。首个 profile 启用上述四个接口，默认 `lan`，启用全部 CLI 选项及 SHA256，禁用 readline、file-security 和其他接口。名称仅表示测试范围；上游二进制仍包含控制命令。

Build/runtime environment is explicit (`LC_ALL=C`, `TZ=UTC`); comparison subprocesses do not inherit credentials, user registry paths or loader overrides. The pinned synthetic enterprise registry contains only enterprise 343 named `Synthetic fixture vendor`; it is **not** the complete authoritative IANA registry. An empty registry makes this upstream version fail before authentication. OEM names outside this fixture and other data profiles remain unverified.

构建/运行环境明确固定；比较子进程不继承凭据、用户厂商表路径或动态库覆盖设置。固定的合成厂商表只含上述测试项，**不是**完整权威 IANA 数据。上游在空表时会在认证前失败。其他厂商名及数据 profile 仍待验证。

On macOS the build uses `-Wl,-no_fixup_chains`: the unmodified upstream packed Dell table otherwise fails to link with the tested Apple linker because it contains unaligned pointers. This recorded linker choice is not a source patch or proof of Dell functionality. Linux does not use the flag.

macOS 显式使用该链接选项：测试中的 Apple 链接器无法直接处理上游 Dell 紧凑结构表内未对齐的指针。该选项有记录，不是源码补丁，也不证明 Dell 功能通过。Linux 不使用该选项。

`profile.json` records source-archive, binary, daemon, config and data SHA-256; OS/architecture, compiler/autotools, OpenSSL version, configure/environment, enabled features and readable linked-library hashes. `reference_profile.py` checks these files before execution. An explicit `--ipmitool` or PATH fallback is labelled `UNFROZEN_VERSION_ONLY`, never silently promoted. Implementation reports include the binary hash, Git commit and dirty-tree flag; dirty local runs are not exact-commit evidence. CI artifacts bind clean checkout runs to their workflow commit.

profile 记录源码归档、两个程序、配置、数据的哈希，以及系统/架构、工具链、OpenSSL、编译参数、特性和可读取动态库哈希；运行前逐项核对。未提供 profile 的对照明确标记为仅版本号证据。实现端也记录二进制哈希、提交与工作区状态；本地未提交运行不能冒充精确提交证据，CI 产物绑定干净检出提交。

Toolchain packages and OS libraries are fingerprinted, not provided as a hermetic lock or guaranteed bit-for-bit rebuild. Build paths affect the binary/config hashes. Each CI platform produces its own profile; preserve artifacts instead of comparing its binary hash to a different machine's. Other interfaces, readline builds, restricted options, file-security, crypto variants and full data snapshots remain P1 work.

工具链及系统库目前记录身份，并未提供封闭依赖锁或逐字节重构保证；路径会影响二进制及配置哈希。每个平台各自产生 profile 并保留产物，不能强求不同机器哈希相同。其他接口、readline、受限选项、file-security、加密变体及完整数据快照仍属 P1 未完成项。

## Reproduce / 复现

Install C/OpenSSL 3/pkg-config plus Git, Python 3.9+, autoconf, automake and libtool (`glibtoolize` on macOS). Use a new output directory for each build; no `make install` is needed.

安装上述构建依赖；每次构建使用新的输出目录，不运行安装目标。

```sh
git clone --depth 1 --branch IPMITOOL_1_8_19 https://github.com/ipmitool/ipmitool.git _build/ipmitool-source
python3 tools/reference_build.py --source _build/ipmitool-source --output _build/ipmitool-reference
moon build --target native --deny-warn
python3 tools/reference_cases.py --reference-profile _build/ipmitool-reference/profile.json --output _build/reference-cases.json
python3 tools/diagnostics_check.py --reference-profile _build/ipmitool-reference/profile.json --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe --output _build/diagnostics-comparison.json
```

The same `--reference-profile` argument is supported by `compare_clients.py`, `sdr_check.py`, `address_check.py` and the reference modes of `go_interop.py`. Reports/build logs stay under ignored `_build`; do not commit local paths, generated binaries or execution reports. CI retains profiles and reports as artifacts.

原三读、SDR、地址校验及 `go_interop.py` 的参考模式也接受同一参数。报告及日志留在忽略目录，不提交本机路径、二进制或执行报告。CI 以产物保存证据。

## Leaf inventory and actual evidence / 叶项及实际证据

Local validation on 2026-11-11: macOS 27.2 arm64, Apple clang 21.0.0, OpenSSL 3.6.3, autoconf 2.72, automake 1.18.1. This is not Linux/other-platform evidence; consult the new CI run for those results.

本地验证使用上述环境，不能代替 Linux 或其他平台结果；其他平台以本次 CI 实际结果为准。

| Identity / 身份 | SHA-256 |
|---|---|
| Unpatched Git archive / 无补丁源码归档 | `17dd44f0fb6c4017b5446a3fd33fc2407842eeedb4300ea065032556f1f1d03b` |
| Measured local ipmitool / 本地参考程序 | `3a54ae3de3646929a644d23cf33047ad6d3878dcd93435f94eef893b83528eb5` |
| Synthetic registry / 合成厂商表 | `df7ba33bbda02e24d0eb0fb7e750c35c832944caf0ea4c68a875eee2e42694cb` |

| Stable leaf IDs / 稳定叶 ID | Actual result / 实际结果 | Limit / 限制 |
|---|---|---|
| `C01.dispatch-help` … `C38.dispatch-help` | 37 reference observations; `C30` blocked by disabled readline / 37 项参考记录，shell 构建阻塞 | Literal `help` dispatch only; echo/exec/set/TSOL have distinct semantics; no moonipmi CLI / 仅实际分发行为，无兼容 CLI |
| `C39.help`, `O01.help/version/invalid-option`, `O02.invalid-interface`, `D03.help/version` | 7 pre-session reference observations / 7 项会话前参考记录 | Exact stdout/stderr/exit recorded, not parity passes / 输出与退出码记录，不算一致通过 |
| `Oxx.missing-<flag>` | All 26 argument-taking global options reject missing arguments / 26 个必需参数选项的缺参路径 | No valid-value/default/boundary completeness claim / 未覆盖合法值、默认和完整边界 |
| `C05.status.chassis-{basic,faults,buttons,reserved-policy}` | 4 semantic projections pass / 4 项语义映射通过 | All printed status fields checked, not identical CLI/wire sequence / 校验全部打印字段，不代表 CLI 或报文序列相同 |
| `C05.capabilities.raw` | Six bytes match reference raw / 六字节对照通过 | Reference raw query, not a complete chassis family / 仅该 raw 查询 |
| `C05.restart-cause.0` … `.11` | 12 description projections pass / 12 个描述映射通过 | Reserved values remain raw/None; channel checked against fixture / 保留值不解释，通道与 fixture 核对 |
| `C12.print.byte`, `.word` | 2 complete label/value sets pass / 2 组完整标签和值通过 | Basic ASCII fixture; whitespace/file/encoding/multirecord/CLI gaps remain / 基础 ASCII，其他差距保留 |
| `C14.info.basic`, `.version-2` | 2 complete printed-field projections pass / 2 组全部打印字段映射通过 | Two known version encodings, fixed UTC and capability flags / 固定时间和能力组合 |
| `C14.get.raw.1`, `.3`, `.5` | 3 full raw-record comparisons pass / 3 条完整原始记录通过 | Full `sel list` reference stdout additionally asserted; moonipmi lacks its formatter/OEM interpretation / 另断言完整参考列表输出，实现端仍缺格式化及 OEM 解释 |

The diagnostic run has **24 differential projections across 62 executions**, including moonipmi-only short-read, empty and 13 rejection/deadline cases. Do not call these 62 direct comparisons. The reference catalogue has **71 leaf states: 70 observed, one build-blocked**. These seeds do not exhaust nested subcommands, parameter tables, privileges, build variants, error paths or G0–G7.

诊断运行共 **24 项差分映射、62 次执行**，含仅 moonipmi 的短读、空仓库及 13 项拒绝/时限场景，不能把 62 次称为直接对照。参考目录共 **71 个叶项状态：70 已观察、1 构建阻塞**。仍未穷尽嵌套子命令、参数表、权限、构建变体、错误路径及 G0–G7。

Also passed locally with this reference: 41 native tests, offline/independent loopback example, the 30-execution three-client matrix, 33 SDR-backed output projections plus nine repository boundaries, and 24 response-policy executions. These are distinct scopes, not additive coverage percentages. The last matrix still shows authenticated responder/netfn/LUN/checksum differences.

本地还通过原生 41 组、离线及独立模拟示例、三客户端 30 次执行、SDR 33 项输出及 9 项边界、报文策略 24 次执行。不同范围不合并成覆盖率；最后一组依然证明 responder/netfn/LUN/checksum 的接受行为有差异。

## Corrections and decisions / 修正与待决定项

Restart descriptions 1 and 4 now exactly match the known reference strings (`chassis power control command`, `watchdog expired`). SEL info now accepts both reference-recognized version bytes `0x51` and `0x02`, while unknown versions remain errors. These read-only corrections do not change authentication or packet validation.

已修正两个已知重启原因字符串，并接受参考已识别的两种 SEL 版本编码；未知版本仍报错。均为只读修正，不改变认证或报文校验。

For K01–K03, the recommendation for review is to keep suite 17, explicit User privilege and strict authenticated-packet checks as the library defaults. If a reference-compatible mode is required, design it explicitly with synthetic downgrade/default-privilege tests first; do not introduce silent fallback or relax validation now. Keeping the defaults necessarily retains observable differences and cannot satisfy an unqualified “no differences” claim. In particular, accepting a bad IPMI checksum solely because the outer HMAC is valid should remain a recorded divergence unless a concrete compatibility policy is approved.

K01–K03 建议供审核：库默认继续保持套件 17、明确 User 权限和严格的认证后报文校验；如需参考兼容模式，先单独设计，并在合成环境验证降级及默认权限行为，目前不引入静默回退或放宽校验。保留这些默认必然有可观察差异，不能宣称无差异。尤其“外层 HMAC 正确即接受错误 IPMI 校验和”建议继续标记差异，等待具体兼容策略决定。

P1 still needs additional build/data profiles and nested leaf expansion. P2 security/privilege/retry policy decisions, complete CLI/API work, vendor/platform fixtures and eventually separately authorized hardware evidence remain open. The [full matrix](IPMITOOL_PARITY_MATRIX.en.md) keeps all missing/different families in scope; [中文矩阵](IPMITOOL_PARITY_MATRIX.md) retains the same states. Mooncakes publication remains a manual maintainer action.

P1 尚需其他构建/数据 profile 及更深叶项展开；P2 的安全、权限、重试策略、完整 CLI/API、厂商/平台模拟器及以后另行授权的硬件证据均未完成。中英矩阵保留所有缺失/差异，Mooncakes 仍由维护者手动发布。
