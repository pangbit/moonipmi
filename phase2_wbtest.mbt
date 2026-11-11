///|
test "chassis capability optional bridge and restart cause are typed" {
  let c = Response::{ completion_code: 0, data: b"\x0f\x20\x22\x24\x26\x28", }.chassis_capabilities()
  assert_eq(c.flags, 15)
  assert_eq(c.fru_address, 32)
  assert_eq(c.bridge_address, Some(40))
  assert_eq(
    Response::{ completion_code: 0, data: b"\x00\x20\x22\x24\x26", }.chassis_capabilities().bridge_address,
    None,
  )
  let cause = Response::{ completion_code: 0, data: b"\x04\x01", }.restart_cause()
  assert_eq(cause.cause, 4)
  assert_eq(cause.channel, 1)
  assert_eq(cause.description(), Some("watchdog expired"))
  assert_eq(RestartCause::{ cause: 15, channel: 0, }.description(), None)
  for size in [0, 4, 7] {
    rejected(() => {
      ignore(
        Response::{ completion_code: 0, data: Bytes::make(size, 0), }.chassis_capabilities(),
      )
    })
  }
  for size in [0, 1, 3] {
    rejected(() => {
      ignore(
        Response::{ completion_code: 0, data: Bytes::make(size, 0), }.restart_cause(),
      )
    })
  }
  rejected(() => {
    ignore(
      Response::{ completion_code: 0xc1, data: b"\x00\x00", }.restart_cause(),
    )
  })
}

///|
test "FRU size is bytes regardless of access unit and response lengths are strict" {
  let b = Response::{ completion_code: 0, data: b"\x00\x01\x00", }.fru_info()
  let w = Response::{ completion_code: 0, data: b"\x00\x01\x01", }.fru_info()
  assert_eq(b.size_bytes, 256)
  assert_eq(w.size_bytes, 256)
  assert_eq(w.word_access, true)
  for data in [b"", b"\x00\x01", b"\x00\x01\x02", b"\x00\x01\x01\x00"] {
    rejected(() => ignore(Response::{ completion_code: 0, data, }.fru_info()))
  }
}

///|
test "SEL standard events preserve raw fields and timestamp sentinels" {
  let raw = b"\x01\x00\x02\x00\xf1\x53\x65\x20\x00\x04\x01\x30\x81\x09\x00\x00"
  let record = decode_sel_record(raw)
  assert_eq(record.raw, raw)
  guard record.event() is Some(event) else { fail("missing event") }
  assert_eq(event.timestamp, 0x6553f100U)
  assert_eq(event.generator_id, 0x20)
  assert_eq(event.sensor_number, 0x30)
  assert_eq(event.deassertion, true)
  assert_eq(event.threshold_description(), Some("Upper Critical going high"))
  assert_eq(SelEvent::{ ..event, revision: 3, }.threshold_description(), None)
  assert_eq(
    SelEvent::{ ..event, event_type: 0x6f, }.threshold_description(),
    None,
  )
  assert_eq(sel_time(0xffffffffU), Unspecified)
  assert_eq(sel_time(0U), Relative(0U))
  assert_eq(sel_time(0x1fffffffU), Relative(0x1fffffffU))
  assert_eq(sel_time(0x20000000U), UnixSeconds(0x20000000U))
  for kind in [0x03, 0xc0, 0xdf, 0xe0, 0xff] {
    let data = raw.to_array()
    data[2] = byte(kind)
    let unknown = decode_sel_record(Bytes::from_array(data))
    assert_eq(unknown.event(), None)
    assert_eq(unknown.record_type, kind)
    assert_eq(unknown.raw.length(), 16)
  }
  for size in [0, 15, 17] {
    rejected(() => ignore(decode_sel_record(Bytes::make(size, 0))))
  }
}

///|
test "SEL info validates version length and completion code" {
  let info = Response::{
    completion_code: 0,
    data: b"\x51\x03\x00\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x82",
  }.sel_info()
  assert_eq(info.entries, 3)
  assert_eq(info.last_addition, 0xffffffffU)
  assert_eq(info.operations, 0x82)
  let v2 = Response::{
    completion_code: 0,
    data: b"\x02\x03\x00\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x82",
  }.sel_info()
  assert_eq(v2.version, 2)
  assert_eq(v2.entries, info.entries)
  rejected(() => {
    ignore(
      Response::{
        completion_code: 0,
        data: b"\x50\x03\x00\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x82",
      }.sel_info(),
    )
  })
  for size in [0, 13, 15] {
    rejected(() => {
      ignore(
        Response::{ completion_code: 0, data: Bytes::make(size, 0), }.sel_info(),
      )
    })
  }
  rejected(() => {
    ignore(Response::{ completion_code: 0xc1, data: b"", }.sel_info())
  })
}
