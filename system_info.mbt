///|
/// String parameters exposed by ipmitool 1.8.19 mc getsysinfo.
#derive(Eq, @debug.Debug)
pub(all) enum SystemInfoParameter {
  FirmwareVersion
  SystemName
  PrimaryOsName
  OsName
  DellOsVersion
  DellUrl
}

///|
pub fn SystemInfoParameter::selector(self : SystemInfoParameter) -> Byte {
  match self {
    FirmwareVersion => 1
    SystemName => 2
    PrimaryOsName => 3
    OsName => 4
    DellOsVersion => 0xe4
    DellUrl => 0xde
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct SystemInfoBlock {
  revision : Int32
  selector : Int32
  data : Bytes
}

///|
pub fn Response::system_info_block(
  self : Response,
) -> SystemInfoBlock raise ProtocolError {
  let d = command_data(self, "Get System Info Parameters")
  guard d.length() == 18 else {
    raise invalid("System Info string block must contain 18 bytes")
  }
  { revision: d[0].to_int(), selector: d[1].to_int(), data: slice(d, 2, 18), }
}

///|
#derive(Eq, @debug.Debug)
pub struct SystemInfoString {
  parameter : SystemInfoParameter
  revision : Int32
  encoding_byte : Int32
  encoding : Int32
  data : Bytes
  blocks : Array[SystemInfoBlock]
}

///|
/// Interpret encoding zero only when every byte is ASCII. Embedded NUL is
/// preserved; it does not truncate the returned string or the raw data.
pub fn SystemInfoString::ascii_text(self : SystemInfoString) -> String? {
  if self.encoding != 0 || self.data.to_array().any(b => b.to_int() > 127) {
    None
  } else {
    Some(
      String::from_array(
        self.data.to_array().map(b => b.to_int().unsafe_to_char()),
      ),
    )
  }
}

///|
/// Read one of the six named string parameters, in 14-byte then 16-byte chunks.
/// Bounded to the advertised length (0..255) and one overall deadline. This does
/// not lock configuration or provide an atomic snapshot. No partial result is
/// returned on a failed block, inconsistent revision/selector, or timeout.
pub async fn Client::system_info(
  self : Client,
  parameter : SystemInfoParameter,
  max_bytes~ : Int32 = 255,
  timeout_ms~ : Int32 = 10000,
) -> SystemInfoString {
  guard max_bytes >= 0 && max_bytes <= 255 else {
    raise invalid("System Info byte limit must be in 0..255")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let first = self
      .exchange(6, 0x59, Bytes::from_array([0, parameter.selector(), 0, 0]))
      .system_info_block()
    guard first.selector == 0 else {
      raise invalid("System Info selector mismatch")
    }
    let length = first.data[1].to_int()
    guard length <= max_bytes else {
      raise invalid("System Info exceeds byte limit")
    }
    let blocks = [first]
    let data = slice(first.data, 2, 2 + length.min(14)).to_array()
    while data.length() < length {
      let selector = blocks.length()
      let block = self
        .exchange(
          6,
          0x59,
          Bytes::from_array([0, parameter.selector(), byte(selector), 0]),
        )
        .system_info_block()
      guard block.selector == selector else {
        raise invalid("System Info selector mismatch")
      }
      guard block.revision == first.revision else {
        raise invalid("System Info revision changed")
      }
      append(data, slice(block.data, 0, (length - data.length()).min(16)))
      blocks.push(block)
    }
    {
      parameter,
      revision: first.revision,
      encoding_byte: first.data[0].to_int(),
      encoding: first.data[0].to_int() & 15,
      data: Bytes::from_array(data),
      blocks,
    }
  })
}

///|
pub extend SystemInfoParameter with Eq::{equal, not_equal}

///|
pub extend SystemInfoParameter with @debug.Debug::{to_repr}

///|
pub extend SystemInfoBlock with Eq::{equal, not_equal}

///|
pub extend SystemInfoBlock with @debug.Debug::{to_repr}

///|
pub extend SystemInfoString with Eq::{equal, not_equal}

///|
pub extend SystemInfoString with @debug.Debug::{to_repr}
