///|
/// SDR Repository Info (§33.9); timestamps are raw IPMI seconds, not local time.
#derive(Eq, @debug.Debug)
pub struct SdrRepositoryInfo {
  version : Int32
  record_count : Int32
  free_space : Int32
  last_addition : UInt32
  last_erase : UInt32
  operations : Int32
}

///|
pub extend SdrRepositoryInfo with Eq::{equal, not_equal}

///|
pub extend SdrRepositoryInfo with @debug.Debug::{to_repr}

///|
fn command_data(
  response : Response,
  command : String,
) -> Bytes raise ProtocolError {
  guard response.completion_code == 0 else {
    raise invalid(
      "\{command} failed (completion code \{response.completion_code})",
    )
  }
  response.data
}

///|
pub fn Response::sdr_repository_info(
  self : Response,
) -> SdrRepositoryInfo raise ProtocolError {
  let d = command_data(self, "Get SDR Repository Info")
  guard d.length() == 14 else {
    raise invalid("SDR Repository Info must contain 14 bytes")
  }
  guard d[0] == 0x51 || d[0] == 0x02 else {
    raise invalid("unsupported SDR repository version")
  }
  {
    version: d[0].to_int(),
    record_count: u16(d, 1),
    free_space: u16(d, 3),
    last_addition: u32(d, 5),
    last_erase: u32(d, 9),
    operations: d[13].to_int(),
  }
}

///|
pub async fn Client::sdr_repository_info(self : Client) -> SdrRepositoryInfo {
  self.exchange(0x0a, 0x20, b"").sdr_repository_info()
}

///|
fn sdr_request(
  reservation : Int32,
  id : Int32,
  offset : Int32,
  count : Int32,
) -> Bytes {
  Bytes::from_array([
    byte(reservation),
    byte(reservation >> 8),
    byte(id),
    byte(id >> 8),
    byte(offset),
    byte(count),
  ])
}

///|
fn sdr_chunk(
  response : Response,
  count : Int32,
) -> (Int32, Bytes) raise ProtocolError {
  let d = command_data(response, "Get SDR")
  guard d.length() == 2 + count else {
    raise invalid("Get SDR chunk length mismatch")
  }
  (u16(d, 0), slice(d, 2, d.length()))
}

///|
/// Read the SDR repository with a reservation and bounded 16-byte partial reads.
/// Does not rebuild an empty repository, retry lost reservations, or use Device
/// SDRs/bridging. Records are returned only after complete, consistent traversal.
/// max_records defaults to 1024, allowed range 1..4096. Each exchange uses the
/// client's timeout; callers can apply an overall async timeout if needed.
pub async fn Client::sdr_records(
  self : Client,
  max_records~ : Int32 = 1024,
) -> Array[SdrRecord] {
  guard max_records >= 1 && max_records <= 4096 else {
    raise invalid("SDR record limit must be in 1..4096")
  }
  let info = self.sdr_repository_info()
  guard info.record_count <= max_records else {
    raise invalid("SDR repository exceeds record limit")
  }
  if info.record_count == 0 {
    return []
  }
  guard (info.operations & 2) != 0 else {
    raise invalid("SDR reservation support is required for partial reads")
  }
  let reserved = command_data(
    self.exchange(0x0a, 0x22, b""),
    "Reserve SDR Repository",
  )
  guard reserved.length() == 2 && u16(reserved, 0) != 0 else {
    raise invalid("invalid SDR reservation ID")
  }
  let reservation = u16(reserved, 0)
  let result : Array[SdrRecord] = []
  let seen : Map[Int32, Bool] = Map([])
  let mut id = 0
  while id != 0xffff {
    guard result.length() < info.record_count else {
      raise invalid("SDR record count changed or chain is cyclic")
    }
    let (next, header) = sdr_chunk(
      self.exchange(0x0a, 0x23, sdr_request(reservation, id, 0, 5)),
      5,
    )
    let actual_id = u16(header, 0)
    guard actual_id != 0xffff &&
      (id == 0 || actual_id == id) &&
      !seen.contains(actual_id) else {
      raise invalid("SDR record identity mismatch or repeated record")
    }
    seen[actual_id] = true
    let data = header.to_array()
    let length = 5 + header[4].to_int()
    while data.length() < length {
      let offset = data.length()
      let count = (length - offset).min(16)
      let (chunk_next, chunk) = sdr_chunk(
        self.exchange(
          0x0a,
          0x23,
          sdr_request(reservation, actual_id, offset, count),
        ),
        count,
      )
      guard chunk_next == next else {
        raise invalid("SDR next-record ID changed during read")
      }
      append(data, chunk)
    }
    result.push(decode_sdr_record(Bytes::from_array(data)))
    id = next
  }
  guard result.length() == info.record_count else {
    raise invalid("SDR chain ended before advertised record count")
  }
  result
}

///|
/// Read a local unshared sensor using its SDR identity. Unsupported routing is
/// rejected before sending Get Sensor Reading, never silently redirected.
pub async fn Client::read_sensor(
  self : Client,
  sensor : SdrSensor,
) -> SensorReading {
  if sensor.read_support() is Some(reason) {
    raise invalid(reason)
  }
  self.read(GetSensorReading(sensor.number)).sensor_reading()
}
