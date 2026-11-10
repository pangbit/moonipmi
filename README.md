# moonipmi

[简体中文](README.zh-CN.md)

An experimental IPMI 2.0 / RMCP+ library for MoonBit native applications.

**Current status: protocol foundation, not a usable authenticated LAN client.**
There is no networking, cryptographic verification, or authenticated session yet.
Parsing an Open Session or RAKP packet does **not** authenticate a BMC. Do not use
this milestone to send credentials or operate production management networks.
It is not a complete IPMI implementation or a port of every go-ipmi command.

## Implemented

- IPMI LAN request framing, both checksums, and strict response correlation.
- Read-only command codecs: Get Device ID, Get Chassis Status, Get Sensor Reading.
- RMCP+ handshake envelopes with bounded lengths and strict header validation.
- Open Session request/response and RAKP 1–4 layouts for cipher suite 17.
- Rejection of a changed cipher suite, malformed packets, and mismatched identities.
- Offline examples and deterministic tests using synthetic data only.

The proposed first client will use User privilege and cipher suite 17:
RAKP-HMAC-SHA256 / HMAC-SHA256-128 / AES-CBC-128. A native cryptography backend,
UDP transport, authenticated session state, replay checks, deadlines, and a
loopback interoperability test are still required. No downgrade fallback,
power-control command, user administration, OEM command, SOL, SEL, FRU or SDR
repository traversal is in this initial scope. Sensor values remain raw bytes;
physical-unit conversion needs sensor-specific SDR metadata.

## Try the offline example

Use a current MoonBit native toolchain. This milestone was checked with
`moon 0.1.20261104` and does not require external runtime libraries.

```sh
moon check --target native --deny-warn
moon test --target native --deny-warn
moon run examples/offline --target native
```

```moonbit
let request = @ipmi.ReadCommand::GetDeviceId.encode(0)
// request is a Bytes value. No network packet is sent.
```

Import `pangbit/moonipmi` with the alias `ipmi` in your package manifest. The
module has not yet been published; the example above runs from this checkout.
`encode_request` is a low-level packet encoder, not an authorized command sender.

## Design and validation

Keep protocol validation independent of I/O and cryptography. Reject malformed
lengths before indexing, correlate every response, and expose completion codes
without interpreting failed replies as successful results. A small typed
read-only surface is preferable to an unreviewed generic BMC control API.

See [scope and evidence](docs/STATUS.md), [security](SECURITY.md), and
[contributing](CONTRIBUTING.md). Public API descriptions are generated with
`moon info`; run `moon doc` for API documentation.

## References and license

The protocol source is the **IPMI v2.0 specification**, particularly RMCP+ session
establishment (§13) and the command definitions for Get Device ID, Get Chassis
Status, and Get Sensor Reading. The comparison implementation is
[bougou/go-ipmi](https://github.com/bougou/go-ipmi), Apache-2.0, reviewed at
[`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6).
It is a reference, not a runtime dependency or an endorsement. See [NOTICE](NOTICE).

Apache-2.0. Personally maintained; APIs may change before the first stable release.
