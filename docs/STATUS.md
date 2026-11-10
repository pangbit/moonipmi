# Scope and evidence / 范围与证据

## Current milestone / 当前阶段

Implemented: bounded IPMI LAN and RMCP+ handshake codecs; strict checksums and
request correlation; typed read-only command payloads; suite 17 handshake
layouts. No socket is opened by any public function or example at this stage.

已实现：有界 IPMI LAN 与 RMCP+ 握手编解码、严格校验和与请求关联、类型化只读命令响应，
以及套件 17 握手布局。当前任何公共函数和示例都不会打开 socket。

Native verification: nine test groups cover golden bytes, truncation, altered
headers/checksums, mismatched sequences and commands, failure completion codes,
cipher downgrade, RAKP lengths and typed command fields. The offline example
runs locally without credentials. These are unit/codec checks, not hardware or
end-to-end authenticated interoperability evidence.

native 验证包含九组测试，覆盖固定字节向量、截断、头部/校验和篡改、序号/命令不匹配、
失败完成码、套件降级、RAKP 长度和类型化字段。离线示例无需凭据即可运行。
这些是单元/编解码验证，不是硬件或完整认证会话互操作证据。

## Before the first client release / 客户端首发门槛

- Select and document a minimal native cryptography backend and its dependencies.
- Authenticate RAKP and protected packets; verify AES-CBC and KDF with independent vectors.
- Add bounded UDP exchange, deadlines, sequence/replay handling and explicit close.
- Pass a synthetic loopback BMC test, then document separately any authorised hardware test.
- Verify Linux/macOS builds, examples, package contents and secret/privacy checks.
- Confirm the registry publication and event-submission requirements before release.

首发前需要：确定并说明最小加密后端；完成 RAKP 与报文认证、独立 AES/KDF 向量；
增加有界 UDP、超时、序号/防重放和关闭流程；通过合成本地 BMC 测试；真实硬件测试必须单独授权并单独说明；
核实 Linux/macOS、示例、打包内容与敏感信息检查；发布前确认包仓库和活动的提交条件。

## Deliberate exclusions / 明确不含

No full-IPMI claim, cipher-suite fallback, anonymous authentication, OEM/SOL,
write commands, automatic sensor-unit conversion, promiscuous discovery or
production-BMC access. A small, verifiable read-only subset is the initial goal.

不宣称完整 IPMI；不含套件降级、匿名认证、OEM/SOL、写命令、自动传感器单位换算、
泛网段发现或生产 BMC 访问。首期目标是小而可验证的只读子集。
