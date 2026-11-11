///|
/// Raw IPMI seconds are not silently converted to a calendar date.
#derive(Eq, @debug.Debug)
pub(all) enum SelTime {
  Unspecified
  Relative(UInt32)
  UnixSeconds(UInt32)
}

///|
pub extend SelTime with Eq::{equal, not_equal}

///|
pub extend SelTime with @debug.Debug::{to_repr}

///|
pub fn sel_time(raw : UInt32) -> SelTime {
  if raw == 0xffffffffU {
    Unspecified
  } else if raw < 0x20000000U {
    Relative(raw)
  } else {
    UnixSeconds(raw)
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct SelInfo {
  version : Int32
  entries : Int32
  free_space : Int32
  last_addition : UInt32
  last_erase : UInt32
  operations : Int32
}

///|
pub extend SelInfo with Eq::{equal, not_equal}

///|
pub extend SelInfo with @debug.Debug::{to_repr}

///|
pub fn Response::sel_info(self : Response) -> SelInfo raise ProtocolError {
  let d = command_data(self, "Get SEL Info")
  guard d.length() == 14 && d[0] == 0x51 else {
    raise invalid("invalid or unsupported SEL Info")
  }
  {
    version: d[0].to_int(),
    entries: u16(d, 1),
    free_space: u16(d, 3),
    last_addition: u32(d, 5),
    last_erase: u32(d, 9),
    operations: d[13].to_int(),
  }
}

///|
/// Every 16-byte record is retained verbatim, including OEM/unknown formats.
#derive(Eq, @debug.Debug)
pub struct SelRecord {
  record_id : Int32
  record_type : Int32
  raw : Bytes
}

///|
pub extend SelRecord with Eq::{equal, not_equal}

///|
pub extend SelRecord with @debug.Debug::{to_repr}

///|
pub fn decode_sel_record(raw : Bytes) -> SelRecord raise ProtocolError {
  guard raw.length() == 16 else {
    raise invalid("SEL record must contain 16 bytes")
  }
  { record_id: u16(raw, 0), record_type: raw[2].to_int(), raw, }
}

///|
#derive(Eq, @debug.Debug)
pub struct SelEvent {
  timestamp : UInt32
  generator_id : Int32
  revision : Int32
  sensor_type : Int32
  sensor_number : Int32
  event_type : Int32
  deassertion : Bool
  event_data : Bytes
}

///|
pub extend SelEvent with Eq::{equal, not_equal}

///|
pub extend SelEvent with @debug.Debug::{to_repr}

///|
/// Decode only standard system-event records (type 0x02). OEM records stay raw.
pub fn SelRecord::event(self : SelRecord) -> SelEvent? raise ProtocolError {
  guard self.raw.length() == 16 else {
    raise invalid("SEL record must contain 16 bytes")
  }
  if self.record_type != 2 {
    return None
  }
  let d = self.raw
  Some({
    timestamp: u32(d, 3),
    generator_id: u16(d, 7),
    revision: d[9].to_int(),
    sensor_type: d[10].to_int(),
    sensor_number: d[11].to_int(),
    event_type: d[12].to_int() & 127,
    deassertion: (d[12].to_int() & 128) != 0,
    event_data: slice(d, 13, 16),
  })
}

///|
/// Threshold event direction describes the recorded transition, not live health.
/// OEM/sensor-specific events and unknown event revisions are not interpreted.
pub fn SelEvent::threshold_description(self : SelEvent) -> String? {
  if self.revision != 4 || self.event_type != 1 || self.event_data.length() != 3 {
    return None
  }
  match self.event_data[0].to_int() & 15 {
    0 => Some("Lower Non-critical going low")
    1 => Some("Lower Non-critical going high")
    2 => Some("Lower Critical going low")
    3 => Some("Lower Critical going high")
    4 => Some("Lower Non-recoverable going low")
    5 => Some("Lower Non-recoverable going high")
    6 => Some("Upper Non-critical going low")
    7 => Some("Upper Non-critical going high")
    8 => Some("Upper Critical going low")
    9 => Some("Upper Critical going high")
    10 => Some("Upper Non-recoverable going low")
    11 => Some("Upper Non-recoverable going high")
    _ => None
  }
}

///|
pub async fn Client::sel_info(self : Client) -> SelInfo {
  self.exchange(0x0a, 0x40, b"").sel_info()
}

///|
/// Whole-record reads need no reservation. Reject cycles, identity/count changes,
/// and changed repository timestamps. This is not an atomic snapshot: mutations
/// that preserve count/timestamps can escape detection. No clear/delete/repair.
pub async fn Client::sel_records(
  self : Client,
  max_records~ : Int32 = 256,
  timeout_ms~ : Int32 = 10000,
) -> Array[SelRecord] {
  guard max_records >= 1 && max_records <= 4096 else {
    raise invalid("SEL record limit must be in 1..4096")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let info = self.sel_info()
    guard info.entries <= max_records else {
      raise invalid("SEL repository exceeds record limit")
    }
    let records : Array[SelRecord] = []
    if info.entries == 0 {
      return records
    }
    let seen : Map[Int32, Bool] = Map([])
    let mut id = 0
    while id != 0xffff {
      guard records.length() < info.entries else {
        raise invalid("SEL record count changed or chain is cyclic")
      }
      let data = command_data(
        self.exchange(
          0x0a,
          0x43,
          Bytes::from_array([0, 0, byte(id), byte(id >> 8), 0, 0xff]),
        ),
        "Get SEL Entry",
      )
      guard data.length() == 18 else {
        raise invalid("Get SEL Entry must return a complete record")
      }
      let record = decode_sel_record(slice(data, 2, 18))
      guard record.record_id != 0 &&
        record.record_id != 0xffff &&
        (id == 0 || record.record_id == id) &&
        !seen.contains(record.record_id) else {
        raise invalid("SEL record identity mismatch or repeated record")
      }
      seen[record.record_id] = true
      records.push(record)
      id = u16(data, 0)
    }
    guard records.length() == info.entries else {
      raise invalid("SEL chain ended before advertised record count")
    }
    let after = self.sel_info()
    guard after.entries == info.entries &&
      after.last_addition == info.last_addition &&
      after.last_erase == info.last_erase else {
      raise invalid("SEL repository changed during read")
    }
    records
  })
}
