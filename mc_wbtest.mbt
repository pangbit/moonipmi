///|
test "self test result status is distinct from protocol completion" {
  for
    (code, expected) in [
      (0x55, Passed),
      (0x56, NotImplemented),
      (0x57, Corrupted),
      (0x58, FatalError),
      (0xff, Reserved),
      (0x99, DeviceSpecific),
    ] {
    let result = Response::{
      completion_code: 0,
      data: Bytes::from_array([byte(code), 0xa5]),
    }.self_test()
    assert_eq(result.status(), expected)
    assert_eq(result.detail, 0xa5)
    assert_eq(
      result.corruption_flags(),
      if code == 0x57 {
        Some(0xa5)
      } else {
        None
      },
    )
  }
}

///|
test "global enables decode each bit and preserve the reserved flag" {
  for bit in 0..<8 {
    let e = Response::{
      completion_code: 0,
      data: Bytes::from_array([byte(1 << bit)]),
    }.global_enables()
    assert_eq(e.flags, 1 << bit)
    assert_eq(e.receive_message_queue_interrupt, bit == 0)
    assert_eq(e.event_message_buffer_full_interrupt, bit == 1)
    assert_eq(e.event_message_buffer, bit == 2)
    assert_eq(e.system_event_logging, bit == 3)
    assert_eq(e.oem0, bit == 5)
    assert_eq(e.oem1, bit == 6)
    assert_eq(e.oem2, bit == 7)
  }
}

///|
test "watchdog preserves reserved bits and unsigned 100ms countdown units" {
  let raw = b"\xfc\xba\xff\xa5\xff\xff\x01\x80"
  let timer = Response::{ completion_code: 0, data: raw, }.watchdog_timer()
  assert_eq(timer.raw, raw)
  assert_eq(timer.timer_use, 4)
  assert_eq(timer.timer_use_description(), "SMS/OS")
  assert_eq(timer.running, true)
  assert_eq(timer.logging_enabled, false)
  assert_eq(timer.timeout_action, 2)
  assert_eq(timer.timeout_action_description(), "Power Down")
  assert_eq(timer.pre_timeout_interrupt, 3)
  assert_eq(timer.pre_timeout_interrupt_description(), "Messaging")
  assert_eq(timer.pre_timeout_seconds, 255)
  assert_eq(timer.expiration_flags, 0xa5)
  assert_eq(timer.initial_countdown_tenths, 65535)
  assert_eq(timer.present_countdown_tenths, 32769)
  assert_eq(timer.initial_countdown_seconds(), 6553.5)
  assert_eq(timer.present_countdown_seconds(), 3276.9)
}

///|
test "power on counter retains full unsigned range without floating point loss" {
  let maximum = Response::{ completion_code: 0, data: b"\xff\xff\xff\xff\xff", }.power_on_hours()
  assert_eq(maximum.count, 0xffffffffU)
  assert_eq(maximum.total_minutes(), 1095216660225UL)
  let precise = Response::{ completion_code: 0, data: b"\x01\x01\x00\x00\x01", }.power_on_hours()
  assert_eq(precise.total_minutes(), 16777217UL)
  let zero = Response::{ completion_code: 0, data: b"\x00\xff\xff\xff\xff", }.power_on_hours()
  assert_eq(zero.total_minutes(), 0UL)
}

///|
test "management reads reject truncated extended and unsuccessful responses" {
  for
    (size, decode) in [
      (2, (response : Response) => ignore(response.self_test())),
      (1, (response : Response) => ignore(response.global_enables())),
      (8, (response : Response) => ignore(response.watchdog_timer())),
      (5, (response : Response) => ignore(response.power_on_hours())),
    ] {
    for length in [0, size - 1, size + 1] {
      rejected(() => {
        decode(Response::{ completion_code: 0, data: Bytes::make(length, 0), })
      })
    }
    for completion in [0xc1, 0xd4] {
      rejected(() => {
        decode(Response::{
          completion_code: completion,
          data: Bytes::make(size, 0),
        })
      })
    }
  }
}
