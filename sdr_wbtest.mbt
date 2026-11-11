///|
fn full_sensor_test(
  format~ : Int32 = 0,
  m~ : Int32 = 1,
  b~ : Int32 = 0,
  exp~ : Int32 = 0,
  linear~ : Int32 = 0,
) -> SdrSensor raise {
  let d : Array[Byte] = Array::make(47, 0)
  d[0] = 0x20
  d[2] = 0x2a
  d[4] = 0x81
  d[7] = 1
  d[8] = 1
  d[15] = byte(format << 6)
  d[16] = 1
  d[18] = byte(linear)
  d[19] = byte(m)
  d[20] = byte((m >> 2) & 0xc0)
  d[21] = byte(b)
  d[22] = byte((b >> 2) & 0xc0)
  d[24] = byte(exp)
  d[42] = 0xc4
  for i in 0..<4 {
    d[43 + i] = b"Temp"[i]
  }
  let record : SdrRecord = {
    record_id: 1,
    record_type: 1,
    data: Bytes::from_array(d),
  }
  guard record.sensor() is Some(sensor) else { fail("missing full sensor") }
  sensor
}

///|
fn reading_test(
  raw : Int32,
  flags~ : Int32 = 0xc0,
  status~ : Bytes = b"\x00\x00",
) -> SensorReading raise ProtocolError {
  let d = [byte(raw), byte(flags)]
  append(d, status)
  Response::{ completion_code: 0, data: Bytes::from_array(d), }.sensor_reading()
}

///|
test "Full Sensor parses signed factors exponents and local identity" {
  let s = full_sensor_test(m=-512, b=511, exp=0x87)
  assert_eq(
    s.conversion,
    Some({
      linearization: 0,
      m: -512,
      b: 511,
      b_exponent: 7,
      result_exponent: -8,
    }),
  )
  assert_eq(s.name, Some("Temp"))
  assert_eq(s.raw_name, b"Temp")
  assert_eq(s.number, 0x2a)
  assert_eq(s.entity_instance, 1)
  assert_eq(s.logical_entity, true)
  assert_eq(s.read_support(), None)
  assert_eq(s.unit(), Some("degrees C"))
}

///|
test "common engineering values and signed raw formats" {
  assert_eq(full_sensor_test().value(reading_test(42)), Numeric(42.0))
  assert_eq(full_sensor_test(exp=0xf0).value(reading_test(120)), Numeric(12.0))
  assert_eq(full_sensor_test(m=60).value(reading_test(100)), Numeric(6000.0))
  assert_eq(
    full_sensor_test(m=2, b=-10).value(reading_test(80)),
    Numeric(150.0),
  )
  assert_eq(full_sensor_test(format=2).value(reading_test(246)), Numeric(-10.0))
  assert_eq(full_sensor_test(format=1).value(reading_test(245)), Numeric(-10.0))
  assert_eq(full_sensor_test(format=1).value(reading_test(255)), Numeric(0.0))
  assert_eq(
    full_sensor_test(format=2).value(reading_test(128)),
    Numeric(-128.0),
  )
  assert_eq(
    full_sensor_test(b=2, exp=0x11).value(reading_test(3)),
    Numeric(230.0),
  )
}

///|
test "unavailable disabled discrete and unsupported conversion stay explicit" {
  let s = full_sensor_test()
  assert_eq(s.value(reading_test(238, flags=0xe0)), Unavailable)
  assert_eq(s.value(reading_test(238, flags=0x80)), ScanningDisabled)
  assert_eq(s.value(reading_test(42, flags=0x40)), Numeric(42.0))
  assert_eq(full_sensor_test(format=3).value(reading_test(42)), Discrete)
  for linear in [1, 0x70, 0x7f, 0x80] {
    assert_eq(
      full_sensor_test(linear~).value(reading_test(42)),
      Unsupported("nonlinear/OEM sensor conversion is not implemented"),
    )
  }
}

///|
test "Compact Sensor does not invent analog values or shared instances" {
  let d : Array[Byte] = Array::make(28, 0)
  d[0] = 0x20
  d[7] = 5
  d[8] = 0x6f
  d[15] = 0xc0
  d[26] = 0xc1
  d[27] = 0x43
  let record : SdrRecord = {
    record_id: 7,
    record_type: 2,
    data: Bytes::from_array(d),
  }
  guard record.sensor() is Some(s) else { fail("missing compact sensor") }
  assert_eq(s.name, Some("C"))
  assert_eq(s.value(reading_test(0)), Discrete)
  assert_eq(s.state(reading_test(0, status=b"\x01\x80")), Discrete(1))
  assert_eq(s.discrete_state_name(0), Some("General Chassis intrusion"))
  assert_eq(s.discrete_state_name(7), None)
  let shared = { ..s, sharing_count: 2, }
  assert_true(shared.read_support() != None)
  assert_eq(
    shared.value(reading_test(0)),
    Unsupported("shared Compact Sensor expansion is not implemented"),
  )
}

///|
test "unknown routing names unit encodings and record types are not guessed" {
  let s = full_sensor_test()
  for
    changed in [
      { ..s, owner_id: 0x22, },
      { ..s, owner_channel: 1, },
      { ..s, owner_lun: 1, },
    ] {
    assert_true(changed.read_support() != None)
  }
  assert_eq(SdrSensor::{ ..s, base_unit: 255, }.unit(), None)
  assert_eq(SdrSensor::{ ..s, unit_flags: 6, }.unit(), None)
  assert_eq(SdrSensor::{ ..s, unit_flags: 56, }.unit(), None)
  assert_eq(
    SdrSensor::{ ..s, unit_flags: 1, base_unit: 0, }.unit(),
    Some("percent"),
  )
  assert_eq(
    SdrSensor::{ ..s, unit_flags: 2, base_unit: 6, modifier_unit: 4, }.unit(),
    Some("Watts/Volts"),
  )
  assert_eq(
    SdrSensor::{ ..s, unit_flags: 24, base_unit: 7, }.unit(),
    Some("Joules/s"),
  )
  let unknown = decode_sdr_record(b"\x01\x00\x51\xc0\x01\xff")
  assert_eq(unknown.sensor(), None)
  assert_eq(unknown.data, b"\xff")
  let bytes : Array[Byte] = Array::make(44, 0)
  bytes[42] = 0x81
  bytes[43] = 0x41
  let record : SdrRecord = {
    record_id: 1,
    record_type: 1,
    data: Bytes::from_array(bytes),
  }
  guard record.sensor() is Some(encoded) else { fail("missing sensor") }
  assert_eq(encoded.name, None)
  assert_eq(encoded.name_encoding, 2)
  assert_eq(encoded.raw_name, b"A")
}

///|
test "threshold masks retain severity and missing status is not healthy" {
  let s = full_sensor_test()
  for
    (mask, status) in [
      (0, "ok"),
      (1, "nc"),
      (8, "nc"),
      (2, "cr"),
      (16, "cr"),
      (4, "nr"),
      (32, "nr"),
      (63, "nr"),
    ] {
    let state = s.state(
      reading_test(42, status=Bytes::from_array([byte(mask)])),
    )
    assert_eq(state, Threshold(mask))
    assert_eq(state.threshold_status(), Some(status))
  }
  assert_eq(s.state(reading_test(42, status=b"")), MissingStatus)
  assert_eq(s.state(reading_test(42, flags=0xe0)), Unavailable)
  assert_eq(s.state(reading_test(42, flags=0x80)), ScanningDisabled)
  assert_eq(SensorState::MissingStatus.threshold_status(), None)
  assert_eq(
    SdrSensor::{ ..s, event_type: 0x6f, }.state(
      reading_test(42, status=b"\x01"),
    ),
    MissingStatus,
  )
}

///|
test "malformed SDR records and partial responses fail closed" {
  for
    d in [
      b"", b"\x01\x00\x51\x01", b"\x01\x00\x50\xc0\x00", b"\x01\x00\x51\xc0\x01",
    ] {
    rejected(() => ignore(decode_sdr_record(d)))
  }
  for (kind, size) in [(1, 42), (2, 26), (1, 44)] {
    let r : SdrRecord = {
      record_id: 1,
      record_type: kind,
      data: Bytes::make(size, 0),
    }
    rejected(() => ignore(r.sensor()))
  }
  rejected(() => {
    ignore(sdr_chunk({ completion_code: 0, data: b"\xff\xff\x00", }, 5))
  })
  rejected(() => ignore(sdr_chunk({ completion_code: 0xc5, data: b"", }, 5)))
  assert_eq(sdr_request(0x1234, 0x5678, 245, 15), b"\x34\x12\x78\x56\xf5\x0f")
}

///|
test "SDR repository info parses count capabilities and timestamps" {
  let response : Response = {
    completion_code: 0,
    data: b"\x51\x03\x00\xff\xff\x01\x02\x03\x04\x05\x06\x07\x08\x02",
  }
  let info = response.sdr_repository_info()
  assert_eq(info.record_count, 3)
  assert_eq(info.last_addition, 0x04030201U)
  assert_eq(info.last_erase, 0x08070605U)
  assert_eq(info.operations, 2)
  for length in [0, 13, 15] {
    rejected(() => {
      ignore(
        Response::{ completion_code: 0, data: Bytes::make(length, 0), }.sdr_repository_info(),
      )
    })
  }
}
