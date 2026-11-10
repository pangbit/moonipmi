///|
priv struct Handshake {
  username : Bytes
  password_key : Bytes
  console_id : UInt32
  console_random : Bytes
}

///|
fn handshake(
  username : Bytes,
  password : Bytes,
  console_id : UInt32,
  console_random : Bytes,
) -> Handshake raise ProtocolError {
  guard username.length() >= 1 &&
    username.length() <= 16 &&
    password.length() >= 1 &&
    password.length() <= 20 &&
    console_id != 0U &&
    console_random.length() == 16 else {
    raise invalid(
      "username must contain 1..16 bytes and password 1..20 bytes; nonzero ID and 16 random bytes required",
    )
  }
  let padded = Array::make(20, b'\x00')
  for i in 0..<password.length() {
    padded[i] = password[i]
  }
  {
    username,
    password_key: Bytes::from_array(padded),
    console_id,
    console_random,
  }
}

///|
priv struct SessionKeys {
  sik : Bytes
  k1 : Bytes
  k2 : Bytes
}

///|
fn derive_keys(h : Handshake, challenge : RakpChallenge) -> SessionKeys raise {
  let input : Array[Byte] = []
  append(input, h.console_random)
  append(input, challenge.bmc_random)
  input.append([2, byte(h.username.length())])
  append(input, h.username)
  let sik = @crypto.hmac_sha256(h.password_key, Bytes::from_array(input))
  {
    sik,
    k1: @crypto.hmac_sha256(sik, Bytes::make(20, 1)),
    k2: slice(@crypto.hmac_sha256(sik, Bytes::make(20, 2)), 0, 16),
  }
}

///|
fn verify_rakp2(
  h : Handshake,
  bmc_id : UInt32,
  challenge : RakpChallenge,
) -> SessionKeys raise {
  let input : Array[Byte] = []
  put32(input, h.console_id)
  put32(input, bmc_id)
  append(input, h.console_random)
  append(input, challenge.bmc_random)
  append(input, challenge.bmc_guid)
  input.append([2, byte(h.username.length())])
  append(input, h.username)
  let expected = @crypto.hmac_sha256(h.password_key, Bytes::from_array(input))
  guard @crypto.constant_time_equal(expected, challenge.authentication_code) else {
    raise invalid("RAKP2 authentication failed")
  }
  derive_keys(h, challenge)
}

///|
fn rakp3_code(h : Handshake, challenge : RakpChallenge) -> Bytes raise {
  let input : Array[Byte] = []
  append(input, challenge.bmc_random)
  put32(input, h.console_id)
  input.append([2, byte(h.username.length())])
  append(input, h.username)
  @crypto.hmac_sha256(h.password_key, Bytes::from_array(input))
}

///|
fn verify_rakp4(
  h : Handshake,
  bmc_id : UInt32,
  challenge : RakpChallenge,
  keys : SessionKeys,
  code : Bytes,
) -> Unit raise {
  let input : Array[Byte] = []
  append(input, h.console_random)
  put32(input, bmc_id)
  append(input, challenge.bmc_guid)
  let expected = slice(
    @crypto.hmac_sha256(keys.sik, Bytes::from_array(input)),
    0,
    16,
  )
  guard @crypto.constant_time_equal(expected, code) else {
    raise invalid("RAKP4 authentication failed")
  }
}

///|
fn pad_payload(payload : Bytes) -> Bytes raise ProtocolError {
  guard payload.length() >= 1 && payload.length() <= 1024 else {
    raise invalid("invalid plaintext payload length")
  }
  let padding = (16 - (payload.length() + 1) % 16) % 16
  let out = payload.to_array()
  for i in 1..<=padding {
    out.push(byte(i))
  }
  out.push(byte(padding))
  Bytes::from_array(out)
}

///|
fn unpad_payload(data : Bytes) -> Bytes raise ProtocolError {
  guard data.length() >= 16 && data.length() % 16 == 0 else {
    raise invalid("invalid encrypted payload size")
  }
  let padding = data[data.length() - 1].to_int()
  guard padding <= 15 && padding + 1 < data.length() else {
    raise invalid("invalid IPMI confidentiality padding")
  }
  let end = data.length() - padding - 1
  for i in 0..<padding {
    guard data[end + i].to_int() == i + 1 else {
      raise invalid("invalid IPMI confidentiality padding")
    }
  }
  slice(data, 0, end)
}

///|
fn protect_payload(
  payload : Bytes,
  session_id : UInt32,
  sequence : UInt32,
  keys : SessionKeys,
  iv : Bytes,
) -> Bytes raise {
  guard session_id != 0U && sequence != 0U else {
    raise invalid("zero active session ID or sequence")
  }
  let cipher = @crypto.aes_cbc(true, keys.k2, iv, pad_payload(payload))
  let out : Array[Byte] = [6, 0, 0xff, 7, 6, 0xc0]
  put32(out, session_id)
  put32(out, sequence)
  let length = 16 + cipher.length()
  out.append([byte(length & 255), byte(length >> 8)])
  append(out, iv)
  append(out, cipher)
  let pad = (4 - (out.length() - 4 + 2) % 4) % 4
  for _ in 0..<pad {
    out.push(0xff)
  }
  out.append([byte(pad), 7])
  let mac = @crypto.hmac_sha256(keys.k1, Bytes::from_array(out[4:]))
  append(out, slice(mac, 0, 16))
  Bytes::from_array(out)
}

///|
fn unprotect_payload(
  data : Bytes,
  session_id : UInt32,
  previous_sequence : UInt32,
  keys : SessionKeys,
) -> (UInt32, Bytes) raise {
  guard data.length() >= 66 && data.length() <= 1120 else {
    raise invalid("invalid protected datagram length")
  }
  guard data[0] == 6 &&
    data[1] == 0 &&
    data[2] == 0xff &&
    data[3] == 7 &&
    data[4] == 6 &&
    data[5] == 0xc0 else {
    raise invalid("expected encrypted and authenticated RMCP+ IPMI packet")
  }
  guard u32(data, 6) == session_id && session_id != 0U else {
    raise invalid("session identity mismatch")
  }
  let sequence = u32(data, 10)
  guard sequence != 0U && sequence > previous_sequence else {
    raise invalid("stale session sequence")
  }
  let length = data[14].to_int() | (data[15].to_int() << 8)
  let end = 16 + length
  guard length >= 32 && length % 16 == 0 && end + 18 <= data.length() else {
    raise invalid("invalid confidentiality payload length")
  }
  let authenticated_end = data.length() - 16
  let mac = @crypto.hmac_sha256(keys.k1, slice(data, 4, authenticated_end))
  guard @crypto.constant_time_equal(
    slice(mac, 0, 16),
    slice(data, authenticated_end, data.length()),
  ) else {
    raise invalid("packet integrity check failed")
  }
  // All parsing below is of authenticated bytes. In particular, never expose
  // a CBC padding oracle by decrypting an unauthenticated datagram.
  let padding = data[authenticated_end - 2].to_int()
  guard padding <= 3 &&
    end + padding + 2 == authenticated_end &&
    (authenticated_end - 4) % 4 == 0 &&
    data[authenticated_end - 1] == 7 else {
    raise invalid("invalid integrity trailer")
  }
  for i in end..<(end + padding) {
    guard data[i] == 0xff else { raise invalid("invalid integrity padding") }
  }
  let iv = slice(data, 16, 32)
  let clear = @crypto.aes_cbc(false, keys.k2, iv, slice(data, 32, end))
  (sequence, unpad_payload(clear))
}
