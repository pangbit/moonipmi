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

///|
test "failure diagnostics retain status codes without request data" {
  let changed = open_fixture().to_array()
  changed[1] = 13
  let message = try {
    ignore(decode_open_session(Bytes::from_array(changed), 7, 0x11223344U))
    "unexpected success"
  } catch {
    ProtocolError(message) => message
  }
  assert_eq(message, "BMC rejected Open Session (status 13)")
  let failed : Response = { completion_code: 193, data: b"", }
  let message = try {
    ignore(failed.device_id())
    "unexpected success"
  } catch {
    ProtocolError(message) => message
  }
  assert_eq(message, "Get Device ID failed (completion code 193)")
}

///|
test "requester address tolerance matches ipmitool without rewriting requests" {
  assert_eq(encode_request(6, 1, 0, b"")[3], 0x81)
  // ipmitool does not use rqAddr for matching, rather than allowing only 0x20.
  for address in 0..<=255 {
    let packet = response_fixture(6, 0x3b, 0, 0, b"\x02").to_array()
    packet[0] = byte(address)
    packet[2] = checksum(packet[0:2])
    assert_eq(
      decode_response(Bytes::from_array(packet), 6, 0x3b, 0).data,
      b"\x02",
    )
  }
}

///|
test "requester tolerance retains responder, LUN, netfn, command and sequence checks" {
  for
    (index, value) in [(3, 0x22), (1, 0x24), (1, 0x1d), (4, 1), (4, 4), (5, 2)] {
    let packet = response_fixture(6, 1, 0, 0, b"").to_array()
    packet[0] = 0x20
    packet[index] = byte(value)
    packet[2] = checksum(packet[0:2])
    packet[packet.length() - 1] = checksum(packet[3:packet.length() - 1])
    let error = try {
      ignore(decode_response(Bytes::from_array(packet), 6, 1, 0))
      "unexpected success"
    } catch {
      ProtocolError(message) => message
    }
    assert_eq(
      error,
      if index == 3 {
        "IPMI response address mismatch"
      } else {
        "IPMI response does not match request"
      },
    )
  }
}

///|
test "Device ID exposes capability bits and preserves auxiliary firmware bytes" {
  let base : Response = {
    completion_code: 0,
    data: b"\x12\x03\x01\x23\x02\x01\x57\x01\x00\x34\x12",
  }
  let d = base.device_id()
  assert_eq(d.provides_device_sdrs, false)
  assert_eq(d.additional_device_support, 1)
  // Device SDRs and an SDR repository are independent advertised capabilities.
  let repository : Response = {
    completion_code: 0,
    data: b"\x12\x03\x01\x23\x02\x02\x57\x01\x00\x34\x12",
  }
  assert_eq(repository.device_id().provides_device_sdrs, false)
  assert_eq(repository.device_id().additional_device_support, 2)
  let extended : Response = {
    completion_code: 0,
    data: b"\x12\x83\x81\x23\x02\xff\x57\x01\x00\x34\x12\x01\x23\x45\x67",
  }
  let d = extended.device_id()
  assert_eq(d.provides_device_sdrs, true)
  assert_eq(d.device_revision, 3)
  assert_eq(d.additional_device_support, 255)
  assert_eq(d.firmware_available, false)
  assert_eq(d.auxiliary_firmware, Some(b"\x01\x23\x45\x67"))
}

///|
test "chassis fault flags and optional front-panel byte remain distinct" {
  for bit in [1, 2, 4, 8] {
    let r : Response = {
      completion_code: 0,
      data: Bytes::from_array([0x4a, 0x0b, byte(bit)]),
    }
    let c = r.chassis_status()
    assert_eq(c.power_on, false)
    assert_eq(c.power_overload, true)
    assert_eq(c.power_fault, true)
    assert_eq(c.restore_policy, 2)
    assert_eq(c.last_power_event, 11)
    assert_eq(c.intrusion_active(), bit == 1)
    assert_eq(c.front_panel_lockout(), bit == 2)
    assert_eq(c.drive_fault(), bit == 4)
    assert_eq(c.cooling_fan_fault(), bit == 8)
    assert_eq(c.front_panel_buttons, None)
  }
  let present : Response = { completion_code: 0, data: b"\x01\x00\x00\x00", }
  assert_eq(present.chassis_status().front_panel_buttons, Some(0))
  for size in [0, 2, 5] {
    let r : Response = { completion_code: 0, data: Bytes::make(size, 0), }
    rejected(() => ignore(r.chassis_status()))
  }
}

///|
test "sensor usable raw reading rejects unavailable and disabled scanning, not disabled events" {
  for
    (flags, expected) in [
      (0xc0, Some(0)),
      (0xe0, None),
      (0x80, None),
      (0x40, Some(0)),
    ] {
    let r : Response = {
      completion_code: 0,
      data: Bytes::from_array([0, byte(flags)]),
    }
    let s = r.sensor_reading()
    assert_eq(s.usable_raw_reading(), expected)
    assert_eq(s.reading_available, (flags & 0x20) == 0)
    assert_eq(s.status_bits, b"")
  }
  let r : Response = { completion_code: 0, data: b"\x2a\xc0\x01\x02", }
  assert_eq(r.sensor_reading().status_bits, b"\x01\x02")
  for size in [0, 1, 5] {
    let r : Response = { completion_code: 0, data: Bytes::make(size, 0), }
    rejected(() => ignore(r.sensor_reading()))
  }
}
