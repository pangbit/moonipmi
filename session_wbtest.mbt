///|
// Synthetic expected values generated independently by tools/vectors.py.
fn synthetic_handshake() -> Handshake raise ProtocolError {
  handshake(
    b"tester",
    b"synthetic-password",
    0x11223344U,
    Bytes::from_array(Array::makei(16, i => byte(i))),
  )
}

///|
fn synthetic_challenge() -> RakpChallenge {
  {
    bmc_random: Bytes::from_array(Array::makei(16, i => byte(i + 16))),
    bmc_guid: Bytes::from_array(Array::makei(16, i => byte(i + 32))),
    authentication_code: b"\x52\x10\xe7\xf8\xac\xaa\x4a\x76\x35\x3a\x4e\xeb\x31\xe3\x3d\xf7\xcb\x5a\x7e\xa2\x92\xc0\x02\x3c\xd2\x5d\x3f\x71\xe4\x3e\xfa\x94",
  }
}

///|
fn reject_any(f : () -> Unit raise) -> Unit raise {
  let failed = try {
    f()
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "suite 17 RAKP and protected packet independent vectors" {
  let h = synthetic_handshake()
  let challenge = synthetic_challenge()
  let keys = verify_rakp2(h, 0x55667788U, challenge)
  assert_eq(
    keys.sik,
    b"\x4a\xdc\xcd\x29\x16\xb7\x58\x9b\xc9\x72\xab\x0b\xbf\x84\x7c\xb2\x9e\x54\x63\xa6\x76\x7d\x00\x2c\xee\x3e\x5e\xa3\x66\x05\x77\xb7",
  )
  assert_eq(
    keys.k1,
    b"\x48\x84\xfe\x39\x99\x0d\xc9\x2f\xcc\x91\x23\x4a\x57\x92\x9b\x43\x7d\xf2\x7e\x35\xd5\x18\x59\x7f\xa9\x72\x58\x48\x7e\x84\x26\xc2",
  )
  assert_eq(
    keys.k2,
    b"\xa2\x18\x0b\x53\x75\x4d\xbc\xa7\x12\xde\x24\x0b\xdf\x66\x0c\x23",
  )
  assert_eq(
    rakp3_code(h, challenge),
    b"\x7e\x7e\x6e\x4f\x26\x2f\xd5\x49\xe7\x23\xca\x8d\x96\xfb\xff\x65\xbe\x4a\x2f\x52\xb3\x96\xe7\x24\x72\xd7\x86\x34\xd3\xb4\xe0\x1b",
  )
  verify_rakp4(
    h, 0x55667788U, challenge, keys, b"\x79\x97\x1f\x3d\x74\x95\xa8\x5b\x3c\xea\xbe\x2d\x0a\xdf\xa2\x5a",
  )
  let plain = encode_request(6, 1, 0, b"")
  let packet = protect_payload(
    plain,
    0x55667788U,
    1U,
    keys,
    Bytes::from_array(Array::makei(16, i => byte(i + 48))),
  )
  assert_eq(
    packet, b"\x06\x00\xff\x07\x06\xc0\x88\x77\x66\x55\x01\x00\x00\x00\x20\x00\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x66\xcf\x19\x4d\x51\x0d\xc9\x7e\x58\x1e\xe0\x92\x65\xcf\x6f\x06\xff\xff\x02\x07\xe4\x74\xb3\x61\x9c\x2d\x7b\xfd\x6c\x3c\xf7\x0e\x0b\x5e\xa8\xa4",
  )
  let (sequence, decoded) = unprotect_payload(packet, 0x55667788U, 0U, keys)
  assert_eq(sequence, 1U)
  assert_eq(decoded, plain)
}

///|
test "protected packets reject tampering, replay, truncation and wrong session" {
  let keys = verify_rakp2(
    synthetic_handshake(),
    0x55667788U,
    synthetic_challenge(),
  )
  let packet = protect_payload(
    encode_request(6, 1, 0, b""),
    0x55667788U,
    3U,
    keys,
    Bytes::make(16, 0),
  )
  for index in 0..<packet.length() {
    let changed = packet.to_array()
    changed[index] = byte(changed[index].to_int() ^ 1)
    reject_any(() => {
      ignore(
        unprotect_payload(Bytes::from_array(changed), 0x55667788U, 0U, keys),
      )
    })
  }
  for length in 0..<packet.length() {
    reject_any(() => {
      ignore(unprotect_payload(slice(packet, 0, length), 0x55667788U, 0U, keys))
    })
  }
  reject_any(() => ignore(unprotect_payload(packet, 0x55667788U, 3U, keys)))
  reject_any(() => ignore(unprotect_payload(packet, 0x55667788U, 4U, keys)))
  reject_any(() => ignore(unprotect_payload(packet, 0x55667789U, 0U, keys)))
  let wrong = synthetic_challenge()
  let altered : RakpChallenge = {
    bmc_random: wrong.bmc_random,
    bmc_guid: wrong.bmc_guid,
    authentication_code: Bytes::make(32, 0),
  }
  reject_any(() => {
    ignore(verify_rakp2(synthetic_handshake(), 0x55667788U, altered))
  })
  reject_any(() => {
    verify_rakp4(
      synthetic_handshake(),
      0x55667788U,
      wrong,
      keys,
      Bytes::make(16, 0),
    )
  })
}

///|
test "IPMI padding covers every residue and rejects altered pad bytes" {
  for size in 1..<=32 {
    let plain = Bytes::make(size, 0xaa)
    let padded = pad_payload(plain)
    assert_eq(padded.length() % 16, 0)
    assert_eq(unpad_payload(padded), plain)
    if padded[padded.length() - 1] != 0 {
      let changed = padded.to_array()
      changed[size] = 0
      reject_any(() => ignore(unpad_payload(Bytes::from_array(changed))))
    }
  }
  reject_any(() => ignore(unpad_payload(Bytes::make(16, 16))))
  reject_any(() => ignore(handshake(b"", b"password", 1U, Bytes::make(16, 0))))
  reject_any(() => ignore(handshake(b"tester", b"", 1U, Bytes::make(16, 0))))
  reject_any(() => {
    ignore(
      @crypto.aes_cbc(true, b"short", Bytes::make(16, 0), Bytes::make(16, 0)),
    )
  })
}
