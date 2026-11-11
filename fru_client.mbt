///|
#derive(Eq, @debug.Debug)
pub struct FruInfo {
  size_bytes : Int32
  word_access : Bool
}

///|
pub extend FruInfo with Eq::{equal, not_equal}

///|
pub extend FruInfo with @debug.Debug::{to_repr}

///|
pub fn Response::fru_info(self : Response) -> FruInfo raise ProtocolError {
  let d = command_data(self, "Get FRU Inventory Area Info")
  guard d.length() == 3 && (d[2].to_int() & 0xfe) == 0 else {
    raise invalid("invalid FRU Inventory Area Info")
  }
  // The inventory size is in bytes even on word-access devices (§34.1).
  { size_bytes: u16(d, 0), word_access: d[2] == 1, }
}

///|
pub async fn Client::fru_info(self : Client, device_id : Byte) -> FruInfo {
  self.exchange(0x0a, 0x10, Bytes::from_array([device_id])).fru_info()
}

///|
/// Read one explicitly selected local FRU device. No SDR discovery or bridging.
/// At most max_bytes (8..65535, default 8192), in 16-byte chunks, within an
/// overall timeout (1..60000 ms, default 10000). No retries or partial results.
pub async fn Client::fru_inventory(
  self : Client,
  device_id : Byte,
  max_bytes~ : Int32 = 8192,
  timeout_ms~ : Int32 = 10000,
) -> FruInventory {
  guard max_bytes >= 8 && max_bytes <= 65535 else {
    raise invalid("FRU byte limit must be in 8..65535")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let info = self.fru_info(device_id)
    guard info.size_bytes >= 8 && info.size_bytes <= max_bytes else {
      raise invalid("FRU inventory exceeds byte limit or is too small")
    }
    guard !info.word_access || info.size_bytes % 2 == 0 else {
      raise invalid("word-access FRU size must be even")
    }
    let data : Array[Byte] = []
    while data.length() < info.size_bytes {
      let count = (info.size_bytes - data.length()).min(16)
      let offset = if info.word_access {
        data.length() / 2
      } else {
        data.length()
      }
      let request = Bytes::from_array([
        device_id,
        byte(offset),
        byte(offset >> 8),
        byte(count),
      ])
      let chunk = command_data(
        self.exchange(0x0a, 0x11, request),
        "Read FRU Data",
      )
      guard chunk.length() >= 1 else {
        raise invalid("missing FRU returned count")
      }
      // Response count is access units; request count above is always bytes.
      let returned = chunk[0].to_int() * (if info.word_access { 2 } else { 1 })
      guard returned > 0 && returned <= count && chunk.length() == returned + 1 else {
        raise invalid("FRU returned count or length mismatch")
      }
      append(data, slice(chunk, 1, chunk.length()))
    }
    decode_fru_inventory(Bytes::from_array(data))
  })
}
