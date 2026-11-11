///|
/// Get Chassis Capabilities. Addresses are retained as reported, never followed.
#derive(Eq, @debug.Debug)
pub struct ChassisCapabilities {
  flags : Int32
  fru_address : Int32
  sdr_address : Int32
  sel_address : Int32
  system_management_address : Int32
  bridge_address : Int32?
}

///|
pub extend ChassisCapabilities with Eq::{equal, not_equal}

///|
pub extend ChassisCapabilities with @debug.Debug::{to_repr}

///|
pub fn Response::chassis_capabilities(
  self : Response,
) -> ChassisCapabilities raise ProtocolError {
  let d = command_data(self, "Get Chassis Capabilities")
  guard d.length() == 5 || d.length() == 6 else {
    raise invalid("Chassis Capabilities must contain 5 or 6 bytes")
  }
  {
    flags: d[0].to_int(),
    fru_address: d[1].to_int(),
    sdr_address: d[2].to_int(),
    sel_address: d[3].to_int(),
    system_management_address: d[4].to_int(),
    bridge_address: if d.length() == 6 {
      Some(d[5].to_int())
    } else {
      None
    },
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct RestartCause {
  cause : Int32
  channel : Int32
}

///|
pub extend RestartCause with Eq::{equal, not_equal}

///|
pub extend RestartCause with @debug.Debug::{to_repr}

///|
pub fn Response::restart_cause(
  self : Response,
) -> RestartCause raise ProtocolError {
  let d = command_data(self, "Get System Restart Cause")
  guard d.length() == 2 else {
    raise invalid("Restart Cause must contain 2 bytes")
  }
  { cause: d[0].to_int() & 15, channel: d[1].to_int() & 15, }
}

///|
/// Unknown and OEM-defined causes remain numeric rather than guessed.
pub fn RestartCause::description(self : RestartCause) -> String? {
  match self.cause {
    0 => Some("unknown")
    1 => Some("chassis power control command")
    2 => Some("reset via pushbutton")
    3 => Some("power-up via pushbutton")
    4 => Some("watchdog expired")
    5 => Some("OEM")
    6 => Some("power-up due to always-restore power policy")
    7 => Some("power-up due to restore-previous power policy")
    8 => Some("reset via PEF")
    9 => Some("power-cycle via PEF")
    10 => Some("soft reset")
    11 => Some("power-up via RTC wakeup")
    _ => None
  }
}

///|
pub async fn Client::chassis_capabilities(self : Client) -> ChassisCapabilities {
  self.exchange(0, 0, b"").chassis_capabilities()
}

///|
pub async fn Client::restart_cause(self : Client) -> RestartCause {
  self.exchange(0, 7, b"").restart_cause()
}
