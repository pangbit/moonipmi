# Authentication capability and LAN statistics reads / 认证能力与 LAN 统计读取

The unreleased library adds two diagnostic APIs on the existing suite-17/User
session. Capability queries describe what a channel reports; they do not activate
algorithms, change the authenticated role, supply Kg or permit anonymous login.
LAN statistics always use the non-clearing selector. All validation uses synthetic
localhost peers; no real devices or Mooncakes publication are involved.

未发布库在既有 suite 17/User 会话上新增两个诊断 API。认证能力查询只读取通道声明，不启用
算法、不改变认证权限、不提供 Kg 或允许匿名登录。LAN 统计始终使用“不清零”选择器。
全部验证采用本机合成对端，不涉及真实设备或 Mooncakes 发布。

```moonbit
let capabilities = client.channel_auth_capabilities(2, channel=14)
let basic_query = client.channel_auth_capabilities(2, channel=1, version2=false)
let statistics = client.lan_statistics(1, timeout_ms=10000)
```

| API / 方法 | Wire operations / 报文操作 |
|---|---|
| `channel_auth_capabilities(privilege, channel~, version2~)` | `06/38 [channel OR extended-data-bit, privilege]` |
| `lan_statistics(channel, timeout_ms~)` | Two `06/42 [channel]` LAN-medium checks, then `0c/04 [channel, 00]` / 两次通道类型检查后读取不清零统计 |

## Capability query / 认证能力查询

Channels default to 14 and accept 0..11, 14 and 15. The queried privilege accepts
1..5 or 15, following the reference `channel authcap` argument validator; it is
independent of the current session's User role. `version2=true` sets bit 7 of the
channel byte to request extended capability data. `false` clears only that query
bit and is compared with reference `raw`; it does not select an IPMI 1.5 transport
or weaken authentication. There is no automatic retry/fallback after failure.

通道默认 14，允许 0..11、14、15；查询权限允许 1..5 或 15，与参考参数校验一致，独立于当前
User 会话权限。默认设置通道字节第 7 位，请求扩展能力数据；`version2=false` 仅清除此查询位，
用参考 `raw` 对照，不选择 IPMI 1.5 传输，也不降低认证强度。失败后不会自动重试或回退。

`ChannelAuthCapabilities` requires exactly eight response bytes and retains `raw`,
the full reported channel byte, six-bit legacy authentication mask, extended-data
availability, Kg-status bit, per-message/user authentication enable flags, named/
null/anonymous-user flags, IPMI 1.5/2.0 support bits, OEM IANA and auxiliary byte.
Disabled wire bits are inverted for the two enable flags. Unknown/reserved bits
remain available in `raw`; the mask does not mean this client implements those
algorithms. Kg and version-support bit values must be interpreted together with
`v20_data_available`; the decoder preserves them even when extended data is not
declared available. Likewise OEM fields are retained when the OEM mask is absent.
Reported support never proves that a particular login or privilege will succeed.

返回严格要求八字节，保留原始值、完整通道字节、六位旧式认证掩码、扩展数据可用标志、Kg 状态位、
逐消息/用户认证使能、非空/空/匿名用户标志、IPMI 1.5/2.0 支持位、OEM IANA 和辅助字节。
两个使能字段由禁用位取反；未知/保留位可从 `raw` 获取，认证掩码不代表客户端已实现对应算法。
Kg 和版本支持位必须结合 `v20_data_available` 解释；即使未声明扩展数据可用，解码器仍保留
这些位值。未声明 OEM 认证时也保留 OEM 字段。支持声明不证明特定登录或权限请求会成功。

All nonzero completion codes are errors. This single query uses the existing
exchange deadline and error contract. The `Response::channel_auth_capabilities`
decoder is also public for offline interpretation.

所有非零完成码均作为错误，单次查询沿用既有交换时限和错误合同；响应解码器也公开供离线使用。

## LAN statistics / LAN 统计

An explicit channel is required. This entry point accepts **1..14**, including
12/13, matching the reference LAN dispatcher; this differs from the separate
`channel` command's argument range. There is no automatic channel discovery yet.
Two consecutive Get Channel Info replies must each report medium 4 (802.3 LAN)
or 6 (other LAN). This intentionally matches the reference's two checks, including
failure if the second reply changes to a non-LAN medium. Each info response must
have the existing exact nine-byte layout. The requested channel remains the
target even if a reply reports a different channel number.

必须显式指定通道，允许 **1..14**（含 12/13），与参考 LAN 入口一致，区别于独立 `channel`
命令的参数范围。尚无自动通道发现。连续两次通道信息都必须报告类型 4（802.3 LAN）或 6
（其他 LAN），有意复现参考的两次检查；第二次改成非 LAN 类型时也失败。通道信息沿用严格
九字节布局。即使响应报告不同通道编号，后续请求仍针对调用者指定的通道。

`LanStatistics` requires exactly 18 response bytes and exposes nine unsigned
16-bit counters as `Int32`: received IP packets, IP header errors, IP address
errors, fragmented IP packets, transmitted IP packets, received UDP packets,
valid RMCP packets, received UDP proxy packets and dropped UDP proxy packets.
The decoder follows the pinned reference's **big-endian** byte interpretation and
retains `raw`. Values such as 65535 remain numeric; no overflow, reset, rate,
unsupported-counter or health interpretation is inferred. Hardware counter
semantics and byte order still need real-device validation.

统计响应严格要求 18 字节，九个无符号 16 位计数以 `Int32` 返回：IP 接收、IP 头错误、IP 地址
错误、IP 分片、IP 发送、UDP 接收、有效 RMCP、UDP 代理接收及丢弃。按固定参考的**大端**
字节顺序解码并保留原始值；65535 等值仍是数字，不推断溢出、重置、速率、不支持计数器或
健康状态。实际硬件的计数语义和字节序仍待实机验证。

The operation uses one overall deadline, default 10000 ms and range 1..60000.
At most three command reads occur. Errors, malformed responses, non-LAN medium
and timeouts abort the local session and return no statistics result. No counter
clear, ARP suspension or LAN configuration write is exposed. The standalone
`Response::lan_statistics` decoder does not perform medium checks.

整体时限默认 10000 ms、范围 1..60000，最多三次命令读取。错误、坏响应、非 LAN 类型和超时
均中止本地会话，不返回统计结果。未开放清零、ARP 暂停或 LAN 配置写入；离线响应解码器不查询
通道类型。

## Reference differences and decisions / 参考差异与裁决

- The reference `channel authcap` retries without the extended-data bit after
  any failed first query, including permission-denied completion. Six exercised
  cases retain `DIVERGENT_QUERY_FALLBACK`, whether the second query succeeds or
  fails. Both clients still authenticate with suite 17/User. This is a query
  sequencing difference, not an observed authentication downgrade.
- The reference ignores a successful response's extra byte in two cases;
  the library rejects it. These remain `DIVERGENT_EXTRA_RESPONSE_BYTES`.
- Four short-response cases are `OBSERVED_REFERENCE_SHORT_RESPONSE`: the
  reference prints values without checking the required length. Values read
  beyond supplied response bytes are retained in evidence but not assumed
  deterministic across builds. The library rejects these incomplete layouts.
- Named `authcap` and `lan stats get` ignore `-c` in the exercised cases and
  keep the same text layout. This is a measured output projection, not a claim
  that the library has a compatible CLI.

- 参考 `channel authcap` 在首次失败后去掉扩展数据位重查，包括权限拒绝完成码。无论第二次
  成功或失败，六项用例均保留查询回退差异。双方仍以 suite 17/User 认证，这是查询顺序差异，
  不是观察到认证降级。
- 参考在两个成功响应中忽略额外一字节，库拒绝，保留额外响应字节差异。
- 四个短响应用例标为参考观察：参考未检查所需长度便打印数值。超出实际返回字节的取值保留在
  证据中，不假定跨构建稳定；库拒绝这些不完整布局。
- 实测命名 `authcap` 和 `lan stats get` 忽略 `-c`，仍输出相同文本；输出映射不等于已有兼容 CLI。

The [decision register](PARITY_DECISIONS.md) recommends keeping the current
single-query default, and considering a separate explicit compatibility option
with at most one query fallback in the same authenticated session, preserving
the first completion code. Whether a future compatible CLI enables that option
remains pending. This batch does not add it or change authentication defaults.
Strict lengths and all earlier identity/partial-output/safety decisions remain open.

[裁决汇总](PARITY_DECISIONS.md)建议保留当前单次查询默认值，后续考虑显式兼容选项：在同一
认证会话内最多回退查询一次，并保留首次完成码。未来兼容 CLI 是否启用该选项仍待裁决；本批
未添加它或改变认证默认值。严格长度及既有身份、部分输出、安全事项继续保留。

## Validation / 验证

Build the [fixed unpatched reference](IPMITOOL_REFERENCE.md), then run:

构建[固定无补丁参考](IPMITOOL_REFERENCE.md)后执行：

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
python3 tools/network_status_check.py \
  --reference-profile _build/ipmitool-reference/profile.json \
  --moon-client _build/native/debug/build/examples/diagnostics/diagnostics.exe \
  --output _build/network-status-comparison.json
```

Local native tests total **64 passing groups**. **291 actual-client executions /
158 leaves** record **105 output projections, 6 raw projections, 18 rejection
projections, 17 moon-only boundaries, 8 differences and 4 short-response
observations**. Coverage includes all 64 authentication masks, selected status/
support-bit combinations, all accepted privilege values, channel endpoints,
explicit non-extended reads, fallback completion outcomes, distinct/zero/maximum
counters, both LAN media, changing medium, both preflight rejection positions,
malformed data and whole-operation timeouts. This is not an exhaustive matrix.
Both CI platforms run the checker and archive build identities, exact argv,
output bytes, exits, request/response traces and elapsed times. The fixture rejects
any counter-clear selector and verifies the authenticated role is unchanged.

本地共 **64 组原生测试通过**。**291 次实际客户端执行、158 个叶项**记录 **105 项输出映射、
6 项 raw、18 项拒绝映射、17 项本库边界、8 项差异和 4 项短响应观察**。覆盖全部 64 种认证掩码、
选定状态/支持位组合、全部合法查询权限、通道端点、显式非扩展查询、回退完成码结果、不同/零/最大
计数、两种 LAN 类型、类型变化、两个预检查拒绝位置、坏数据和整体超时，尚非穷尽矩阵。
两个 CI 平台均执行并归档构建身份、完整调用、输出字节、退出码、请求/响应和耗时。模拟器拒绝
任何统计清零选择器，并验证认证权限未改变。

C04/C20 remain partial/divergent. LAN configuration, alerts, automatic discovery,
clearing/writes, compatible CLI, other authentication/transports and real-device
privilege/counter semantics are missing or unverified. No full-family parity is claimed.

C04/C20 仍部分实现/存在差异。LAN 配置、告警、自动发现、清零/写入、兼容 CLI、其他认证/传输
及真实设备权限/计数语义仍缺失或未验证，不宣称完整功能族一致。

Pinned sources: [capability query](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_channel.c),
[capability fields](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/include/ipmitool/ipmi_channel.h),
[LAN dispatcher and statistics](https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_lanp.c).
