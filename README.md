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
- Authenticate each packet **before** decryption; validate session, responder,
  LUN/netfn, command/sequence, checksums, lengths, padding and receive sequences.
  Like ipmitool 1.8.19, do not require the response requester address to echo `0x81`.
- A single connected UDP peer, one request in flight, per-exchange deadlines,
  no automatic retry, explicit close and immediate local abort.
  Use plain IPv4 rather than IPv4-mapped IPv6; mapped forms are rejected.
- Typed Device ID, Chassis Status and raw Sensor Reading commands.
- Stored self-test results, global enables, watchdog status and the power-on counter,
  with exact countdown/counter units. See [management reads](docs/MANAGEMENT.md).
- Device GUID with explicit/automatic encoding and bounded reads of six System Info strings.
  Raw data and known reference differences are retained; see [identity reads](docs/IDENTITY.md).
- Channel information, volatile/nonvolatile channel policy and bounded IPMI/SOL cipher-list
  reads, without enabling algorithms or payloads. See [channel reads](docs/CHANNEL.md).
- Chassis capabilities/restart cause, bounded basic FRU inventory and SEL records,
  SEL info accepts reference version bytes `0x51` and `0x02`; known restart descriptions match ipmitool 1.8.19.
  Reads have total size/count and whole-operation deadlines. See [diagnostics](docs/DIAGNOSTICS.md).
- Bounded SDR repository traversal, Full/Compact Sensor records, common linear
  engineering values, threshold/discrete states and units. See [SDR support](docs/SDR.md).

No hardware-control writes, generic network command API, general OEM command families/SOL, FRU writes or SEL mutation,
Device SDRs, bridging, IPMI 1.5, cipher negotiation, Kg override or automatic
reconnection. Session housekeeping and SDR reservations do not change hardware
configuration. Nonlinear/OEM conversion and shared Compact expansion are explicitly
unsupported. Username/password lengths are 1..16/1..20 bytes.

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
read. For discovery and engineering values, use `client.sdr_records()`,
`record.sensor()`, `client.read_sensor(sensor)`, then `sensor.value(reading)`,
`state(reading)` and `unit()`. Value/status enums distinguish missing and unsupported
results from numeric zero. Check `sensor.read_support()` before attempting a read.
The [SDR example and limits](docs/SDR.md) include real ipmitool `sdr`/`sensor`
commands against the same synthetic repository.

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
§20.1 Get Device ID, §28.2 Get Chassis Status, §33 SDR Repository,
§35.14 Get Sensor Reading and §43 Sensor Data Records.
The primary functional baseline is [ipmitool 1.8.19](https://codeberg.org/IPMITool/ipmitool),
within the implemented read-only, SDR and diagnostics subset, not all ipmitool commands.
The auxiliary comparison implementation is [bougou/go-ipmi](https://github.com/bougou/go-ipmi),
Apache-2.0, reviewed at
[`d4fb9c6`](https://github.com/bougou/go-ipmi/tree/d4fb9c6923cb22f7e3c982590e57f1f2c3b58ce6).
It is a reference, not a runtime dependency or endorsement. The pinned reference
BMC hardcodes response requester address `0x20` rather than echoing `0x81`.
moonipmi now tolerates that field like ipmitool, without a compatibility flag.
Both clients read Device ID and Chassis Status; both receive completion `0xc1`
for Get Sensor Reading from that reference. **Full three-read interoperability
with that go-ipmi BMC remains unverified.** Separately, all three clients pass
the common Python fixture's three-read matrix with status boundaries and two
error classes. The address-only change does not copy ipmitool's tolerance of
other malformed fields. See [policy, risks and comparison](docs/COMPARISON.md),
[evidence and limitations](docs/STATUS.md) and [NOTICE](NOTICE).
These are validation tools, not runtime dependencies. The change is unreleased;
Mooncakes 0.1.0 retains its old requester-address check.

Apache-2.0. Personally maintained; APIs may change before the first stable release.
