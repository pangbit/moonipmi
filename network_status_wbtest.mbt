///|
test "authentication capability flags preserve raw values and disabled-bit polarity" {
  for flags in 0..<256 {
    let raw = Bytes::from_array([
      0xfe,
      byte(flags),
      byte(flags),
      byte(flags),
      0x56,
      0x34,
      0x12,
      0xaa,
    ])
    let c = Response::{ completion_code: 0, data: raw, }.channel_auth_capabilities()
    assert_eq(c.channel, 254)
    assert_eq(c.auth_types, flags & 63)
    assert_eq(c.v20_data_available, (flags & 128) != 0)
    assert_eq(c.kg_nonzero, (flags & 32) != 0)
    assert_eq(c.per_message_auth_enabled, (flags & 16) == 0)
    assert_eq(c.user_level_auth_enabled, (flags & 8) == 0)
    assert_eq(c.non_null_usernames, (flags & 4) != 0)
    assert_eq(c.null_usernames, (flags & 2) != 0)
    assert_eq(c.anonymous_login, (flags & 1) != 0)
    assert_eq(c.ipmi15_supported, (flags & 1) != 0)
    assert_eq(c.ipmi20_supported, (flags & 2) != 0)
    assert_eq(c.oem_id, 0x123456)
    assert_eq(c.oem_auxiliary, 170)
    assert_eq(c.raw, raw)
  }
}

///|
test "LAN statistics retain distinct big-endian counters and maximum values" {
  let raw = b"\x00\x00\x00\x01\x01\x00\x12\x34\x80\x00\xff\xff\x00\xff\x01\x02\xab\xcd"
  let c = Response::{ completion_code: 0, data: raw, }.lan_statistics()
  assert_eq(
    [
      c.ip_received,
      c.ip_header_errors,
      c.ip_address_errors,
      c.ip_fragmented,
      c.ip_transmitted,
      c.udp_received,
      c.rmcp_received,
      c.udp_proxy_received,
      c.udp_proxy_dropped,
    ],
    [0, 1, 256, 0x1234, 32768, 65535, 255, 258, 0xabcd],
  )
  assert_eq(c.raw, raw)
}

///|
test "network status decoders enforce lengths completions and command-specific ranges" {
  for
    (size, decode) in [
      (8, (r : Response) => ignore(r.channel_auth_capabilities())),
      (18, (r : Response) => ignore(r.lan_statistics())),
    ] {
    for n in [0, size - 1, size + 1] {
      rejected(() => {
        decode(Response::{ completion_code: 0, data: Bytes::make(n, 0), })
      })
    }
    for code in [0xc1, 0xcc, 0xd4] {
      rejected(() => {
        decode(Response::{ completion_code: code, data: Bytes::make(size, 0), })
      })
    }
  }
  for p in [1, 2, 3, 4, 5, 15] {
    validate_authcap_privilege(p)
  }
  for p in [-1, 0, 6, 14, 16, 255] {
    rejected(() => validate_authcap_privilege(p))
  }
  for c in [1, 11, 12, 13, 14] {
    validate_lan_statistics_channel(c)
  }
  for c in [-1, 0, 15, 16, 256] {
    rejected(() => validate_lan_statistics_channel(c))
  }
}
