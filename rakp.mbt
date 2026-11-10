///|
/// Fixed User privilege (02h), name-and-privilege lookup (bit 4 clear).
/// Username is an opaque sequence of 1..16 bytes, not a locale-dependent string.
pub fn rakp1_request(
  tag : Int32,
  bmc_id : UInt32,
  console_random : Bytes,
  username : Bytes,
) -> Bytes raise ProtocolError {
  guard tag >= 0 &&
    tag <= 255 &&
    bmc_id != 0U &&
    console_random.length() == 16 &&
    username.length() >= 1 &&
    username.length() <= 16 else {
    raise invalid("invalid RAKP1 parameters")
  }
  let out : Array[Byte] = [byte(tag), 0, 0, 0]
  put32(out, bmc_id)
  append(out, console_random)
  out.append([2, 0, 0, byte(username.length())])
  append(out, username)
  Bytes::from_array(out)
}

///|
/// Parsed, NOT authenticated RAKP2 challenge. Callers must authenticate it
/// before sending RAKP3. Parsing alone does not establish a trusted session.
pub struct RakpChallenge {
  bmc_random : Bytes
  bmc_guid : Bytes
  authentication_code : Bytes
}

///|
pub fn decode_rakp2(
  data : Bytes,
  tag : Int32,
  console_id : UInt32,
) -> RakpChallenge raise ProtocolError {
  guard tag >= 0 && tag <= 255 && console_id != 0U else {
    raise invalid("invalid expected session identity")
  }
  guard data.length() >= 8 else { raise invalid("truncated RAKP2") }
  guard data[0].to_int() == tag &&
    u32(data, 4) == console_id &&
    data[2] == 0 &&
    data[3] == 0 else {
    raise invalid("RAKP2 response identity mismatch")
  }
  guard data[1] == 0 else { raise invalid("BMC rejected RAKP1") }
  guard data.length() == 72 else {
    raise invalid("suite 17 RAKP2 must contain 72 bytes")
  }
  {
    bmc_random: slice(data, 8, 24),
    bmc_guid: slice(data, 24, 40),
    authentication_code: slice(data, 40, 72),
  }
}

///|
/// Encode a suite 17 RAKP3 packet. Authentication code must already have been
/// calculated after successful RAKP2 verification. This function does not verify it.
pub fn rakp3_request(
  tag : Int32,
  bmc_id : UInt32,
  authentication_code : Bytes,
) -> Bytes raise ProtocolError {
  guard tag >= 0 &&
    tag <= 255 &&
    bmc_id != 0U &&
    authentication_code.length() == 32 else {
    raise invalid("invalid suite 17 RAKP3 parameters")
  }
  let out : Array[Byte] = [byte(tag), 0, 0, 0]
  put32(out, bmc_id)
  append(out, authentication_code)
  Bytes::from_array(out)
}

///|
/// Return the unverified suite 17 RAKP4 integrity value. A session may only
/// become active after a constant-time comparison to the calculated value.
pub fn decode_rakp4(
  data : Bytes,
  tag : Int32,
  console_id : UInt32,
) -> Bytes raise ProtocolError {
  guard tag >= 0 && tag <= 255 && console_id != 0U else {
    raise invalid("invalid expected session identity")
  }
  guard data.length() >= 8 else { raise invalid("truncated RAKP4") }
  guard data[0].to_int() == tag &&
    u32(data, 4) == console_id &&
    data[2] == 0 &&
    data[3] == 0 else {
    raise invalid("RAKP4 response identity mismatch")
  }
  guard data[1] == 0 else { raise invalid("BMC rejected RAKP3") }
  guard data.length() == 24 else {
    raise invalid("suite 17 RAKP4 must contain 24 bytes")
  }
  slice(data, 8, 24)
}
