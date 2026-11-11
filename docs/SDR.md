# SDR-backed sensor readings / 基于 SDR 的传感器读数

This is an **unreleased read-only subset**, not full ipmitool compatibility or a
hardware qualification. It uses the existing authenticated suite-17/User client.
No new native dependency, arbitrary command dispatch or hardware-control API is
introduced. Mooncakes 0.1.0 is unchanged; publication remains manual.

本功能是**未发布的只读子集**，不表示完整兼容 ipmitool 或通过实机认证。
继续使用套件 17/User 已认证客户端，不新增原生依赖、任意命令入口或硬件控制 API。
Mooncakes 0.1.0 未变，仍由维护者手动发布。

## API and supported data / API 与支持范围

- `Client.sdr_repository_info()` reads version, count, free space, timestamps and
  operation flags. `Client.sdr_records(max_records=1024)` reserves the repository
  and retrieves each header/body in chunks of at most 16 bytes. The limit is
  configurable within 1..4096 records; the example uses 64.
- An empty repository returns an empty array. It is **never rebuilt**. A nonempty
  repository must advertise reservation support. Lost reservations, malformed
  chunks, changed next IDs, repeated IDs, count mismatches and limits fail the
  operation without returning a partial inventory. There is no automatic retry.
- `decode_sdr_record()` accepts the 0x51 record format. Unknown record types retain
  their bytes; `record.sensor()` returns `None` for them. Full (0x01) and Compact
  (0x02) records expose names, owner/channel/LUN, sensor number/type, entity ID,
  instance and logical-entity flag, event type and unit metadata.
- Printable ASCII ID strings are decoded; other encodings retain `raw_name` and
  `name_encoding`, with `name=None`. No guessed or lossy decoded name is returned.
- `sensor.read_support()` explains unsupported routing. `client.read_sensor(sensor)`
  reads only unshared local BMC sensors (owner 0x20, channel 0, LUN 0), rejecting
  other routes before sending. No bridging or shared Compact expansion is hidden.
- `sensor.value(reading)` converts linear Full threshold sensors with
  `(M*x + B*10^Bexp)*10^Rexp`, including unsigned, one's complement and two's
  complement raw bytes, signed 10-bit M/B and signed four-bit exponents. Compact
  and non-analog/discrete records do not invent numeric values. Nonlinear/OEM
  conversions return `Unsupported`; Get Sensor Reading Factors is not implemented.
- `sensor.state(reading)` returns the six threshold bits or the 15-bit discrete
  event mask. A missing status byte is not a healthy state; the optional high
  discrete byte defaults to zero. Unavailable and scanning-disabled results remain
  distinct. Disabling event messages alone does not invalidate a reading.
- `state.threshold_status()` groups threshold severity as `ok`, `nc`, `cr`, `nr`,
  while retaining the complete mask. `sensor.discrete_state_name(bit_offset)` names
  common device-presence, chassis-intrusion and power-supply events; unknown
  event types or offsets return `None`. A discrete mask is not overall health.
- `sensor.unit()` covers temperature, voltage, current, power/energy, airflow,
  RPM, frequency and time units, with percentage, modifier and rate metadata.
  Unknown/reserved codes return `None` and preserve their numeric metadata.

- 仓库信息接口读取版本、记录数、可用空间、时间戳和操作位；遍历先预留，再按最多 16 字节读取。
  默认最多 1024 条，可设为 1..4096；示例上限 64。空仓库返回空数组，**绝不重建**。
- 非空仓库必须声明支持预留。预留失效、片段畸形、next ID 改变、重复 ID、计数不符或超限均失败，
  不返回半份清单，也不自动重试。
- 解码 0x51 记录格式；未知记录类型保留原始内容，其 `sensor()` 返回 `None`。
  Full/Compact 提供名称、所有者/通道/LUN、编号/类型、实体/实例/逻辑实体位、事件类型和单位元数据。
- 名称只解码可打印 ASCII；其他编码保留原始字节及编码，名称返回 `None`，不猜测或有损转换。
- 只读取 owner=0x20、channel=0、LUN=0 的非共享本地传感器；其他路由在发送前拒绝。
  不静默桥接，也不将共享 Compact 误当成单个本地传感器。
- Full 阈值记录支持上述线性公式、无符号/反码/补码读数、带符号 M/B 和指数。
  Compact 或离散记录不伪造模拟量；非线性/OEM 返回 `Unsupported`，未实现动态读取换算因子。
- 状态保留六位阈值或十五位离散掩码；缺少状态不等于正常，可选离散高字节缺失按零处理。
  不可用与停扫分开，只有事件消息关闭仍可读。阈值严重度保留完整掩码；常见存在、入侵、电源事件
  可查询名称，未知返回 `None`。离散状态不能直接等同整体健康。
- 单位支持常见温度、电压、电流、功率/能量、风量、RPM、频率和时间，以及百分比、修饰/速率。
  未知/保留单位返回 `None`，保留数值元数据。

After connecting to an explicitly authorised peer, a minimal application flow is:
连接明确授权的对端后，最小使用流程为：

```moonbit
let records = client.sdr_records(max_records=1024)
for record in records {
  if record.sensor() is Some(sensor) {
    if sensor.read_support() is None {
      let reading = client.read_sensor(sensor)
      let value = sensor.value(reading)
      let state = sensor.state(reading)
      let unit = sensor.unit()
      // Store/display the enums and optional unit without replacing missing values.
    }
  }
}
```

Use the existing `defer client.abort()` and explicit `client.close()` lifecycle.
Each exchange has its configured timeout; apply an outer async timeout if an
entire traversal needs a tighter deadline. A reservation is not a hardware write,
but it is transient repository state and may be invalidated by another client.
Do not silently rerun an inconsistent snapshot.

沿用 `defer client.abort()` 与显式 `client.close()`。每次交换有既定超时；若需限制整次遍历，
请另加外层 async 超时。预留不写硬件配置，但属于临时仓库状态，可能被其他客户端取消；
不应静默重跑不一致的快照。

## Actual ipmitool comparison / 实际 ipmitool 对照

Install the README dependencies and **ipmitool 1.8.19**, then run:
准备 README 依赖及 **ipmitool 1.8.19** 后运行：

```sh
moon build --target native --deny-warn
python3 tools/sdr_check.py \
  --moon-client _build/native/debug/build/examples/sdr/sdr.exe \
  --output _build/sdr-comparison.json
```

The runner opens a fresh loopback BMC/session for each client/command. All receive
identical synthetic SDR and reading bytes; the fixture does not identify clients.
It actually executes **`ipmitool -c sdr list all`** and **`ipmitool -c sensor list`**,
not raw-command output interpreted as an SDR test. The example is loopback-only
and uses public synthetic credentials; no real BMC is contacted.

每个客户端/命令使用新的本机 BMC/会话，收到完全相同的合成 SDR 和读数字节，模拟器不识别客户端。
实际执行上述两个 ipmitool 命令，不把 raw 读数包装成 SDR 对照。示例仅支持 loopback，
使用公开合成凭据，不接触真实 BMC。

| Synthetic sensor / 合成传感器 | Compared result / 对照结果 |
|---|---|
| Temperature / 温度 | 42 degrees C, `ok` |
| Voltage / 电压 | 12 Volts, negative decimal exponent / 负十进制指数 |
| Fan / 风扇 | 6000 RPM, multiplier 60 / 倍率 60 |
| Power / 功率 | 150 Watts, signed B offset / 带符号 B 偏移 |
| Signed + one's complement / 补码与反码 | -10 degrees C each / 均为 -10 |
| Unavailable + scanning disabled / 不可用与停扫 | No numeric value / 无数值 |
| Events disabled / 事件关闭 | 42 degrees C remains usable / 仍可读 |
| Upper critical / 上限严重 | 80 degrees C, `cr` |
| Compact intrusion / Compact 入侵 | Asserted bit 0 and matching `sdr` event text / 位 0 与事件文字一致 |

This gives **33 output comparisons** (11 records × three output modes), plus nine
MoonBit repository scenarios: empty, count limit, no reservation support, expired
reservation, cycle, early end, changed next ID, short chunk and wrong record ID.
The runner checks actual authenticated SDR/reading commands, full traversal and
successful close, not only exit codes. On repository failures the example aborts
locally; no partial sensor inventory is emitted.

共 **33 项输出对照**（11 条记录 × 三种输出），另有九项 MoonBit 仓库场景：空仓库、计数超限、
无预留能力、预留失效、循环、提前结束、next ID 改变、短片段、记录 ID 错误。
运行器检查实际认证命令、完整遍历和成功关闭，不只检查退出码。仓库错误时示例在本地中止，
不输出部分传感器清单。

Formatting and unavailable-unit display differ: `sdr` hides units when unavailable;
`sensor list` uses `na`, sometimes with a blank unit. Compare units for usable
analog values, normalise missing readings, and separately verify MoonBit's distinct
unavailable/scanning-disabled states. Compact `sensor list` prints status bytes
high-text-first (`0x0100` for bytes `01 00`); this is not the library's little-endian
mask value `1`. The runner asserts both actual representations.

格式和无效单位显示存在差异：`sdr` 隐去不可用单位，`sensor list` 显示 `na` 且有时留空单位。
只对有效模拟值比较单位，归一化缺失读数，并单独断言 MoonBit 的不可用/停扫区别。
Compact 的 `sensor list` 将 `01 00` 显示为 `0x0100`，不同于库中小端掩码整数 `1`；
运行器断言这两种真实表示。

Threshold **settings**, calibration accuracy/tolerance, non-ASCII ID decoding,
Device SDRs, bridged sensors, shared-record expansion, OEM/nonlinear factors and
full vendor event tables are outside this first subset. The fixture reports no
readable dynamic thresholds for `sensor list`; it does not claim the library can
retrieve or change them. Go-ipmi is not part of this SDR comparison.

本阶段不含阈值**设置值**读取、精度/容差、非 ASCII 名称解码、Device SDR、桥接、共享记录展开、
OEM/非线性因子及完整厂商事件表。模拟器为 `sensor list` 报告无可读动态阈值，不代表库已能读取或修改。
此 SDR 对照不包括 go-ipmi。

## References / 参考

- [IPMI 2.0 specification](https://www.intel.de/content/dam/www/public/us/en/documents/product-specifications/ipmi-v2-rev1-1-spec-errata-6-markup.pdf):
  SDR repository commands, Full/Compact records and sensor unit codes.
- [ipmitool 1.8.19 sensor logic and conversion](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sdr.c)
- [ipmitool 1.8.19 record layouts](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_sdr.h)

These are specification/behaviour references, not copied runtime source or new
dependencies. Tests establish synthetic interoperability, not real hardware
compatibility, production readiness or a security audit.

以上为规范和行为参考，不复制运行时代码、不新增依赖。验证证明合成互操作，
不证明真实硬件兼容、生产可用或通过安全审计。
