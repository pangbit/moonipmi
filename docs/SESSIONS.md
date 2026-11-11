# Session information reads / 会话信息读取

Two unreleased APIs add Get Session Info (`06/3d`) on the existing suite-17/User
transport. They query remote session metadata without changing privileges or
closing the queried sessions. No other transport, authentication mode, retry or
CLI policy is introduced. All evidence below comes from synthetic localhost peers.

两个未发布 API 在既有 suite 17/User 传输上新增 Get Session Info（`06/3d`）。
它们查询远端会话元数据，不改变权限、不关闭被查询会话；未新增其他传输、认证方式、重试或
CLI 策略。下述证据全部来自本机合成对端。

```moonbit
let current = client.session_info()
let by_id = client.session_info(selector=Id(0x12345678U))
let by_handle = client.session_info(selector=Handle(7))
let slot = client.session_info(selector=Slot(1))
let entries = client.sessions(max_slots=63, timeout_ms=10000)
```

| Selector / 选择器 | Wire request / 请求 | Accepted input / 输入 |
|---|---|---|
| `Current` (default / 默认) | `00` | No argument / 无参数 |
| `Id(UInt32)` | `ff` plus four little-endian bytes / 加四字节小端值 | Full uint32, including zero / 完整 uint32，含零 |
| `Handle(Int32)` | `fe handle` | 0..255 |
| `Slot(Int32)` | One slot byte / 单槽位字节 | 1..63; reference raw for individual slots / 单槽位与参考 raw 对照 |

`session_info` sends one read; all nonzero completion codes are errors, including
0xcb/0xcc. Invalid handles/slots fail before this read. It uses the existing
exchange deadline. These reported fields do not prove that the caller can control
or even inspect every session: actual BMC policy may deny the query.

`session_info` 发出一次读取，所有非零完成码（包括 0xcb/0xcc）均作为错误。
非法句柄/槽位在读取前失败，沿用既有逐次交换时限。返回字段不证明调用者具有控制或查询所有
会话的权限，实际 BMC 策略可能拒绝查询。

## Returned values / 返回值

`SessionInfo` retains all `raw` bytes, the eight-bit handle, six-bit slot count and
six-bit active count. A three-byte response has `details=None`; this indicates no
detailed record, not proof that no other sessions exist. Otherwise `SessionDetails`
contains the six-bit user ID, four-bit privilege, channel and auxiliary nibbles,
and a `SessionConnection` describing the returned layout:

`SessionInfo` 完整保留 `raw`、八位句柄、六位槽位数和六位活动数。三字节响应的 `details=None`
表示没有详细记录，不证明其他会话不存在。其余响应的 `SessionDetails` 包含六位用户 ID、
四位权限、通道及辅助半字节，以及描述返回布局的 `SessionConnection`：

| Response bytes / 响应字节数 | Interpretation / 解释 |
|---|---|
| 3 | Counts only / 只有计数 |
| 6 | Common details, `HeaderOnly`, no channel address data / 公共详情，无通道地址数据 |
| 12 | `Serial`: activity, four-bit destination, four IPv4 bytes, no port / 串口：活动类型、目的选择器、IPv4，无端口 |
| 14 | `Serial`: same plus little-endian port at offsets 12..13 / 同上，加偏移 12..13 的小端端口 |
| 18 | `Lan`: four IPv4 bytes, six MAC bytes, little-endian port at offsets 16..17 / LAN：IPv4、MAC 及偏移 16..17 的小端端口 |

Other lengths are rejected; the library does not guess missing fields or silently
discard extra bytes. Reserved bits remain in `raw`; unknown privilege, auxiliary,
activity and destination values stay numeric. In particular, a nonzero auxiliary
nibble is not reduced to a Boolean. Layout interpretation alone does not implement
a serial transport or validate the peer's reported network topology. A reference
display maps any nonzero auxiliary value to `IPMIv2/RMCP+`; projections preserve
that display rule without losing the underlying number.

其他长度被拒绝，不猜测缺失字段、不静默丢弃尾部字节。保留位仍可从 `raw` 获取，未知权限、
辅助、活动和目的选择器保持数值；尤其不把非零辅助半字节简化为布尔值。解释布局不等于实现
串口传输或验证对端报告的网络拓扑。参考将任意非零辅助值显示为 `IPMIv2/RMCP+`；输出映射
复现该显示规则，但 API 不丢失原始数值。

## Bounded enumeration / 有界枚举

`sessions` starts at slot 1, including when that reply reports zero slots, and
uses each latest reported slot count, matching the reference's `session info all`
loop. It returns ordered `SessionEntry { slot, completion_code, info }` records.
Only enumeration accepts completion 0xcb/0xcc with a complete supported response
layout, preserving the code explicitly. It does not invent empty metadata for a
missing/short response or infer the reason for these codes. Changing counts and
apparently contradictory values are retained; there is no atomic snapshot.

`sessions` 从槽位 1 开始，即使首次响应报告零槽位；每步使用最新报告数量，与参考
`session info all` 循环一致。按顺序返回包含槽位、完成码及信息的记录。仅枚举允许带完整
已支持布局的 0xcb/0xcc，并显式保留完成码；不为缺失/截短响应虚构空元数据，不推断完成码
原因。变化中的计数及看似矛盾的值均保留，不保证原子快照。

The default `max_slots=63` accepts 1..63. A reported maximum above the selected
limit aborts before adding that record. At most 63 reads occur; slot 0 and the
ID/handle selectors are never used for enumeration. One overall deadline defaults
to 10000 ms and accepts 1..60000 ms. Completion errors outside the named exception,
malformed responses, limit failures and timeouts abort the local session and
return no partial list. None of these operations closes another remote session.

默认数量上限 63、可选范围 1..63；报告上限超出限制时，在加入该条记录前失败。最多 63 次读取，
枚举不使用槽位 0 或 ID/句柄选择器。整体时限默认 10000 ms、范围 1..60000 ms。除上述例外外，
完成码、坏响应、超限和超时均中止本地会话且不返回部分列表，不关闭其他远端会话。

## Measured differences / 实测差异

- **PPP port:** the pinned reference reads the LAN union's offsets 16..17 for
  a 14-byte serial/PPP response. A single query prints zero; after a LAN record
  in an enumeration it can print the preceding LAN port. The API decodes the
  supplied serial port at 12..13. Six text/CSV leaves remain divergent.
- **Response lengths:** the reference accepts malformed lengths for a single
  query, zero-fills absent bytes, truncates data beyond 18, and reuses earlier
  fields in some short enumeration records. The API rejects these layouts.
  Twenty-six exercised leaves remain divergent.
- **Partial output:** ten later-failure leaves retain earlier reference rows
  with a nonzero exit, while the API returns no partial array.
- **Handle range:** reference CLI parses uint32 and then truncates to a byte.
  Handle 256 is a paired difference; uint32 maximum is one explicitly
  reference-only observation outside the API's `Int32` handle type. The API
  requires a byte-sized handle and rejects invalid input.

- **PPP 端口：** 固定参考在 14 字节串口/PPP 响应中读取 LAN 联合体的偏移 16..17，单条查询
  显示零，枚举中可能沿用前一条 LAN 端口。API 使用串口字段偏移 12..13，六项文本/CSV 差异保留。
- **响应长度：** 参考单条查询接受坏长度、缺失字段补零、超过 18 字节则截断，枚举部分短记录
  会沿用先前字段；API 拒绝这些布局，二十六项实测差异保留。
- **部分输出：** 十项后续失败用例中，参考非零退出但保留此前行，API 不返回部分数组。
- **句柄范围：** 参考 CLI 先解析 uint32 再截成一字节。256 是成对差异，uint32 最大值是
  一项超出 API `Int32` 句柄类型的参考单侧观察。API 要求字节范围句柄并拒绝非法输入。

These are pending [compatibility decisions](PARITY_DECISIONS.md), not approved
exceptions. The recommendation is to preserve accurate raw/typed data and bounded
failures, then settle per-command CLI compatibility together with earlier identity,
precision and output decisions. No authentication or packet-validation rule changed.

上述均为[待裁决兼容事项](PARITY_DECISIONS.md)，不代表获准的例外。建议保留准确原始/类型数据
及有界失败，再与既有身份、精度和输出事项统一决定逐命令 CLI 规则。认证及报文校验策略未变。

## Evidence and reproduction / 证据与复现

Build the [fixed unpatched reference](IPMITOOL_REFERENCE.md), then run:

构建[固定无补丁参考](IPMITOOL_REFERENCE.md)后执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/session_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/session-comparison.json
```

Local native checks pass **61 test groups**. The session checker records
**283 actual client executions / 186 leaves**: **116 output projections, two raw
projections, 12 rejection projections, 12 moon-only boundaries, 43 differences
and one reference-only observation**. It covers the selector endpoints, all
privilege/auxiliary nibbles, serial activities, zero/full counts, changing counts,
all five decoded layouts, completion exceptions, malformed responses, limits and
whole-operation deadlines. It does not exhaust all combinations or all 32-bit IDs.
Both CI platforms execute it and retain build/profile hashes, exact argv,
stdout/stderr bytes, exits, request/response traces and elapsed times. Only Get
Session Info and session/discovery housekeeping are allowed in the fixture.
Deadline cases allow a valid one- or two-read prefix while requiring failure,
no partial result, local abort and bounded elapsed time.

本地 **61 组原生测试**通过。新检查记录 **283 次实际客户端执行、186 个叶项**：
**116 项输出映射、2 项 raw、12 项拒绝映射、12 项本库边界、43 项差异及 1 项参考单侧观察**。
覆盖选择器端点、全部权限/辅助半字节、串口活动、零/满计数及动态计数、五种解码布局、完成码
例外、坏响应、上限和整体时限；并非所有组合或全部 32 位 ID 穷举。两个 CI 平台均执行并保留
构建/profile 哈希、精确参数、输出字节、退出码、请求/响应及耗时。模拟器白名单仅允许会话
信息读取及会话/发现维护命令。超时用例允许合法一至两次读取前缀，同时要求失败、无部分结果、
本地中止及有界总耗时。

C21 remains **partial/divergent**. A compatible CLI, complete default/argument/error
behavior, other transports/privileges and actual hardware evidence remain missing.
Synthetic reads do not establish full ipmitool parity. No real device was contacted
and no Mooncakes package was published.

C21 仍为**部分实现/存在差异**；兼容 CLI、完整默认/参数/错误行为、其他传输/权限及真实硬件
证据仍缺失。模拟读取不能证明完整 ipmitool 一致，未访问真实设备、未发布 Mooncakes。

Pinned sources: [session command and output](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_session.c),
[response layouts](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_session.h).
