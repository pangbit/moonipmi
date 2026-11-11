///|
/// Explicit wire encodings understood by the ipmitool 1.8.19 reference.
#derive(Eq, @debug.Debug)
pub(all) enum GuidEncoding {
  Ipmi
  Rfc4122
  Smbios
  Dump
}

///|
#derive(Eq, @debug.Debug)
pub struct DeviceGuid {
  raw : Bytes
}

///|
#derive(Eq, @debug.Debug)
pub struct DecodedGuid {
  encoding : GuidEncoding
  value : String
  raw_version : Int32?
  version : Int32?
  unix_seconds : Int64?
}

///|
pub fn Response::device_guid(self : Response) -> DeviceGuid raise ProtocolError {
  let data = command_data(self, "Get Device GUID")
  guard data.length() == 16 else {
    raise invalid("Device GUID must contain 16 bytes")
  }
  { raw: data, }
}

///|
fn guid_text(data : Bytes, dump : Bool) -> String {
  let alphabet = if dump {
    [
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E',
      'F',
    ]
  } else {
    [
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
      'f',
    ]
  }
  let text : Array[Char] = []
  for i in 0..<16 {
    if !dump && (i == 4 || i == 6 || i == 8 || i == 10) {
      text.push('-')
    }
    text.push(alphabet[data[i].to_int() >> 4])
    text.push(alphabet[data[i].to_int() & 15])
  }
  String::from_array(text)
}

///|
pub fn DeviceGuid::decode(
  self : DeviceGuid,
  encoding : GuidEncoding,
) -> DecodedGuid raise ProtocolError {
  guard self.raw.length() == 16 else {
    raise invalid("Device GUID must contain 16 bytes")
  }
  if encoding == Dump {
    return {
      encoding,
      value: guid_text(self.raw, true),
      raw_version: None,
      version: None,
      unix_seconds: None,
    }
  }
  let data = match encoding {
    Ipmi => Bytes::from_array(Array::makei(16, i => self.raw[15 - i]))
    Smbios =>
      Bytes::from_array(
        [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15].map(i => {
          self.raw[i]
        }),
      )
    Rfc4122 | Dump => self.raw
  }
  let raw_version = data[6].to_int() >> 4
  let version = if raw_version <= 5 { raw_version } else { 0 }
  let timestamp = if version == 1 {
    let mut intervals = (data[6].to_uint64() & 15UL) << 56
    intervals = intervals | (data[7].to_uint64() << 48)
    intervals = intervals | (data[4].to_uint64() << 40)
    intervals = intervals | (data[5].to_uint64() << 32)
    for i in 0..<4 {
      intervals = intervals | (data[i].to_uint64() << ((3 - i) * 8))
    }
    Some((intervals / 10000000UL).reinterpret_as_int64() - 12219292800L)
  } else {
    None
  }
  {
    encoding,
    value: guid_text(data, false),
    raw_version: Some(raw_version),
    version: Some(version),
    unix_seconds: timestamp,
  }
}

///|
/// Reference auto-detection is year-dependent. Supply the current UTC year
/// explicitly so callers can reproduce or freeze the decision without hidden I/O.
/// A v1 timestamp in any part of that year is eligible, as in ipmitool 1.8.19.
pub fn DeviceGuid::detect(
  self : DeviceGuid,
  current_year : Int32,
) -> DecodedGuid raise ProtocolError {
  guard current_year >= 1970 && current_year <= 9999 else {
    raise invalid("GUID detection year must be in 1970..9999")
  }
  let days = (current_year - 1969).to_int64() * 365L +
    (current_year / 4 - current_year / 100 + current_year / 400 - 477).to_int64()
  let next_year = days * 86400L
  let mut selected = self.decode(Dump)
  for encoding in [Rfc4122, Ipmi, Smbios] {
    let candidate = self.decode(encoding)
    if candidate.version is Some(version) && version >= 1 && version <= 5 {
      selected = candidate
      if candidate.unix_seconds is Some(seconds) &&
        seconds >= 0L &&
        seconds < next_year {
        break
      }
    }
  }
  selected
}

///|
pub async fn Client::device_guid(self : Client) -> DeviceGuid {
  self.exchange(6, 0x37, b"").device_guid()
}

///|
pub extend GuidEncoding with Eq::{equal, not_equal}

///|
pub extend GuidEncoding with @debug.Debug::{to_repr}

///|
pub extend DeviceGuid with Eq::{equal, not_equal}

///|
pub extend DeviceGuid with @debug.Debug::{to_repr}

///|
pub extend DecodedGuid with Eq::{equal, not_equal}

///|
pub extend DecodedGuid with @debug.Debug::{to_repr}
