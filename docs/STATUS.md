# Scope and evidence / 范围与证据

## Implemented / 已实现

Suite 17 RAKP authentication, protected RMCP+ packets, replay/identity validation,
connected UDP transport, per-exchange deadlines, single-flight requests, User
privilege and close/abort. Three typed read-only commands: Device ID, Chassis
Status and raw Sensor Reading, plus SDR repository traversal and Full/Compact
sensor interpretation. Protocol/session logic is MoonBit; cryptographic
primitives are supplied by OpenSSL 3 through a small C adapter.

已实现套件 17 RAKP 认证、受保护 RMCP+ 报文、防重放/身份校验、连接式 UDP、逐次超时、
单在途请求、User 权限及关闭/中止。提供设备标识、机箱状态、传感器原始值三项类型化只读命令，以及 SDR 仓库遍历和 Full/Compact 解释。
MoonBit 负责协议和会话，薄 C 适配调用 OpenSSL 3 密码学原语。

## Read-only diagnostics / 只读诊断

Current unreleased source also provides chassis capabilities/restart cause,
validated basic FRU inventory (byte/word access), and bounded SEL enumeration with
raw OEM retention and standard event metadata. FRU/SEL enforce total size/count
and overall deadlines. See [scope and reproduction](DIAGNOSTICS.md). Local macOS
verification passes 41 native test groups and the focused ipmitool 1.8.19
comparison/boundary checker. Exact-commit CI is separate evidence; no real BMC
validation or publication is claimed.

当前未发布源码新增机箱能力/重启原因、经校验的基础 FRU（字节/字访问）和有界 SEL 枚举，
保留 OEM 原始记录，解析标准事件元数据。FRU/SEL 限制总量及整体时长。
本地 macOS 已通过 41 组原生测试和聚焦 ipmitool 1.8.19 对照/边界检查；确切提交的 CI
是独立证据，不宣称实机验证或已发布。

## Management reads / 管理状态读取

The current source also implements `self_test`, `global_enables`, `watchdog_timer`
and `power_on_hours`. Local native tests now total 46 groups. The new checker
records 56 output projections, eight completion-error projections, 11 moon-only
length boundaries and one POH display-precision difference across 127 executions.
See [API semantics and evidence](MANAGEMENT.md). These actual read-only APIs do
not add a compatible CLI, controls or real-device evidence.

当前源码还实现四个管理状态读取 API；本地原生测试增至 46 组。新检查在 127 次执行中记录
56 项输出映射、8 项完成码错误映射、11 项仅 moonipmi 的长度边界及 1 项通电计数显示精度差异。
语义与证据见 [管理状态读取](MANAGEMENT.md)；尚无兼容 CLI、控制功能或实机证据。

## Full-parity work / 完整对齐工作

P1 now identifies an unpatched reference build and per-platform CI artifacts,
records 71 reference leaf states (70 observations, one build blocker), and checks
24 diagnostic projections across 62 executions. Known restart text and SEL version
encoding gaps are corrected. See [reference evidence and remaining decisions](IPMITOOL_REFERENCE.md)
and the [full acceptance matrix](IPMITOOL_PARITY_MATRIX.en.md). No family has passed
full parity; there is no compatible CLI or real-BMC evidence. Authentication and
packet-validation differences remain recorded, without relaxing the current policy.

P1 已固定首个无补丁参考构建及各平台 CI 产物，记录 71 个参考叶项状态（70 已观察、1 构建阻塞），
并验证 62 次执行中的 24 项诊断映射，修正已知重启描述和 SEL 版本编码缺口。
详见 [P1 证据与待决定事项](IPMITOOL_REFERENCE.md)和[完整矩阵](IPMITOOL_PARITY_MATRIX.md)。
没有功能族通过完整一致验收，尚无兼容 CLI 或实机证据，认证及报文校验差异保留，未放宽策略。

## Earlier verified evidence / 早期已验证证据

- 24 native test groups on macOS: codecs, malformed inputs, RAKP/KDF, protected
  packet tampering/truncation/replay, all AES padding residues, deadlines and cleanup.
- RFC 4231 HMAC-SHA256 and NIST SP 800-38A raw AES-CBC vectors.
- Independent Python HMAC/OpenSSL-generated synthetic RAKP/KDF/packet vectors.
- An independent loopback Python BMC validates the full handshake, three reads,
  and graceful close. The in-process MoonBit mock additionally covers failure paths.
- Default native check/test/build, offline example, and a separate downstream
  workspace consumer built without custom link flags and passed the Python exchange.
- ipmitool 1.8.19 independently cross-checked the Python fixture: suite 17,
  synthetic Device ID and graceful close. This validates the fixture, not real hardware.
- Focused read-only review of authentication, FFI lengths and error cleanup.

macOS 已验证：24 组 native 测试；RFC/NIST 密码学向量；Python 独立生成的合成会话/报文向量；
独立 Python 本地 BMC 全握手、三项读取、关闭会话；MoonBit 内置模拟器验证失败路径；
默认检查/测试/构建、离线示例及无需自定义链接参数的独立消费方构建与交互。
ipmitool 1.8.19 已独立交叉验证 Python 模拟器的套件 17、合成设备标识及关闭；不是硬件验证。
已完成一次认证、FFI 长度及错误清理的聚焦只读审查，不等于安全审计。

The expanded baseline at `92301fd` passed both Linux and macOS CI:
[verified run](https://github.com/pangbit/moonipmi/actions/runs/42864609585).
Both jobs passed the 23 native tests, check/build, offline example and complete
MoonBit/Python loopback exchange. The 30-case three-client matrix and both
response-address probes passed in the **Linux job**; those optional steps are
skipped in macOS CI and have separate local macOS evidence above. This is evidence
for that exact revision, not a claim about untested future commits.

扩展基线 `92301fd` 已通过上述 Linux/macOS CI。两个任务均通过 23 组 native 测试、
检查/构建、离线示例及 MoonBit/Python 完整本地交互。30 项三客户端矩阵与两个响应地址探针
在 **Linux 任务**中通过；macOS CI 跳过这些可选步骤，其本地 macOS 证据见上。
该结果对应这一确切版本，不替代后续提交的验证。

## SDR subset / SDR 子集

The original SDR stage passed 32 native test groups on local macOS, 33 output comparisons
across moonipmi and actual ipmitool 1.8.19 `sdr list all`/`sensor list`, and nine
repository boundary scenarios. Linux CI includes the same SDR comparison; macOS
CI now builds the pinned reference and runs diagnostic comparisons, while the SDR comparison remains Linux-only in CI. See [scope and reproduction](SDR.md).
These local results do not substitute for CI on a specific commit.

原 SDR 阶段在本地 macOS 通过 32 组 native 测试、moonipmi 与实际 ipmitool 1.8.19
`sdr list all`/`sensor list` 的 33 项输出对照及九项仓库边界场景。Linux CI 加入相同 SDR 对照，
macOS CI 现已构建固定参考并运行诊断对照，SDR 对照在 CI 中仍仅由 Linux 执行。范围及复现见 [SDR 文档](SDR.md)。
本地结果不替代确切提交的 CI 证据。

## Not verified / 尚未验证

No real hardware BMC, production network, platform certification, exhaustive IPMI
conformance or external security audit. Full three-read interoperability with the
pinned go-ipmi BMC has not passed because it does not implement Get Sensor Reading.

未验证真实 BMC、生产网络、平台认证、完整规范一致性或外部安全审计。
固定 go-ipmi BMC 未实现 Get Sensor Reading，尚未通过完整三读互操作。

## Requester compatibility and reference limit / 请求者兼容与对照限制

The current unreleased source tolerates the response requester byte like ipmitool
1.8.19 while preserving all other existing checks. Local macOS verification passed
24 native test groups, the 24-case response-policy comparison and the existing
30-case three-client matrix. See [exact policy, retained differences and risks](COMPARISON.md).
These current local results do not replace CI evidence for a specific commit.

At go-ipmi commit `d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6`, responses hardcode
requester `0x20`, rather than echoing `0x81`. moonipmi and ipmitool now both return
matching Device ID and Chassis Status from this unmodified BMC; both receive sensor
completion `0xc1`. The former requester rejection had hidden this separate command
limit. Python remains the independent three-read target. See [demo instructions](DEMO.md).
Mooncakes 0.1.0 remains unchanged and still rejects the requester mismatch.

当前未发布源码与 ipmitool 1.8.19 一样容忍响应请求者字节，保留其他既有检查。
macOS 本地已通过 24 组 native 测试、24 项报文策略对照和既有 30 项三客户端矩阵。
具体策略、保留差异和风险见对照文档；当前本地结果不替代确切提交的 CI 证据。
固定 go-ipmi 服务端将请求者硬编码为 `0x20`，未回显 `0x81`。两客户端现均能读取一致的
设备标识和机箱状态，传感器均收到 `0xc1`。旧地址拒绝曾遮住此独立命令限制。
独立三读目标仍是 Python 模拟器。Mooncakes 0.1.0 未变，仍拒绝请求者地址不匹配。

## Common-target client comparison / 同目标客户端对照

The three clients (moonipmi, pinned go-ipmi, ipmitool 1.8.19) passed 30 cases on
one independent Python fixture: three read-only results, representative status boundaries and two error classes.
See [comparison scope, normalized fields, differences and reproduction](COMPARISON.md).
The separate response-policy comparison records requester tolerance and retained
strict checks. Neither comparison proves hardware compatibility.

三客户端在同一独立 Python 模拟器上通过 30 项：三项只读结果、代表性状态边界和两类错误。
范围、归一化字段、差异及复现见对照说明；独立报文策略对照记录请求者宽容和保留的严格检查。
这些对照均不表示硬件兼容已验证。

## Release gate / 发布门槛

Pass the Linux/macOS CI, inspect package contents and privacy/secret checks,
confirm native downstream-consumer support and registry requirements.
Hackathon acceptance is separate and is not claimed by this package release.
Describe the release as an experimental read-only subset. Hardware access, if
needed later, requires a separately authorised target and account.

发布前需要 Linux/macOS CI、打包内容与敏感信息检查、原生消费方兼容性验证，以及包仓库要求确认。
本次包发布不表示赛事资格已通过或已完成活动报名。
发布描述应准确写明实验性只读子集。后续真实硬件验证必须另有明确授权的目标与账号。

## Explicit exclusions / 明确不含

No anonymous access, downgrade fallback, IPMI 1.5, Kg override, OEM/SOL, hardware
writes, automatic reconnect/retry, nonlinear/OEM sensor conversion, Device SDRs,
bridging, shared Compact expansion or network scanning. Each exchange fails closed; an application may explicitly reconnect.
The module uses the toolchain's documented experimental native build-config API;
that API and its pinned toolchain compatibility are maintenance considerations.

不含匿名、降级、IPMI 1.5、Kg 覆盖、OEM/SOL、硬件写操作、自动重连/重试、非线性/OEM 换算、
Device SDR、桥接、共享 Compact 展开或网络扫描。
每次交换失败即关闭；应用可以明确重新连接。使用官方文档中的实验性原生构建配置 API，
维护时需要关注其变化和固定工具链兼容性。
