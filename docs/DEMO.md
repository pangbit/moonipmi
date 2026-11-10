# Reproduce the read-only demo / 复现只读演示

This demonstration uses only `127.0.0.1` and synthetic data. It does not need
BMC access, a privileged port, a password supplied by the operator, or any
hardware-control command. Install the dependencies listed in the README first.

演示仅使用 `127.0.0.1` 和合成数据，不需要真实 BMC、特权端口、操作者提供的密码，
也不执行硬件控制命令。先安装 README 中列出的依赖。

## Default demonstration / 默认演示

From the repository root / 在仓库根目录运行：

```sh
moon update
moon build examples/loopback --target native --deny-warn
python3 tools/interop.py _build/native/debug/build/examples/loopback/loopback.exe
```

The Python simulator binds a temporary loopback UDP port and launches the MoonBit
example. Expected results / Python 模拟器监听临时本地 UDP 端口并启动 MoonBit 示例，预期结果：

```text
PASS: authenticated suite 17, three read-only commands, graceful close
PASS: independent Python emulator verified RAKP, packet integrity and all five commands
```

The five commands are Set Session Privilege, Get Device ID, Get Chassis Status,
Get Sensor Reading and Close Session. Only the middle three read hardware-style
values; the first and last manage the simulated session. All processes and
sockets are closed after the demonstration, including on a failed check.

五条命令分别是设置会话权限、读取设备标识、读取机箱状态、读取传感器原始值、关闭会话。
中间三条是只读数据访问，首尾只管理模拟会话。成功或失败后都会关闭进程和 socket。

## Pinned go-ipmi reference / 固定版本 go-ipmi 对照

This optional check additionally requires Go 1.24 or later and network access
for Go module downloads. Go is **not** a library runtime dependency. It runs the
unmodified reference server with an entirely in-memory mock HAL, suite 17 only,
IPMI 1.5 disabled and the same fixed synthetic user. The adapter cannot bind a
non-loopback address or select a hardware HAL.

可选检查需要 Go 1.24 或以上版本，以及下载 Go 模块的网络。Go **不是**库的运行时依赖。
它使用未修改的 go-ipmi 参考服务端，后端全部是内存模拟 HAL，只启用套件 17、禁用 IPMI 1.5，
使用固定的合成用户。适配器不能监听非 loopback 地址，也不能选择真实硬件 HAL。

```sh
go -C tools/go-reference build -mod=readonly -o ../../_build/reference-bmc .
python3 tools/go_interop.py \
  _build/native/debug/build/examples/loopback/loopback.exe \
  _build/reference-bmc --expect-address-rejection
```

The reference is pinned in `tools/go-reference/go.mod` and `go.sum` to commit
`d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6`. This revision hardcodes a response
requester address that differs from our request. The explicit flag verifies that
the client rejects this exact mismatch after successful authentication. It does
**not** turn any error into a pass. Omitting the flag attempts the full exchange
and currently fails. Expected output:

```text
PASS: pinned go-ipmi response-address mismatch rejected after authenticated handshake
LIMIT: full go-ipmi interoperability is NOT verified; no checks were relaxed
```

参考版本由 go.mod 与 go.sum 固定到上述提交。该版本硬编码的响应请求者地址与请求不一致。
显式开关只验证认证后拒绝这一具体地址不匹配，**不会**将任意错误算作通过。
省略开关会尝试完整交互，目前失败。预期输出如上；原因详见 [STATUS](STATUS.md)。

## What this proves / 证明范围

The default demonstration covers RAKP authentication, encrypted/integrity-protected
request/response framing, three read-only results, and graceful close between
independent implementations. The go-ipmi check demonstrates the known rejection,
not full interoperability. Unit tests cover rejection and timeout cases.
Neither demonstration proves real-BMC compatibility, full IPMI coverage, a
security audit, or compliance with a competition's submission rules.

默认演示验证独立实现之间的 RAKP 认证、加密/完整性保护报文、三项只读结果与正常关闭。
go-ipmi 对照证明已知拒绝行为，不是完整互通。拒绝畸形输入和超时由单元测试覆盖。演示不代表真实 BMC 兼容、完整 IPMI、安全审计，
也不代表已满足赛事申报规则。
