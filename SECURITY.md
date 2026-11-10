# Security / 安全

This milestone is an offline protocol codec, not an authenticated client. Never
interpret successful parsing as successful authentication. The suite 17 fields
are encoded and checked, but cryptographic verification is not implemented yet.
A future session must verify RAKP2 and RAKP4, authenticate packets before AES
padding is inspected, reject replay/identity mismatch, and use OS-backed random
bytes for nonces and IVs. Do not add cipher-suite 0 or silent downgrade fallback.

IPMI management interfaces can expose powerful hardware controls. Test only on
authorised systems and isolated management networks. Even read-only requests
can leave audit records and consume BMC resources. No real BMC tests or real
credentials are included in this repository. Synthetic fixtures are not proof
of hardware interoperability or a security audit.

Do not post passwords, keys, session material, captures, private addresses,
serial numbers, GUIDs or unredacted logs. Use GitHub private vulnerability
reporting if enabled; otherwise open an issue requesting a private contact
without including the vulnerability details or private information.

当前仅为离线协议编解码器，不具备认证客户端能力。解析成功不等于认证成功；
套件 17 字段已编码和检查，但尚未完成密码学校验。后续会话必须校验 RAKP2/RAKP4，
先验证报文完整性再检查 AES padding，拒绝重放与身份不匹配，并使用系统安全随机源。
禁止增加套件 0 或静默降级。

仅在明确授权的系统和隔离管理网络测试。只读请求也可能产生日志、占用 BMC 资源。
仓库不包含真实 BMC 测试或真实凭据；合成测试不代表硬件互操作验证或安全审计。
不要提交密码、密钥、会话材料、抓包、私有地址、序列号、GUID 和未脱敏日志。
优先通过已启用的 GitHub 私密漏洞报告联系；否则只公开请求私密联系方式，不公开漏洞细节或隐私。
