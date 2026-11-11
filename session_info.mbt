///|
#derive(Eq, @debug.Debug)
pub(all) enum SessionSelector {
  Current
  Id(UInt32)
  Handle(Int32)
  Slot(Int32)
}

///|
fn SessionSelector::request(
  self : SessionSelector,
) -> Bytes raise ProtocolError {
  match self {
    Current => b"\x00"
    Id(id) => {
      let data : Array[Byte] = [0xff]
      put32(data, id)
      Bytes::from_array(data)
    }
    Handle(handle) => {
      guard handle >= 0 && handle <= 255 else {
        raise invalid("session handle must be in 0..255")
      }
      Bytes::from_array([0xfe, byte(handle)])
    }
    Slot(slot) => {
      guard slot >= 1 && slot <= 63 else {
        raise invalid("session slot must be in 1..63")
      }
      Bytes::from_array([byte(slot)])
    }
  }
}

///|
/// Variant describes the returned byte layout, not the active transport.
#derive(Eq, @debug.Debug)
pub(all) enum SessionConnection {
  HeaderOnly
  Lan(console_ip~ : Bytes, console_mac~ : Bytes, console_port~ : Int32)
  Serial(
    activity~ : Int32,
    destination~ : Int32,
    console_ip~ : Bytes,
    console_port~ : Int32?
  )
}

///|
#derive(Eq, @debug.Debug)
pub struct SessionDetails {
  user_id : Int32
  privilege_level : Int32
  channel : Int32
  auxiliary : Int32
  connection : SessionConnection
}

///|
#derive(Eq, @debug.Debug)
pub struct SessionInfo {
  handle : Int32
  slot_count : Int32
  active_count : Int32
  details : SessionDetails?
  raw : Bytes
}

///|
fn decode_session_info(d : Bytes) -> SessionInfo raise ProtocolError {
  let size = d.length()
  guard size == 3 || size == 6 || size == 12 || size == 14 || size == 18 else {
    raise invalid("Session Info must contain 3, 6, 12, 14 or 18 bytes")
  }
  let details = if size == 3 {
    None
  } else {
    let connection = match size {
      18 =>
        SessionConnection::Lan(
          console_ip=slice(d, 6, 10),
          console_mac=slice(d, 10, 16),
          console_port=u16(d, 16),
        )
      12 | 14 =>
        SessionConnection::Serial(
          activity=d[6].to_int(),
          destination=d[7].to_int() & 15,
          console_ip=slice(d, 8, 12),
          console_port=if size == 14 { Some(u16(d, 12)) } else { None },
        )
      _ => SessionConnection::HeaderOnly
    }
    Some(SessionDetails::{
      user_id: d[3].to_int() & 63,
      privilege_level: d[4].to_int() & 15,
      channel: d[5].to_int() & 15,
      auxiliary: d[5].to_int() >> 4,
      connection,
    })
  }
  {
    handle: d[0].to_int(),
    slot_count: d[1].to_int() & 63,
    active_count: d[2].to_int() & 63,
    details,
    raw: d,
  }
}

///|
pub fn Response::session_info(
  self : Response,
) -> SessionInfo raise ProtocolError {
  decode_session_info(command_data(self, "Get Session Info"))
}

///|
/// Query remote session metadata, without changing or closing that session.
pub async fn Client::session_info(
  self : Client,
  selector~ : SessionSelector = Current,
) -> SessionInfo {
  self.exchange(6, 0x3d, selector.request()).session_info()
}

///|
#derive(Eq, @debug.Debug)
pub struct SessionEntry {
  slot : Int32
  // Enumeration alone permits 0xcb/0xcc with a complete response layout.
  completion_code : Int32
  info : SessionInfo
}

///|
/// Probe slot 1 even when it reports zero slots; follow the latest six-bit
/// slot count like ipmitool session info all. No atomic snapshot is promised.
pub async fn Client::sessions(
  self : Client,
  max_slots~ : Int32 = 63,
  timeout_ms~ : Int32 = 10000,
) -> Array[SessionEntry] {
  guard max_slots >= 1 && max_slots <= 63 else {
    raise invalid("session slot limit must be in 1..63")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let entries : Array[SessionEntry] = []
    let mut slot = 1
    while slot <= 63 {
      let response = self.exchange(
        6,
        0x3d,
        SessionSelector::Slot(slot).request(),
      )
      let info = if response.completion_code == 0xcb ||
        response.completion_code == 0xcc {
        decode_session_info(response.data)
      } else {
        response.session_info()
      }
      guard info.slot_count <= max_slots else {
        raise invalid("session enumeration exceeds slot limit")
      }
      entries.push({ slot, completion_code: response.completion_code, info, })
      slot += 1
      if slot > info.slot_count {
        break
      }
    }
    entries
  })
}

///|
pub extend SessionSelector with Eq::{equal, not_equal}

///|
pub extend SessionSelector with @debug.Debug::{to_repr}

///|
pub extend SessionConnection with Eq::{equal, not_equal}

///|
pub extend SessionConnection with @debug.Debug::{to_repr}

///|
pub extend SessionDetails with Eq::{equal, not_equal}

///|
pub extend SessionDetails with @debug.Debug::{to_repr}

///|
pub extend SessionInfo with Eq::{equal, not_equal}

///|
pub extend SessionInfo with @debug.Debug::{to_repr}

///|
pub extend SessionEntry with Eq::{equal, not_equal}

///|
pub extend SessionEntry with @debug.Debug::{to_repr}
