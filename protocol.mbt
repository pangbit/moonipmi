///|
/// Malformed, unsupported, mismatched, or failed IPMI exchange.
#derive(@debug.Debug)
pub suberror ProtocolError {
  ProtocolError(String)
}

///|
pub extend ProtocolError with @debug.Debug::{to_repr}

///|
fn invalid(message : String) -> ProtocolError {
  ProtocolError(message)
}

///|
fn byte(value : Int32) -> Byte {
  value.to_byte()
}

///|
fn slice(data : Bytes, start : Int32, end : Int32) -> Bytes {
  Bytes::from_array(Array::makei(end - start, i => data[start + i]))
}

///|
fn u32(data : Bytes, at : Int32) -> UInt32 {
  data[at].to_uint() |
  (data[at + 1].to_uint() << 8) |
  (data[at + 2].to_uint() << 16) |
  (data[at + 3].to_uint() << 24)
}

///|
fn put32(out : Array[Byte], value : UInt32) -> Unit {
  for shift in [0, 8, 16, 24] {
    out.push((value >> shift).to_byte())
  }
}

///|
fn append(out : Array[Byte], data : Bytes) -> Unit {
  for item in data {
    out.push(item)
  }
}

///|
fn checksum(data : ArrayView[Byte]) -> Byte {
  let mut sum = 0
  for item in data {
    sum = (sum + item.to_int()) & 255
  }
  byte((256 - sum) & 255)
}

///|
/// IPMI LAN request. Sequence is a six-bit value; data is bounded to 1024 bytes.
/// This low-level encoder does not transmit anything.
pub fn encode_request(
  netfn : Int32,
  command : Int32,
  sequence : Int32,
  data : Bytes,
) -> Bytes raise ProtocolError {
  guard netfn >= 0 && netfn <= 62 && netfn % 2 == 0 else {
    raise invalid("request netfn must be even and in 0..62")
  }
  guard command >= 0 && command <= 255 && sequence >= 0 && sequence <= 63 else {
    raise invalid("command or sequence out of range")
  }
  guard data.length() <= 1024 else {
    raise invalid("request data exceeds 1024 bytes")
  }
  let out : Array[Byte] = [0x20, byte(netfn << 2)]
  out.push(checksum(out[:]))
  out.push(0x81)
  out.push(byte(sequence << 2))
  out.push(byte(command))
  append(out, data)
  out.push(checksum(out[3:]))
  Bytes::from_array(out)
}

///|
#derive(Eq, @debug.Debug)
pub struct Response {
  completion_code : Int32
  data : Bytes
}

///|
pub extend Response with Eq::{equal, not_equal}

///|
pub extend Response with @debug.Debug::{to_repr}

///|
/// Validate both checksums and correlate addresses, LUNs, netfn, command and sequence.
/// Nonzero completion codes remain structured protocol results.
pub fn decode_response(
  data : Bytes,
  netfn : Int32,
  command : Int32,
  sequence : Int32,
) -> Response raise ProtocolError {
  guard netfn >= 0 &&
    netfn <= 62 &&
    netfn % 2 == 0 &&
    command >= 0 &&
    command <= 255 &&
    sequence >= 0 &&
    sequence <= 63 else {
    raise invalid("invalid expected response identity")
  }
  guard data.length() >= 8 && data.length() <= 1032 else {
    raise invalid("invalid IPMI response length")
  }
  let values = data.to_array()
  guard checksum(values[0:3]) == 0 && checksum(values[3:]) == 0 else {
    raise invalid("invalid IPMI checksum")
  }
  guard data[0] == 0x81 &&
    data[1].to_int() == (netfn + 1) << 2 &&
    data[3] == 0x20 &&
    data[4].to_int() == sequence << 2 &&
    data[5].to_int() == command else {
    raise invalid("IPMI response does not match request")
  }
  {
    completion_code: data[6].to_int(),
    data: slice(data, 7, data.length() - 1),
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct DeviceId {
  device_id : Int32
  device_revision : Int32
  firmware_major : Int32
  firmware_minor_bcd : Int32
  firmware_available : Bool
  ipmi_major : Int32
  ipmi_minor : Int32
  manufacturer_id : UInt32
  product_id : Int32
  auxiliary_firmware : Bytes?
}

///|
pub extend DeviceId with Eq::{equal, not_equal}

///|
pub extend DeviceId with @debug.Debug::{to_repr}

///|
/// Decode Get Device ID (Application netfn 06h, command 01h).
pub fn Response::device_id(self : Response) -> DeviceId raise ProtocolError {
  guard self.completion_code == 0 else {
    raise invalid("Get Device ID returned a failure completion code")
  }
  let d = self.data
  guard d.length() == 11 || d.length() == 15 else {
    raise invalid("Get Device ID payload must contain 11 or 15 bytes")
  }
  {
    device_id: d[0].to_int(),
    device_revision: d[1].to_int() & 15,
    firmware_major: d[2].to_int() & 127,
    firmware_minor_bcd: d[3].to_int(),
    firmware_available: (d[2].to_int() & 128) == 0,
    ipmi_major: d[4].to_int() & 15,
    ipmi_minor: d[4].to_int() >> 4,
    manufacturer_id: d[6].to_uint() |
    (d[7].to_uint() << 8) |
    (d[8].to_uint() << 16),
    product_id: d[9].to_int() | (d[10].to_int() << 8),
    auxiliary_firmware: if d.length() == 15 {
      Some(slice(d, 11, 15))
    } else {
      None
    },
  }
}

///|
/// Unauthenticated RMCP+ handshake envelope. Authenticated IPMI packets use a
/// different parser that verifies integrity before exposing plaintext.
#derive(Eq, @debug.Debug)
pub struct HandshakePacket {
  payload_type : Int32
  payload : Bytes
}

///|
pub extend HandshakePacket with Eq::{equal, not_equal}

///|
pub extend HandshakePacket with @debug.Debug::{to_repr}

///|
pub fn encode_handshake(
  payload_type : Int32,
  payload : Bytes,
) -> Bytes raise ProtocolError {
  guard payload_type >= 0x10 && payload_type <= 0x15 else {
    raise invalid("not an RMCP+ handshake payload type")
  }
  guard payload.length() <= 1024 else {
    raise invalid("handshake payload too large")
  }
  let out : Array[Byte] = [0x06, 0, 0xff, 0x07, 0x06, byte(payload_type)]
  put32(out, 0U)
  put32(out, 0U)
  out.push(byte(payload.length() & 255))
  out.push(byte(payload.length() >> 8))
  append(out, payload)
  Bytes::from_array(out)
}

///|
pub fn decode_handshake(data : Bytes) -> HandshakePacket raise ProtocolError {
  guard data.length() >= 16 && data.length() <= 1040 else {
    raise invalid("invalid handshake datagram length")
  }
  guard data[0] == 6 &&
    data[1] == 0 &&
    data[2] == 0xff &&
    data[3] == 7 &&
    data[4] == 6 else {
    raise invalid("invalid RMCP+ header")
  }
  let kind = data[5].to_int()
  guard kind >= 0x10 && kind <= 0x15 && u32(data, 6) == 0 && u32(data, 10) == 0 else {
    raise invalid("invalid handshake envelope")
  }
  let length = data[14].to_int() | (data[15].to_int() << 8)
  guard data.length() == 16 + length else {
    raise invalid("RMCP+ payload length mismatch")
  }
  { payload_type: kind, payload: slice(data, 16, data.length()), }
}

///|
/// Open a User-privilege session with cipher suite 17 only:
/// RAKP-HMAC-SHA256, HMAC-SHA256-128, AES-CBC-128. No downgrade negotiation.
pub fn open_session_request(
  tag : Int32,
  console_id : UInt32,
) -> Bytes raise ProtocolError {
  guard tag >= 0 && tag <= 255 && console_id != 0U else {
    raise invalid("invalid session tag or zero console session ID")
  }
  let out : Array[Byte] = [byte(tag), 2, 0, 0]
  put32(out, console_id)
  for (kind, algorithm) in [(0, 3), (1, 4), (2, 1)] {
    out.append([byte(kind), 0, 0, 8, byte(algorithm), 0, 0, 0])
  }
  Bytes::from_array(out)
}

///|
#derive(Eq, @debug.Debug)
pub struct OpenSession {
  bmc_id : UInt32
}

///|
pub extend OpenSession with Eq::{equal, not_equal}

///|
pub extend OpenSession with @debug.Debug::{to_repr}

///|
/// Reject a non-success status, wrong identity, excessive privilege, or downgrade.
pub fn decode_open_session(
  data : Bytes,
  tag : Int32,
  console_id : UInt32,
) -> OpenSession raise ProtocolError {
  guard tag >= 0 && tag <= 255 && console_id != 0U else {
    raise invalid("invalid expected session identity")
  }
  guard data.length() >= 8 else {
    raise invalid("truncated Open Session response")
  }
  guard data[0].to_int() == tag && u32(data, 4) == console_id else {
    raise invalid("Open Session response identity mismatch")
  }
  guard data[1] == 0 else { raise invalid("BMC rejected Open Session") }
  guard data.length() == 36 &&
    data[2] == 2 &&
    data[3] == 0 &&
    u32(data, 8) != 0U else {
    raise invalid("invalid Open Session response")
  }
  for (offset, kind, algorithm) in [(12, 0, 3), (20, 1, 4), (28, 2, 1)] {
    guard data[offset].to_int() == kind &&
      data[offset + 1] == 0 &&
      data[offset + 2] == 0 &&
      data[offset + 3] == 8 &&
      data[offset + 4].to_int() == algorithm &&
      data[offset + 5] == 0 &&
      data[offset + 6] == 0 &&
      data[offset + 7] == 0 else {
      raise invalid("BMC selected an unsupported cipher suite")
    }
  }
  { bmc_id: u32(data, 8), }
}
