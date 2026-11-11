# moonipmi

[简体中文](README.zh-CN.md)

An experimental IPMI 2.0 / RMCP+ read-only client for MoonBit native applications.
Protocol and session logic are written in MoonBit; a small C adapter calls
OpenSSL 3 for HMAC-SHA256, raw AES-CBC, constant-time comparison and secure randomness.

**Status: an early, tested subset, not a complete IPMI implementation.**
Linux/macOS CI and an independent synthetic loopback BMC exchange pass.
No real hardware BMC has been tested, and this is not a security-audited client.
Use only on explicitly authorised systems and isolated management networks.

## Scope

- Cipher suite **17 only**: RAKP-HMAC-SHA256 / HMAC-SHA256-128 / AES-CBC-128.
- User privilege; verified RAKP2 and RAKP4; no anonymous access or downgrade.
- Authenticate each packet **before** decryption; strict session/request correlation,
  checksums, lengths, padding and monotonically increasing receive sequences.
- A single connected UDP peer, one request in flight, per-exchange deadlines,
  no automatic retry, explicit close and immediate local abort.
  Use plain IPv4 rather than IPv4-mapped IPv6; mapped forms are rejected.
- Three typed read-only commands: Get Device ID, Get Chassis Status, Get Sensor Reading.

No hardware-control writes, generic network command API, OEM/SOL, SEL/FRU/SDR
repository traversal, IPMI 1.5, cipher negotiation, Kg override or automatic
reconnection. Set Session Privilege and Close Session are session housekeeping,
not hardware configuration. Raw sensor values need SDR metadata before they can
be converted into physical units. Username/password lengths are 1..16/1..20 bytes.

## Build and test

Requires a recent MoonBit native toolchain, a C compiler, **OpenSSL 3 development
files**, `pkg-config` and Python 3. Tested locally with `moon 0.1.20261104`
(`moonc v0.10.20+65efd5b93`) and OpenSSL 3.6.3.

```sh
# macOS
brew install openssl@3 pkg-config
# Debian/Ubuntu (if not already installed)
sudo apt-get install libssl-dev pkg-config python3 build-essential

moon update
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
moon run examples/offline --target native
python3 tools/interop.py _build/native/debug/build/examples/loopback/loopback.exe
```

The last command starts a **loopback-only synthetic BMC**, runs the example
client, verifies the handshake and all three reads, and closes the session. It
never contacts a real BMC. `tools/vectors.py` independently regenerates the
synthetic RAKP/KDF/packet vectors using Python HMAC and the OpenSSL CLI.

### Native dependency configuration

`build.py` uses MoonBit's documented **experimental native prebuild configuration**
to discover OpenSSL through `pkg-config` and propagate `libcrypto` link settings.
It only reads installed metadata: no downloads, installation or environment logs.
On Homebrew macOS it can locate `openssl@3` automatically. Downstream users need
the same installed dependencies; they do **not** need machine paths or a custom
compiler wrapper in their manifest. This toolchain API may change; the CI pins
our tested toolchain. Both default build and an independent downstream module
have been checked. The native target is required; this is not a zero-C library.

## Use

Import `pangbit/moonipmi` with alias `ipmi`. Inside an async function, with an
explicitly authorised peer address and credentials supplied by your application:

```moonbit
let client = @ipmi.Client::connect(addr, username, password, timeout_ms=2000)
defer client.abort()
let device = client.read(GetDeviceId).device_id()
client.close()
```

In the current checkout, `DeviceId` also exposes `provides_device_sdrs` and the
`additional_device_support` bitmask (bits 7..0: chassis, bridge, IPMB event generator,
event receiver, FRU, SEL, SDR repository, sensor). Chassis helpers name the common
intrusion/lockout/drive/cooling flags; raw historical events and optional panel
metadata remain available. For a sensor, use `reading.usable_raw_reading()` instead
of assuming its raw byte is meaningful: unavailable or disabled-scanning results
return `None`, not zero. Disabling event messages alone does not invalidate the
read. SDR metadata is still required to interpret a sensor type, states or units.

A completion-code failure is returned as `Response.completion_code`; typed
successful-result decoders reject it. Network, framing, authentication or replay
failures close the client, preventing uncertain retransmissions. `abort()` is
idempotent and sends nothing; after it, the BMC session may remain until timeout.
The registry still contains the original **0.1.0** release; later checkout changes
are listed as [Unreleased](CHANGELOG.md) and are not published automatically.
In 0.1.0, use plain IPv4: mapped IPv6 forms can bypass non-peer destination checks.
Install the original experimental release with `moon add pangbit/moonipmi@0.1.0`.
See the runnable checkout examples for a credential-free local demonstration.

## Design, evidence and references

See the [three use scenarios](docs/SCENARIOS.md), [reproducible demo](docs/DEMO.md),
[client comparison](docs/COMPARISON.md),
[scope/evidence](docs/STATUS.md),
[security](SECURITY.md), and
[contributing](CONTRIBUTING.md). Run `moon info` / `moon doc` for API documentation.

The protocol source is the **IPMI v2.0 specification**, especially §13 RMCP+,
§20.1 Get Device ID, §28.2 Get Chassis Status, and §35.14 Get Sensor Reading.
The primary functional baseline is [ipmitool 1.8.19](https://codeberg.org/IPMITool/ipmitool),
within the three-read scope, not all ipmitool commands.
The auxiliary comparison implementation is [bougou/go-ipmi](https://github.com/bougou/go-ipmi),
Apache-2.0, reviewed at
[`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6).
It is a reference, not a runtime dependency or endorsement. The pinned reference
BMC was executed: authentication succeeds, but it hardcodes the first response's
requester address to `0x20` instead of echoing our `0x81`. The client rejects that
mismatch without weakening validation. [ipmitool](https://github.com/ipmitool/ipmitool)
independently cross-checks our Python fixture; neither is a runtime dependency.
**Full interoperability with that go-ipmi BMC has not passed.** Separately, the
moonipmi/go-ipmi/ipmitool clients pass the same synthetic three-read matrix with status boundaries and two error classes. See [evidence and limitations](docs/STATUS.md) and [NOTICE](NOTICE).

Apache-2.0. Personally maintained; APIs may change before the first stable release.
