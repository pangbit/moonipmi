///|
/// Read-only commands exposed by the intended high-level client.
/// No arbitrary command dispatch is exposed by this enum.
#derive(Eq, @debug.Debug)
pub(all) enum ReadCommand {
  GetDeviceId
  GetChassisStatus
  GetSensorReading(Byte)
}

///|
pub extend ReadCommand with Eq::{equal, not_equal}

///|
pub extend ReadCommand with @debug.Debug::{to_repr}

///|
pub fn ReadCommand::encode(
  self : ReadCommand,
  sequence : Int32,
) -> Bytes raise ProtocolError {
  match self {
    GetDeviceId => encode_request(6, 1, sequence, b"")
    GetChassisStatus => encode_request(0, 1, sequence, b"")
    GetSensorReading(sensor) =>
      encode_request(4, 0x2d, sequence, Bytes::from_array([sensor]))
  }
}

///|
pub fn ReadCommand::decode(
  self : ReadCommand,
  data : Bytes,
  sequence : Int32,
) -> Response raise ProtocolError {
  match self {
    GetDeviceId => decode_response(data, 6, 1, sequence)
    GetChassisStatus => decode_response(data, 0, 1, sequence)
    GetSensorReading(_) => decode_response(data, 4, 0x2d, sequence)
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct ChassisStatus {
  power_on : Bool
  power_overload : Bool
  power_interlock : Bool
  power_fault : Bool
  power_control_fault : Bool
  restore_policy : Int32
  last_power_event : Int32
  misc_status : Int32
  front_panel_buttons : Int32?
}

///|
pub extend ChassisStatus with Eq::{equal, not_equal}

///|
pub extend ChassisStatus with @debug.Debug::{to_repr}

///|
pub fn Response::chassis_status(
  self : Response,
) -> ChassisStatus raise ProtocolError {
  guard self.completion_code == 0 else {
    raise invalid("Get Chassis Status returned a failure completion code")
  }
  let d = self.data
  guard d.length() == 3 || d.length() == 4 else {
    raise invalid("Get Chassis Status payload must contain 3 or 4 bytes")
  }
  let flags = d[0].to_int()
  {
    power_on: (flags & 1) != 0,
    power_overload: (flags & 2) != 0,
    power_interlock: (flags & 4) != 0,
    power_fault: (flags & 8) != 0,
    power_control_fault: (flags & 16) != 0,
    restore_policy: (flags >> 5) & 3,
    last_power_event: d[1].to_int(),
    misc_status: d[2].to_int(),
    front_panel_buttons: if d.length() == 4 {
      Some(d[3].to_int())
    } else {
      None
    },
  }
}

///|
/// Raw reading only. Converting it to physical units requires an SDR record.
#derive(Eq, @debug.Debug)
pub struct SensorReading {
  raw_reading : Int32
  reading_available : Bool
  scanning_enabled : Bool
  events_enabled : Bool
  status_bits : Bytes
}

///|
pub extend SensorReading with Eq::{equal, not_equal}

///|
pub extend SensorReading with @debug.Debug::{to_repr}

///|
pub fn Response::sensor_reading(
  self : Response,
) -> SensorReading raise ProtocolError {
  guard self.completion_code == 0 else {
    raise invalid("Get Sensor Reading returned a failure completion code")
  }
  let d = self.data
  guard d.length() >= 2 && d.length() <= 4 else {
    raise invalid("Get Sensor Reading payload must contain 2..4 bytes")
  }
  let flags = d[1].to_int()
  {
    raw_reading: d[0].to_int(),
    reading_available: (flags & 0x20) == 0,
    scanning_enabled: (flags & 0x40) != 0,
    events_enabled: (flags & 0x80) != 0,
    status_bits: slice(d, 2, d.length()),
  }
}
