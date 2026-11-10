///|
/// Single-flight IPMI 2.0 LAN client. Only suite 17 and User privilege are
/// supported. No password or key appears in a derived Show/Debug implementation.
pub struct Client {
  priv socket : @socket.UdpClient
  priv console_id : UInt32
  priv bmc_id : UInt32
  priv keys : SessionKeys
  priv timeout_ms : Int32
  priv mut send_sequence : UInt32
  priv mut receive_sequence : UInt32
  priv mut request_sequence : Int32
  priv mut busy : Bool
  priv mut closed : Bool
}

///|
async fn datagram(
  socket : @socket.UdpClient,
  request : Bytes,
  timeout_ms : Int32,
) -> Bytes {
  @async.with_timeout(timeout_ms, async fn() {
    socket.send(request)
    let buffer : FixedArray[Byte] = FixedArray::make(2048, 0)
    let count = socket.recv(buffer)
    guard count <= 1120 else { raise invalid("oversized RMCP+ datagram") }
    Bytes::from_array(Array::makei(count, i => buffer[i]))
  })
}

///|
async fn handshake_exchange(
  socket : @socket.UdpClient,
  kind : Int32,
  payload : Bytes,
  timeout_ms : Int32,
) -> Bytes {
  let packet = decode_handshake(
    datagram(socket, encode_handshake(kind, payload), timeout_ms),
  )
  guard packet.payload_type == kind + 1 else {
    raise invalid("unexpected handshake response type")
  }
  packet.payload
}

///|
fn validate_destination(addr : @socket.Addr) -> Unit raise ProtocolError {
  guard addr.port() >= 1 && !addr.is_multicast() else {
    raise invalid("a non-multicast peer and nonzero port are required")
  }
  if addr.is_ipv6() {
    let text = addr.to_string()
    guard !text.has_prefix("[::]:") &&
      !text.has_prefix("[::%") &&
      !text.has_prefix("[::ffff:0:0]") &&
      !text.has_prefix("[::ffff:ffff:ffff]") else {
      raise invalid(
        "unspecified or limited-broadcast destination is not allowed",
      )
    }
  } else {
    guard addr.ip() != 0U && addr.ip() != 0xffffffffU else {
      raise invalid(
        "unspecified or limited-broadcast destination is not allowed",
      )
    }
  }
}

///|
/// Connect to one explicit peer address, authenticate RAKP2/4, and request
/// User privilege. No anonymous access, Kg override, retry or downgrade fallback.
/// Each exchange has a timeout (default 2000 ms, range 1..60000).
/// Username/password are raw bytes. Nothing is written to hardware configuration.
pub async fn Client::connect(
  addr : @socket.Addr,
  username : Bytes,
  password : Bytes,
  timeout_ms~ : Int32 = 2000,
) -> Client {
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("timeout 1..60000 ms required")
  }
  validate_destination(addr)
  // Validate credentials before opening a socket or consuming network resources.
  ignore(handshake(username, password, 1U, Bytes::make(16, 0)))
  let random = @crypto.random(21)
  let console_id = u32(random, 0)
  let h = handshake(username, password, console_id, slice(random, 4, 20))
  let tag = random[20].to_int()
  let socket = @socket.UdpClient(addr)
  errdefer socket.close()
  let open = decode_open_session(
    handshake_exchange(
      socket,
      0x10,
      open_session_request(tag, console_id),
      timeout_ms,
    ),
    tag,
    console_id,
  )
  let challenge = decode_rakp2(
    handshake_exchange(
      socket,
      0x12,
      rakp1_request(tag, open.bmc_id, h.console_random, username),
      timeout_ms,
    ),
    tag,
    console_id,
  )
  let keys = verify_rakp2(h, open.bmc_id, challenge)
  let confirmation = decode_rakp4(
    handshake_exchange(
      socket,
      0x14,
      rakp3_request(tag, open.bmc_id, rakp3_code(h, challenge)),
      timeout_ms,
    ),
    tag,
    console_id,
  )
  verify_rakp4(h, open.bmc_id, challenge, keys, confirmation)
  let client : Client = {
    socket,
    console_id,
    bmc_id: open.bmc_id,
    keys,
    timeout_ms,
    send_sequence: 1U,
    receive_sequence: 0U,
    request_sequence: 0,
    busy: false,
    closed: false,
  }
  errdefer client.abort()
  let privilege = client.exchange(6, 0x3b, b"\x02")
  guard privilege.completion_code == 0 && privilege.data == b"\x02" else {
    raise invalid("BMC refused User session privilege")
  }
  client
}

///|
async fn Client::exchange(
  self : Client,
  netfn : Int32,
  command : Int32,
  data : Bytes,
) -> Response {
  guard !self.closed else { raise invalid("session is closed") }
  guard !self.busy else { raise invalid("only one request may be in flight") }
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer self.abort()
  guard self.send_sequence != 0U && self.send_sequence < 0xffffffffU else {
    raise invalid("session sequence exhausted; reconnect required")
  }
  let request_sequence = self.request_sequence
  let request = encode_request(netfn, command, request_sequence, data)
  let packet = protect_payload(
    request,
    self.bmc_id,
    self.send_sequence,
    self.keys,
    @crypto.random(16),
  )
  // Never reuse a sequence or IV after an uncertain exchange outcome.
  self.send_sequence += 1U
  self.request_sequence = (request_sequence + 1) & 63
  let (sequence, clear) = unprotect_payload(
    datagram(self.socket, packet, self.timeout_ms),
    self.console_id,
    self.receive_sequence,
    self.keys,
  )
  let response = decode_response(clear, netfn, command, request_sequence)
  self.receive_sequence = sequence
  response
}

///|
/// Execute one of the three explicitly read-only command variants.
/// Any I/O, authentication, identity or framing failure closes the session.
pub async fn Client::read(self : Client, command : ReadCommand) -> Response {
  match command {
    GetDeviceId => self.exchange(6, 1, b"")
    GetChassisStatus => self.exchange(0, 1, b"")
    GetSensorReading(sensor) =>
      self.exchange(4, 0x2d, Bytes::from_array([sensor]))
  }
}

///|
/// Close the remote session and always close the local socket. Idempotent once
/// closed. A busy session must be aborted or allowed to complete first.
pub async fn Client::close(self : Client) -> Unit {
  if self.closed {
    return
  }
  guard !self.busy else {
    raise invalid("cannot gracefully close a busy session")
  }
  defer self.abort()
  let data : Array[Byte] = []
  put32(data, self.bmc_id)
  let response = self.exchange(6, 0x3c, Bytes::from_array(data))
  guard response.completion_code == 0 else {
    raise invalid("BMC rejected Close Session")
  }
}

///|
/// Close the local socket immediately without sending a command. Safe to repeat.
/// The BMC may retain its session until its own inactivity timeout.
pub fn Client::abort(self : Client) -> Unit {
  if !self.closed {
    self.closed = true
    self.socket.close()
  }
}
