# Pending compatibility decisions / 待统一裁决的兼容事项

This register consolidates observed differences and recommendations under K01–K10
of the [full-parity plan](IPMITOOL_PARITY_PLAN.en.md). It does not approve exceptions,
change defaults or narrow the target. The user has instructed that large-count
precision stay unchanged and CLI behavior await a unified decision. Independent
read-only implementation may continue; stateful controls, real-device control and
Mooncakes publication remain outside the current authorization.

本页汇总[完整对齐计划](IPMITOOL_PARITY_PLAN.md) K01–K10 下的实测差异及建议，不批准例外、
修改默认值或缩小目标。用户已要求大计数精度保持现状，CLI 表现等待统一裁决。
独立只读开发继续；有状态控制开发、真实设备控制及 Mooncakes 发布仍不在当前授权内。

| Decision / 事项 | Observed impact / 已观察影响 | Recommendation and status / 建议及状态 |
|---|---|---|
| K10 POH precision / 通电精度 | Reference float display loses a minute at count 16,777,217; API is exact / 参考单精度显示少一分钟，API 精确 | **Preserve exact API: instructed. CLI rounding pending** / **按指示保留精度；CLI 舍入待定**. [Evidence / 证据](MANAGEMENT.md) |
| K10 GUID time / GUID 时间 | Reference uint32/SEL formatter wraps or shows relative time; API retains signed seconds / 参考时间回绕或显示为相对时间 | Preserve raw GUID and signed time; decide CLI timestamp presentation / 建议保留原始值与有符号时间，CLI 显示待定. [Evidence / 证据](IDENTITY.md) |
| K08 System Info strings / 系统信息字符串 | Signed-char long-length behavior, NUL truncation, extra padding and encoding-specific request counts differ / 长度符号性、零字节截断、填充及编码请求数不同 | Preserve declared-length raw values; text/request emulation remains pending / 建议保留声明长度原始值，文本/请求模拟待定. [Evidence / 证据](IDENTITY.md) |
| K08/K10 partial failures / 部分失败 | System Info errors can exit 0 with partial text; channel-info later errors retain prior sections and exit nonzero; malformed cipher records print a prefix and exit 0 / 三类命令的部分输出及退出行为不同 | Keep typed failures explicit; settle per-command CLI partial stdout/stderr/exits together / 建议库保持明确错误，逐命令 CLI 部分输出及退出码统一裁决. [Identity](IDENTITY.md), [channel](CHANNEL.md) |
| K10 cipher printing / 套件列表显示 | Measured reference prints at most 12 records; multiple unknown labels can alias depending on compiler / 参考最多显示 12 条，多个未知标签可能随编译器出现别名 | Preserve all records and distinct algorithm IDs; do not silently copy truncation or claim equality / 建议保留完整列表与各算法 ID，不静默复现截断或宣称一致；待裁决. [Evidence / 证据](CHANNEL.md) |
| K01/K02 authentication and privilege / 认证与权限 | Suite 17/nonempty credentials/User/role 02 differ from reference options/defaults and role 12 / 与参考认证范围、默认权限和 lookup 位不同 | Keep current defaults while weak/legacy modes and privilege policy await explicit review / 保持当前默认值，弱/旧认证及权限策略待明确审核. [Plan / 计划](IPMITOOL_PARITY_PLAN.md) |
| K03 packet validation / 报文校验 | Authenticated responder/netfn/LUN/checksum acceptance differs / 已认证报文的相关字段接受行为不同 | Retain current checks pending decision; stricter is not equivalent / 待裁决前保留检查，更严格不等于一致. [24-case evidence / 24 项证据](COMPARISON.md) |
| K04/K08 bounds and cleanup / 边界与清理 | No retries, whole-operation bounds, strict record/metadata failures and local abort differ / 无重试、整体限制、严格校验及本地中止有差异 | Preserve bounded reads now; review retry, partial-result and cleanup contracts together / 当前保留有界读取，重试、部分结果和清理合同统一审核 |
| K05/K06 controls and secrets / 控制与秘密 | Arbitrary writes/controls and reference credential/logging paths are not implemented / 任意写控制及参考凭据/日志路径未实现 | No expansion into controls or real-secret exposure in this batch / 本批不扩展控制或真实秘密暴露；继续保留阻塞 |
| K07/K09 environments / 环境 | Single-peer native transport and one four-interface reference profile do not cover all platforms/builds / 单对端传输与首个四接口 profile 不覆盖全平台/构建 | Keep missing transports, profiles and hardware visible; never replace missing evidence with PASS / 缺失接口、构建和硬件继续明确标记，不以通过替代证据 |

Recommendations above are proposals, not user decisions. Preserving an observable
difference prevents an unqualified “no omissions or differences” claim. Unknown
or unsafe upstream behavior must remain a documented blocker rather than being
silently omitted or reproduced. The raw/API layers and a future CLI may need
different contracts; that separation alone does not establish full equivalence.

以上建议不等于用户裁决。保留可观察差异就不能无条件声称“无缺失或差异”。未知或不安全的参考行为
必须继续作为有记录的阻塞，不能静默删去或照搬。原始值/API 与未来 CLI 可能需要不同合同，但分层本身
不构成完整一致证明。
