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

- 19 native test groups on macOS: codecs, malformed inputs, RAKP/KDF, protected
  packet tampering/truncation/replay, all AES padding residues, deadlines and cleanup.
- RFC 4231 HMAC-SHA256 and NIST SP 800-38A raw AES-CBC vectors.
- Independent Python HMAC/OpenSSL-generated synthetic RAKP/KDF/packet vectors.
- An independent loopback Python BMC validates the full handshake, three reads,
  and graceful close. The in-process MoonBit mock additionally covers failure paths.
- Default native check/test/build, offline example, and a separate downstream
  workspace consumer built without custom link flags and passed the Python exchange.
- Focused read-only review of authentication, FFI lengths and error cleanup.

macOS 已验证：19 组 native 测试；RFC/NIST 密码学向量；Python 独立生成的合成会话/报文向量；
独立 Python 本地 BMC 全握手、三项读取、关闭会话；MoonBit 内置模拟器验证失败路径；
默认检查/测试/构建、离线示例及无需自定义链接参数的独立消费方构建与交互。
已完成一次认证、FFI 长度及错误清理的聚焦只读审查，不等于安全审计。

Linux and macOS CI both passed for source commit `ff71dfe`; see the
[verified run](https://github.com/pangbit/moonipmi/actions/runs/42824737938).
Linux 与 macOS CI 已通过该源码提交，链接见上。

## Not verified / 尚未验证

No real hardware BMC, production network, platform certification, exhaustive IPMI
conformance, external security audit or full go-ipmi interoperability. The pinned
reference BMC has been executed, with the known rejection described below.

未验证真实 BMC、生产网络、平台认证、完整规范一致性、外部安全审计或完整 go-ipmi 互操作。
已执行固定版本参考 BMC，已知拒绝原因见下。

## Known reference incompatibility / 已知对照不兼容

At go-ipmi commit `d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6`,
[`BuildIPMIResponse`](https://github.com/bougou/go-ipmi/blob/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6/pkg/protocol/ipmb.go)
hardcodes `RemoteConsoleAddr = 0x20`; its request parser does not preserve `rqSA`.
Our request uses `rqSA = 0x81` and requires the response to return to that address.
The reference handshake and protected response pass authentication/decryption,
but the first session command's response fails address correlation. No reference
source was changed and no client checks were relaxed. This is a reproducible
compatibility rejection, **not** a successful full exchange or a claim about all
versions/uses of go-ipmi. The pinned test asserts this exact address error after
checksum, netfn/LUN, command and sequence checks; unrelated failures still fail CI.
The independent Python simulator continues to cover all three reads and close.
See [demo instructions](DEMO.md) for both paths.

上述固定版本的参考 BMC 将响应请求者地址硬编码为 `0x20`，请求解析器不保留 `rqSA`。
本客户端使用 `0x81` 并要求响应回到同一地址。参考握手及受保护响应已通过认证/解密，
但第一条会话命令的响应未通过地址关联检查。未修改参考源码，也未放宽客户端校验。
这是可复现的不兼容拒绝，**不是**完整交互成功，也不代表 go-ipmi 所有版本/用法。
对照测试在校验和、netfn/LUN、命令和序号检查之后，只接受这一具体地址错误；其他失败仍令 CI 失败。
三项读取与关闭继续由独立 Python 模拟器验证，两条复现路径见演示说明。

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
writes, automatic reconnect/retry, SDR-based physical-unit conversion or network
scanning. Each exchange fails closed; an application may explicitly reconnect.
The module uses the toolchain's documented experimental native build-config API;
that API and its pinned toolchain compatibility are maintenance considerations.

不含匿名、降级、IPMI 1.5、Kg 覆盖、OEM/SOL、硬件写操作、自动重连/重试、SDR 物理单位换算或扫描。
每次交换失败即关闭；应用可以明确重新连接。使用官方文档中的实验性原生构建配置 API，
维护时需要关注其变化和固定工具链兼容性。
