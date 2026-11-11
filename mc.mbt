///|
/// Classification of Get Self Test Results, not an IPMI completion code.
#derive(Eq, @debug.Debug)
pub(all) enum SelfTestStatus {
  Passed
  NotImplemented
  Corrupted
  FatalError
  Reserved
  DeviceSpecific
}

///|
#derive(Eq, @debug.Debug)
pub struct SelfTestResult {
  code : Int32
  detail : Int32
}

///|
pub fn SelfTestResult::status(self : SelfTestResult) -> SelfTestStatus {
  match self.code {
    0x55 => Passed
    0x56 => NotImplemented
    0x57 => Corrupted
    0x58 => FatalError
    0xff => Reserved
    _ => DeviceSpecific
  }
}

///|
/// Only result 0x57 defines detail as the standard corruption bitmap.
pub fn SelfTestResult::corruption_flags(self : SelfTestResult) -> Int32? {
  if self.code == 0x57 {
    Some(self.detail)
  } else {
    None
  }
}

///|
pub fn Response::self_test(
  self : Response,
) -> SelfTestResult raise ProtocolError {
  let d = command_data(self, "Get Self Test Results")
  guard d.length() == 2 else {
    raise invalid("Self Test Results must contain 2 bytes")
  }
  { code: d[0].to_int(), detail: d[1].to_int(), }
}

///|
/// Raw flags retain reserved bit 4; the seven defined flags are decoded.
#derive(Eq, @debug.Debug)
pub struct GlobalEnables {
  flags : Int32
  receive_message_queue_interrupt : Bool
  event_message_buffer_full_interrupt : Bool
  event_message_buffer : Bool
  system_event_logging : Bool
  oem0 : Bool
  oem1 : Bool
  oem2 : Bool
}

///|
pub fn Response::global_enables(
  self : Response,
) -> GlobalEnables raise ProtocolError {
  let d = command_data(self, "Get Global Enables")
  guard d.length() == 1 else {
    raise invalid("Global Enables must contain 1 byte")
  }
  let flags = d[0].to_int()
  {
    flags,
    receive_message_queue_interrupt: (flags & 1) != 0,
    event_message_buffer_full_interrupt: (flags & 2) != 0,
    event_message_buffer: (flags & 4) != 0,
    system_event_logging: (flags & 8) != 0,
    oem0: (flags & 0x20) != 0,
    oem1: (flags & 0x40) != 0,
    oem2: (flags & 0x80) != 0,
  }
}

///|
/// Countdown values are unsigned little-endian counts of 100 milliseconds.
/// Reading this status does not reset, stop or configure the watchdog.
#derive(Eq, @debug.Debug)
pub struct WatchdogTimer {
  timer_use : Int32
  running : Bool
  logging_enabled : Bool
  timeout_action : Int32
  pre_timeout_interrupt : Int32
  pre_timeout_seconds : Int32
  expiration_flags : Int32
  initial_countdown_tenths : Int32
  present_countdown_tenths : Int32
  raw : Bytes
}

///|
pub fn Response::watchdog_timer(
  self : Response,
) -> WatchdogTimer raise ProtocolError {
  let d = command_data(self, "Get Watchdog Timer")
  guard d.length() == 8 else {
    raise invalid("Watchdog Timer must contain 8 bytes")
  }
  let use_flags = d[0].to_int()
  let action = d[1].to_int()
  {
    timer_use: use_flags & 7,
    running: (use_flags & 0x40) != 0,
    logging_enabled: (use_flags & 0x80) == 0,
    timeout_action: action & 7,
    pre_timeout_interrupt: (action >> 4) & 7,
    pre_timeout_seconds: d[2].to_int(),
    expiration_flags: d[3].to_int(),
    initial_countdown_tenths: u16(d, 4),
    present_countdown_tenths: u16(d, 6),
    raw: d,
  }
}

///|
pub fn WatchdogTimer::timer_use_description(self : WatchdogTimer) -> String {
  match self.timer_use {
    1 => "BIOS FRB2"
    2 => "BIOS/POST"
    3 => "OS Load"
    4 => "SMS/OS"
    5 => "OEM"
    _ => "Reserved"
  }
}

///|
pub fn WatchdogTimer::timeout_action_description(
  self : WatchdogTimer,
) -> String {
  match self.timeout_action {
    0 => "No action"
    1 => "Hard Reset"
    2 => "Power Down"
    3 => "Power Cycle"
    _ => "Reserved"
  }
}

///|
pub fn WatchdogTimer::pre_timeout_interrupt_description(
  self : WatchdogTimer,
) -> String {
  match self.pre_timeout_interrupt {
    0 => "None"
    1 => "SMI"
    2 => "NMI/Diagnostic"
    3 => "Messaging"
    _ => "Reserved"
  }
}

///|
pub fn WatchdogTimer::initial_countdown_seconds(self : WatchdogTimer) -> Double {
  self.initial_countdown_tenths.to_double() / 10.0
}

///|
pub fn WatchdogTimer::present_countdown_seconds(self : WatchdogTimer) -> Double {
  self.present_countdown_tenths.to_double() / 10.0
}

///|
/// Get stored self-test results; does not initiate a test or reset the BMC.
/// An unhealthy/unsupported test result is returned as data, not a transport error.
pub async fn Client::self_test(self : Client) -> SelfTestResult {
  self.exchange(6, 4, b"").self_test()
}

///|
pub async fn Client::global_enables(self : Client) -> GlobalEnables {
  self.exchange(6, 0x2f, b"").global_enables()
}

///|
pub async fn Client::watchdog_timer(self : Client) -> WatchdogTimer {
  self.exchange(6, 0x25, b"").watchdog_timer()
}

///|
pub extend SelfTestStatus with Eq::{equal, not_equal}

///|
pub extend SelfTestStatus with @debug.Debug::{to_repr}

///|
pub extend SelfTestResult with Eq::{equal, not_equal}

///|
pub extend SelfTestResult with @debug.Debug::{to_repr}

///|
pub extend GlobalEnables with Eq::{equal, not_equal}

///|
pub extend GlobalEnables with @debug.Debug::{to_repr}

///|
pub extend WatchdogTimer with Eq::{equal, not_equal}

///|
pub extend WatchdogTimer with @debug.Debug::{to_repr}
