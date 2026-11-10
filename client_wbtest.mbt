///|
// In-process synthetic BMC. It shares framing helpers with the client, so this
// test proves transport/state integration, not independent interoperability.
async fn mock_receive(server : @socket.UdpServer) -> (Bytes, @socket.Addr) {
  let buffer : FixedArray[Byte] = FixedArray::make(2048, 0)
  let (length, peer) = server.recvfrom(buffer)
  (Bytes::from_array(Array::makei(length, i => buffer[i])), peer)
}

///|
async fn mock_bmc(server : @socket.UdpServer, mode : Int32) -> Unit {
  let (initial, peer) = mock_receive(server)
  let open = decode_handshake(initial)
  assert_eq(open.payload_type, 0x10)
  let tag = open.payload[0].to_int()
  let console_id = u32(open.payload, 4)
  assert_eq(open.payload, open_session_request(tag, console_id))
  let bmc_id = 0x55667788U
  let response : Array[Byte] = [byte(tag), 0, 2, 0]
  put32(response, console_id)
  put32(response, bmc_id)
  append(response, slice(open.payload, 8, 32))
  server.sendto(encode_handshake(0x11, Bytes::from_array(response)), peer)
  let (r1_datagram, peer2) = mock_receive(server)
  assert_eq(peer, peer2)
  let r1 = decode_handshake(r1_datagram).payload
  assert_eq(slice(r1, 24, 28), b"\x02\x00\x00\x06")
  assert_eq(slice(r1, 28, r1.length()), b"tester")
  let h = handshake(
    b"tester",
    b"synthetic-password",
    console_id,
    slice(r1, 8, 24),
  )
  let bmc_random = Bytes::make(16, 0xbb)
  let guid = Bytes::make(16, 0xcc)
  let input : Array[Byte] = []
  put32(input, console_id)
  put32(input, bmc_id)
  append(input, h.console_random)
  append(input, bmc_random)
  append(input, guid)
  input.append([2, 6])
  append(input, b"tester")
  let code = @crypto.hmac_sha256(h.password_key, Bytes::from_array(input))
  let challenge : RakpChallenge = {
    bmc_random,
    bmc_guid: guid,
    authentication_code: code,
  }
  let r2 : Array[Byte] = [byte(tag), 0, 0, 0]
  put32(r2, console_id)
  append(r2, bmc_random)
  append(r2, guid)
  append(r2, if mode == 1 { Bytes::make(32, 0) } else { code })
  server.sendto(encode_handshake(0x13, Bytes::from_array(r2)), peer)
  if mode == 1 {
    return
  }
  let (r3_datagram, peer3) = mock_receive(server)
  assert_eq(peer, peer3)
  assert_eq(
    decode_handshake(r3_datagram).payload,
    rakp3_request(tag, bmc_id, rakp3_code(h, challenge)),
  )
  let keys = derive_keys(h, challenge)
  let icv_input : Array[Byte] = []
  append(icv_input, h.console_random)
  put32(icv_input, bmc_id)
  append(icv_input, guid)
  let r4 : Array[Byte] = [byte(tag), 0, 0, 0]
  put32(r4, console_id)
  append(
    r4,
    slice(@crypto.hmac_sha256(keys.sik, Bytes::from_array(icv_input)), 0, 16),
  )
  server.sendto(encode_handshake(0x15, Bytes::from_array(r4)), peer)
  let mut previous_sequence = 0U
  for stage in 0..<3 {
    let (packet, sender) = mock_receive(server)
    assert_eq(sender, peer)
    let (sequence, request) = unprotect_payload(
      packet, bmc_id, previous_sequence, keys,
    )
    previous_sequence = sequence
    let request_sequence = request[4].to_int() >> 2
    let command = if stage == 0 { 0x3b } else if stage == 1 { 1 } else { 0x3c }
    let command_data = if stage == 0 {
      b"\x02"
    } else if stage == 1 {
      b""
    } else {
      b"\x88\x77\x66\x55"
    }
    assert_eq(
      request,
      encode_request(6, command, request_sequence, command_data),
    )
    if mode == 3 && stage == 1 {
      @async.sleep(150)
      return
    }
    let result = if stage == 0 {
      b"\x02"
    } else if stage == 1 {
      b"\x12\x03\x01\x23\x02\x01\x57\x01\x00\x34\x12"
    } else {
      b""
    }
    let reply = protect_payload(
      response_fixture(6, command, request_sequence, 0, result),
      console_id,
      (stage + 1).reinterpret_as_uint(),
      keys,
      Bytes::make(16, byte(stage)),
    )
    if mode == 2 && stage == 1 {
      let tampered = reply.to_array()
      tampered[32] = byte(tampered[32].to_int() ^ 1)
      server.sendto(Bytes::from_array(tampered), peer)
      return
    }
    server.sendto(reply, peer)
  }
}

///|
async test "loopback authenticates, reads Device ID and closes the BMC session" {
  @async.with_timeout(3000, async fn() {
    @async.with_task_group(async fn(group) {
      let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(async fn() { mock_bmc(server, 0) })
      let client = Client::connect(
        server.addr,
        b"tester",
        b"synthetic-password",
      )
      defer client.abort()
      let result = client.read(GetDeviceId).device_id()
      assert_eq(result.manufacturer_id, 343U)
      assert_eq(result.product_id, 0x1234)
      client.close()
      client.close()
      let rejected = try {
        ignore(client.read(GetDeviceId))
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    })
  })
}

///|
async test "loopback rejects a false RAKP2 before activating a session" {
  @async.with_timeout(3000, async fn() {
    @async.with_task_group(async fn(group) {
      let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(async fn() { mock_bmc(server, 1) })
      let rejected = try {
        let client = Client::connect(
          server.addr,
          b"tester",
          b"synthetic-password",
        )
        client.abort()
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    })
  })
}

///|
async test "loopback tampering and timeout permanently close a client" {
  for mode in [2, 3] {
    @async.with_timeout(3000, async fn() {
      @async.with_task_group(async fn(group) {
        let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        group.spawn_bg(async fn() { mock_bmc(server, mode) })
        let client = Client::connect(
          server.addr,
          b"tester",
          b"synthetic-password",
          timeout_ms=100,
        )
        defer client.abort()
        let rejected = try {
          ignore(client.read(GetDeviceId))
          false
        } catch {
          _ => true
        }
        assert_true(rejected)
        assert_true(client.closed)
        let closed = try {
          ignore(client.read(GetDeviceId))
          false
        } catch {
          _ => true
        }
        assert_true(closed)
      })
    })
  }
}

///|
test "invalid non-peer destinations are rejected before socket creation" {
  for
    address in [
      "0.0.0.0:623", "255.255.255.255:623", "224.0.0.1:623", "[::]:623", "[ff02::1]:623",
      "127.0.0.1:0",
    ] {
    let addr = @socket.Addr::parse(address)
    rejected(() => validate_destination(addr))
  }
  validate_destination(@socket.Addr::parse("127.0.0.1:623"))
  validate_destination(@socket.Addr::parse("[::1]:623"))
}

///|
test "mapped IPv4 cannot bypass non-peer destination checks" {
  for
    address in [
      "[::ffff:0.0.0.0]:623", "[::ffff:255.255.255.255]:623", "[::ffff:224.0.0.1]:623",
      "[0:0:0:0:0:ffff:efff:ffff]:623", "[::ffff:127.0.0.1]:623",
    ] {
    let addr = @socket.Addr::parse(address)
    rejected(() => validate_destination(addr))
  }
  // Callers can use ordinary IPv4 unicast; no packet is sent by this test.
  validate_destination(@socket.Addr::parse("127.0.0.1:623"))
  validate_destination(@socket.Addr::parse("[2001:db8::1]:623"))
}
