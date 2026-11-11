///|
fn validate_channel(channel : Int32) -> Unit raise ProtocolError {
  guard (channel >= 0 && channel <= 11) || channel == 14 || channel == 15 else {
    raise invalid("channel must be in 0..11 or 14..15")
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct ChannelInfo {
  channel : Int32
  medium : Int32
  protocol : Int32
  session_support : Int32
  active_sessions : Int32
  vendor_id : Int32
  auxiliary : Bytes
  raw : Bytes
}

///|
pub fn Response::channel_info(
  self : Response,
) -> ChannelInfo raise ProtocolError {
  let d = command_data(self, "Get Channel Info")
  guard d.length() == 9 else {
    raise invalid("Channel Info must contain 9 bytes")
  }
  {
    channel: d[0].to_int() & 15,
    medium: d[1].to_int() & 127,
    protocol: d[2].to_int() & 31,
    session_support: d[3].to_int() >> 6,
    active_sessions: d[3].to_int() & 63,
    vendor_id: u16(d, 4) | (d[6].to_int() << 16),
    auxiliary: slice(d, 7, 9),
    raw: d,
  }
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum ChannelSettings {
  Volatile
  NonVolatile
}

///|
#derive(Eq, @debug.Debug)
pub struct ChannelAccess {
  access_mode : Int32
  alerting_enabled : Bool
  per_message_auth_enabled : Bool
  user_level_auth_enabled : Bool
  privilege_limit : Int32
  raw : Bytes
}

///|
pub fn Response::channel_access(
  self : Response,
) -> ChannelAccess raise ProtocolError {
  let d = command_data(self, "Get Channel Access")
  guard d.length() == 2 else {
    raise invalid("Channel Access must contain 2 bytes")
  }
  let flags = d[0].to_int()
  {
    access_mode: flags & 7,
    alerting_enabled: (flags & 32) == 0,
    per_message_auth_enabled: (flags & 16) == 0,
    user_level_auth_enabled: (flags & 8) == 0,
    privilege_limit: d[1].to_int() & 15,
    raw: d,
  }
}

///|
pub async fn Client::channel_info(
  self : Client,
  channel~ : Int32 = 14,
) -> ChannelInfo {
  validate_channel(channel)
  self.exchange(6, 0x42, Bytes::from_array([byte(channel)])).channel_info()
}

///|
/// Read stored policy; this does not change the current session's privilege.
pub async fn Client::channel_access(
  self : Client,
  settings : ChannelSettings,
  channel~ : Int32 = 14,
) -> ChannelAccess {
  validate_channel(channel)
  let selector : Byte = match settings {
    Volatile => 0x80
    NonVolatile => 0x40
  }
  self
  .exchange(6, 0x41, Bytes::from_array([byte(channel), selector]))
  .channel_access()
}

///|
/// Listing a payload's algorithms does not activate that payload or select a cipher.
#derive(Eq, @debug.Debug)
pub(all) enum CipherPayload {
  Ipmi
  Sol
}

///|
#derive(Eq, @debug.Debug)
pub struct ChannelCipherPage {
  channel : Int32
  raw_channel : Int32
  data : Bytes
}

///|
pub fn Response::channel_cipher_page(
  self : Response,
) -> ChannelCipherPage raise ProtocolError {
  let d = command_data(self, "Get Channel Cipher Suites")
  guard d.length() >= 1 && d.length() <= 17 else {
    raise invalid("Channel Cipher page must contain 1..17 bytes")
  }
  {
    channel: d[0].to_int() & 15,
    raw_channel: d[0].to_int(),
    data: slice(d, 1, d.length()),
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct ChannelCipherSuite {
  suite_id : Int32
  iana : Int32?
  authentication : Int32
  integrity : Int32
  confidentiality : Int32
  raw : Bytes
}

///|
/// Decode complete standard (5-byte) and OEM (8-byte) suite records. Algorithm
/// numbers are identifiers, not a claim that the client implements them.
/// Unknown tags and incomplete records raise instead of returning a prefix.
pub fn decode_channel_cipher_suites(
  data : Bytes,
) -> Array[ChannelCipherSuite] raise ProtocolError {
  guard data.length() <= 1024 else {
    raise invalid("cipher suite data exceeds 1024 bytes")
  }
  let suites : Array[ChannelCipherSuite] = []
  let mut offset = 0
  while offset < data.length() {
    let size = match data[offset] {
      0xc0 => 5
      0xc1 => 8
      _ => raise invalid("unknown cipher suite record tag")
    }
    guard data.length() - offset >= size else {
      raise invalid("incomplete cipher suite record")
    }
    let raw = slice(data, offset, offset + size)
    suites.push({
      suite_id: raw[1].to_int(),
      iana: if size == 8 {
        Some(u16(raw, 2) | (raw[4].to_int() << 16))
      } else {
        None
      },
      authentication: raw[size - 3].to_int() & 63,
      integrity: raw[size - 2].to_int() & 63,
      confidentiality: raw[size - 1].to_int() & 63,
      raw,
    })
    offset += size
  }
  suites
}

///|
#derive(Eq, @debug.Debug)
pub struct ChannelCipherSuites {
  suites : Array[ChannelCipherSuite]
  pages : Array[ChannelCipherPage]
  raw : Bytes
  // False means all 64 protocol pages were full: no short end marker was seen.
  terminated : Bool
}

///|
/// Read at most 64 pages of 16 bytes, with a whole-operation deadline. Preserve
/// every page's reported channel; these payload fields do not select
/// a destination. No retries, authentication fallback or cipher negotiation.
pub async fn Client::channel_cipher_suites(
  self : Client,
  payload : CipherPayload,
  channel~ : Int32 = 14,
  max_bytes~ : Int32 = 1024,
  timeout_ms~ : Int32 = 10000,
) -> ChannelCipherSuites {
  validate_channel(channel)
  guard max_bytes >= 0 && max_bytes <= 1024 else {
    raise invalid("cipher byte limit must be in 0..1024")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let kind : Byte = match payload {
      Ipmi => 0
      Sol => 1
    }
    let pages : Array[ChannelCipherPage] = []
    let data : Array[Byte] = []
    let mut terminated = false
    for index in 0..<64 {
      let page = self
        .exchange(
          6,
          0x54,
          Bytes::from_array([byte(channel), kind, byte(0x80 | index)]),
        )
        .channel_cipher_page()
      guard data.length() + page.data.length() <= max_bytes else {
        raise invalid("cipher list exceeds byte limit")
      }
      pages.push(page)
      append(data, page.data)
      if page.data.length() < 16 {
        terminated = true
        break
      }
    }
    let raw = Bytes::from_array(data)
    { suites: decode_channel_cipher_suites(raw), pages, raw, terminated, }
  })
}

///|
pub extend ChannelInfo with Eq::{equal, not_equal}

///|
pub extend ChannelInfo with @debug.Debug::{to_repr}

///|
pub extend ChannelSettings with Eq::{equal, not_equal}

///|
pub extend ChannelSettings with @debug.Debug::{to_repr}

///|
pub extend ChannelAccess with Eq::{equal, not_equal}

///|
pub extend ChannelAccess with @debug.Debug::{to_repr}

///|
pub extend CipherPayload with Eq::{equal, not_equal}

///|
pub extend CipherPayload with @debug.Debug::{to_repr}

///|
pub extend ChannelCipherPage with Eq::{equal, not_equal}

///|
pub extend ChannelCipherPage with @debug.Debug::{to_repr}

///|
pub extend ChannelCipherSuite with Eq::{equal, not_equal}

///|
pub extend ChannelCipherSuite with @debug.Debug::{to_repr}

///|
pub extend ChannelCipherSuites with Eq::{equal, not_equal}

///|
pub extend ChannelCipherSuites with @debug.Debug::{to_repr}
