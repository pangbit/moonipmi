///|
test "GUID encodings preserve all bytes and unknown versions" {
  let guid = Response::{
    completion_code: 0,
    data: b"\x00\x11\x22\x33\x44\x55\x46\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xff",
  }.device_guid()
  assert_eq(guid.decode(Rfc4122).value, "00112233-4455-4677-8899-aabbccddeeff")
  assert_eq(guid.decode(Smbios).value, "33221100-5544-7746-8899-aabbccddeeff")
  assert_eq(guid.decode(Smbios).raw_version, Some(7))
  assert_eq(guid.decode(Smbios).version, Some(0))
  assert_eq(guid.decode(Ipmi).value, "ffeeddcc-bbaa-9988-7746-554433221100")
  assert_eq(guid.decode(Dump).value, "00112233445546778899AABBCCDDEEFF")
  assert_eq(guid.decode(Dump).version, None)
  assert_eq(guid.decode(Rfc4122).unix_seconds, None)
  assert_eq(guid.detect(2026).encoding, Rfc4122)
}

///|
test "GUID time uses full signed seconds and explicit detection year" {
  let raw = b"\xa7\x47\xc0\x00\x2c\x29\x11\xea\x9a\xbc\x12\x34\x56\x78\x9a\xbc"
  let guid = DeviceGuid::{ raw, }
  assert_eq(guid.decode(Rfc4122).unix_seconds, Some(1577836800L))
  assert_eq(guid.detect(2020).encoding, Rfc4122)
  let epoch = DeviceGuid::{
    raw: b"\x13\x81\x40\x00\x1d\xd2\x11\xb2\x9a\xbc\x12\x34\x56\x78\x9a\xbc",
  }
  assert_eq(epoch.decode(Rfc4122).unix_seconds, Some(0L))
  assert_eq(epoch.detect(1970).encoding, Rfc4122)
  let gregorian = DeviceGuid::{
    raw: b"\x00\x00\x00\x00\x00\x00\x10\x00\x9a\xbc\x12\x34\x56\x78\x9a\xbc",
  }
  assert_eq(gregorian.decode(Rfc4122).unix_seconds, Some(-12219292800L))
  for year in [1969, 10000] {
    rejected(() => ignore(guid.detect(year)))
  }
  // Multiple plausible non-time versions: the final valid encoding wins.
  let ambiguous = DeviceGuid::{
    raw: b"\x00\x11\x22\x33\x44\x55\x46\x57\x88\x39\xaa\xbb\xcc\xdd\xee\xff",
  }
  assert_eq(ambiguous.detect(2026).encoding, Smbios)
  assert_eq(
    DeviceGuid::{ raw: Bytes::make(16, 0), }.detect(2026).encoding,
    Dump,
  )
}

///|
test "identity response decoders check completion and exact lengths" {
  for
    (size, decode) in [
      (16, (r : Response) => ignore(r.device_guid())),
      (18, (r : Response) => ignore(r.system_info_block())),
    ] {
    for length in [0, size - 1, size + 1] {
      rejected(() => {
        decode(Response::{ completion_code: 0, data: Bytes::make(length, 0), })
      })
    }
    rejected(() => {
      decode(Response::{ completion_code: 0xd4, data: Bytes::make(size, 0), })
    })
  }
}

///|
test "system info parameter mapping and block payload are lossless" {
  for
    (parameter, selector) in [
      (FirmwareVersion, 1),
      (SystemName, 2),
      (PrimaryOsName, 3),
      (OsName, 4),
      (DellOsVersion, 0xe4),
      (DellUrl, 0xde),
    ] {
    assert_eq(parameter.selector().to_int(), selector)
  }
  let raw = b"\x11\x02\xf0\x03\x61\x00\x62\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let block = Response::{ completion_code: 0, data: raw, }.system_info_block()
  assert_eq(block.revision, 0x11)
  assert_eq(block.selector, 2)
  assert_eq(block.data, slice(raw, 2, 18))
  let info = SystemInfoString::{
    parameter: SystemName,
    revision: 0x11,
    encoding_byte: 0xf0,
    encoding: 0,
    data: b"a\x00b",
    blocks: [block],
  }
  assert_eq(info.ascii_text(), Some("a\u0000b"))
  assert_eq(SystemInfoString::{ ..info, encoding: 1, }.ascii_text(), None)
  assert_eq(SystemInfoString::{ ..info, data: b"\xff", }.ascii_text(), None)
}
