///|
test "channel info preserves reserved and auxiliary bytes" {
  let raw = b"\xf1\x84\xe5\xbf\x56\x34\x12\xaa\x55"
  let info = Response::{ completion_code: 0, data: raw, }.channel_info()
  assert_eq(info.channel, 1)
  assert_eq(info.medium, 4)
  assert_eq(info.protocol, 5)
  assert_eq(info.session_support, 2)
  assert_eq(info.active_sessions, 63)
  assert_eq(info.vendor_id, 0x123456)
  assert_eq(info.auxiliary, b"\xaa\x55")
  assert_eq(info.raw, raw)
}

///|
test "channel access enable flags invert disabled wire bits" {
  for flags in 0..<256 {
    let value = Response::{
      completion_code: 0,
      data: Bytes::from_array([byte(flags), 0xf4]),
    }.channel_access()
    assert_eq(value.access_mode, flags & 7)
    assert_eq(value.alerting_enabled, (flags & 32) == 0)
    assert_eq(value.per_message_auth_enabled, (flags & 16) == 0)
    assert_eq(value.user_level_auth_enabled, (flags & 8) == 0)
    assert_eq(value.privilege_limit, 4)
    assert_eq(value.raw[0].to_int(), flags)
  }
}

///|
test "channel decoders enforce reference wire lengths and completion codes" {
  for
    (size, decode) in [
      (9, (r : Response) => ignore(r.channel_info())),
      (2, (r : Response) => ignore(r.channel_access())),
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
  for length in [0, 18] {
    rejected(() => {
      ignore(
        Response::{ completion_code: 0, data: Bytes::make(length, 0), }.channel_cipher_page(),
      )
    })
  }
  rejected(() => {
    ignore(
      Response::{ completion_code: 0xc1, data: b"\x01", }.channel_cipher_page(),
    )
  })
  let page = Response::{ completion_code: 0, data: b"\xf1", }.channel_cipher_page()
  assert_eq(page.channel, 1)
  assert_eq(page.raw_channel, 0xf1)
  assert_eq(page.data, b"")
}

///|
test "cipher records preserve OEM identity algorithm flags and ordering" {
  let records = decode_channel_cipher_suites(
    b"\xc0\x11\x03\x44\x81\xc1\x80\x56\x34\x12\xff\xfe\xfd\xc1\x80\x00\x00\x00\x00\x40\x80",
  )
  assert_eq(records.length(), 3)
  assert_eq(records[0].suite_id, 17)
  assert_eq(records[0].iana, None)
  assert_eq(records[0].authentication, 3)
  assert_eq(records[0].integrity, 4)
  assert_eq(records[0].confidentiality, 1)
  assert_eq(records[1].iana, Some(0x123456))
  assert_eq(records[1].authentication, 63)
  assert_eq(records[1].integrity, 62)
  assert_eq(records[1].confidentiality, 61)
  assert_eq(records[2].iana, Some(0))
  assert_eq(decode_channel_cipher_suites(b"").length(), 0)
}

///|
test "cipher parsing rejects malformed suffix without returning a prefix" {
  for
    raw in [
      b"\xc0", b"\xc0\x11\x03\x44", b"\xc1\x80\x00\x00\x00\x03\x44", b"\xc2", b"\xc0\x11\x03\x44\x81\xc2",
    ] {
    rejected(() => ignore(decode_channel_cipher_suites(raw)))
  }
  rejected(() => ignore(decode_channel_cipher_suites(Bytes::make(1025, 0))))
  for channel in [-1, 12, 13, 16, 256] {
    rejected(() => validate_channel(channel))
  }
  for channel in [0, 11, 14, 15] {
    validate_channel(channel)
  }
}
