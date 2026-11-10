# Changelog / 更新记录

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
