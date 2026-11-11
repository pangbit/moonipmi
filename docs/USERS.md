# User and per-user access reads / 用户与逐用户访问读取

The unreleased library adds four client methods using only Get User Access
(`06/44`) and Get User Name (`06/46`) on the existing suite-17/User session.
It does not set names/passwords/privileges, enable or disable accounts, test
passwords, or change the current session role. All validation uses synthetic
localhost peers; no real BMC or Mooncakes publication is involved.

未发布库新增四个客户端方法，只在既有 suite 17/User 会话中读取用户访问权限和名字。
不设置名字、密码或权限，不启停账户、不测试密码，也不改变当前会话角色。
全部验证使用本机合成对端，不涉及真实 BMC 或 Mooncakes 发布。

```moonbit
let summary = client.user_access(1) // Reference user summary reads ID 1.
let name = client.user_name(2)
let record = client.user_record(2, channel=1, timeout_ms=10000)
let list = client.users(channel=1, max_users=63, timeout_ms=10000)
let fixed_scan = client.users(channel=1, mode=InitialMaximum)
```

| Method / 方法 | Request / 请求 | Result / 返回 |
|---|---|---|
| `user_access(user_id, channel~)` | `06/44 [channel, user_id]` | `UserAccess` |
| `user_name(user_id)` | `06/46 [user_id]` | `UserName` |
| `user_record(user_id, channel~, timeout_ms~)` | Access then name / 先权限后名字 | `UserRecord` |
| `users(channel~, mode~, max_users~, timeout_ms~)` | Access/name for each ID / 逐 ID 读取权限和名字 | `Array[UserRecord]` |

User IDs must be 1..63. Channels default to 14 (current) and accept 0..11, 14 or
15, matching the reference's public argument validation. Invalid arguments fail
before sending these reads. The new `user_access` is **per-user policy**, unlike
the existing `channel_access` that reads channel-wide volatile/nonvolatile settings.
Reported privileges do not imply the authenticated account has those privileges.

用户 ID 范围为 1..63；通道默认 14（当前通道），接受 0..11、14、15，与参考公开参数校验一致。
非法值在发出这些读取前失败。新增 `user_access` 是**逐用户策略**，区别于既有读取通道活动/
持久策略的 `channel_access`。设备报告的权限不等于当前认证账户实际具备该权限。

## Data and name semantics / 数据与名字语义

The access response must be exactly four bytes. `UserAccess` retains `raw`, the
six-bit maximum/enabled/fixed-name counts, enable status (0 unknown, 1 enabled,
2 disabled, 3 reserved), call-in availability, link authentication, IPMI messaging
and the four-bit privilege limit. Call-in availability inverts the callback-only
wire bit. Reserved values, contradictory counts and all unused bits remain
available; no inferred account-health or consistency verdict is added.

权限响应严格要求四字节，保留原始值、六位最大/启用/固定名字数量、启用状态（0 未知、1 启用、
2 禁用、3 保留）、允许呼入、链路认证、IPMI 消息及四位权限上限。“允许呼入”由报文中
“仅回调”位取反。保留值、可能矛盾的计数及未使用位均保留，不推断账户健康或配置一致。

The name response must be exactly 16 bytes. `UserName.raw` preserves all of them;
`data` ends at the first NUL, or includes all 16 bytes if no NUL is present, matching
the reference's fixed-field C-string boundary. Nonzero bytes after NUL remain in
`raw`. `ascii_text()` returns `Some` only for an all-ASCII prefix; it does not trim
spaces, escape control characters or guess a non-ASCII encoding. Binary names
remain usable as bytes. Unlike variable-length System Info strings, the fixed
username field has this explicit NUL-terminated interpretation.

名字响应严格要求 16 字节，`raw` 完整保留；`data` 在首个零字节处结束，没有零字节则保留全部
16 字节，与参考固定字段的 C 字符串边界一致。零字节之后的非零数据仍保留在 `raw`。
只有前缀全为 ASCII 才返回可选文本，不裁剪空格、不转义控制字符或猜测非 ASCII 编码。
二进制名字仍可按字节使用；固定用户名与变长 System Info 字符串的边界规则不同。

`user_name` directly exposes all nonzero completion codes as errors. Compound
`user_record`/`users` deliberately follow the reference's exception for name
completion **0xcc** (invalid request data field): `UserRecord.name=None` preserves
that outcome. A successful all-zero name is instead `Some` with empty `data`.
Reference displays both as empty. This fallback does not apply to access completion
0xcc or any other name completion code, and does not prove why the BMC rejected
the name query. Corresponding `Response` decoders are public for offline use.

单独的 `user_name` 将所有非零完成码作为错误。组合读取按参考的特殊处理，将名字命令返回
**0xcc（请求数据字段无效）**保留为 `name=None`。成功返回全零名字则是包含空 `data` 的 `Some`，
参考显示均为空，但库区分二者。该回退不适用于权限查询的 0xcc 或其他名字完成码，也不推断
BMC 拒绝查询的原因。对应响应解码器公开用于离线处理。

## Enumeration and bounds / 枚举与边界

`FollowMaximum` is the default and follows `ipmitool user list`: read access then
name starting at ID 1, and use each latest reported maximum to decide whether to
continue. `InitialMaximum` follows `channel getaccess` without a user ID: freeze
the first maximum, while retaining later changing counts in each record. Explicit
`user_record(id)` corresponds to the single-ID variant. Both scans probe ID 1 even
when the first response reports maximum zero, as the reference's do/while loops do.
This is not a claim that an actual zero-capacity device supports ID 1.

默认 `FollowMaximum` 对应 `user list`：从 ID 1 开始，先权限后名字，并按每次最新报告的最大值
决定是否继续。`InitialMaximum` 对应省略用户 ID 的 `channel getaccess`：固定首次上限，后续变化
仍保留在各记录中；显式单 ID 对应 `user_record`。两种扫描都会探测 ID 1，即使首次报告最大值为零，
与参考 do/while 行为一致；这不代表实际零容量设备一定支持 ID 1。

`max_users` defaults to 63 and accepts 1..63. A selected maximum above the limit
fails before that record's name query. A growing maximum is checked again in
FollowMaximum mode; InitialMaximum continues using the first bound. No scan
requests ID 0 or 64, and a full 63-user scan uses at most 126 user commands.
Neither mode locks configuration or promises an atomic snapshot; changing names
or policies can be observed between requests.

数量上限默认 63、范围 1..63。按所选模式得到的最大值超过上限时，在该记录的名字查询前失败。
跟随模式会再次检查增大的最大值，固定模式继续使用首次值。扫描不请求 ID 0 或 64，完整 63 用户
扫描最多发送 126 个用户命令。不锁定配置、不保证原子快照，各次请求间可能观察到变化。

Both compound methods use one overall deadline, default 10000 ms and range
1..60000. Other than the named 0xcc exception, completion errors, malformed
responses, limit failures and timeouts abort the local session and return no
record/list. Single-command methods use the existing exchange deadline and
response/error contract. No retry or authentication fallback is introduced.

两个组合方法使用整体时限，默认 10000 ms、范围 1..60000。除上述名字 0xcc 例外外，完成码、坏响应、
上限或超时均使本地会话中止且不返回记录/列表。单命令方法沿用已有交换时限及响应/错误合同。
没有新增重试或认证回退。

## Differences and reference observations / 差异与参考观察

When a later user read fails, both reference list entry points exit nonzero but
keep previously printed rows/sections. The library returns no partial array;
the JSON adapter emits no successful result. Twelve exercised text/CSV/detail
leaves remain `DIVERGENT_PARTIAL_OUTPUT`, grouped with earlier partial-output
decisions in the [decision register](PARITY_DECISIONS.md).

较晚的用户读取失败时，参考两种列表入口均非零退出，却保留此前已打印的行/段落；库不返回部分数组，
JSON 适配器不输出成功结果。十二个文本/CSV/详情叶项保持部分输出差异，与此前事项一并纳入
[统一裁决汇总](PARITY_DECISIONS.md)。

The reference prints name bytes directly. Commas, quotes and newlines are not
escaped, including in CSV. Three leaves are marked `OBSERVED_REFERENCE_UNESCAPED_NAME`,
not ordinary parity passes: a byte projection can reproduce the output, but the
library has no compatible CLI renderer. Its JSON example escapes control characters.
Raw/text display, CSV quoting and logging rules remain pending; raw-byte preservation
alone does not settle that policy. No real account information is used in fixtures.

参考直接打印名字字节，包含 CSV 在内均不转义逗号、引号和换行。三项叶用例标为参考未转义名字的
观察记录，不记普通对齐通过：字节映射可重建输出，但库尚无兼容 CLI 渲染器，JSON 示例会转义
控制字符。原始/文本显示、CSV 引用与日志规则仍待裁决，保留原始字节本身不解决该策略。
模拟器不使用真实账户信息。

## Validation / 验证

After building the [fixed unpatched ipmitool reference](IPMITOOL_REFERENCE.md):

构建固定无补丁参考后执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/user_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/user-comparison.json
```

Local checks pass **58 native test groups**. The new fixture records **174 actual
client executions / 104 leaves**: **57 output projections, 5 raw projections,
12 rejection projections, 15 moon-only boundaries, 12 partial-output differences
and 3 unescaped-name observations**. It covers all privilege nibbles, enable states,
access flags, zero/full counts, both enumeration rules, changing counts, name bytes
and 0xcc handling, malformed/denied reads, later failures, limits and deadlines.
Both CI platforms run it. Reports retain binary/profile identities, exact requests
and responses, argv, stdout/stderr **hex bytes**, readable escaped views, exits and
elapsed times. The shared runner's optional binary capture leaves existing text
checks unchanged. Allowed commands are user reads plus session/discovery housekeeping.
The 200 ms deadline cases accept the valid one- or two-request prefix, since CI
scheduling may consume the first response budget; failure, no partial result and
bounded elapsed time remain required.

本地通过 **58 组原生测试**。新模拟器记录 **174 次实际客户端执行、104 个叶项**：
**57 项输出映射、5 项原始值映射、12 项拒绝映射、15 项本库边界、12 项部分输出差异及 3 项
未转义名字观察**。覆盖全部权限半字节、启用状态、访问位、零/满计数、两种扫描规则、动态计数、
名字字节及 0xcc、坏响应/权限拒绝、后续失败、上限与时限。两个 CI 平台均执行；报告保留构建身份、
精确请求/响应、完整调用、输出**十六进制字节**及可读转义视图、退出码和耗时。
共享运行器新增可选二进制捕获，既有文本检查保持原行为。白名单仅含用户读取及会话/发现命令。
200 ms 超时用例允许合法的一至两次请求前缀，因为 CI 调度可能消耗首个响应的时间预算；
仍必须失败、不返回部分结果并满足总耗时限制。

C19/C20 remain partial/divergent. Password testing, account writes, channel authcap,
the complete CLI, other authentication/transports and real-device privilege policies
remain missing or unverified. No local simulation establishes full ipmitool parity.

C19/C20 仍为部分实现/存在差异；密码测试、账户写入、通道认证能力查询、完整 CLI、其他认证/传输
及真实设备权限策略仍缺失或未验证。本地模拟不能证明完整 ipmitool 一致。

Pinned sources: [user operations](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_user.c),
[channel getaccess](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_channel.c),
[user wire fields](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_user.h).
