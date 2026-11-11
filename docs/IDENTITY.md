# GUID and System Info reads / GUID 与系统信息读取

The unreleased library now provides `Client.device_guid()` (`06/37`) and
`Client.system_info(parameter)` (`06/59`) over the existing suite-17/User session.
They are actual read operations, with public offline response decoders. They do
not change authentication, implement configuration writes, or add a compatible
CLI. No real device was contacted; Mooncakes 0.1.0 is unchanged.

未发布库新增两个实际客户端读取操作及公开离线响应解码器，沿用套件 17/User 会话。
不改变认证、不实现配置写入或兼容 CLI；未连接真实设备，Mooncakes 0.1.0 不变。

```moonbit
// An already authenticated client for an explicitly authorised peer.
let guid = client.device_guid()
let explicit = guid.decode(Ipmi)
let detected = guid.detect(2026) // Supply the current UTC year, or a frozen test year.
let info = client.system_info(SystemName, max_bytes=255, timeout_ms=10000)
let ascii = info.ascii_text()
```

## GUID interpretation / GUID 解释

The response must contain exactly 16 bytes. `DeviceGuid.raw` preserves those
bytes. Explicit `Ipmi`, `Rfc4122`, `Smbios` and `Dump` modes reproduce the pinned
reference's byte ordering and canonical string/dump representation. The actual
reference CLI token is `rfc`. `DecodedGuid` exposes the selected encoding,
formatted value, raw version nibble, recognized version (0–5), and signed
`Int64` Unix seconds for version 1; other versions have no timestamp. Dump mode
has no version interpretation. Unknown versions remain visible.

响应严格要求 16 字节并保留原始值。四种显式模式采用固定参考版本的字节序及字符串表示，
参考 CLI 实际接受的标记为 `rfc`。解码结果包含所选编码、格式化值、原始版本半字节、
识别版本（0–5）及版本 1 的有符号 `Int64` Unix 秒；其他版本无时间值，Dump 不解释版本。
未知版本不会被隐藏。

`detect(current_year)` tries RFC4122, IPMI, then SMBIOS. The last supported
version wins unless an earlier version-1 candidate has a UTC year in
1970..current_year; no valid version falls back to Dump. The explicit year must
be 1970..9999. This matches the reference's **year-based** heuristic, including
future dates within the current year, without hidden clock access. It is not
proof of the device's intended encoding. Callers can select an encoding directly.

自动检测按 RFC4122、IPMI、SMBIOS 顺序选择最后一个受支持版本；若较早的版本 1 候选时间
位于 1970 至指定 UTC 年，则立即采用；无合法候选时转 Dump。参数范围为 1970..9999。
该规则与参考按**年份**判断的启发式一致，包括当年尚未到来的日期，并避免隐式读取时钟。
它不能证明设备原本采用哪种编码，调用方可显式指定。

The reference formats GUID time through its uint32 SEL timestamp formatter.
Pre-epoch and post-2106 values wrap; early values can appear as relative BMC time.
The API retains full signed seconds. Six exercised leaves are explicitly marked
`DIVERGENT_TIMESTAMP_DISPLAY`; reconstructing that CLI presentation in the checker
does not turn them into parity passes. K10 CLI/time policy remains open.

参考通过 uint32 SEL 时间格式化函数显示 GUID 时间，纪元前及 2106 年后的值会回绕，
较早值可能显示为 BMC 相对时间；库保留完整有符号秒数。六个已执行叶项明确记为时间显示差异，
检查器重建参考显示不等于对齐通过。K10 的 CLI/时间规则仍待裁决。

## Named System Info strings / 命名系统信息字符串

| Parameter / 参数 | Selector / 选择值 | Reference name / 参考名称 |
|---|---|---|
| `FirmwareVersion` | `01` | `system_fw_version` |
| `SystemName` | `02` | `system_name` |
| `PrimaryOsName` | `03` | `primary_os_name` |
| `OsName` | `04` | `os_name` |
| `DellOsVersion` | `e4` | `delloem_os_version` |
| `DellUrl` | `de` | `delloem_url` |

All requests are `[0, parameter, selector, 0]`. The first block supplies encoding,
declared byte length and 14 data bytes; subsequent blocks supply 16. The reader
retains exactly the advertised 0..255 bytes (at most 17 requests), the full encoding
byte, its low-nibble encoding, parameter revision and every raw 16-byte block
payload. `ascii_text()` returns text only for encoding zero with all bytes below
128, preserving embedded NUL. Other encodings retain raw bytes without claiming
Unicode/text interpretation. The Dell selectors alone do not establish general
OEM support or real Dell compatibility.

请求按上述四字节发送。首块包含编码、声明字节长度及 14 字节数据，后续块各 16 字节。
读取器准确保留声明的 0..255 字节（最多 17 次请求）、完整编码字节及低半字节编码、
参数修订号与每块原始 16 字节载荷。只有编码为零且全部字节小于 128 才返回 ASCII 文本，
其中零字节保留；其他编码仅保留原始数据，不宣称 Unicode/文本解释。
两个 Dell 参数不代表通用 OEM 支持或实机 Dell 兼容。

`max_bytes` defaults to 255 and accepts 0..255; `timeout_ms` defaults to 10000
and accepts 1..60000. A limit violation, nonzero completion, non-18-byte block,
incorrect echoed selector, changed revision or overall deadline fails the whole
read and aborts the local session, without returning partial data. Invalid
caller limits fail before a read is sent. The operation does not lock parameters
or detect concurrent changes that keep the same revision: it is not an atomic
snapshot. It never sends Set System Info (`06/58`).

字节上限默认 255、范围 0..255；整体时限默认 10000 ms、范围 1..60000。
超限、非零完成码、块长度不为 18、选择值回显错误、修订号变化或整体超时均使整个读取失败，
本地会话中止且不返回部分数据。调用参数越界在发起读取前失败。
不加参数锁，也无法发现修订号不变的并发修改，因此不保证原子快照；从不调用设置命令。

## Retained reference differences / 保留的参考差异

| Case / 情形 | Actual reference behavior / 参考实测行为 | Library / 库行为 |
|---|---|---|
| Length 128 / 长度 128 | Local signed-`char` build reads only 14 bytes; unsigned-`char` builds may read all / 本地有符号 char 构建仅读首块，其他构建可不同 | Reads 128 bytes / 完整读取 |
| Embedded NUL / 内嵌零字节 | Truncates printed text / 显示截断 | Preserves all bytes/text / 保留完整值 |
| Nonzero padding / 非零填充 | Can print past declared length / 可显示声明长度之外的数据 | Uses declared length / 遵守声明长度 |
| Nonzero encoding / 非零编码 | Reads 4 blocks, or 2 for Dell URL; prints raw C string / 固定读 4 块，Dell URL 读 2 块 | Reads advertised length, raw bytes only / 按声明长度读，保留原始值 |
| Completion `80/c1/d4` / 完成码 | Error on stderr, newline on stdout, **exit 0** / 输出错误却零退出 | Raises `ProtocolError` / 抛错 |
| Failure in block 2 / 第二块失败 | Prints first 14 bytes, error, **exit 0** / 输出首块、错误并零退出 | No partial return / 无部分结果 |
| Wrong selector/revision, short/extra block / 选择值、修订号、块长度错误 | Ignores metadata, zero-fills short data or truncates extras / 忽略元数据、补零或截去多余数据 | Rejects / 拒绝 |

These are `DIVERGENT_*` leaves, not accepted exceptions to the full-parity goal.
Recommendation for K08/K10 review: preserve raw data, explicit decoding and bounded
failure behavior in the library; decide reference display/exit emulation together
for the future CLI. Reproducing unchecked buffer behavior is not recommended.
The 255-byte boundary is tested only on moonipmi because the reference's chunk
copy can exceed its fixed output buffer on an unsigned-`char` build. No authentication
or security defaults have been changed. The existing exact POH counter is untouched.

这些叶项标为差异，不是完整对齐目标的已批准例外。K08/K10 建议：库保留原始值、显式解码及
有界失败行为，未来 CLI 的参考显示与退出码模拟统一裁决；不建议复现未检查的缓冲区行为。
255 字节边界只在 moonipmi 执行，因为参考在无符号 char 构建中可能超出固定输出缓冲区。
未改变认证或安全默认值，现有累计通电大计数精度保持不变。

## Validation / 验证

Build the [pinned unpatched reference](IPMITOOL_REFERENCE.md), then run:

先构建固定的无补丁参考，再执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/identity_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/identity-comparison.json
```

The local macOS run passed **50 native test groups** and recorded **180 real client
executions / 94 leaves**: **62 output projections, 5 rejection projections,
8 moon-only boundaries and 19 retained differences**. The report freezes the UTC
year, records all argv/stdout/stderr/exits, typed results, request/response traces
and binary/profile identities. GUID coverage includes all version nibbles, explicit
encodings, auto-selection order and time limits. String coverage includes all six
selectors, chunk boundaries, empty/127/128/255 bytes, encoding/NUL/padding,
completion errors, metadata/length faults, limits and a whole-operation timeout.
The checker accepts either observed signedness outcome for length 128 and records
it explicitly; counts can therefore differ with the reference build.

本地 macOS 通过 **50 组原生测试**；差分报告包含 **180 次实际客户端执行、94 个叶项**：
**62 项输出映射、5 项拒绝映射、8 项本库边界及 19 项保留差异**。报告冻结 UTC 年份，保留
完整调用、输出、退出码、类型化结果、报文 trace 和构建身份。覆盖 GUID 各版本/编码/检测顺序
与时间边界，以及六个字符串参数、分块和长度边界、编码/零字节/填充、完成码、元数据/长度错误、
上限及整体超时。长度 128 用例显式记录两种 char 符号性结果，因此其他构建的状态计数可能不同。

Both CI platforms run this checker and retain its report. Every trace is restricted
to the requested reads and session/discovery housekeeping; success requires a closed
session. The adapter connects only to loopback using synthetic credentials. C08
remains partial/divergent: controls, the full CLI, additional build/privilege/OEM
combinations and real hardware remain unverified or absent.

两个 CI 平台均执行并保留报告。trace 只允许目标读取及会话/发现命令；成功操作须关闭会话。
适配器只连接本机回环地址并使用合成凭据。C08 仍为部分实现/存在差异，控制、完整 CLI、其他构建/
权限/OEM 组合及真实硬件仍缺失或未验证。

Pinned sources: [MC operations](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c),
[wire definitions](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_mc.h),
[time presentation](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_time.c).
