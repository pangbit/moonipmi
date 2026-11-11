///|
#derive(Eq, @debug.Debug)
pub struct ChannelAuthCapabilities {
  channel : Int32
  auth_types : Int32
  v20_data_available : Bool
  kg_nonzero : Bool
  per_message_auth_enabled : Bool
  user_level_auth_enabled : Bool
  non_null_usernames : Bool
  null_usernames : Bool
  anonymous_login : Bool
  ipmi15_supported : Bool
  ipmi20_supported : Bool
  oem_id : Int32
  oem_auxiliary : Int32
  raw : Bytes
}

///|
pub fn Response::channel_auth_capabilities(
  self : Response,
) -> ChannelAuthCapabilities raise ProtocolError {
  let d = command_data(self, "Get Channel Authentication Capabilities")
  guard d.length() == 8 else {
    raise invalid("Channel Authentication Capabilities must contain 8 bytes")
  }
  let flags = d[2].to_int()
  {
    channel: d[0].to_int(),
    auth_types: d[1].to_int() & 63,
    v20_data_available: (d[1].to_int() & 128) != 0,
    kg_nonzero: (flags & 32) != 0,
    per_message_auth_enabled: (flags & 16) == 0,
    user_level_auth_enabled: (flags & 8) == 0,
    non_null_usernames: (flags & 4) != 0,
    null_usernames: (flags & 2) != 0,
    anonymous_login: (flags & 1) != 0,
    ipmi15_supported: (d[3].to_int() & 1) != 0,
    ipmi20_supported: (d[3].to_int() & 2) != 0,
    oem_id: u16(d, 4) | (d[6].to_int() << 16),
    oem_auxiliary: d[7].to_int(),
    raw: d,
  }
}

///|
fn validate_authcap_privilege(privilege : Int32) -> Unit raise ProtocolError {
  guard (privilege >= 1 && privilege <= 5) || privilege == 15 else {
    raise invalid("capability query privilege must be in 1..5 or 15")
  }
}

///|
/// Query reported capabilities for a privilege, without changing the current
/// session role or enabling any reported algorithm. version2 selects only the
/// query's extended-data bit. No automatic fallback after a failed query.
pub async fn Client::channel_auth_capabilities(
  self : Client,
  privilege : Int32,
  channel~ : Int32 = 14,
  version2~ : Bool = true,
) -> ChannelAuthCapabilities {
  validate_channel(channel)
  validate_authcap_privilege(privilege)
  let selector = if version2 { channel | 128 } else { channel }
  self
  .exchange(6, 0x38, Bytes::from_array([byte(selector), byte(privilege)]))
  .channel_auth_capabilities()
}

///|
#derive(Eq, @debug.Debug)
pub struct LanStatistics {
  ip_received : Int32
  ip_header_errors : Int32
  ip_address_errors : Int32
  ip_fragmented : Int32
  ip_transmitted : Int32
  udp_received : Int32
  rmcp_received : Int32
  udp_proxy_received : Int32
  udp_proxy_dropped : Int32
  raw : Bytes
}

///|
/// Match the pinned reference's big-endian 16-bit counter interpretation;
/// retain all bytes and numeric values, including 65535, without inference.
pub fn Response::lan_statistics(
  self : Response,
) -> LanStatistics raise ProtocolError {
  let d = command_data(self, "Get LAN Statistics")
  guard d.length() == 18 else {
    raise invalid("LAN Statistics must contain 18 bytes")
  }
  let counters = Array::makei(9, i => {
    (d[2 * i].to_int() << 8) | d[2 * i + 1].to_int()
  })
  {
    ip_received: counters[0],
    ip_header_errors: counters[1],
    ip_address_errors: counters[2],
    ip_fragmented: counters[3],
    ip_transmitted: counters[4],
    udp_received: counters[5],
    rmcp_received: counters[6],
    udp_proxy_received: counters[7],
    udp_proxy_dropped: counters[8],
    raw: d,
  }
}

///|
fn validate_lan_statistics_channel(channel : Int32) -> Unit raise ProtocolError {
  // The reference LAN entry point accepts 1..14, including 12/13, unlike
  // the separate channel command's public argument validator.
  guard channel >= 1 && channel <= 14 else {
    raise invalid("LAN statistics channel must be in 1..14")
  }
}

///|
/// Mirror explicit-channel `lan stats get`: two LAN-medium checks then a
/// non-clearing read. Automatic channel discovery is not implemented here.
pub async fn Client::lan_statistics(
  self : Client,
  channel : Int32,
  timeout_ms~ : Int32 = 10000,
) -> LanStatistics {
  validate_lan_statistics_channel(channel)
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    for _ in 0..<2 {
      let info = self
        .exchange(6, 0x42, Bytes::from_array([byte(channel)]))
        .channel_info()
      guard info.medium == 4 || info.medium == 6 else {
        raise invalid("selected channel is not a LAN channel")
      }
    }
    self.exchange(12, 4, Bytes::from_array([byte(channel), 0])).lan_statistics()
  })
}

///|
pub extend ChannelAuthCapabilities with Eq::{equal, not_equal}

///|
pub extend ChannelAuthCapabilities with @debug.Debug::{to_repr}

///|
pub extend LanStatistics with Eq::{equal, not_equal}

///|
pub extend LanStatistics with @debug.Debug::{to_repr}
