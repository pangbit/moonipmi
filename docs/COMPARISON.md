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

The original three-read sensor baseline invokes **`ipmitool raw 0x04 0x2d`**, not `sensor list/get`.
The new, separate [SDR comparison](SDR.md) actually executes `sdr list all` and `sensor list`.
The original baseline's usable-value normalization is derived from response flags; it does not
claim an execution of ipmitool's SDR-based presentation. The rule is checked
against IPMI §16.5 and [ipmitool 1.8.19's actual sensor-reading logic](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sdr.c#L1643-L1664):
scanning and availability gate the reading; SDR metadata separately determines
whether it is an analog value. No physical units or numeric sensor type are inferred.
Device/chassis semantics also use [Get Device ID](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c#L394-L475)
and [Chassis Status](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_chassis.c#L411-L464).

原三读对照的传感器基线命令是 `ipmitool raw`，不是依赖 SDR 的 `sensor list/get`。
新增的独立 [SDR 对照](SDR.md) 已实际执行 `sdr list all` 和 `sensor list`。
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

## Requester-address compatibility / 请求者地址兼容

The default now follows **ipmitool 1.8.19 lanplus**: requests still use `rqSA=0x81`,
but the response's requester-address byte is not a correlation key. There is no
special `0x20` exception or opt-in flag. Checksums and every other existing check
remain in place. This applies to both `decode_response` and the authenticated
`Client`; the low-level decoder alone does not provide authentication.

默认行为现与 **ipmitool 1.8.19 lanplus** 一致：请求仍使用 `rqSA=0x81`，但响应的请求者地址字节
不参与关联。不仅特许 `0x20`，也不需要用户启用开关。校验和及其他既有检查全部保留。
该行为同时适用于 `decode_response` 与已认证的 `Client`；底层解码器本身不提供认证。

### Source and tradeoff / 源码与取舍

- [IPMI 2.0 rev1.1 E6 §13.8, Figure 13-4, printed pp.136–137](https://www.intel.de/content/dam/www/public/us/en/documents/product-specifications/ipmi-v2-rev1-1-spec-errata-6-markup.pdf#page=162)
  describes the response's first field as the original requester's address.
  Tolerance does not make a mismatched echo conforming to that layout.
- [ipmitool 1.8.19 matching](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c#L318-L328)
  looks up sequence/command, not requester address. Its receive path checks
  [session identity and authentication before decryption](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c#L658-L691).
- [Pinned go-ipmi response construction](https://github.com/bougou/go-ipmi/blob/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6/pkg/protocol/ipmb.go#L18-L67)
  hardcodes `0x20` instead of preserving the incoming requester. This is one
  reproducible compatibility case, not evidence of widespread hardware behaviour.

The tradeoff is loss of one malformed/misrouted-response diagnostic. A response
from the authenticated peer with the expected session/request identifiers is no
longer rejected solely for that byte. An unauthenticated sender still cannot
forge a valid HMAC. Peer filtering, RAKP, suite 17, HMAC-before-decryption, session
identity, replay protection, responder address, LUN/netfn, sequence/command,
checksums, bounds and padding checks are unchanged. Do not use address tolerance
as a reason to trust an untrusted management network.

上述规范描述请求者字段含义，容忍错误回显不代表它符合该布局。固定 ipmitool 源码按序号/命令匹配，
并在解密前验证会话与认证；固定 go-ipmi 服务端的 `0x20` 是可复现个例，不证明大量硬件都有此行为。
取舍是减少一项畸形/错误路由响应的诊断：来自已认证对端且会话/请求标识匹配的响应，不再仅因该字节被拒绝。
未认证发送者仍不能伪造有效 HMAC。对端过滤、RAKP、套件 17、先 HMAC 后解密、会话、防重放、响应者地址、
LUN/netfn、序号/命令、校验和、长度及 padding 检查均不变，仍应使用可信管理网络。

### Focused packet comparison / 聚焦报文对照

`tools/address_check.py` uses the same suite-17 Python fixture for both clients,
changing only authenticated Device ID responses. It verifies normal decoding,
three non-echoed requester values, and eight negative controls: **24 comparisons**.
Each field mutation except the intentional checksum case has repaired IPMI
checksums; only the intentional MAC case lacks a valid HMAC. Unit tests additionally
cover all 256 requester-byte values and retain tampering/session/replay tests.

| Response / 响应 | moonipmi | ipmitool 1.8.19 |
|---|---|---|
| Normal requester `0x81` / 正常请求者 | Accept / 接受 | Accept / 接受 |
| Requester `0x20`, `0x00`, `0xff` / 请求者不同 | Accept / 接受 | Accept / 接受 |
| Wrong responder `0x22` / 响应者错误 | Reject / 拒绝 | Accept / 接受 |
| Wrong netfn or either LUN / netfn 或任一 LUN 错误 | Reject / 拒绝 | Accept / 接受 |
| Wrong command or request sequence / 命令或请求序号错误 | Reject / 拒绝 | Reject / 拒绝 |
| Bad IPMI checksum, valid HMAC / 校验和错误但 HMAC 正确 | Reject / 拒绝 | Accept / 接受 |
| Bad HMAC / HMAC 错误 | Reject / 拒绝 | Reject / 拒绝 |

These remaining differences are intentional: requester compatibility does not
copy every permissive ipmitool behaviour. Rejection timing/messages differ too:
moonipmi fails closed immediately; ipmitool may discard a response and wait.
The probe uses `-R 1` for one attempt; `-R 0` restores ipmitool's default retries.

两客户端使用同一套件 17 模拟器，仅修改已认证的设备标识响应，共 24 项。
除故意破坏校验和的用例外均重算校验和；仅故意破坏 MAC 的用例没有有效 HMAC。
单元测试另覆盖全部 256 个请求者字节值，并保留篡改/会话/防重放测试。
表中剩余差异是有意保留的边界，不为对齐请求者地址而照搬其他宽容行为。
拒绝时机/信息也不同：moonipmi 立即失败关闭，ipmitool 可能丢弃后等待。
探针用 `-R 1` 限定一次尝试；`-R 0` 实际恢复 ipmitool 默认重试次数。

```sh
python3 tools/address_check.py \
  --moon-client _build/native/debug/build/examples/comparison/comparison.exe \
  --output _build/address-comparison.json
```

### Unmodified go-ipmi BMC / 未修改的 go-ipmi BMC

Against the pinned server, moonipmi and ipmitool now both read Device ID and Chassis
Status. Both report **completion `0xc1`** for Get Sensor Reading: this reference
BMC does not implement that command. Removing the requester rejection exposes
that separate limitation; it does not make a full three-read exchange pass.
The common Python fixture above remains the three-read comparison.

固定服务端上，两客户端现均可读取设备标识和机箱状态；读取传感器均返回 **完成码 `0xc1`**，
因为该参考 BMC 未实现此命令。去除请求者拒绝只是暴露后续限制，不表示完整三读交互成功。
三项读取的共同对照目标仍是前文 Python 模拟器。

```sh
go -C tools/go-reference build -mod=readonly -o ../../_build/reference-bmc .
python3 tools/go_interop.py \
  _build/native/debug/build/examples/comparison/comparison.exe \
  _build/reference-bmc --compare-reads
python3 tools/go_interop.py "$(command -v ipmitool)" _build/reference-bmc \
  --ipmitool-address-probe
```

These checks passed locally on macOS with ipmitool 1.8.19; Linux CI runs them too.
Reports contain synthetic results, not verbose cryptographic logs. This change
is unreleased: Mooncakes 0.1.0 retains its prior requester check. No real BMC,
full protocol coverage or security audit is claimed.

上述检查已在 macOS 本地以 ipmitool 1.8.19 通过，Linux CI 也执行这些检查。
报告只含合成结果，不输出密码学调试日志。改动尚未发布，Mooncakes 0.1.0 仍使用旧请求者校验。
不宣称真实 BMC、完整协议或安全审计。

## Separate read-only subsets / 单独实现的只读子集

The current unreleased source separately implements the [SDR subset](SDR.md) and
[chassis, FRU and SEL diagnostics](DIAGNOSTICS.md): chassis capabilities/restart
cause, validated basic FRU inventory in byte/word access modes, and bounded SEL
enumeration with standard event metadata. FRU/SEL enforce total limits and
overall deadlines and fail without partial results. Unsupported FRU encodings
and internal-use/multirecord semantics, plus unsupported SEL sensor-specific/OEM
meanings, remain uninterpreted with raw data retained. These reads are not atomic
snapshots. Hardware controls, FRU writes, SEL mutations, automatic FRU discovery,
other cipher suites, IPMI 1.5 sessions, OEM commands/SOL and bridging remain
outside scope.

当前未发布源码已单独实现 [SDR 子集](SDR.md)及[机箱、FRU 与 SEL 只读诊断](DIAGNOSTICS.md)：
机箱能力/重启原因、经校验的基础 FRU 字节/字访问清单，以及带标准事件元数据的有界 SEL 枚举。
FRU/SEL 限制总量和整体时长，失败不返回部分结果。不支持的 FRU 编码与内部区/多记录区语义，
以及不支持的 SEL 传感器专有/OEM 含义均不作解释，保留原始数据。读取不是原子快照。
硬件控制、FRU 写入、SEL 修改、FRU 自动发现、其他密码套件、IPMI 1.5 会话、OEM 命令/SOL
及桥接仍不在范围内。

The original diagnostic checker had 30 mixed executions/boundary cases. The
[P1 reference work](IPMITOOL_REFERENCE.md) replaces weak text assertions with
24 field/description/raw projections across 62 executions, using an unpatched,
hash-bound reference; moon-only negative cases are counted separately. The current
CI recipe builds the fixed reference and runs diagnostics on Linux and macOS.
This does not extend the original three-client matrix or the pinned go-ipmi BMC
comparison to FRU/SEL, establish full CLI/wire equivalence, real-BMC compatibility
or a security audit. These APIs remain unreleased; Mooncakes 0.1.0 is unchanged.

原诊断脚本包含 30 次混合执行/边界检查。[P1 参考工作](IPMITOOL_REFERENCE.md)使用无补丁、
绑定哈希的参考程序，将弱文本断言改为 62 次执行中的 24 项字段/描述/raw 映射；仅 moonipmi
的负面场景单独计数。当前 CI 流程在 Linux/macOS 均构建固定参考并执行诊断。
这不表示原三客户端矩阵或 go-ipmi BMC 对照扩展到 FRU/SEL，也不证明完整 CLI/报文一致、
真实 BMC 兼容或安全审计。API 仍未发布，Mooncakes 0.1.0 不变。
