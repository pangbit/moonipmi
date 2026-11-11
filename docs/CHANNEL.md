# Read-only channel APIs / 只读通道 API

The unreleased library adds three actual client operations on its existing
suite-17/User session. No channel settings, user permissions, cipher choice or
SOL payload state are changed. Listing advertised algorithms is not support for
authenticating with those algorithms. No real BMC was contacted or package published.

未发布库新增三个实际客户端操作，沿用 suite 17/User 会话。不修改通道设置、用户权限、
密码套件选择或 SOL 状态；列出算法不代表支持用这些算法认证。未连接真实 BMC 或发布包。

```moonbit
let info = client.channel_info() // Default channel 14 means the current channel.
let active = client.channel_access(Volatile, channel=1)
let stored = client.channel_access(NonVolatile, channel=1)
let suites = client.channel_cipher_suites(Ipmi, channel=1,
  max_bytes=1024, timeout_ms=10000)
```

| Method / 方法 | Request / 请求 | Result / 返回 |
|---|---|---|
| `channel_info(channel~)` | `06/42 [channel]` | `ChannelInfo` |
| `channel_access(settings, channel~)` | `06/41 [channel, 80 or 40]` | `ChannelAccess` |
| `channel_cipher_suites(payload, channel~, max_bytes~, timeout_ms~)` | `06/54 [channel, 0 or 1, 80 OR page]` | `ChannelCipherSuites` |

All channel arguments default to 14 and accept 0..11, 14 or 15, matching the
reference's public channel-number validation. Invalid numbers fail before the
read. `channel_access` reads **channel policy**: it is not the reference CLI's
`channel getaccess`, which reads **per-user access** and remains unimplemented.
The reference `channel info` reads channel policy for LAN media 4 and 6, first
volatile, then nonvolatile; the demonstration adapter follows that sequence.
The library exposes separate operations, without claiming an atomic combined snapshot.

通道默认值均为 14，接受 0..11、14、15，与参考公开参数检查一致，非法值在发起读取前拒绝。
`channel_access` 读取**通道策略**，并非参考 CLI 的**逐用户权限**命令 `channel getaccess`，
后者仍未实现。参考 `channel info` 对 LAN 介质 4/6 依次读取活动及持久策略，示例按此顺序执行。
库提供独立操作，不保证三次读取组成原子快照。

## Returned fields / 返回字段

`ChannelInfo` requires exactly nine response bytes and retains `raw` and the two
auxiliary bytes. It exposes channel (low four bits), medium (low seven), protocol
(low five), session support (0=session-less, 1=single, 2=multi, 3=session-based),
active session count and the little-endian 24-bit protocol vendor ID.

通道信息严格要求九字节，保留全部原始数据及两个辅助字节。解释通道低四位、介质低七位、
协议低五位、会话支持方式（0 无会话、1 单会话、2 多会话、3 基于会话）、活动会话数及
小端 24 位协议厂商 ID。

`ChannelAccess` requires exactly two bytes and retains both. Access modes 0/1/2/3
mean disabled/pre-boot-only/always/shared; 4..7 remain numeric reserved values.
The alerting, per-message-authentication and user-level-authentication booleans
invert the corresponding wire **disable** bits. `privilege_limit` retains the
low nibble even though `channel info` does not print it. These are reported
settings, not a guarantee that the current account can exercise any privilege.

通道访问策略严格要求两字节并完整保留。模式 0/1/2/3 分别代表禁用、仅预启动、始终可用和共享，
4..7 保留数值。告警、逐消息认证、用户级认证的布尔值由报文中的**禁用位**取反。
权限上限保留低半字节，虽然参考 `channel info` 不打印它；设备报告的策略不代表当前账户具备该权限。

Cipher pages contain one channel byte and 0..16 data bytes. Records may cross
pages: standard records are five bytes, OEM records eight. Each parsed record
retains raw bytes, suite ID, optional 24-bit IANA and the low six bits of each
algorithm ID. `None` IANA identifies a standard record; `Some(0)` remains an OEM
record. Unknown algorithm numbers and duplicate IDs remain visible. Unknown
record tags or incomplete records fail instead of returning a parsed prefix.

套件分页响应包含通道字节及 0..16 字节数据，记录可跨页；标准记录五字节，OEM 记录八字节。
每条记录保留原始字节、套件 ID、可选 24 位 IANA 和三个算法 ID 的低六位。
无 IANA 表示标准记录，OEM 的零 IANA 仍单独保留。未知算法编号及重复 ID 均保留；
未知记录标记或不完整记录使整个解码失败，不返回已解析前缀。

`CipherPayload::Ipmi/Sol` maps to query selector 0/1. Reads stop on a short page
or after 64 pages. The complete raw list and every page's channel byte are kept.
Like the reference, the reader does not use the reported page channel to route
requests or reject changes in that payload metadata; authenticated packet
identity/integrity checks are unchanged. `terminated=false` explicitly means
all 64 pages were full, so no short end marker was observed. This is a protocol
ceiling, not proof that the device has no further records.

IPMI/SOL 查询值分别为 0/1，遇短页或达到 64 页即停止，保留完整原始列表及每页通道字节。
与参考相同，响应载荷中的通道值不参与路由，也不因该元数据变化而拒绝；已认证报文的身份和完整性
校验不变。`terminated=false` 明确表示 64 页均满、未观察到短页终止标志；这只是协议上限，
不证明设备没有更多记录。

The cipher byte limit defaults to 1024 (allowed 0..1024), and the overall deadline
defaults to 10000 ms (allowed 1..60000). A completion error, malformed page,
limit violation, parse failure or deadline aborts the local session and returns
no list. There are no retries. Simple info/access reads use the existing exchange
deadline. The multi-read example buffers its JSON until all reads succeed;
separate library calls can already have returned earlier results.

套件字节上限默认 1024、范围 0..1024，整体时限默认 10000 ms、范围 1..60000。
完成码、坏页、超限、解析错误或超时使本地会话中止且不返回列表，无自动重试。
单次信息/策略读取沿用交换时限。示例等待三项读取完成才打印 JSON；库的独立调用则可能已返回较早结果。

## Actual reference differences / 实际参考差异

The fixed source initializes its print-loop record capacity with `sizeof(*suites)`
instead of the array's element count. In the measured profile this is **12**, so
13/18/204-standard-record and 128-OEM-record fixtures are fully read from the wire
but only the first 12 records are printed. The API returns all parsed records.
Sixteen text/CSV/IPMI/SOL leaves remain `DIVERGENT_REFERENCE_RECORD_LIMIT`.

固定源码将打印列表容量设为单条结构体的字节大小，而非数组元素数；本次构建中为 **12**。
13/18/204 条标准及 128 条 OEM 记录的报文被完整读取，但仅打印前 12 条；库返回完整解析结果。
对应文本/CSV/IPMI/SOL 的 16 个叶项保持列表数量差异。

The reference's unknown-value labels share a static buffer. Three distinct unknown
algorithm IDs in one row can all print the same ID, with the selected label
dependent on compiler argument-evaluation order. Four leaves record that display
difference; the checker accepts only the observed defect's possible aliases and
keeps the exact output. It never treats them as equal to the three API values.

参考未知值标签共用静态缓冲区，同一行三个不同的未知算法编号可能显示为同一编号，具体值依赖
编译器实参求值顺序。四项叶用例记录显示差异；检查器只接受该缺陷可能产生的别名并保留实际输出，
不把它们视为与三个 API 数值相同。

On a malformed cipher record, reference `getciphers` prints the valid prefix and
exits zero; the library rejects the list (three divergent leaves). On later
channel-access failure, reference `channel info` retains earlier printed sections
and exits nonzero; the example emits no JSON (three divergent leaves). These are
unresolved API/CLI behavior differences, grouped with GUID/System Info and security
decisions in the [decision register](PARITY_DECISIONS.md), not approved exceptions.

套件记录损坏时，参考打印合法前缀并零退出，库拒绝列表（三项差异）；后续通道访问读取失败时，
参考保留已打印段落并非零退出，示例不打印 JSON（三项差异）。这些 API/CLI 行为差异与 GUID、
系统信息及安全事项一并记录在[裁决汇总](PARITY_DECISIONS.md)，不是已批准的目标例外。

## Validation / 验证

After building the [pinned unpatched reference](IPMITOOL_REFERENCE.md):

构建固定无补丁参考后执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/channel_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/channel-comparison.json
```

Local checks passed **55 native test groups**. The new report contains **178 actual
client executions / 108 leaves**: **61 output projections, 2 raw projections,
9 rejection projections, 10 moon-only boundaries and 26 retained differences**.
It checks exact read payloads and page data, all returned fields including reserved
bits, output/CSV projections, missing/denied commands, malformed lengths/records,
partial failures, protocol ceiling, byte limits and the overall deadline. Both CI
platforms run this checker and retain its binary/profile identities, argv, complete
outputs/exits and authenticated traces. The allowlist contains only these reads
plus session/discovery housekeeping. The adapter is localhost-only.

本地通过 **55 组原生测试**。新报告包含 **178 次实际客户端执行、108 个叶项**：
**61 项输出映射、2 项原始值映射、9 项拒绝映射、10 项本库边界及 26 项保留差异**。
验证精确请求及分页数据、全部返回字段及保留位、文本/CSV 映射、缺失/权限错误、坏长度/记录、
部分失败、协议页数上限、字节限制与整体时限。两个 CI 平台均执行并保留构建身份、完整调用/
输出/退出码和认证 trace。命令白名单只含这些读取及会话/发现操作，适配器仅连接本机。

C20 remains partial/divergent. `authcap`, per-user `getaccess`, controls, a complete
CLI, other authentication/transports, real privilege policies and hardware are
still absent or unverified. No test count is a full-parity percentage.

C20 仍为部分实现/存在差异；认证能力查询、逐用户访问读取、控制、完整 CLI、其他认证/传输、
实际权限策略及硬件仍缺失或未验证，测试计数不是完整对齐覆盖率。

Pinned sources: [channel implementation](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_channel.c),
[record layout](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_intf.h),
[unknown labels and channel validation](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/helper.c).
