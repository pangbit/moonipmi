# Read-only chassis, FRU and SEL / 只读机箱、FRU 与 SEL

This checkout extends the existing suite-17/User client. These APIs are unreleased;
Mooncakes 0.1.0 is unchanged. There are no new runtime dependencies or control commands.
All examples below assume an already authenticated client for an explicitly authorised peer.

当前源码扩展既有 suite 17/User 客户端；这些 API 尚未发布，Mooncakes 0.1.0 不变。
不增加运行时依赖或控制命令。以下代码假定已连接明确授权的对端。

## Chassis diagnostics / 机箱诊断

```moonbit
let capabilities = client.chassis_capabilities()
let status = client.read(GetChassisStatus).chassis_status()
let restart = client.restart_cause()
```

Capabilities retain the flags and FRU/SDR/SEL/system-management addresses plus the
optional bridge address. Addresses are metadata, never destinations to follow.
Restart cause/channel are numeric; `restart.description()` names known causes and
returns `None` for reserved values. Known descriptions match ipmitool 1.8.19. Each request has the client's exchange deadline.
No power, reset, boot, identify or front-panel controls are exposed.

能力结果保留标志、FRU/SDR/SEL/系统管理地址及可选桥接地址；地址仅作元数据，不自动访问。
重启原因和通道保留数值，`restart.description()` 返回与 ipmitool 1.8.19 一致的已知描述，保留值返回 `None`。
每次请求沿用客户端交换超时。不提供电源、复位、启动、指示灯或前面板控制。

Stored self-test results and the power-on counter are now available alongside
these chassis reads; see [management status](MANAGEMENT.md) for API examples,
reference self-test exit differences and the POH rounding difference.

现也可读取已有自检结果与累计通电计数；[管理状态](MANAGEMENT.md)说明 API、参考自检退出差异和计数显示舍入差异。

## Basic FRU inventory / 基础 FRU 清单

```moonbit
let inventory = client.fru_inventory(0, max_bytes=8192, timeout_ms=10000)
// inventory.chassis / .board / .product are optional FruArea values.
// area.fields keeps standard field order followed by custom fields.
```

The device ID is explicit; no automatic FRU locator discovery or bridging. Defaults
are 8192 bytes and a 10-second overall deadline; accepted limits are 8..65535 bytes
and 1..60000 ms. The deadline covers info, all reads and decoding, in addition to
per-exchange deadlines. Fixed requests ask for at most 16 bytes. Inventory size is
always bytes. On word-access devices the offset and returned count are words,
while the requested count remains bytes, matching ipmitool 1.8.19. Short positive
responses advance by the actual returned count; zero, overlong or inconsistent
responses fail. There is no chunk-size retry or partial result. Failure aborts the
session locally; the BMC may retain it until its inactivity timeout.

Common-header and area versions, offsets, overlap, length, checksums, required
fields, terminators and padding are validated. Field ordering:

- Chassis: part number, serial number, custom fields.
- Board: manufacturer, product, serial number, part number, FRU file ID, custom fields.
- Product: manufacturer, name, part/model number, version, serial number, asset tag,
  FRU file ID, custom fields.

`FruField.raw` and `.encoding` always remain available. `.text` decodes only
printable ASCII in type-3 fields in chassis or language-code-zero areas. Other
encodings/languages return `None`, not guessed text. Board manufacturing time is
raw minutes since 1996-01-01, zero meaning unspecified. Internal-use/multirecord
semantics are unsupported and preserved raw; multirecord framing/checksums are
validated. No FRU editing or writing. A mutable FRU is not an atomic snapshot;
checksums detect some inconsistent reads, not all concurrent changes.

设备 ID 必须明确指定，不自动发现或桥接。默认最多 8192 字节、整体 10 秒；允许范围为
8..65535 字节与 1..60000 毫秒。整体时限覆盖信息、全部分块和解析，逐次超时仍生效。
每次最多请求 16 字节。清单大小始终以字节计；字访问设备的偏移和返回计数以字计，
请求计数仍以字节计，与 ipmitool 1.8.19 一致。有效短响应按实际长度推进；零长度、
超长或不一致响应报错。不自动调整重试，不返回部分清单；失败时本地关闭会话。
BMC 可能保留远端会话直到其空闲超时。

校验头部/区域版本、偏移、重叠、长度、校验和、必需字段、结束标记和填充。
字段按规范顺序保留：机箱为部件号/序列号；主板为厂商/产品/序列号/部件号/FRU 文件 ID；
产品为厂商/名称/型号/版本/序列号/资产标签/FRU 文件 ID，其后为自定义字段。
保留字段编码和原始字节，仅将机箱或语言码零区域的 type-3 可打印 ASCII 解码为文本。
不支持的编码/语言返回 `None`。制造时间保留从 1996-01-01 起的分钟数，零表示未指定。
内部区和多记录区保留原始数据，不解释语义；多记录区仍校验结构和校验和。不提供 FRU 写入。
FRU 读取不是原子快照，校验和不能发现全部并发变化。

## SEL enumeration / SEL 枚举

```moonbit
let info = client.sel_info()
let records = client.sel_records(max_records=256, timeout_ms=10000)
for record in records {
  if record.event() is Some(event) {
    let time = @ipmi.sel_time(event.timestamp)
    // event.threshold_description() is optional, never current sensor health.
    ignore(time)
  }
}
```

SEL info accepts the reference-recognized version bytes `0x51` and `0x02`; other versions are rejected.

Defaults are 256 records and a 10-second overall deadline; allowed limits are
1..4096 records (16 bytes each) and 1..60000 ms. Repository count is checked before
entries are read. Whole-record reads use reservation zero and do not reserve,
clear, delete, add, repair or change timestamps. Empty repositories return no
records. Traversal checks record identity, repeated IDs, exact lengths, count,
and final info count/addition/erase timestamps. Changes fail without partial
results. These checks do not make an atomic snapshot; in-place changes preserving
count/timestamps may escape detection. Completion errors are surfaced, never
silently treated as empty. Failed traversal aborts the local session.

Type 0x02 exposes raw timestamp, generator, revision, sensor identity, direction,
event type and three event bytes. Revision-4 threshold transitions have names;
these are historical transitions, not a current health assessment. Unsupported
revisions and sensor-specific/OEM meanings stay uninterpreted. Every record,
including OEM types and unknown types, retains its complete 16 bytes.
`sel_time` distinguishes `0xffffffff` (unspecified), values below `0x20000000`
(relative/pre-initialisation), and Unix seconds. No timezone or fabricated date.
FRU identifiers and SEL event data can be private; do not log raw results by default.

SEL 信息接受参考已识别的版本字节 `0x51`/`0x02`，其他版本拒绝。

默认最多 256 条、整体 10 秒；范围为 1..4096 条（每条 16 字节）与 1..60000 毫秒。
读取前先检查记录数。完整记录使用零预留 ID，不执行预留、清除、删除、添加、修复或改时间。
空仓库返回空数组。检查记录身份、重复 ID、长度、数量，以及结束时的信息计数/添加/删除时间。
变化即失败，不返回部分结果；这不是原子快照，同数量/时间戳的原地变化可能无法检测。
完成码错误直接暴露，不当作空仓库。遍历失败会关闭本地会话。

标准 0x02 记录暴露原始时间、生成器、版本、传感器身份、方向、事件类型与三字节事件数据。
版本 4 的阈值转换有名称，它表示历史事件而非当前健康状态。不解释其他版本或传感器专有/OEM 语义。
OEM 和未知记录仍完整保留 16 字节。`sel_time` 区分未指定 `0xffffffff`、初始化前相对时间
（小于 `0x20000000`）和 Unix 秒数，不编造日期或时区。FRU 标识和 SEL 数据可能敏感，默认勿记录原始内容。

## Reproduction and evidence / 复现与证据

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/diagnostics_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/diagnostics-comparison.json
```

The loopback-only suite-17 fixture uses public synthetic credentials and fixed
chassis, board/product FRU and three SEL records. Actual ipmitool 1.8.19 runs
`chassis status`, `chassis restart_cause`, read-only raw capability/entry queries,
`fru print 0` in both byte/word modes, and `sel info`/`sel list`. The focused checker
also exercises short FRU progress, malformed count/checksum, size/record limits,
SEL cycles/identity/count/change/completion failures, empty SEL and slow-drip
whole-operation timeouts. It asserts no partial output and the client command
allowlist. The current CI recipe runs the pinned reference build and diagnostics on both Linux and macOS.
Build the profile first using [P1 instructions](IPMITOOL_REFERENCE.md); that page distinguishes 24 differential projections from 62 total executions.
No real BMC, hardware compatibility certification or security audit is implied.

本机模拟器使用公开合成凭据、固定机箱/主板/产品 FRU 和三条 SEL。实际 ipmitool 1.8.19
运行上述只读命令，包括字节/字 FRU 对照。另验证有效短读、坏计数/校验和、总量限额、
SEL 循环/身份/数量/变化/完成码、空仓库与慢速分批响应下的整体超时，并断言无部分输出和命令白名单。
当前 CI 流程在 Linux/macOS 均构建固定参考并执行诊断对照。先按 [P1 说明](IPMITOOL_REFERENCE.md)构建 profile；其中区分 24 项差分映射与 62 次总执行。不代表真实 BMC 兼容认证或安全审计。

References: IPMI v2.0 §§28 (chassis), 31 (SEL), 34 (FRU) and the IPMI FRU
Information Storage Definition; [ipmitool 1.8.19 source](https://github.com/ipmitool/ipmitool/tree/IPMITOOL_1_8_19/lib).
