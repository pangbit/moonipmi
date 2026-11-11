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
| K08/K10 partial failures / 部分失败 | System Info errors can exit 0 with partial text; channel-info later errors retain prior sections and exit nonzero; malformed cipher records print a prefix and exit 0; user/session scans retain earlier rows on failure / 各类命令的部分输出及退出行为不同，用户/会话扫描失败保留前面记录 | Keep typed failures explicit; settle per-command CLI partial stdout/stderr/exits together / 建议库保持明确错误，逐命令 CLI 部分输出及退出码统一裁决. [Identity](IDENTITY.md), [channel](CHANNEL.md), [users](USERS.md), [sessions](SESSIONS.md) |
| K03/K04/K10 session decoding and selectors / 会话解码与选择器 | Reference PPP port reads the LAN union offset; malformed-length records are padded/truncated or reuse prior fields; uint32 handles truncate to bytes / 参考 PPP 端口取 LAN 偏移，坏长度补零/截断或沿用先前字段，uint32 句柄截成一字节 | Preserve the wire serial port, complete layouts and byte-sized handles; decide CLI emulation separately / 建议保留报文中的串口端口、完整布局及字节范围句柄，CLI 模拟待统一裁决. [43 differences plus one observation / 43 项差异及一项观察](SESSIONS.md) |
| K06/K08 username rendering / 用户名显示 | Reference prints name bytes directly, including commas/quotes/newlines in CSV; three observed cases / 参考直接打印名字字节，CSV 中的逗号/引号/换行也不转义，已有三项观察 | Preserve raw bytes and distinguish missing versus empty names; CLI quoting/logging policy pending / 保留原始字节及缺失/空名字区别，CLI 引用与日志规则待定. [Evidence / 证据](USERS.md) |
| K10 cipher printing / 套件列表显示 | Measured reference prints at most 12 records; multiple unknown labels can alias depending on compiler / 参考最多显示 12 条，多个未知标签可能随编译器出现别名 | Preserve all records and distinct algorithm IDs; do not silently copy truncation or claim equality / 建议保留完整列表与各算法 ID，不静默复现截断或宣称一致；待裁决. [Evidence / 证据](CHANNEL.md) |
| K01/K02 authentication and privilege / 认证与权限 | Suite 17/nonempty credentials/User/role 02 differ from reference options/defaults and role 12 / 与参考认证范围、默认权限和 lookup 位不同 | Keep current defaults while weak/legacy modes and privilege policy await explicit review / 保持当前默认值，弱/旧认证及权限策略待明确审核. [Plan / 计划](IPMITOOL_PARITY_PLAN.md) |
| K04 capability-query fallback / 能力查询回退 | Reference retries without the extended-data bit after a failed query, even on permission denial; API returns the first failure. Both stay suite17/User / 参考首次失败（含权限拒绝）后清除扩展位重查，API 返回首次错误，双方仍为 suite17/User | Keep the single-query default; consider an explicit same-session option with at most one fallback and preserved first completion code; future CLI behavior pending / 建议保留单次查询默认值，后续考虑显式选项：同一会话最多回退查询一次并保留首次完成码；未来 CLI 行为待定. [Six cases / 六项证据](NETWORK_STATUS.md) |
| K03/K10 network response lengths / 网络响应长度 | Authcap/statistics reference ignores extra bytes and prints values for incomplete data; bytes outside supplied responses are not assumed stable / 参考能力/统计查询忽略多余字节，短响应仍打印，未返回字节的取值不假定稳定 | Keep complete-layout checks and raw values; do not emulate unspecified tail reads / 建议保留完整布局校验与原始值，不模拟未指定尾部取值，兼容规则待裁决. [Evidence / 证据](NETWORK_STATUS.md) |
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
