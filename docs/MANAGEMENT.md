# Read-only management status / 只读管理状态

The current unreleased library adds four actual client operations on the existing suite-17/User session. They send one empty-payload read each and use the client's exchange deadline. There are no new runtime dependencies, authentication defaults or control operations. Mooncakes 0.1.0 remains unchanged.

当前未发布库新增四个实际客户端操作，沿用套件 17/User 会话，每项发送一个无参数读取命令并使用已有交换时限。不增加运行时依赖，不改变认证默认值，不提供控制操作；Mooncakes 0.1.0 不变。

```moonbit
// An already authenticated client for an explicitly authorised peer.
let result = client.self_test()
let enables = client.global_enables()
let timer = client.watchdog_timer()
let counter = client.power_on_hours()
```

| Client method / 方法 | IPMI netfn / command | Response / 返回值 | Reference operation / 参考功能 |
|---|---|---|---|
| `self_test()` | `06 / 04` | `SelfTestResult` | `mc selftest`, `chassis selftest` |
| `global_enables()` | `06 / 2f` | `GlobalEnables` | `mc getenables` |
| `watchdog_timer()` | `06 / 25` | `WatchdogTimer` | `mc watchdog get` |
| `power_on_hours()` | `00 / 0f` | `PowerOnHours` | `chassis poh` |

Corresponding `Response` decoders are public for offline use. The example `examples/diagnostics` exposes `self-test`, `enables`, `watchdog` and `poh` modes, hardcoded to loopback with synthetic credentials. It is a demonstration/validation adapter, not an ipmitool-compatible CLI.

对应 `Response` 解码器也公开供离线使用。诊断示例新增四个模式，固定连接本机回环地址并使用合成凭据；它是示例和验证适配器，尚不是兼容 ipmitool 的 CLI。

## Results and interpretation / 结果与解释

`SelfTestResult` preserves both result bytes, `code` and `detail`. `status()` classifies `55/56/57/58/ff` as `Passed/NotImplemented/Corrupted/FatalError/Reserved`, with other codes classified as `DeviceSpecific` following the pinned reference. Device-specific does not imply healthy. `corruption_flags()` returns a bitmap only for `0x57`; detail has a different meaning for other codes.

自检保留两个原始结果字节，并按固定参考版本分类。设备专有结果不代表健康；只有 `0x57` 的详情才按标准损坏位图解释，其他状态不套用这套位含义。

| Bit / 位 | `0x57` detail / 详情含义 |
|---|---|
| 7 | SEL inaccessible / 无法访问 SEL |
| 6 | SDR repository inaccessible / 无法访问 SDR 仓库 |
| 5 | FRU inaccessible / 无法访问 FRU |
| 4 | IPMB signal failure / IPMB 信号无响应 |
| 3 | SDR repository empty / SDR 仓库为空 |
| 2 | Internal Use Area corruption / 内部使用区域损坏 |
| 1 | Update boot block corruption / 更新启动块损坏 |
| 0 | Operational firmware corruption / 工作固件损坏 |

Reading stored self-test results does not initiate a test/reset. A valid result reporting corruption, fatal error or an unsupported test is returned as data. Nonzero **IPMI completion codes** instead raise `ProtocolError`. The reference CLI has a separate contract: `mc selftest` exits nonzero for `0x56/57/58/ff`, whereas `chassis selftest` exits zero for the same valid responses and uses different text. The adapter's successful JSON read is not an assertion of device health or a matching CLI exit code.

此命令只读取已有自检结果，不发起自检或复位。设备报告损坏、致命错误或不支持测试时，合法响应仍作为数据返回；非零 **IPMI 完成码**才抛出协议错误。参考 CLI 有独立规则：`mc selftest` 对上述四种结果非零退出，而 `chassis selftest` 对同一合法响应零退出且文字不同。示例成功读出 JSON 不等于设备健康，也不宣称退出码一致。

`GlobalEnables` exposes seven named booleans: receive-queue interrupt, event-buffer-full interrupt, event buffer, system-event logging and OEM 0/1/2. `flags` retains all eight bits, including reserved bit 4. The read never calls Set Global Enables (`06/2e`).

全局使能状态提供七个命名布尔值，并保留含第 4 保留位在内的完整标志字节；不调用设置命令。

`WatchdogTimer` exposes timer use, running/logging state, timeout action, pre-timeout interrupt and interval, expiration flags and two unsigned 16-bit countdowns. Countdowns are stored in tenths of a second; the seconds helpers divide by ten. Description helpers match the known/reserved reference labels. `raw` preserves all eight bytes, including reserved bits. Expiration bits 1–5 correspond to BIOS FRB2, BIOS/POST, OS Load, SMS/OS and OEM; bits 0/6/7 remain reserved. Reading does not reset (`06/22`), configure (`06/24`) or stop the timer.

看门狗返回用途、运行及日志状态、超时动作、预超时中断及秒数、到期位图，以及两个无符号 16 位倒计时。倒计时原单位为 0.1 秒，秒数方法除以十。描述与参考已知/保留标签一致，`raw` 保留全部八字节及保留位。到期位 1–5 对应上述用途，0/6/7 保留；读取不重置、配置或停止计时器。

`PowerOnHours` preserves the reported minutes-per-count byte and unsigned 32-bit count, including a zero multiplier. `total_minutes()` returns their exact `UInt64` product without overflow over the complete wire range. This is the reported counter, not a guarantee of accurate wall-clock uptime.

累计通电计数保留设备报告的分钟倍率（含零）及无符号 32 位计数，`total_minutes()` 返回完整报文范围内无溢出的精确 `UInt64` 乘积。它是设备报告值，不保证等于准确的实际开机时长。

## Known behavior differences / 已知行为差异

The reference computes POH display values using `float`. For a synthetic multiplier of 1 and count **16,777,217**, both clients read the same bytes, but the reference prints **11,650 days, 20 hours, 16 minutes**; the exact API value corresponds to **17 minutes**. The differential leaf is `DIVERGENT_DISPLAY_PRECISION`, not PASS. Recommendation for K10 review: preserve exact raw/API values, and decide separately whether a future compatibility CLI must reproduce reference display rounding. No existing API/default was changed to hide this difference.

参考使用单精度浮点计算显示值。上述合成输入中，两客户端原始值一致，但参考显示少一分钟。该叶项明确标记显示精度差异，未记通过。K10 建议供审核：库继续保留无损原始值及精确值，未来兼容 CLI 是否复现参考舍入另行裁决；本轮未改动既有 API 或默认值来掩盖差异。

Fixed-length decoders require 2/1/8/5 bytes respectively and reject truncation or extra bytes. The reference uses unchecked fixed-layout access for these responses; malformed buffers are tested only on moonipmi, not counted as differential passes. Existing suite-17-only authentication, User defaults, strict packet checks, no-retry behavior and failure cleanup differences remain. No real BMC, privilege-policy or hardware compatibility is established.

解码器分别严格要求 2/1/8/5 字节，拒绝截断和多余字节。参考采用未检查的固定布局访问，因此坏长度只验证 moonipmi，不能算差分通过。既有认证、权限默认值、严格报文检查、无重试及失败清理差异仍保留；没有实机、实际权限策略或硬件兼容证据。

## Validation / 验证

Build the [pinned reference profile](IPMITOOL_REFERENCE.md) first, then:

先构建固定参考 profile，再执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/management_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/management-comparison.json
```

Local checks passed 46 native test groups. The new independent synthetic fixture executes the actual reference and library against identical reset input. Its **127 executions** record **56 successful output projections, eight completion-error projections, 11 moonipmi-only length boundaries and one retained display difference**. Self-test cases cover every standard failure bit and all reference result categories; enables cover each bit; watchdog covers all use/action/interrupt values, running/logging states, expiration bits and countdown boundaries; POH covers units, unsigned values and the precision difference.

本地通过 46 组原生测试。新独立模拟器让两个实际客户端分别读取相同初始输入。**127 次执行**记录 **56 项成功输出映射、8 项完成码错误映射、11 项仅 moonipmi 的长度边界、1 项保留的显示差异**。覆盖自检全部标准错误位和参考结果类别、使能各位、看门狗全部用途/动作/中断值及状态/计数边界、通电倍率/无符号数及精度差异。

The report records binary/profile identities, exact argv/stdout/stderr/exit codes, typed values and request/response traces. It requires one requested read per invocation and an allowlist that excludes control commands. Both CI platforms run the checker and retain its report. These are typed API/output projections; neither a family-level PASS nor a compatible CLI is claimed. GUID/system-info reads and management controls are still missing from the MC family.

报告保留构建身份、完整调用/输出/退出码、类型化值和请求/响应 trace，并断言每次只发一次目标读取、禁止控制命令。两个 CI 平台均执行并保留报告。这些是类型化 API/输出映射，不是完整功能族或 CLI 一致证明；MC 的 GUID、系统信息读取及控制功能仍缺失。

Pinned sources: [MC reads](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c), [wire definitions](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_mc.h), [chassis self-test/POH](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_chassis.c).
