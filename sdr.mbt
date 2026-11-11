///|
/// One SDR repository record, preserving unsupported record types verbatim.
/// Only SDR version 0x51 (IPMI 1.5/2.0 record format) is decoded.
#derive(Eq, @debug.Debug)
pub struct SdrRecord {
  record_id : Int32
  record_type : Int32
  data : Bytes
}

///|
pub extend SdrRecord with Eq::{equal, not_equal}

///|
pub extend SdrRecord with @debug.Debug::{to_repr}

///|
fn u16(data : Bytes, at : Int32) -> Int32 {
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
pub fn decode_sdr_record(data : Bytes) -> SdrRecord raise ProtocolError {
  guard data.length() >= 5 else { raise invalid("truncated SDR header") }
  guard data[2] == 0x51 else { raise invalid("unsupported SDR record version") }
  guard data.length() == 5 + data[4].to_int() else {
    raise invalid("SDR record length mismatch")
  }
  {
    record_id: u16(data, 0),
    record_type: data[3].to_int(),
    data: slice(data, 5, data.length()),
  }
}

///|
/// Signed M/B and signed four-bit exponents from a Full Sensor record.
#derive(Eq, @debug.Debug)
pub struct SensorConversion {
  linearization : Int32
  m : Int32
  b : Int32
  b_exponent : Int32
  result_exponent : Int32
}

///|
pub extend SensorConversion with Eq::{equal, not_equal}

///|
pub extend SensorConversion with @debug.Debug::{to_repr}

///|
/// Parsed Full (1) or Compact (2) Sensor record. Unknown ID encodings preserve
/// raw_name and return no name. Compact shared-record expansion is not supported.
#derive(Eq, @debug.Debug)
pub struct SdrSensor {
  record_type : Int32
  owner_id : Int32
  owner_lun : Int32
  owner_channel : Int32
  number : Byte
  entity_id : Int32
  entity_instance : Int32
  logical_entity : Bool
  sensor_type : Int32
  event_type : Int32
  name : String?
  raw_name : Bytes
  name_encoding : Int32
  analog_format : Int32
  unit_flags : Int32
  base_unit : Int32
  modifier_unit : Int32
  sharing_count : Int32
  conversion : SensorConversion?
}

///|
pub extend SdrSensor with Eq::{equal, not_equal}

///|
pub extend SdrSensor with @debug.Debug::{to_repr}

///|
fn signed_bits(value : Int32, width : Int32) -> Int32 {
  if (value & (1 << (width - 1))) != 0 {
    value - (1 << width)
  } else {
    value
  }
}

///|
pub fn SdrRecord::sensor(self : SdrRecord) -> SdrSensor? raise ProtocolError {
  guard self.record_type == 1 || self.record_type == 2 else { return None }
  let d = self.data
  let name_offset = if self.record_type == 1 { 42 } else { 26 }
  guard d.length() > name_offset else {
    raise invalid("truncated Full/Compact Sensor SDR")
  }
  let name_code = d[name_offset].to_int()
  let name_length = name_code & 31
  guard name_length <= 16 && d.length() == name_offset + 1 + name_length else {
    raise invalid("invalid SDR sensor ID length")
  }
  let raw_name = slice(d, name_offset + 1, d.length())
  let name_encoding = name_code >> 6
  // Printable ASCII is a safe subset of the 8-bit ASCII/Latin-1 encoding.
  let name = if name_encoding == 3 &&
    raw_name.to_array().all(b => b >= 0x20 && b <= 0x7e) {
    Some(
      String::from_array(
        raw_name.to_array().map(b => b.to_int().unsafe_to_char()),
      ),
    )
  } else {
    None
  }
  let conversion = if self.record_type == 1 {
    Some(SensorConversion::{
      linearization: d[18].to_int(),
      m: signed_bits(d[19].to_int() | ((d[20].to_int() & 0xc0) << 2), 10),
      b: signed_bits(d[21].to_int() | ((d[22].to_int() & 0xc0) << 2), 10),
      b_exponent: signed_bits(d[24].to_int() & 15, 4),
      result_exponent: signed_bits(d[24].to_int() >> 4, 4),
    })
  } else {
    None
  }
  Some({
    record_type: self.record_type,
    owner_id: d[0].to_int(),
    owner_lun: d[1].to_int() & 3,
    owner_channel: d[1].to_int() >> 4,
    number: d[2],
    entity_id: d[3].to_int(),
    entity_instance: d[4].to_int() & 0x7f,
    logical_entity: (d[4].to_int() & 0x80) != 0,
    sensor_type: d[7].to_int(),
    event_type: d[8].to_int(),
    name,
    raw_name,
    name_encoding,
    analog_format: d[15].to_int() >> 6,
    unit_flags: d[15].to_int() & 63,
    base_unit: d[16].to_int(),
    modifier_unit: d[17].to_int(),
    sharing_count: if self.record_type == 2 {
      d[18].to_int() & 15
    } else {
      0
    },
    conversion,
  })
}

///|
/// This initial reader addresses only an unshared sensor at BMC 0x20, channel/LUN 0.
/// Other owners, channels/LUNs and shared Compact records must not be misread as local.
pub fn SdrSensor::read_support(self : SdrSensor) -> String? {
  if self.owner_id != 0x20 || self.owner_lun != 0 || self.owner_channel != 0 {
    Some("unsupported sensor owner/channel/LUN; bridging is not implemented")
  } else if self.sharing_count > 1 {
    Some("shared Compact Sensor expansion is not implemented")
  } else {
    None
  }
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum SensorValue {
  Numeric(Double)
  Discrete
  Unavailable
  ScanningDisabled
  Unsupported(String)
}

///|
pub extend SensorValue with Eq::{equal, not_equal}

///|
pub extend SensorValue with @debug.Debug::{to_repr}

///|
fn power10(exponent : Int32) -> Double {
  let mut result = 1.0
  for _ in 0..<exponent.abs() {
    result *= 10.0
  }
  if exponent < 0 {
    1.0 / result
  } else {
    result
  }
}

///|
/// Convert common linear Full threshold sensors: (M*x+B*10^Bexp)*10^Rexp.
/// Compact/discrete sensors never invent an analog value. Nonlinear/OEM factors
/// are explicitly unsupported; unavailable readings are never replaced by zero.
pub fn SdrSensor::value(
  self : SdrSensor,
  reading : SensorReading,
) -> SensorValue {
  if !reading.reading_available {
    return Unavailable
  }
  if !reading.scanning_enabled {
    return ScanningDisabled
  }
  if self.sharing_count > 1 {
    return Unsupported("shared Compact Sensor expansion is not implemented")
  }
  if self.record_type == 2 || self.analog_format == 3 || self.event_type != 1 {
    return Discrete
  }
  guard self.conversion is Some(conversion) else {
    return Unsupported("missing conversion factors")
  }
  guard conversion.linearization == 0 else {
    return Unsupported("nonlinear/OEM sensor conversion is not implemented")
  }
  let raw = reading.raw_reading
  let value = match self.analog_format {
    0 => raw
    1 => if raw >= 128 { -(255 - raw) } else { raw }
    _ => signed_bits(raw, 8)
  }
  Numeric(
    (
      conversion.m.to_double() * value.to_double() +
      conversion.b.to_double() * power10(conversion.b_exponent)
    ) *
    power10(conversion.result_exponent),
  )
}

///|
fn sensor_unit(code : Int32) -> String? {
  match code {
    0 => Some("unspecified")
    1 => Some("degrees C")
    2 => Some("degrees F")
    3 => Some("degrees K")
    4 => Some("Volts")
    5 => Some("Amps")
    6 => Some("Watts")
    7 => Some("Joules")
    17 => Some("CFM")
    18 => Some("RPM")
    19 => Some("Hz")
    20 => Some("microsecond")
    21 => Some("millisecond")
    22 => Some("second")
    23 => Some("minute")
    24 => Some("hour")
    25 => Some("day")
    _ => None
  }
}

///|
/// Common IPMI unit names with percentage, modifier and rate. Unknown/reserved
/// unit codes return None, with original unit fields retained on the sensor.
pub fn SdrSensor::unit(self : SdrSensor) -> String? {
  let relation = (self.unit_flags >> 1) & 3
  let rate = self.unit_flags >> 3
  guard relation != 3 && rate != 7 else { return None }
  guard sensor_unit(self.base_unit) is Some(base) else { return None }
  let percent = (self.unit_flags & 1) != 0
  let mut label = if percent && self.base_unit == 0 && relation == 0 {
    "percent"
  } else {
    (if percent { "% " } else { "" }) + base
  }
  if relation != 0 {
    guard sensor_unit(self.modifier_unit) is Some(modifier) else { return None }
    label += (if relation == 1 { "/" } else { "*" }) + modifier
  }
  if rate != 0 {
    let rates = ["", "/us", "/ms", "/s", "/min", "/hour", "/day"]
    label += rates[rate]
  }
  Some(label)
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum SensorState {
  Unavailable
  ScanningDisabled
  MissingStatus
  Threshold(Int32)
  Discrete(Int32)
}

///|
pub extend SensorState with Eq::{equal, not_equal}

///|
pub extend SensorState with @debug.Debug::{to_repr}

///|
/// Threshold bits 0..5 are LNC/LCR/LNR/UNC/UCR/UNR. Discrete bits 0..14
/// remain an event-type-specific mask, not a generic healthy/fault boolean.
pub fn SdrSensor::state(
  self : SdrSensor,
  reading : SensorReading,
) -> SensorState {
  if !reading.reading_available {
    return Unavailable
  }
  if !reading.scanning_enabled {
    return ScanningDisabled
  }
  let d = reading.status_bits
  if self.event_type == 1 {
    if d.length() < 1 {
      MissingStatus
    } else {
      Threshold(d[0].to_int() & 63)
    }
  } else if d.length() < 2 {
    MissingStatus
  } else {
    Discrete(u16(d, 0) & 0x7fff)
  }
}

///|
/// ipmitool-style threshold severity, preserving the full mask in Threshold.
/// Unavailable/missing/discrete states return None, never "ok".
pub fn SensorState::threshold_status(self : SensorState) -> String? {
  guard self is Threshold(mask) else { return None }
  Some(
    if (mask & 0x24) != 0 {
      "nr"
    } else if (mask & 0x12) != 0 {
      "cr"
    } else if (mask & 0x09) != 0 {
      "nc"
    } else {
      "ok"
    },
  )
}

///|
/// Common discrete event names; None means an unknown bit or event/sensor type.
/// The input is an asserted bit offset (0..14), not a raw sensor reading.
pub fn SdrSensor::discrete_state_name(
  self : SdrSensor,
  offset : Int32,
) -> String? {
  if self.event_type == 0x09 {
    match offset {
      0 => Some("Device Absent")
      1 => Some("Device Present")
      _ => None
    }
  } else if self.event_type == 0x6f && self.sensor_type == 0x05 {
    let names = [
      "General Chassis intrusion", "Drive Bay intrusion", "I/O Card area intrusion",
      "Processor area intrusion", "System unplugged from LAN", "Unauthorized dock",
      "FAN area intrusion",
    ]
    if offset >= 0 && offset < names.length() {
      Some(names[offset])
    } else {
      None
    }
  } else if self.event_type == 0x6f && self.sensor_type == 0x08 {
    let names = [
      "Presence detected", "Failure detected", "Predictive failure", "Power Supply AC lost",
      "AC lost or out-of-range", "AC out-of-range, but present", "Config Error",
    ]
    if offset >= 0 && offset < names.length() {
      Some(names[offset])
    } else {
      None
    }
  } else {
    None
  }
}
