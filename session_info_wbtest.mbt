///|
test "session selectors encode exact wire bytes without truncating handles" {
  assert_eq(SessionSelector::Current.request(), b"\x00")
  assert_eq(SessionSelector::Id(0x12345678U).request(), b"\xff\x78\x56\x34\x12")
  assert_eq(SessionSelector::Id(0xffffffffU).request(), b"\xff\xff\xff\xff\xff")
  assert_eq(SessionSelector::Id(0U).request(), b"\xff\x00\x00\x00\x00")
  assert_eq(SessionSelector::Handle(255).request(), b"\xfe\xff")
  assert_eq(SessionSelector::Handle(0).request(), b"\xfe\x00")
  assert_eq(SessionSelector::Slot(63).request(), b"\x3f")
  for n in [-1, 256, 65535] {
    rejected(() => ignore(SessionSelector::Handle(n).request()))
  }
  for n in [-1, 0, 64, 254, 255] {
    rejected(() => ignore(SessionSelector::Slot(n).request()))
  }
}

///|
test "session layouts retain reserved bits and decode serial port at its own offset" {
  let raw = b"\xff\xc3\xc2\xff\xfe\xab\xc0\x00\x02\x01\x02\xaa\xbb\xcc\xdd\xee\x6f\x02"
  let info = Response::{ completion_code: 0, data: raw, }.session_info()
  assert_eq(info.handle, 255)
  assert_eq(info.slot_count, 3)
  assert_eq(info.active_count, 2)
  assert_eq(info.raw, raw)
  assert_eq(
    info.details,
    Some(SessionDetails::{
      user_id: 63,
      privilege_level: 14,
      channel: 11,
      auxiliary: 10,
      connection: Lan(
        console_ip=b"\xc0\x00\x02\x01",
        console_mac=b"\x02\xaa\xbb\xcc\xdd\xee",
        console_port=623,
      ),
    }),
  )
  for size in [12, 14] {
    let serial = decode_session_info(
      slice(
        b"\x01\x03\x02\x01\x02\x11\xfe\xf7\xc0\x00\x02\x02\x34\x12", 0, size,
      ),
    )
    assert_eq(
      serial.details,
      Some(SessionDetails::{
        user_id: 1,
        privilege_level: 2,
        channel: 1,
        auxiliary: 1,
        connection: Serial(
          activity=254,
          destination=7,
          console_ip=b"\xc0\x00\x02\x02",
          console_port=if size == 14 { Some(0x1234) } else { None },
        ),
      }),
    )
  }
  assert_eq(decode_session_info(b"\x00\x00\x00").details, None)
  assert_eq(
    decode_session_info(b"\x01\x01\x01\x00\x00\x00").details,
    Some(SessionDetails::{
      user_id: 0,
      privilege_level: 0,
      channel: 0,
      auxiliary: 0,
      connection: HeaderOnly,
    }),
  )
}

///|
test "session decoders enforce complete known layouts and completion errors" {
  for size in 0..<21 {
    if size == 3 || size == 6 || size == 12 || size == 14 || size == 18 {
      ignore(decode_session_info(Bytes::make(size, 0)))
    } else {
      rejected(() => ignore(decode_session_info(Bytes::make(size, 0))))
    }
  }
  for code in [0xc1, 0xcb, 0xcc, 0xd4, 255] {
    rejected(() => {
      ignore(
        Response::{ completion_code: code, data: b"\x00\x01\x00", }.session_info(),
      )
    })
  }
}
