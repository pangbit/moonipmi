# Three read-only use scenarios / 三个只读使用场景

These workflows exercise the current **GitHub checkout**, including Unreleased
metadata APIs absent from Mooncakes 0.1.0. They demonstrate useful application
building blocks against a synthetic BMC, not a ready-made fleet manager or proof
of real-device compatibility. All input values below are public test data.

以下流程使用当前 **GitHub 源码**，包括 Mooncakes 0.1.0 中尚无的未发布元数据 API。
它们验证应用可复用的真实读取流程，但目标是合成 BMC，不是现成集群管理器，也不证明实机兼容。
下列值均为公开测试数据。

## Common setup and evidence / 共同准备与证据

From the repository root, install the README's native dependencies, Go 1.24 and
ipmitool **1.8.19**, then run the existing comparison once:

在仓库根目录操作，先准备 README 中的原生依赖、Go 1.24 和 ipmitool **1.8.19**，
再运行一次已有对照。首次初始化 Mooncakes/Go 依赖需要网络：

```sh
moon update
moon build --target native --deny-warn
go -C tools/go-reference build -mod=readonly -o ../../_build/reference-client ./client
python3 tools/compare_clients.py \
  --moon-client _build/native/debug/build/examples/comparison/comparison.exe \
  --go-client _build/reference-client \
  --output _build/client-comparison.json
```

Expected final line: `PASS: 30 comparisons across 3 clients; no hardware contacted`.
Each positive case opens a fresh loopback-only UDP session, authenticates with
suite 17 and User privilege, reads one value and closes the session. The runner
asserts authenticated traffic and close, not just printed output. It owns and
closes its temporary sockets; the JSON remains under ignored `_build/`.
The two negative cases separately check a wrong synthetic password and an absent
sensor (`0xcb`). No target, real credentials or hardware-control operation is needed.

预期末行为上述 30 项通过信息。每个成功用例建立新的本机 UDP 会话，以套件 17 和 User
权限认证，读取后关闭；运行器核对已认证流量和关闭，不仅看打印文本。临时 socket 由运行器
关闭，JSON 保留在已忽略的 `_build/` 下。另有错误合成密码及不存在传感器（`0xcb`）两个
负向场景。不需要指定真实目标、真实凭据或执行硬件控制。

Inspect only the MoonBit result rows / 只查看 MoonBit 结果：

```sh
python3 - <<'PY'
import json
with open('_build/client-comparison.json') as f:
    report = json.load(f)
for row in report['cases']:
    if row['client'] == 'moonipmi':
        print(row['case'], row['classification'], json.dumps(row['result'], sort_keys=True))
PY
```

## 1. Inventory controller identity and advertised capabilities / 控制器身份与能力盘点

**Goal:** before integrating a management endpoint, record its IPMI/firmware
identity and advertised capability bits without probing unsupported features.
`Client.read(GetDeviceId).device_id()` provides the typed result.

**目的：**接入管理端点前，读取 IPMI/固件标识及自报能力，避免盲目探测不支持的功能。
使用上述类型化读取入口。

After common setup, inspect `device` and `device-extended`. Both must be `matched`:

完成共同步骤后，检查两个均为 `matched` 的结果：

| Field / 字段 | `device` | `device-extended` |
|---|---|---|
| Device ID / 设备 ID | 18 | 18 |
| Firmware / 固件版本 | 1.23 | 1.23 |
| IPMI version / 版本 | 2.0 | 2.0 |
| Firmware available / 固件可用 | `true` | `false` |
| Device SDR / 设备 SDR | `false` | `true` |
| Additional support bitmask / 额外能力位图 | 1 | 255 |
| Auxiliary firmware / 辅助固件 | `null` | `[1, 35, 69, 103]` |

**Outcome:** an inventory record can preserve unavailable firmware and absent
optional metadata rather than inventing defaults. Capability bits are only what
the BMC advertises: they do not establish working SDR, SEL, FRU or other APIs.
ipmitool's `mc info` is the functional comparison for these overlapping fields.

**结果：**资产记录能区分固件不可用和可选字段缺失，不伪造默认值。能力位只是 BMC 自报，
不代表已实现或验证 SDR、SEL、FRU 等功能。交集字段以 ipmitool `mc info` 为功能对照。

## 2. Triage chassis power and fault flags / 机箱供电与故障只读排查

**Goal:** distinguish an on/no-fault report from an off/fault report before an
operator decides how to investigate. Use `Client.read(GetChassisStatus).chassis_status()`.

**目的：**在操作者决定后续调查前，区分“通电且无故障标志”和“断电且有故障标志”的报告。
使用上述机箱状态读取入口，不自动控制电源。

Inspect `chassis` and `chassis-faults` in the same report. Both must be `matched`:

检查同一报告中的两项，均应为 `matched`：

- `chassis`: `power_on=true`; overload, main-power, intrusion, front-panel lockout,
  drive and cooling/fan fault flags are all `false`; restore policy is 0.
- `chassis-faults`: `power_on=false`; the six flags above are `true`; restore policy
  is 2. Interlock and power-control-fault remain `false` in both fixtures.

- 正常场景：`power_on=true`；过载、主电源、入侵、前面板锁定、驱动器及风扇故障均为
  `false`，恢复策略为 0。
- 故障场景：`power_on=false`；上述六个标志均为 `true`，恢复策略为 2。
  两个场景中的互锁和电源控制故障标志仍为 `false`。

**Outcome:** an application can present the reported flags for human triage.
These are not root-cause diagnoses, overall health certification or observed
physical power transitions. The functional comparison is `ipmitool chassis status`;
no command changes power or restore policy.

**结果：**应用可以展示标志供人工排查，但不能当作根因诊断、整体健康认证或实物电源变化证据。
功能对照为 `ipmitool chassis status`；不会修改电源或恢复策略。

## 3. Gate raw sensor readings by validity / 按有效性筛选传感器原始读数

**Goal:** prevent unavailable sensor bytes from being treated as valid samples.
Read known sensor `0x2a` using `GetSensorReading`, decode `sensor_reading()` and use
`usable_raw_reading()` rather than the raw byte alone.

**目的：**避免将不可用的传感器字节误当作有效样本。读取已知传感器 `0x2a`，通过上述接口
解析后使用 `usable_raw_reading()`，而不是直接采用原始字节。

Inspect these `matched` rows / 检查下列 `matched` 结果：

| Case / 场景 | Raw / 原始值 | Available / 可用 | Scanning / 扫描 | Events / 事件 | Usable raw / 有效原始值 |
|---|---|---|---|---|---|
| `sensor` | 42 | `true` | `true` | `true` | 42 |
| `sensor-unavailable` | 238 | `false` | `true` | `true` | `null` |
| `sensor-disabled` | 238 | `true` | `false` | `true` | `null` |
| `sensor-events-disabled` | 42 | `true` | `true` | `false` | 42 |

**Outcome:** retain 42 only for usable samples; preserve missingness instead of
substituting zero. Disabling event messages alone does not invalidate a reading.
The independent comparison uses `ipmitool raw 0x04 0x2d`, **not** `sensor list/get`.
This library neither discovers sensor numbers through SDR nor turns raw 42 into
degrees, volts or a health threshold. Supply separately verified sensor metadata
before interpreting units; do not infer an actual temperature from this fixture.

**结果：**仅对有效样本保留 42，无效时保留缺失，不填零。仅关闭事件消息不会令读数无效。
独立对照用 `ipmitool raw 0x04 0x2d`，**不是** `sensor list/get`。本库不通过 SDR 发现
传感器编号，也不将原始 42 转成温度、电压或健康阈值。解释单位前须另有经验证的元数据，
不能把模拟值误称为实际温度。

See [comparison details](COMPARISON.md) for normalization and intentional differences,
and [scope/evidence](STATUS.md) for exact CI coverage and remaining limitations.
归一化及有意保留的差异见[对照说明](COMPARISON.md)，确切 CI 覆盖及边界见[范围与证据](STATUS.md)。
