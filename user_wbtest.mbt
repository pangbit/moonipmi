///|
test "user access masks counts preserves status and all raw flags" {
  for flags in 0..<256 {
    let raw = Bytes::from_array([0xff, byte(flags), 0xc5, byte(flags)])
    let access = Response::{ completion_code: 0, data: raw, }.user_access()
    assert_eq(access.max_user_ids, 63)
    assert_eq(access.enabled_user_ids, flags & 63)
    assert_eq(access.fixed_user_ids, 5)
    assert_eq(access.enable_status, flags >> 6)
    assert_eq(access.call_in_allowed, (flags & 64) == 0)
    assert_eq(access.link_authentication, (flags & 32) != 0)
    assert_eq(access.ipmi_messaging, (flags & 16) != 0)
    assert_eq(access.privilege_limit, flags & 15)
    assert_eq(access.raw, raw)
  }
}

///|
test "user names preserve sixteen bytes and stop text at the first NUL" {
  let raw = b"abc\x00suffix\xff\x00\x00\x00\x00\x00"
  let name = Response::{ completion_code: 0, data: raw, }.user_name()
  assert_eq(name.raw, raw)
  assert_eq(name.data, b"abc")
  assert_eq(name.ascii_text(), Some("abc"))
  let full = Response::{ completion_code: 0, data: b"1234567890abcdef", }.user_name()
  assert_eq(full.data, full.raw)
  assert_eq(full.ascii_text(), Some("1234567890abcdef"))
  let empty = Response::{ completion_code: 0, data: Bytes::make(16, 0), }.user_name()
  assert_eq(empty.ascii_text(), Some(""))
  let binary = Response::{
    completion_code: 0,
    data: b"\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  }.user_name()
  assert_eq(binary.data, b"\xff\x80")
  assert_eq(binary.ascii_text(), None)
}

///|
test "user decoders reject wrong lengths and completion errors" {
  for
    (size, decode) in [
      (4, (r : Response) => ignore(r.user_access())),
      (16, (r : Response) => ignore(r.user_name())),
    ] {
    for length in [0, size - 1, size + 1] {
      rejected(() => {
        decode(Response::{ completion_code: 0, data: Bytes::make(length, 0), })
      })
    }
    for completion in [0xc1, 0xcc, 0xd4] {
      rejected(() => {
        decode(Response::{
          completion_code: completion,
          data: Bytes::make(size, 0),
        })
      })
    }
  }
  for user_id in [-1, 0, 64, 256] {
    rejected(() => validate_user_id(user_id))
  }
  for user_id in [1, 63] {
    validate_user_id(user_id)
  }
}
