# Client comparison / 客户端功能对照

## Scope and results / 范围与结果

All three clients run against **the same Python fixture**, with a fresh loopback
UDP socket/session per case, identical synthetic data, suite 17 and a User privilege
ceiling. The fixture does not identify the client or change data for it. No real
BMC is involved and no hardware-control commands are implemented.

三种客户端对同一个 Python 模拟器运行，每项使用新的本机 UDP socket/会话；合成数据、
套件 17 和 User 权限上限相同。模拟器不识别客户端身份、不针对客户端更改业务数据。
没有真实 BMC，也不实现硬件控制命令。

| Case / 用例 | moonipmi | go-ipmi client / 客户端 | ipmitool |
|---|---|---|---|
| Device ID: 12 fields, basic/extended / 设备标识12字段、基本/扩展 | Matched / 一致 | Matched / 一致 | Matched / 一致 |
| Chassis Status: 10 fields, on/off + faults / 机箱10字段、通断电与故障 | Matched / 一致 | Matched / 一致 | Matched / 一致 |
| Raw Sensor Reading: 4 status profiles / 原始读数4种状态 | Matched / 一致 | Matched / 一致 | Matched / 一致 |
| Wrong synthetic password / 错误合成密码 | Rejected before activation / 激活前失败 | Same / 相同 | Same / 相同 |
| Absent sensor: completion `0xcb` / 不存在的传感器 | Nonzero exit and code exposed / 非零退出并显示完成码 | Same / 相同 | Same / 相同 |

The 30-case comparison passed locally on macOS with ipmitool **1.8.19**, Go **1.24.0**,
and go-ipmi pinned to [`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6).
The runner requires ipmitool 1.8.19 and records its version; a different version
requires explicit baseline review. Linux CI runs the same matrix. Native
unit tests and the original complete MoonBit/Python exchange remain separate.

上述 30 项已在 macOS 本地通过，版本如上；运行器要求并记录 ipmitool 1.8.19，其他版本需先审阅基线。
Linux CI 执行相同矩阵。
原生单元测试及原来的 MoonBit/Python 完整交互继续保留。

Only overlapping fields are compared. Firmware minor revision is normalized from
MoonBit's raw BCD to the decoded decimal value; sensor disabled/enabled booleans
are normalized without converting raw readings into physical units. Formatting,
vendor-name databases, random nonces and session identifiers are not compared.
The runner checks actual authenticated fixture commands, successful close for
positive cases, and specific failure phases/codes, not just subprocess exit codes.

只比较功能交集。固件次版本从 MoonBit 的原始 BCD 归一化为十进制；传感器启用/禁用标志
按语义统一，不把原始读数转换成物理单位。不比较文字格式、厂商名称数据库、随机数或会话编号。
运行器核对模拟器实际收到的认证命令、成功场景的关闭，以及错误阶段/完成码，不仅检查进程退出码。

### Status and metadata coverage / 状态与元数据

- Device ID: Device SDR support, the full Additional Device Support bitmask,
  firmware available/unavailable, and absent/present four-byte auxiliary firmware.
  These are advertised capabilities, not proof that extra commands work.
- Chassis: power on and power off with overload/power faults, plus intrusion,
  front-panel lockout, drive and cooling/fan faults. Unit tests also distinguish
  missing front-panel metadata from an explicit zero; historical power-event and
  remaining identify/button fields stay raw, not fully semantically compared.
- Sensor: normal, unavailable, scanning disabled, and event messages disabled.
  `usable_raw_reading()` is `None` for the middle two, but remains available when
  only event messages are disabled. Existing raw fields retain their meaning.
  The runner compares five raw/flag fields and a derived usable-value field.
- The absent sensor is `0xfe`; earlier tests used `0xff`, a reserved sensor number.
  The fixture still returns completion `0xcb`, but now models an ordinary missing sensor.

设备对照覆盖 Device SDR、完整额外能力位图、固件可用/不可用、四字节辅助固件缺失/存在；
这些是设备自报能力，不表示已验证其他命令。机箱覆盖通断电、过载/电源故障及四个常用杂项故障。
单元测试区分前面板字段缺失与零值；历史电源事件、识别灯及按钮字段仍保留原始位，未声称全面语义对齐。
传感器覆盖正常、不可用、停扫及关闭事件消息；新增可选原始值入口拒绝不可用/停扫，关闭事件消息仍可读。
五项原始值/标志之外另检查一个推导的可用值。不存在的传感器改用 `0xfe`，不再用保留编号 `0xff`。

The sensor baseline invokes **`ipmitool raw 0x04 0x2d`**, not `sensor list/get`.
Its usable-value normalization is derived from the response flags; it does not
claim an execution of ipmitool's SDR-based presentation. The rule is checked
against IPMI §16.5 and [ipmitool 1.8.19's actual sensor-reading logic](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sdr.c#L1643-L1664):
scanning and availability gate the reading; SDR metadata separately determines
whether it is an analog value. No physical units or numeric sensor type are inferred.
Device/chassis semantics also use [Get Device ID](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c#L394-L475)
and [Chassis Status](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_chassis.c#L411-L464).

传感器实际基线命令是 `ipmitool raw`，不是依赖 SDR 的 `sensor list/get`。
归一化的可用值由响应标志推导，并以规范 §16.5 与固定版本源码核对，不冒称已实测完整传感器展示功能。
是否为数值型及物理单位仍需 SDR；设备和机箱的对应源码链接如上。

### Observed differences / 已观察的差异

- go-ipmi requests Open Session privilege `0` (highest matching algorithms), then
  RAKP User; the fixture grants only User. moonipmi/ipmitool request `2` directly.
- go-ipmi/ipmitool use RAKP role `0x12` (User plus name-only lookup); moonipmi uses
  `0x02`. Both are valid User requests. HMAC inputs preserve the entire role byte.
- go-ipmi/ipmitool query capabilities first; ipmitool additionally probes PICMG/VITA.
  The same fixture gives unsupported discovery commands completion `0xc1`.
- On the completion-error case, this MoonBit adapter aborts its local socket;
  the Go/ipmitool adapters send Close Session. This is recorded as cleanup behaviour,
  not a data mismatch. Library callers may explicitly close after a completion code.

- go-ipmi 的 Open Session 请求权限为 `0`，之后 RAKP 指定 User；模拟器仅授予 User。
  moonipmi/ipmitool 直接请求 `2`。
- go-ipmi/ipmitool 使用 `0x12`（User + 仅按用户名查找），moonipmi 使用 `0x02`；
  两者都是合法的 User 请求，HMAC 使用完整 role 字节。
- go-ipmi/ipmitool 先查询能力，ipmitool 另探测 PICMG/VITA；同一模拟器统一以 `0xc1` 拒绝不支持的发现命令。
- 完成码错误时，本 MoonBit 适配器关闭本地 socket，Go/ipmitool 适配器发送 Close Session。
  这是清理行为差异，不是数据不一致；库调用方可在收到完成码后显式关闭远端会话。

## Reproduce / 复现

Install the README's native dependencies, Go 1.24 and ipmitool, then run:

安装 README 中的原生依赖、Go 1.24 和 ipmitool，然后执行：

```sh
moon build --target native --deny-warn
go -C tools/go-reference build -mod=readonly -o ../../_build/reference-client ./client
python3 tools/compare_clients.py \
  --moon-client _build/native/debug/build/examples/comparison/comparison.exe \
  --go-client _build/reference-client \
  --output _build/client-comparison.json
```

The JSON contains only synthetic command/results and non-secret protocol metadata;
it records which clients actually ran. Omitting `--go-client` runs twenty cases for
MoonBit/ipmitool, not the full three-client matrix. No package is published.

JSON 只记录合成命令/结果和非秘密协议元数据，并列明实际运行的客户端。
省略 `--go-client` 时只运行 MoonBit/ipmitool 的二十项，不能视为完整三客户端矩阵。不发布包。

## Address mismatch: format versus tolerance / 地址不匹配：格式与宽容策略

This common-fixture comparison is distinct from the known **go-ipmi BMC** issue.
At the pinned revision, its response builder hardcodes requester address `0x20`
instead of echoing our request's `0x81`. moonipmi rejects that response. Direct
loopback testing with the same unmodified server shows ipmitool 1.8.19 sends
`rqAddr=0x81`, receives `rqAddr=0x20`, yet returns Device ID successfully (exit 0).

共同模拟器对照与已知 **go-ipmi BMC** 问题不同。固定版本的响应构造器将请求者地址硬编码为
`0x20`，未回显请求的 `0x81`；moonipmi 拒绝它。对同一未修改服务端的本机实测显示，
ipmitool 1.8.19 发送 `rqAddr=0x81`、收到 `rqAddr=0x20`，仍成功读取设备标识（退出码 0）。

Evidence / 证据：

- [IPMI 2.0 rev1.1 E6 §13.8, Figure 13-4, printed pp.136–137](https://www.intel.de/content/dam/www/public/us/en/documents/product-specifications/ipmi-v2-rev1-1-spec-errata-6-markup.pdf#page=162)
  defines the response's first field as the original requester's address; `0x20`
  is the BMC address, not a universal remote-console address.
- [go-ipmi response construction](https://github.com/bougou/go-ipmi/blob/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6/pkg/protocol/ipmb.go#L18-L67)
  does not preserve the incoming requester address.
- [ipmitool 1.8.19 matching](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c#L318-L328)
  correlates the IPMI request using sequence/command, not requester address. It
  still checks the session and MAC; this is **not** an unauthenticated bypass.
- [Independent OpenBMC response construction](https://github.com/openbmc/phosphor-net-ipmid/blob/1d6c85f05a33ca91e8efabdb53b47fbb27b0eb27/message.hpp#L218-L224)
  copies requester/responder addresses from the request.

规范字段语义、固定双方源码及 OpenBMC 实现均支持请求者地址应对应原请求。
ipmitool 对该字段宽容，不代表错误响应符合规范；它仍检查会话与 MAC，并非无认证接受。
我们没有把“遇到此错误必须终止”冒称为规范中的独立 MUST 条文，拒绝是本库的严格关联策略。

Reproduce the permissive behaviour without changing the reference source:

无需修改参考源码即可复现宽容行为：

```sh
go -C tools/go-reference build -mod=readonly -o ../../_build/reference-bmc .
python3 tools/go_interop.py "$(command -v ipmitool)" _build/reference-bmc \
  --ipmitool-address-probe
```

The probe reports only address fields and the synthetic outcome, not verbose
cryptographic logs. No compatibility relaxation has been added to moonipmi.
Real-BMC compatibility, full protocol coverage, performance and security auditing
remain outside this small comparison. SDR/physical units, writes, other suites,
IPMI 1.5 sessions, OEM/SOL and SEL/FRU traversal are **not applicable**, not failed cases.

探针仅输出地址字段及合成结果，不输出完整密码学调试日志。moonipmi 没有增加放宽校验的兼容模式。
本次不证明真实 BMC 兼容、完整协议覆盖、性能或安全审计。SDR/物理单位、写操作、其他套件、
IPMI 1.5 会话、OEM/SOL、SEL/FRU 遍历均为“不适用”，不是失败用例。
