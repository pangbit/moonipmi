# Security / 安全

Only cipher suite 17 and User privilege are supported. RAKP2/RAKP4 are verified;
packet HMAC is checked before AES-CBC decryption or padding validation. Nonces
and IVs come from OpenSSL RAND_bytes. Authentication tags are compared using
CRYPTO_memcmp. Session IDs, request identities and increasing sequence numbers
are checked. Any malformed/authentication/I/O failure closes the client. There
is no anonymous mode, automatic downgrade or retry.

The high-level client exposes three read-only operations and session housekeeping.
The low-level `encode_request` function only returns bytes and sends nothing.
Use only explicitly authorised systems and isolated management networks. Even
read-only requests may leave audit records and consume BMC resources. UDP peer
filtering is not a replacement for authentication. No real BMC or credential
has been used for the tests in this repository.

This is experimental, not security-audited. IPMI/RAKP permits offline password
attacks by an active peer; use strong unique credentials and a trusted management
network. The MoonBit garbage-collected representation does not guarantee prompt
zeroization of every credential/key copy. Do not log credentials, session keys,
RAKP authentication material, captures, private addresses, serial numbers, GUIDs
or unredacted logs. Client/key types deliberately have no derived Show/Debug.

`build.py` is a read-only dependency-discovery script executed by the MoonBit
native build configuration. Review it like any build-time code. It uses installed
pkg-config metadata, does not download or install code, and does not print the
environment. Dependencies and build tools still form part of the trusted chain.

Report vulnerabilities through GitHub private vulnerability reporting if enabled;
otherwise open an issue requesting a private contact, without including exploit
details or private information.

仅支持套件 17 与 User 权限；校验 RAKP2/RAKP4，先验证 HMAC 再解密或检查 AES padding。
随机数和 IV 来自 OpenSSL RAND_bytes，标签使用 CRYPTO_memcmp 比较。校验会话 ID、请求身份和递增序号；
畸形、认证或 I/O 错误会关闭会话，不提供匿名、自动降级或重试。

高层客户端仅提供三项只读操作与会话管理；底层 encode_request 只生成字节，不发送。
仅访问明确授权的系统和隔离管理网络。只读请求仍可能产生日志、占用资源；UDP 对端过滤不能替代认证。
本仓库测试未使用真实 BMC 或真实凭据。

本项目是实验性实现，未经过安全审计。主动对端可以利用 IPMI/RAKP 进行离线密码攻击，
请使用强且独立的凭据和可信管理网络。MoonBit 垃圾回收表示无法保证每份凭据/密钥副本及时清零。
禁止记录凭据、会话密钥、RAKP 认证材料、抓包、私有地址、序列号、GUID 或未脱敏日志。
客户端/密钥类型不派生 Show/Debug。

build.py 是构建时执行的只读依赖发现脚本，应像其他构建代码一样审查；它只读取已安装 pkg-config 元数据，
不下载、不安装、不输出环境变量。依赖和构建工具仍属于信任范围。
漏洞优先私密报告；若仓库未启用该功能，只公开请求私密联系方式，不公开漏洞细节或隐私。
