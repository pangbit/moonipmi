///|
fn rejected(f : () -> Unit raise ProtocolError) -> Unit raise {
  let result = Ok(f()) catch { e => Err(e) }
  guard result is Err(_) else { fail("malformed input was accepted") }
}

///|
fn response_fixture(
  netfn : Int32,
  command : Int32,
  sequence : Int32,
  code : Int32,
  data : Bytes,
) -> Bytes {
  let out : Array[Byte] = [0x81, byte((netfn + 1) << 2)]
  out.push(checksum(out[:]))
  out.append([0x20, byte(sequence << 2), byte(command), byte(code)])
  append(out, data)
  out.push(checksum(out[3:]))
  Bytes::from_array(out)
}

///|
test "known LAN request bytes and boundary arguments" {
  assert_eq(encode_request(6, 1, 0, b""), b"\x20\x18\xc8\x81\x00\x01\x7e")
  assert_eq(
    ReadCommand::GetSensorReading(0x2a).encode(63),
    b"\x20\x10\xd0\x81\xfc\x2d\x2a\x2c",
  )
  for
    (netfn, command, sequence) in [
      (-2, 1, 0),
      (1, 1, 0),
      (64, 1, 0),
      (6, 256, 0),
      (6, 1, -1),
      (6, 1, 64),
    ] {
    rejected(() => ignore(encode_request(netfn, command, sequence, b"")))
  }
  rejected(() => ignore(encode_request(6, 1, 0, Bytes::make(1025, 0))))
}

///|
test "response checksum and identity fail closed" {
  let wire = response_fixture(6, 1, 2, 0, b"\x01\x02")
  assert_eq(decode_response(wire, 6, 1, 2).data, b"\x01\x02")
  for index in 0..<wire.length() {
    let changed = wire.to_array()
    changed[index] = byte(changed[index].to_int() ^ 1)
    rejected(() => ignore(decode_response(Bytes::from_array(changed), 6, 1, 2)))
  }
  for size in 0..<8 {
    rejected(() => ignore(decode_response(slice(wire, 0, size), 6, 1, 2)))
  }
  rejected(() => ignore(decode_response(wire, 4, 1, 2)))
  rejected(() => ignore(decode_response(wire, 6, 2, 2)))
  rejected(() => ignore(decode_response(wire, 6, 1, 3)))
}

///|
test "completion failures retain code but refuse typed successful decoding" {
  let response = decode_response(response_fixture(6, 1, 0, 0xc1, b""), 6, 1, 0)
  assert_eq(response.completion_code, 0xc1)
  rejected(() => ignore(response.device_id()))
}

///|
test "Device ID byte orders, version nibbles and optional firmware" {
  let payload = b"\x12\x03\x81\x23\x02\x01\x57\x01\x00\x34\x12"
  let response = decode_response(response_fixture(6, 1, 0, 0, payload), 6, 1, 0)
  let device = response.device_id()
  assert_eq(device.manufacturer_id, 343U)
  assert_eq(device.product_id, 0x1234)
  assert_eq(device.ipmi_major, 2)
  assert_eq(device.ipmi_minor, 0)
  assert_eq(device.firmware_available, false)
  assert_eq(device.auxiliary_firmware, None)
  for length in [0, 10, 12, 14, 16] {
    let response : Response = {
      completion_code: 0,
      data: Bytes::make(length, 0),
    }
    rejected(() => ignore(response.device_id()))
  }
}

///|
test "chassis and raw sensor results remain read-only and correctly flag unavailable" {
  let chassis : Response = { completion_code: 0, data: b"\x51\x02\x04\x0f", }
  assert_eq(chassis.chassis_status().power_on, true)
  assert_eq(chassis.chassis_status().restore_policy, 2)
  let sensor : Response = { completion_code: 0, data: b"\x2a\xe0\x01", }
  assert_eq(sensor.sensor_reading().raw_reading, 42)
  assert_eq(sensor.sensor_reading().reading_available, false)
  assert_eq(sensor.sensor_reading().scanning_enabled, true)
}

///|
test "RMCP+ envelope golden bytes and strict length" {
  let golden = b"\x06\x00\xff\x07\x06\x10\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xaa\xbb"
  assert_eq(encode_handshake(0x10, b"\xaa\xbb"), golden)
  assert_eq(decode_handshake(golden).payload, b"\xaa\xbb")
  for length in 0..<golden.length() {
    rejected(() => ignore(decode_handshake(slice(golden, 0, length))))
  }
  for index in [0, 1, 2, 3, 4, 6, 10, 14, 15] {
    let changed = golden.to_array()
    changed[index] = byte(changed[index].to_int() ^ 1)
    rejected(() => ignore(decode_handshake(Bytes::from_array(changed))))
  }
  let flagged = golden.to_array()
  flagged[5] = 0x90
  rejected(() => ignore(decode_handshake(Bytes::from_array(flagged))))
  rejected(() => ignore(encode_handshake(0, b"")))
}

///|
fn open_fixture() -> Bytes {
  b"\x07\x00\x02\x00\x44\x33\x22\x11\x88\x77\x66\x55\x00\x00\x00\x08\x03\x00\x00\x00\x01\x00\x00\x08\x04\x00\x00\x00\x02\x00\x00\x08\x01\x00\x00\x00"
}

///|
test "Open Session pins cipher suite 17 and user privilege" {
  let request = open_session_request(7, 0x11223344U)
  assert_eq(request.length(), 32)
  assert_eq(slice(request, 0, 8), b"\x07\x02\x00\x00\x44\x33\x22\x11")
  assert_eq(slice(request, 8, 32), slice(open_fixture(), 12, 36))
  assert_eq(
    decode_open_session(open_fixture(), 7, 0x11223344U).bmc_id,
    0x55667788U,
  )
  for index in [0, 1, 2, 3, 4, 12, 15, 16, 17, 20, 24, 28, 32] {
    let changed = open_fixture().to_array()
    changed[index] = byte(changed[index].to_int() ^ 1)
    rejected(() => {
      ignore(decode_open_session(Bytes::from_array(changed), 7, 0x11223344U))
    })
  }
  for length in 0..<36 {
    rejected(() => {
      ignore(
        decode_open_session(slice(open_fixture(), 0, length), 7, 0x11223344U),
      )
    })
  }
  rejected(() => ignore(open_session_request(0, 0U)))
}

///|
test "RAKP1 includes raw username and enforces IPMI bounds" {
  let request = rakp1_request(4, 0x11223344U, Bytes::make(16, 0xaa), b"tester")
  assert_eq(request.length(), 34)
  assert_eq(slice(request, 24, 34), b"\x02\x00\x00\x06tester")
  for size in [0, 17] {
    rejected(() => {
      ignore(rakp1_request(0, 1U, Bytes::make(16, 0), Bytes::make(size, 0x61)))
    })
  }
  rejected(() => ignore(rakp1_request(0, 1U, b"", b"tester")))
}

///|
test "RAKP2 and RAKP4 framing do not authenticate a session" {
  let packet : Array[Byte] = [0x04, 0, 0, 0, 0x44, 0x33, 0x22, 0x11]
  packet.append(Array::make(64, 0xaa))
  let wire = Bytes::from_array(packet)
  assert_eq(decode_rakp2(wire, 4, 0x11223344U).authentication_code.length(), 32)
  for length in 0..<72 {
    rejected(() => ignore(decode_rakp2(slice(wire, 0, length), 4, 0x11223344U)))
  }
  rejected(() => ignore(decode_rakp2(wire, 5, 0x11223344U)))
  let r4 = slice(wire, 0, 24)
  assert_eq(decode_rakp4(r4, 4, 0x11223344U), Bytes::make(16, 0xaa))
  rejected(() => ignore(decode_rakp4(wire, 4, 0x11223344U)))
  rejected(() => ignore(rakp3_request(4, 1U, Bytes::make(20, 0))))
  assert_eq(rakp3_request(4, 1U, Bytes::make(32, 0)).length(), 40)
}
