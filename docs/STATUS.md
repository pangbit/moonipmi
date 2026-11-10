# Scope and evidence / 范围与证据

## Implemented / 已实现

Suite 17 RAKP authentication, protected RMCP+ packets, replay/identity validation,
connected UDP transport, per-exchange deadlines, single-flight requests, User
privilege and close/abort. Three typed read-only commands: Device ID, Chassis
Status and raw Sensor Reading. Protocol/session logic is MoonBit; cryptographic
primitives are supplied by OpenSSL 3 through a small C adapter.

已实现套件 17 RAKP 认证、受保护 RMCP+ 报文、防重放/身份校验、连接式 UDP、逐次超时、
单在途请求、User 权限及关闭/中止。提供设备标识、机箱状态、传感器原始值三项类型化只读命令。
MoonBit 负责协议和会话，薄 C 适配调用 OpenSSL 3 密码学原语。

## Verified locally / 本地验证

- 17 native test groups on macOS: codecs, malformed inputs, RAKP/KDF, protected
  packet tampering/truncation/replay, all AES padding residues, deadlines and cleanup.
- RFC 4231 HMAC-SHA256 and NIST SP 800-38A raw AES-CBC vectors.
- Independent Python HMAC/OpenSSL-generated synthetic RAKP/KDF/packet vectors.
- An independent loopback Python BMC validates the full handshake, three reads,
  and graceful close. The in-process MoonBit mock additionally covers failure paths.
- Default native check/test/build, offline example, and a separate downstream
  workspace consumer built without custom link flags and passed the Python exchange.
- Focused read-only review of authentication, FFI lengths and error cleanup.

macOS 已验证：17 组 native 测试；RFC/NIST 密码学向量；Python 独立生成的合成会话/报文向量；
独立 Python 本地 BMC 全握手、三项读取、关闭会话；MoonBit 内置模拟器验证失败路径；
默认检查/测试/构建、离线示例及无需自定义链接参数的独立消费方构建与交互。
已完成一次认证、FFI 长度及错误清理的聚焦只读审查，不等于安全审计。

## Not verified / 尚未验证

No real hardware BMC, production network, platform certification, exhaustive IPMI
conformance, external security audit or executable go-ipmi differential. Linux
CI is a release gate, not a completed result in this milestone. The reference
implementation has been reviewed at the exact revision linked in the README.

未验证真实 BMC、生产网络、平台认证、完整规范一致性、外部安全审计或 go-ipmi 可执行差分。
Linux CI 是发布门槛，当前不能当作已完成结果。对照源码版本见 README。

## Release gate / 发布门槛

Pass the Linux/macOS CI, inspect package contents and privacy/secret checks,
confirm native downstream-consumer support and publication/event requirements.
Describe the release as an experimental read-only subset. Hardware access, if
needed later, requires a separately authorised target and account.

发布前需要 Linux/macOS CI、打包内容与敏感信息检查、原生消费方兼容性验证，以及包仓库/活动规则确认。
发布描述应准确写明实验性只读子集。后续真实硬件验证必须另有明确授权的目标与账号。

## Explicit exclusions / 明确不含

No anonymous access, downgrade fallback, IPMI 1.5, Kg override, OEM/SOL, hardware
writes, automatic reconnect/retry, SDR-based physical-unit conversion or network
scanning. Each exchange fails closed; an application may explicitly reconnect.
The module uses the toolchain's documented experimental native build-config API;
that API and its pinned toolchain compatibility are maintenance considerations.

不含匿名、降级、IPMI 1.5、Kg 覆盖、OEM/SOL、硬件写操作、自动重连/重试、SDR 物理单位换算或扫描。
每次交换失败即关闭；应用可以明确重新连接。使用官方文档中的实验性原生构建配置 API，
维护时需要关注其变化和固定工具链兼容性。
