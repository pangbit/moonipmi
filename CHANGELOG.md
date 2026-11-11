# Changelog / 更新记录

## Unreleased / 未发布

- Match ipmitool 1.8.19 requester-address tolerance by default, preserving all
  other existing validation. Add 24 authenticated response-policy comparisons
  and document retained differences and risks.
- Add a pinned, loopback-only go-ipmi BMC comparison: Device ID and Chassis Status
  match ipmitool; both receive sensor completion `0xc1`. No full three-read claim.
- Add status/completion-code diagnostics without credentials or packet contents,
  an address-mismatch regression, and bilingual reproducible demo instructions.
- Reject IPv4-mapped IPv6 destinations so they cannot bypass IPv4 multicast/
  unspecified/broadcast checks; use plain IPv4 addresses instead.
- Cross-check the Python fixture with the independent ipmitool client, restricted
  to loopback, suite 17, synthetic Device ID and close.
- Add a common-fixture comparison of moonipmi/go-ipmi/ipmitool: three reads and
  two errors, plus a direct address-tolerance probe.
- Expose Device SDR/additional-support metadata, common chassis fault helpers,
  and an optional usable raw sensor reading that excludes unavailable/disabled
  scanning without confusing event-message disabling with reading failure.
- Extend the same-target comparison to 30 cases with representative status
  boundaries; use non-reserved sensor `0xfe` for the absent-sensor test.
- Keep package publication manual; no release automation or version change.

- 默认与 ipmitool 1.8.19 的请求者地址宽容行为对齐，保留其他既有校验；
  增加 24 项已认证报文策略对照，记录保留差异与风险。
- 增加固定版本、仅本机的 go-ipmi BMC 对照：设备标识和机箱状态与 ipmitool 一致，
  两者传感器均返回 `0xc1`，不宣称完整三读互通。
- 增加不含凭据或报文的状态码/完成码诊断、地址回归用例与双语复现演示说明。
- 拒绝 IPv4-mapped IPv6 对端，避免绕过 IPv4 multicast/未指定/广播限制；改用普通 IPv4 地址。
- 用独立 ipmitool 客户端交叉检查 Python 模拟器，仅限本机、套件 17、合成设备标识和关闭。
- 增加 moonipmi/go-ipmi/ipmitool 同目标三读/两错误对照及地址宽容探针。
- 补充 Device SDR/额外设备能力、常用机箱故障入口及可选传感器原始值；排除不可用和停扫，
  不把关闭事件消息误判为读数失败。
- 同目标对照扩展至 30 项代表性状态；不存在传感器用非保留编号 `0xfe`。
- 包发布保持手动；未增加自动发布，也未改变版本。

## 0.1.0 (2026-11-10)

- Initial offline IPMI LAN / RMCP+ protocol codecs and read-only command models.
- Strict checksums, response identities, bounded lengths and suite 17 handshake layouts.
- Synthetic tests, offline example and bilingual project documentation.
- Authenticated suite 17 UDP client backed by OpenSSL 3, with replay checks and fail-closed cleanup.
- Independent synthetic loopback BMC and downstream-consumer validation.
- First experimental release; no real-BMC interoperability or full-IPMI claim.

- 初步提供离线 IPMI LAN / RMCP+ 编解码与只读命令模型。
- 严格校验和、响应关联、长度边界与套件 17 握手布局。
- 合成测试、离线示例及双语项目文档。
- 基于 OpenSSL 3 的套件 17 认证 UDP 客户端、防重放与失败关闭。
- 独立合成本地 BMC 和消费方验证。
- 首次实验性发布，不宣称真实 BMC 互操作或完整 IPMI 支持。
