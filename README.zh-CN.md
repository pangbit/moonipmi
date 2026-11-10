# moonipmi

[English](README.md)

面向 MoonBit native 应用的实验性 IPMI 2.0 / RMCP+ 库。

**当前仅完成协议基础，不是可用的认证 LAN 客户端。** 尚无网络传输、密码学校验和认证会话。
成功解析 Open Session 或 RAKP 报文**不代表** BMC 已通过认证。不要使用本阶段代码发送凭据，
也不要用于生产管理网络。项目不宣称完整实现 IPMI，也不逐项移植 go-ipmi 的全部命令。

## 已实现

- IPMI LAN 请求编码、两段校验和，以及严格的响应关联。
- 只读命令编解码：Get Device ID、Get Chassis Status、Get Sensor Reading。
- 有界长度与严格头部校验的 RMCP+ 握手封装。
- 密码套件 17 对应的 Open Session 与 RAKP 1–4 报文布局。
- 拒绝套件降级、畸形输入和身份不匹配的响应。
- 使用纯合成数据的确定性测试和离线示例。

建议中的首版客户端采用 User 权限与套件 17：RAKP-HMAC-SHA256 / HMAC-SHA256-128 /
AES-CBC-128。原生加密后端、UDP 传输、认证会话状态、防重放、超时和本地互操作测试仍未完成。
初始范围不包含降级回退、电源控制、用户管理、OEM 命令、SOL、SEL、FRU 或 SDR 仓库遍历。
传感器只提供原始读取值；转换成物理单位还需要对应的 SDR 元数据。

## 运行离线示例

使用近期 MoonBit native 工具链。当前阶段已在 `moon 0.1.20261104` 上验证，
不需要额外运行时系统库。

```sh
moon check --target native --deny-warn
moon test --target native --deny-warn
moon run examples/offline --target native
```

```moonbit
let request = @ipmi.ReadCommand::GetDeviceId.encode(0)
// request 只是 Bytes，不会发送网络报文。
```

在包清单中将 `pangbit/moonipmi` 以别名 `ipmi` 导入。本模块尚未发布，以上示例从源码目录运行。
`encode_request` 是底层编码器，不是获得授权即可发送任意命令的网络接口。

## 设计与验证

协议校验与 I/O、密码学分离。索引前先校验长度，逐一关联响应，并保留完成码，
避免把失败响应当作成功结果。优先维护小型、类型明确的只读接口，不引入未经审查的通用 BMC 控制 API。

参见[范围与证据](docs/STATUS.md)、[安全说明](SECURITY.md)、[贡献指南](CONTRIBUTING.md)。
`moon info` 生成公共 API 描述，`moon doc` 生成 API 文档。

## 对照与许可

协议依据为 **IPMI v2.0 规范**，重点包括第 13 节 RMCP+ 会话建立，以及 Get Device ID、
Get Chassis Status、Get Sensor Reading 命令定义。对照项目是
[bougou/go-ipmi](https://github.com/bougou/go-ipmi)，Apache-2.0，已查阅版本
[`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6)。
它只是参考，不是运行时依赖，也不代表其认可本项目。详见 [NOTICE](NOTICE)。

Apache-2.0。个人维护项目；首次稳定发布前 API 可能变化。
