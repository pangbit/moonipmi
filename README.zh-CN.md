# moonipmi

[English](README.md)

面向 MoonBit native 应用的实验性 IPMI 2.0 / RMCP+ 只读客户端。
协议与会话逻辑使用 MoonBit；薄 C 适配层调用 OpenSSL 3 提供 HMAC-SHA256、
原始 AES-CBC、常量时间比较和安全随机数。

**当前是经过测试的早期子集，不是完整 IPMI 实现。** 已通过 Linux/macOS CI 和独立合成本地 BMC
交互；未测试真实硬件 BMC，未经过安全审计。仅用于明确授权的系统和隔离管理网络。

## 范围

- **仅套件 17**：RAKP-HMAC-SHA256 / HMAC-SHA256-128 / AES-CBC-128。
- User 权限，校验 RAKP2 与 RAKP4；禁止匿名认证和降级。
- **先认证报文再解密**，校验会话、响应者、LUN/netfn、命令/序号、校验和、长度、padding 及递增接收序号。
  与 ipmitool 1.8.19 一致，不要求响应请求者地址回显 `0x81`。
- 连接单一 UDP 对端，同一会话只允许一个在途请求；每次交换有超时，不自动重试；支持关闭与本地立即中止。
  IPv4 对端使用普通 IPv4 地址，不接受 IPv4-mapped IPv6 表示。
- 类型化设备标识、机箱状态和传感器原始读数。
- 机箱能力/重启原因、有界基础 FRU 清单与 SEL 记录，限制总量与整体时长，见 [只读诊断](docs/DIAGNOSTICS.md)。
- 有界 SDR 仓库遍历、Full/Compact 记录、常见线性工程值、阈值/离散状态及单位，见 [SDR 支持](docs/SDR.md)。

不包含硬件控制写操作、通用网络命令入口、OEM/SOL、FRU 写入或 SEL 修改、Device SDR、桥接、IPMI 1.5、
密码套件协商、Kg 覆盖或自动重连。会话管理与 SDR 预留不修改硬件配置。
非线性/OEM 换算和共享 Compact 展开明确标记为不支持。用户名/密码长度分别为 1..16 / 1..20 字节。

## 构建与测试

需要近期 MoonBit native 工具链、C 编译器、**OpenSSL 3 开发文件**、`pkg-config` 和 Python 3。
本机已在 `moon 0.1.20261104`（`moonc v0.10.20+65efd5b93`）及 OpenSSL 3.6.3 上验证。

```sh
# macOS
brew install openssl@3 pkg-config
# Debian/Ubuntu（尚未安装时）
sudo apt-get install libssl-dev pkg-config python3 build-essential

moon update
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
moon run examples/offline --target native
python3 tools/interop.py _build/native/debug/build/examples/loopback/loopback.exe
```

最后一条命令只在**本机 loopback** 启动合成 BMC，运行客户端示例，校验握手、三项读取和关闭会话，
不会访问真实 BMC。`tools/vectors.py` 用 Python HMAC 与 OpenSSL CLI 独立重新生成合成 RAKP/KDF/报文向量。

### 原生依赖配置

`build.py` 使用 MoonBit 官方文档中的**实验性原生 prebuild 配置**，通过 `pkg-config` 查找 OpenSSL，
并向消费方传递 `libcrypto` 链接设置。它仅查询已安装依赖，不下载、不安装，也不记录环境变量。
在 Homebrew macOS 上可自动定位 `openssl@3`。消费方需要安装相同依赖，**无需**在清单写入本机路径或配置
自定义编译器包装器。此工具链 API 可能变化，CI 固定已测试工具链。默认构建和独立消费方模块均已验证。
仅支持 native，不能称为完全不依赖 C 的库。

## 使用

将 `pangbit/moonipmi` 以 `ipmi` 别名导入。在 async 函数中，由应用提供明确授权的对端地址与凭据：

```moonbit
let client = @ipmi.Client::connect(addr, username, password, timeout_ms=2000)
defer client.abort()
let device = client.read(GetDeviceId).device_id()
client.close()
```

当前检出版本的只读元数据：

`DeviceId` 补充 `provides_device_sdrs` 与 `additional_device_support` 位图；后者 bit7..0
依次表示机箱、桥、IPMB 事件生成/接收、FRU、SEL、SDR 仓库、传感器能力。
Device SDR 与 SDR 仓库是不同能力，这些只是设备自报信息，不证明其他命令已可用。
机箱提供入侵、前面板锁定、驱动器与风扇故障便捷入口，历史事件和可选面板信息仍保留原始值。
传感器优先使用 `reading.usable_raw_reading()`：不可用或停扫时返回 `None`，不把无效值替换为零；
仅关闭事件消息不影响读数。发现传感器和工程值时，使用 `client.sdr_records()`、`record.sensor()`、
`client.read_sensor(sensor)`，再调用 `sensor.value(reading)`、`state(reading)` 与 `unit()`。
枚举区分缺失、不支持与数值零，读取前可检查 `sensor.read_support()`。
[SDR 示例与边界](docs/SDR.md) 实际运行 ipmitool `sdr`/`sensor` 对同一合成仓库进行对照。
这些新增入口尚未发布到 Mooncakes。

失败完成码保留在 `Response.completion_code`，类型化成功结果解析器会拒绝失败响应。
网络、报文、认证或重放错误会关闭客户端，避免不确定状态下重发。
`abort()` 可重复调用且不发送报文；BMC 端会话可能保留到其超时。
包仓库仍为原始 **0.1.0**；后续源码改动列在[未发布记录](CHANGELOG.md)，不会自动发布。
0.1.0 请使用普通 IPv4 地址：映射式 IPv6 表示可能绕过非单一对端地址限制。
使用 `moon add pangbit/moonipmi@0.1.0` 安装原始实验性版本。
源码中的示例可在不提供真实凭据的情况下进行本地演示。

## 设计、证据与对照

参见[三个使用场景](docs/SCENARIOS.md)、[可复现演示](docs/DEMO.md)、[客户端对照](docs/COMPARISON.md)、[范围/证据](docs/STATUS.md)、[安全说明](SECURITY.md)、[贡献指南](CONTRIBUTING.md)。
`moon info` / `moon doc` 可生成 API 描述与文档。

协议依据是 **IPMI v2.0 规范**，重点包括第 13 节 RMCP+、20.1 Get Device ID、
28.2 Get Chassis Status、33 SDR Repository、35.14 Get Sensor Reading、43 Sensor Data Records。主要功能基线是
[ipmitool 1.8.19](https://codeberg.org/IPMITool/ipmitool)，仅限已实现的只读与 SDR 子集，不表示支持其全部命令。辅助对照项目是
[bougou/go-ipmi](https://github.com/bougou/go-ipmi)，Apache-2.0，查阅版本
[`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6)。
它是参考，不是运行时依赖或背书。固定版本参考 BMC 将响应请求者地址硬编码为 `0x20`，
未回显请求中的 `0x81`。moonipmi 现默认与 ipmitool 一样容忍该字段，不需兼容开关。
两者均成功读取设备标识和机箱状态，读取传感器时均收到参考 BMC 的完成码 `0xc1`。
**尚未与该 go-ipmi BMC 完整三读互通**。另已通过三客户端对共同 Python 模拟器的
三项读取、代表性状态边界与两类错误对照。本次仅调整请求者地址，不照搬 ipmitool 对其他畸形字段的宽容行为。
详见[策略、风险与对照](docs/COMPARISON.md)、[证据与限制](docs/STATUS.md)和 [NOTICE](NOTICE)。
这些实现仅用于验证，不是运行时依赖。改动尚未发布，Mooncakes 0.1.0 仍保留原请求者地址校验。

Apache-2.0。个人维护；首次稳定发布前 API 可能变化。
