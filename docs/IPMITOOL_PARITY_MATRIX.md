# ipmitool parity acceptance matrix / 逐项验收矩阵

[English](IPMITOOL_PARITY_MATRIX.en.md)

状态：**P1 及选定只读实现进行中；没有任何行已通过完整一致验收。** 参考提交、阶段、冲突 K01–K10 与最终门槛见[计划](IPMITOOL_PARITY_PLAN.md)。
[机器可读入口清单](ipmitool-parity-inventory.json)固定 38 个注册命令与 12 个接口；C39 是通用 `help`，D 行是独立 `ipmievd`。
每个注册入口各占一行，避免把别名、OEM 或条件编译功能从范围中移除。

## 阅读与执行规则 / Rules

- `N` = NOT_IMPLEMENTED；`P` = PARTIAL；`U` = UNVERIFIED；`D` = DIVERGENT。这些是当前差距标签，均不是 PASS。
- 所有行都还需要 P1 的叶用例展开和固定构建证据。依赖缺失再加 `BLOCKED_ENV`，冲突未决定加 `BLOCKED_DECISION`；不把阻塞改成“不适用”。
- `R` = 读取设备；`W` = 改变设备/配置/事件；`F` = 本地文件；`T` = 终端；`L` = 本地驱动/服务；`V` = 厂商或扩展硬件。
  R 也可能产生日志、预留或占用资源；W 不代表已经获准执行。远程最低权限由目标策略和参考用例确定，所有权限拒绝路径均需测试。
- 下表每行的“专项验收”都必须叠加 G0–G7 通用用例；同一单元格中的各子命令/参数组必须分别生成 ID，不能只测一个代表即将整行通过。
- 叶 ID 采用 `C12.print.word.short-count` 这样的稳定名称，并附 build/interface/privilege/fixture 维度。已有测试只能回填其实际覆盖的叶项。
- **P1 仅在合成本机对端运行参考帮助及已有只读叶项；不接触真实 BMC，也不开始 W 类开发。** 选定 P3 只读叶项已沿用现有会话实现，其余 P2–P7 工作仍未完成。

## 通用验收维度 / Common cases

| ID | 每个适用叶项必须记录和比较 |
|---|---|
| G0 | 固定 reference/实现 SHA、二进制与数据文件哈希、构建 profile、环境、原始 argv/stdin、初始状态；两个客户端分别重置 fixture |
| G1 | 默认调用、每个有效分支、别名/大小写/前缀、可选参数顺序、组合、帮助；缺失、多余、非法、最小/最大/越界输入 |
| G2 | stdout、stderr、退出码、CSV/verbose、字节序、长度、单位/精度、文本/排序、文件字节；不能只检查进程退出或少数字段 |
| G3 | 完整请求顺序、发现/认证/权限、payload、分块、完成码、重试/超时、清理；仅对随机字段使用审核过的关系校验 |
| G4 | 能力存在/不存在、空/满、未知/OEM/保留值、错误完成码、截断/坏长度、畸形字段、重复/乱序、丢包与迟到响应 |
| G5 | 用户/通道/payload 权限不足、认证失败、本地 ACL 拒绝；不泄露真实秘密；错误阶段和副作用必须匹配 |
| G6 | W 类在可重置模拟器比较每一步状态、重复请求、中途失败、掉线及未知结果；文件/终端/daemon 也比较清理和残留状态 |
| G7 | 各适用平台/接口/固件组合；每个有硬件语义的组最终需另行授权的真实环境证据。合成通过和硬件通过分开记录 |

## 命令功能族 / Commands

源码链接使用固定提交；功能族清单来自分发器、配置表和手册交叉检查。列表覆盖审查组，**不是声称所有参数边界已穷尽**。
`help` 和每个入口无参数/错误参数的默认行为统一由 G1 纳入。写入分支只能在 P4 或之后、限制解除后实施。

| ID / 入口 | 子命令及功能组 | 当前 moonipmi 差距 | 专项验收 | 资源 / 阶段 |
|---|---|---|---|---|
| C01 `raw` [源码][raw] | 任意 netfn/cmd/data，目标 LUN/地址，响应与完成码 | P：离线 `encode_request`，无通用发送 API/CLI | 全字节输入、边界长度、响应 hex、专用超时/尝试次数；读取与写入分别建例 | R/W；P2/P4；K03–K05 |
| C02 `i2c` [源码][raw] | bus/channel、public、地址、读长度和写数据的 Master Write-Read | N | 总线选择、读写组合、长度、NACK/错误、输出；不能把带写前缀的读取当成无副作用 | R/W、I2C 目标；P3/P4 |
| C03 `spd` [源码][raw] | I2C SPD 读取及内存信息解释 | N | 各被参考识别的 SPD 类型/字段、缺失/截断、输出和总线失败 | R、SPD fixture/硬件；P3/P7 |
| C04 `lan` [源码][lanp] | print/printconf；set 的 IP/netmask/MAC/gateway/ARP/VLAN/auth/access/user/password/SNMP/alert/cipher_privs/bad_pass_thresh；alert print/set；stats get/clear | N | 每个参数值/默认 channel、读回、设置顺序/提交、掉线后的状态、统计清除 | R/W、channel 策略；P3/P4 |
| C05 `chassis` [源码][chassis] | status/power/selftest/identify/poh/restart_cause/policy；bootparam get/set、bootdev、bootmbox | P/D：已有状态/能力/重启原因/自检/通电计数 API；计数显示精度有差异，其他读取、控制及 CLI 未完成 | 位字段和可选字段；每个 power 别名；启动参数/邮箱块/持久标志、identify 时长、策略、失败中断 | R/W、通用 BMC；P3/P4 |
| C06 `power` [源码][chassis] | chassis power 快捷入口；status、on/up、off/down、cycle/reset/diag/soft/acpi | P：仅能通过 chassis API 得知状态，无此入口 | 与 C05 对应调用的输出/退出/实际命令一致；不能只复用成功返回 | R/W；P2/P4 |
| C07 `event` [源码][event] | 预定义事件、sensor/event state、事件文件 | N | 所有发送模式、断言/撤销、文件语法、记录副作用、非法状态和重复发送 | W/F；P4 |
| C08 `mc` [源码][mc] | info、guid（auto/ipmi/smbios/rfc/dump）、getenables/setenables、selftest、reset cold/warm、watchdog get/set/off/reset、getsysinfo/setsysinfo | P/D：已有 Device ID/自检/全局使能/看门狗/GUID 及六项系统信息读取；显示/校验有差异，控制及 CLI 缺失 | GUID 模式和手册别名差异、系统信息分块/编码、全局 enables、watchdog 状态机、复位后会话 | R/W；P3/P4 |
| C09 `bmc` [源码][mc] | `mc` 的兼容别名 | N：库无命令别名 | C08 每个叶用例以别名重跑，比较错误文本与退出码 | R/W；P2/P4 |
| C10 `sdr` [源码][sdr] | list/elist 的 all/full/compact/event/mcloc/fru/generic；type/entity/info/get/dump；fill sensors/nosat/file/range | P：仓库遍历、部分 Full/Compact；Device SDR、共享/桥接、完整编码/记录类型、CLI/cache/dump/fill 缺失 | 所有记录类型/路由/共享展开、动态保留与重试、缓存/文件、填充/仓库修改；分别覆盖单条/多条/空/变化 | R/W/F；P3/P4 |
| C11 `sensor` [源码][sensor] | list/get/reading；thresh 单阈值与 lower/upper 组 | P：原始读数、部分线性工程值/状态；完整动态阈值读取、精度、非线性/动态因子与设置缺失 | 每个上游换算分支、单位/精度、不可用与离散值、SDR 查找、阈值 get/set 顺序/错误；支持范围按实际参考测定 | R/W；P3/P4 |
| C12 `fru` [源码][fru] | 无参数扫描、print/list/read/write；internaluse info/print/read/write；get/edit 的 OEM 多记录及 edit field；upgEkey | P：显式 ID、byte/word、基础区域/校验、有限文本；自动定位、全部编码、多记录/OEM 解释、文件和写入缺失 | byte/word/短读及上游分块重试；自动发现/桥接；全部区域/类型/语言；坏校验/部分结果；编辑后布局/校验和/导出 | R/W/F/V；P3/P4/P6；K08 |
| C13 `gendev` [源码][gendev] | list/read/write；Generic Device Locator 对应 EEPROM 等设备文件 | N | 定位/总线/页边界、文件长度、读写/验证失败、错误退出 | R/W/F、设备 fixture；P3/P4 |
| C14 `sel` [源码][sel] | info/list/elist/get、first/last/计数；time get/set；clear/delete/add；save/readraw/ereadraw/writeraw/interpret | P：有界枚举、标准元数据/部分阈值和时间分类、raw OEM；完整事件解释、筛选、文件/时钟/修改缺失 | 全事件/OEM 解释、SDR 联查、ID/时间/时区、仓库变化、溢出/清除/删除；区分 `writeraw` 导出文件与 BMC 写入 | R/W/F/V；P3/P4/P6 |
| C15 `pef` [源码][pef] | capabilities/event/info/status/timer/pet；filter/policy 的 list/enable/disable/create/delete | N | 过滤器/策略位图、目标/告警发送、timer、删除/禁用与错误；PET 实际副作用在模拟接收端记录 | R/W、PEF/PET fixture；P3/P4 |
| C16 `sol` [源码][sol] | info/set、payload enable/disable/status、activate/deactivate、looptest、keepalive 选项 | N | 配置/权限、payload 传输、ACK/重传/流控、断连、escape/break、raw tty 恢复、keepalive 和 looptest | R/W/T、PTY+SOL peer；P3/P5 |
| C17 `tsol` [源码][tsol] | Tyan IPMI 1.5 SOL；IP/port、ro/rw、rows/cols、altterm | N | 目标/端口、只读与输入、终端大小/转义、启动/停止、丢包和退出恢复 | W/T/V、Tyan fixture；P5/P7 |
| C18 `isol` [源码][isol] | Intel IPMI 1.5 SOL info/set/activate | N | 配置字段、legacy session、终端数据、逃逸字符/关闭、接口不支持时的参考结果 | R/W/T/V；P3/P5 |
| C19 `user` [源码][user] | summary/list、test、set name/password/priv、enable/disable | N | ID/channel 边界、16/20 字节密码、禁用/权限矩阵、密码测试与设置区别、部分失败后状态 | R/W、合成用户；P3/P4 |
| C20 `channel` [源码][channel] | authcap/info/getaccess/setaccess/getciphers ipmi/sol | N：内部固定会话流程不等于公开命令实现 | 每个 channel、访问位/持久性、分页密码套件、权限拒绝和非法 payload；设置后实际权限 | R/W；P3/P4 |
| C21 `session` [源码][session] | info active/all/id/handle | N：本库 session 类型是内部协议状态，不是此命令 | 活跃/缺失/多个 session、地址字段、ID/handle 选择、短响应与限制 | R；P3 |
| C22 `dcmi` [源码][dcmi] | discover/oob_discover、sensors、asset_tag/set_asset_tag、get/set_mc_id_string、get_temp_reading、get/set_conf_param、thermalpolicy get/set；power reading/get_limit/set_limit/activate/deactivate | N | 能力页/温度实体、字符串分块、功率限制动作/采样、DHCP 配置、Ping/Pong；每个表驱动参数独立建例 | R/W/V、DCMI peer；P3/P6 |
| C23 `nm` [源码][dcmi] | discover/capability/control；policy add/get/remove/limiting；statistics、power range、suspend、reset、alert、threshold | N | domain/policy ID、trigger、volatile/cores_off、统计模式、阈值和暂停数组、告警目标/删除/重置；按实际版本能力 | R/W/V、Intel NM；P3/P6 |
| C24 `sunoem` [源码][sunoem] | cli（含 force/wait）、led/sbled、sshkey set/del、ping/version/nacname/getval/setval/getfile/getbehavior | N | 属性/传感器映射、交互 CLI、LED 组、文件传输、SSH key 分块、版本能力与厂商错误 | R/W/F/T/V；P3/P6 |
| C25 `kontronoem` [源码][kontronoem] | setsn/setmfgdate/nextboot | N | 自动生成/写入 FRU 标识、制造日期和启动设备、返回状态与失败；不用生产序列号 | W/V、Kontron；P6 |
| C26 `picmg` [源码][picmg] | properties/addrinfo/busres summary/frucontrol/activate/deactivate/policy；portstate/amcportstate、LED、power、clk 的查询/设置与过滤 | N | ATCA/AMC/FRU 路由、链路端口/时钟、granted/denied/all、颜色/功率/激活锁；每种扩展能力与失败 | R/W/V、PICMG；P3/P6 |
| C27 `fwum` [源码][fwum] | info/status/download/upgrade/rollback/tracelog | N | 镜像校验/分块/序号/重试、升级状态/回滚、通信失败点和恢复；需要合法镜像与可恢复目标 | R/W/F/V、Kontron；P6 |
| C28 `firewall` [源码][firewall] | info/enable/disable/reset；channel/lun/netfn/command/subfn/force | N | 所有掩码层级、支持/可配置位、受保护命令、force 和部分设置；不能只验证输出 | R/W；P3/P4 |
| C29 `delloem` [源码][delloem] | lcd、mac、lan、setled、powermonitor、vFlash；对应 mode/line/status、LOM/failover、统计/预算/powercap 等子项 | N | 每个 Dell 代际能力、NIC/屏幕/驱动灯、功率单位/统计清除、预算、vFlash 卡；不把厂商未知记录算支持 | R/W/V、Dell；P3/P6 |
| C30 `shell` [源码][shell] | readline 条件入口；交互/history、TAB 插入、命令分发、help/?、quit/exit | N | 有/无 readline 构建、PTY 编辑/引号、keepalive、错误后会话、EOF/信号/history 与凭据处理；参考禁用命令补全，不能擅自添加后算一致 | T/R/W；P2/P5；K06 |
| C31 `exec` [源码][shell] | 文件中的命令序列 | N | 注释、空行、长度/分词、读文件失败、命令失败是否继续、最后退出码、运行变量和会话复用 | F/R/W；P2/P5 |
| C32 `set` [源码][shell] | host/hostname、user/username、pass/password、privlvl/authtype/localaddr/targetaddr/port/csv/verbose 运行变量 | N | 每个字段/别名、缺失/错误值、后续命令生效时机、重连/会话边界 | T/R/W；P2/P5 |
| C33 `echo` [源码][shell] | 脚本回显、空参数/多参数 | N | 分隔符/换行/空字符串及退出码；虽无帮助描述也不可遗漏 | F/T；P2 |
| C34 `hpm` [源码][hpm] | check；upgrade 的 component/activate/force/debug；compare 的 component/debug；activate/norollback；targetcap/compprop/abort/upgstatus/rollback/rollbackstatus/selftestresult | N | HPM.1 镜像/组件、上传与激活阶段、进度/重试/回滚、中止/断连；手册 `download`/`all` 与分发器差异也需实测 | R/W/F/V、PICMG HPM；P6 |
| C35 `ekanalyzer` [源码][ekanalyzer] | FRU 文件 frushow、print carrier/power/all、summary match/unmatch/all | N | 各文件角色、拓扑/链接配对、电源预算、截断/坏 FRU、输出顺序与错误；离线输出也要完整一致 | F/V 数据格式；P3 |
| C36 `ime` [源码][ime] | info/update/rollback | N | Intel ME 镜像和状态/升级模式、分块、失败恢复、回滚、硬件版本限制 | R/W/F/V、Intel ME；P6 |
| C37 `vita` [源码][vita] | properties/frucontrol/addrinfo/activate/deactivate/policy get/set/LED prop/cap/get/set | N | VITA 46.11 group/FRU/site、策略掩码、LED 与激活、副作用和不支持完成码 | R/W/V；P3/P6 |
| C38 `lan6` [源码][lan6] | print/save/set（nolock）/lock/commit/discard；support/enables/traffic_class/hops/flow_label/地址/DUID/DHCPv6/router 配置表 | N | 全参数表、set/block selector、IPv6 字节序、只读字段、事务锁/提交/丢弃、save 脚本及失败后状态 | R/W/F；P3/P4 |
| C39 `help` [源码][main] | 通用 help、命令目录及未知命令 | N | 条件命令、隐藏描述/别名、空命令、stdout/stderr/退出码；不能按手册示例硬编码清单 | F；P2 |

## 接口与平台 / Interfaces

所有接口均需覆盖正常往返、发送/接收尺寸、超时/取消、拒绝访问、断开和资源释放；再跑其适用命令/权限集合。
接口名一致不代表实现已移植；编译可用性和可用硬件分别登记。

| ID / `-I` | 固定源码 | 平台/依赖及专项验收 | 当前 / 阶段 |
|---|---|---|---|
| T01 `bmc` | [bmc][tbmc] | Solaris BMC 驱动；STREAMS/ABI、设备路径、权限与响应完成码 | N + 环境待提供；P2/P7 |
| T02 `dbus` | [dbus][tdbus] | OpenBMC D-Bus/libsystemd；服务名/方法、类型签名、错误映射与策略拒绝 | N + 环境待提供；P2/P7 |
| T03 `dummy` | [dummy][tdummy] | Linux DummyIPMI、本地模拟 socket 的真实协议和生命周期；不是现有 UDP fixture 的别名 | N；P1/P2 |
| T04 `free` | [free][tfree] | libfreeipmi、受支持系统驱动/设备；库版本分支、自动探测和失败映射 | N + 依赖/设备待提供；P2/P7 |
| T05 `imb` | [imb][timb] | Intel IMB 驱动/设备 ABI；请求/接收/超时及权限 | N + 环境待提供；P2/P7 |
| T06 `lan` | [lan][tlan] | IPMI 1.5/RMCP、auth capabilities、激活/认证类型、ASF、桥接、序号/重试、OEM quirks | N + K01/K04；P2/P7 |
| T07 `lanplus` | [lanplus][tlanplus] | RMCP+、套件映射 0..17 的实际支持/失败、自动选择、Kg/权限、SOL、桥接、缓存/重试/大小调整 | P/D：仅 suite 17/User/只读；P2/P5/P7；K01–K04 |
| T08 `lipmi` | [lipmi][tlipmi] | Solaris 9 LIPMI 头文件/驱动、旧 ABI 和错误路径 | N + 环境待提供；P2/P7 |
| T09 `open` | [open][topen] | Linux OpenIPMI 及源码内 FreeBSD 分支；多个设备、ioctl、异步事件、桥接差别 | N + OS/设备待提供；P2/P5/P7 |
| T10 `serial-basic` | [serial basic][tserialbasic] | POSIX tty、Basic framing/escaping、校验、波特率/系统接口模式、终端恢复 | N + 串口 peer；P2/P7 |
| T11 `serial-terminal` | [serial terminal][tserialterminal] | POSIX tty、Terminal 编码/行边界、分片、波特率/系统接口模式与恢复 | N + 串口 peer；P2/P7 |
| T12 `usb` | [usb][tusb] | AMI OEM USB 接口、系统驱动/设备、请求封装/轮询、文件权限与断连 | N + AMI 环境待提供；P2/P7 |

## 全局选项 / CLI options

选项全集以 [OPTION_STRING 与分支][main]为准；同时覆盖全选项与受限构建。
每个字段必须比较命令行、环境、文件、默认值及重复指定的优先级；“库可由调用方自行处理”不算 CLI 功能完成。

| ID | 选项集合 | 专项验收及当前差距 | 阶段 / 冲突 |
|---|---|---|---|
| O01 | `-h -V` | N：帮助、版本、程序身份、退出；全/受限构建目录 | P2；K10 |
| O02 | `-I -d -D` | N：接口/默认接口、device index、串口 tty/baud/system 参数、缺少依赖错误 | P2/P7；K09 |
| O03 | `-H -p -4 -6` | P：只有显式 Addr；补 DNS、IPv4/IPv6 选择、默认端口、无效/特殊地址行为 | P2；K07 |
| O04 | `-U -P -a -E -f` | N/P：无 CLI 凭据源；空值/长度、prompt、环境变量优先级、密码文件、argv 隐藏 | P2；K01/K06 |
| O05 | `-L -A` | P/D：固定 User，补各角色/默认 Administrator、`+` lookup、IPMI 1.5 auth 类型 | P2；K01/K02 |
| O06 | `-C -k -K -y -Y` | P/D：只有 suite 17；套件显式/自动选择、Kg 文本/hex/环境/prompt、无效输入 | P2；K01 |
| O07 | `-t -T -b -B -l -m` | N：单/双桥接、目标/中继 channel/地址/LUN、默认值及强制权限 | P2；K02/K07 |
| O08 | `-N -R -z` | P/D：超时语义不同；补重试、0/缺省、命令专有覆盖、通信大小限制/探测 | P2；K04 |
| O09 | `-v -c` | N：逐命令 verbose 层级、CSV 支持范围、错误分流/格式/精度、报文日志 | P2/P3；K06/K10 |
| O10 | `-S` | N：SDR cache 文件加载/验证、在线缺失/陈旧缓存、查找及读数影响 | P3；K08/K09 |
| O11 | `-O` | N：OEM SEL 描述文件、语法/查找/优先级和解析错误 | P3/P6；K08/K09 |
| O12 | `-o -g -s` | N：8 个 OEM profiles、list/help、废弃快捷选项、厂商路径中的协议变化 | P2/P6；K01/K09 |
| O13 | `-e` | N：SOL 逃逸字符、重复字符、无 TTY 和 shell/SSH 嵌套情形 | P5 |
| O14 | `-Z` | N：UTC/本地时间、timestamp sentinel、DST、无效时间及多命令输出 | P3；K08/K10 |

## 独立守护程序与横切行为 / Daemon and cross-cutting behavior

| ID | 范围及来源 | 当前差距与专项验收 | 资源 / 阶段 |
|---|---|---|---|
| D01 | `ipmievd open` [源码][evd] | N：OpenIPMI 异步事件、事件接收配置、消息解析/去重与丢失；验证所有设置副作用 | L/R/W、驱动事件源；P5/P7 |
| D02 | `ipmievd sel` [源码][evd] | N：轮询周期、初次基线、仓库清空/轮换/溢出、重复与失败重连、SDR 解释 | R/W、事件 fixture；P5/P7 |
| D03 | daemon/nodaemon/pidfile/timeout、信号和日志 [手册][evdman] | N：daemonize、PID 生命周期、syslog facility/stderr、权限、重复启动和异常退出 | L/F、隔离进程环境；P5 |
| X01 | 已认证报文相关性与校验 | D：[既有 24 项对照](COMPARISON.md)已显示 responder/netfn/LUN/checksum 差异；扩展到其他接口/全部边界 | P1/P2；K03 |
| X02 | RAKP/HMAC/AES、会话 ID/序号/重放/padding | P/U：已有正负测试不是完整差分；逐种算法/身份字段/随机关联/错误阶段与参考对照 | P2；K01/K03 |
| X03 | deadline/retry/backoff/取消/close/abort、并发和会话复用 | D：无重试及本地 abort 与参考关闭/等待不同；故障注入每个 exchange/多块操作、资源回收及总用时 | P2/P5；K04 |
| X04 | 完成码、失败退出、部分结果、缺失能力 | P/D：参考系统信息完成码错误仍零退出；现有 typed 错误不等于 CLI 错误；逐命令比输出/退出/继续或中止，未知/OEM 完成码也覆盖 | P2–P6 |
| X05 | 文本、数字、时间、二进制导出 | P/D：GUID 时间及系统信息文本/长度有差异，通电分钟精确 API 与参考 float 显示有差异；扩展到编码、厂商名、单位/精度、排序、空记录与 locale/DST，保留差异不跳过 | P3；K08/K10 |
| X06 | OEM 自动识别与 profiles [源码][oem] | N：supermicro/intelwv2/intelplus/icts/ibm/i82571spt/kontron/quanta；厂商/产品 ID 分支和 IBM 数据文件、PICMG/VITA 自动发现 | V；P2/P6 |
| X07 | 配套文件/脚本与安装 [目录][contrib] | N：enterprise-numbers、OEM maps、manpages、ipmievd 服务、bmclanconf、bmc-snmp-proxy、exchange-bmc-os-info、collect/log/RRD/web 示例的调用契约；安装路径/权限/外部依赖 | F/R/W、shell/SNMP/RRD 隔离环境；P3–P7 |
| X08 | 加密/驱动/运行依赖与构建变体 [配置][configure] | P/U：native/OpenSSL 3 不能代表 upstream 的 libcrypto/internal MD5、readline、FreeIPMI、libsystemd 组合；冻结支持/失败 profile | P1/P2/P7；K09 |
| X09 | CLI 信号、TTY、流水线/重定向、批处理 | N：SIGINT/EOF、broken pipe、进程退出码、提示/历史/终端恢复和会话关闭 | T/F；P2/P5；K06 |
| X10 | 文件读取安全/权限/符号链接/覆盖行为 | N：`ENABLE_FILE_SECURITY` 两种构建、缺失/不可读文件和长度/格式、缓存/脚本/镜像导入导出；上游缺陷另列阻塞 | F；P1/P3/P6；K09/K10 |
| X11 | 分块、长度协商、仓库保留与变化 | P/D：系统信息边界/元数据检查有差异，现有 FRU 固定 16-byte、有界读取和 SEL 变化拒绝；验证参考自适应大小/重试/部分读取与总量行为 | P3；K04/K08 |
| X12 | 平台/设备能力/角色组合 | U：目前仅两个平台的子集 CI；逐个 T 行与计划资源表实证，记录设备型号/固件/channel/角色；无资源不能 PASS | P7 |
| X13 | 手册/help/源码差异与不稳定行为 | U：例如套件默认选择、HPM download、GUID 拼写、未展示子命令；P1 保存实际参考输出，逐个裁决，不把猜测写成能力 | P1；K10 |

## 已执行的 P1 叶项种子

[参考构建及叶项证据](IPMITOOL_REFERENCE.md)记录 71 个参考状态（70 已观察、1 构建阻塞），以及 62 次诊断执行中的 24 项差分映射。脚本输出稳定叶 ID、stdout/stderr/退出码及 trace。这些仅为部分 G1/语义种子，上述所有功能族状态保持不变；其他子命令、参数、权限、构建和错误路径仍待展开。

## 已实现的管理状态读取

[四个实际客户端 API](MANAGEMENT.md)补齐自检结果、全局使能、看门狗状态和累计通电计数。报告在 127 次执行中记录 56 项输出映射、8 项完成码错误映射、11 项仅 moonipmi 的长度检查及 1 项显示精度差异。`C05.poh.unit-1-count-16777217` 保留准确原始/API 分钟值，参考显示少一分钟（K10 待决定）；自检映射保留 MC/机箱的不同输出与退出码。C05/C08 仍为部分实现，不宣称完整 CLI、默认值、权限或硬件一致。

## 已实现的 GUID 与系统信息读取

[另外两个客户端 API](IDENTITY.md)覆盖 GUID 模式及六项命名字符串。本地 180 次执行形成 94 个叶项：62 项输出映射、5 项拒绝映射、8 项本库边界及 19 项明确差异。报告保留 GUID uint32/SEL 时间显示、系统信息 char 符号性/编码/零字节/填充、坏块接受、完成码错误零退出及部分输出差异。C08 和 X04/X05/X11 仍为部分实现/有差异，K08/K10 待裁决；现有 POH 精度及认证默认值不变。

## 后续叶用例示例 / Reviewable test records

以下为待实施的验收设计，不是本轮运行结果；每项都要按 G0–G7 留存证据。

| 建议叶 ID | 输入/故障 | 必须比较的结果 | 当前状态 |
|---|---|---|---|
| C12.print.word.short-count | 同一 word-access FRU，设备返回有效短读 | offset/count 单位、进度、全部区域输出、后续请求/重试和关闭；现有 fixture 可扩充，不能只看字段集合 | PARTIAL |
| C14.elist.oem.relative-time | 混合标准/OEM SEL、相对/未指定时间、SDR 缺项 | 顺序、时间文本、OEM 描述、stderr/exit、额外 SDR 请求和空结果语义 | NOT_IMPLEMENTED |
| C10.fill.file.mid-failure | 可重置仓库，写入第 N 块失败 | 失败前后记录、保留/清除/提交状态、重试次数、已写部分、退出；不假定回滚 | NOT_IMPLEMENTED；当前禁止开发 |
| T07.auto-cipher.no-17 | 隔离 peer 仅报告 suite 3，另测能力查询失败 | 参考的套件选择/回退、握手与错误；本库是否改变策略须先裁决 K01 | BLOCKED_DECISION |
| X01.response.checksum | 有效 HMAC、故意错误 IPMI checksum | 接受/拒绝、是否继续等待、输出和关闭；现有差异原样登记 | DIVERGENT |
| O04.password.sources | 合成 env/file/argv/prompt 组合及空值 | 优先级、prompt/TTY、长度、错误和可观察日志；只使用公开合成秘密 | NOT_IMPLEMENTED |
| D02.poll.sel-cleared | 模拟事件仓库轮询中清空、增加、ID 重用 | 漏报/重报、syslog 内容与周期、恢复策略和清理 | NOT_IMPLEMENTED |
| C34.upgrade.interrupted | 合法合成 HPM 镜像，上传/激活不同点断连 | 已接受组件、升级状态、重试/查询、失败与回滚行为；未来硬件必须可恢复且另获授权 | NOT_IMPLEMENTED；当前禁止开发 |

每个叶项实际提交结果时还须增加 reference/implementation commit、profile、执行日期、证据路径、差异及审核人字段。
本矩阵仅提交计划，不将未来设计填成已通过；全量结论由[完成条件](IPMITOOL_PARITY_PLAN.md)约束。

[raw]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_raw.c
[lanp]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_lanp.c
[chassis]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_chassis.c
[event]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_event.c
[mc]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_mc.c
[sdr]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sdr.c
[sensor]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sensor.c
[fru]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_fru.c
[gendev]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_gendev.c
[sel]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sel.c
[pef]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_pef.c
[sol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sol.c
[tsol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_tsol.c
[isol]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_isol.c
[user]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_user.c
[channel]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_channel.c
[session]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_session.c
[dcmi]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_dcmi.c
[sunoem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_sunoem.c
[kontronoem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_kontronoem.c
[picmg]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_picmg.c
[fwum]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_fwum.c
[firewall]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_firewall.c
[delloem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_delloem.c
[shell]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmishell.c
[hpm]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_hpmfwupg.c
[ekanalyzer]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_ekanalyzer.c
[ime]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_ime.c
[vita]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_vita.c
[lan6]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_lanp6.c
[main]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_main.c
[evd]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/ipmievd.c
[evdman]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/doc/ipmievd.8.in
[oem]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/lib/ipmi_oem.c
[contrib]: https://github.com/ipmitool/ipmitool/tree/19d78782d795d0cf4ceefe655f616210c9143e62/contrib
[configure]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/configure.ac
[tbmc]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/bmc/bmc.c
[tdbus]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/dbus/dbus.c
[tdummy]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/dummy/dummy.c
[tfree]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/free/free.c
[timb]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/imb/imb.c
[tlan]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lan/lan.c
[tlanplus]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lanplus/lanplus.c
[tlipmi]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/lipmi/lipmi.c
[topen]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/open/open.c
[tserialbasic]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/serial/serial_basic.c
[tserialterminal]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/serial/serial_terminal.c
[tusb]: https://github.com/ipmitool/ipmitool/blob/19d78782d795d0cf4ceefe655f616210c9143e62/src/plugins/usb/usb.c
