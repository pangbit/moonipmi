///|
fn bytes_json(value : Bytes?) -> String {
  match value {
    None => "null"
    Some(data) =>
      "[" + data.to_array().map(b => b.to_int().to_string()).join(",") + "]"
  }
}

///|
// Validation adapter: fixed loopback destination and public synthetic credentials.
// One read per invocation keeps the same fixture comparable across clients.
async fn run_case() -> Unit {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: comparison <local mock port> <scenario>")
  }
  let port = @string.parse_int(args[1])
  guard port >= 1 && port <= 65535 else { fail("invalid local port") }
  let scenario = args[2]
  guard scenario == "device" ||
    scenario == "device-extended" ||
    scenario == "chassis-faults" ||
    scenario == "sensor-unavailable" ||
    scenario == "sensor-disabled" ||
    scenario == "sensor-events-disabled" ||
    scenario == "chassis" ||
    scenario == "sensor" ||
    scenario == "bad-password" ||
    scenario == "completion" else {
    fail("unknown synthetic comparison case")
  }
  let password = if scenario == "bad-password" {
    b"wrong-synthetic-key"
  } else {
    b"synthetic-password"
  }
  let client = @ipmi.Client::connect(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    b"tester",
    password,
    timeout_ms=1000,
  )
  defer client.abort()
  match scenario {
    "device" | "device-extended" | "bad-password" => {
      let d = client.read(GetDeviceId).device_id()
      println(
        "{\"device_id\":\{d.device_id},\"device_revision\":\{d.device_revision},\"firmware_major\":\{d.firmware_major},\"firmware_minor\":\{(d.firmware_minor_bcd >> 4) * 10 + (d.firmware_minor_bcd & 15)},\"ipmi_major\":\{d.ipmi_major},\"ipmi_minor\":\{d.ipmi_minor},\"manufacturer_id\":\{d.manufacturer_id},\"product_id\":\{d.product_id},\"firmware_available\":\{d.firmware_available},\"provides_device_sdrs\":\{d.provides_device_sdrs},\"additional_device_support\":\{d.additional_device_support},\"auxiliary_firmware\":\{bytes_json(d.auxiliary_firmware)}}",
      )
    }
    "chassis" | "chassis-faults" => {
      let c = client.read(GetChassisStatus).chassis_status()
      println(
        "{\"power_on\":\{c.power_on},\"power_overload\":\{c.power_overload},\"power_interlock\":\{c.power_interlock},\"power_fault\":\{c.power_fault},\"power_control_fault\":\{c.power_control_fault},\"restore_policy\":\{c.restore_policy},\"intrusion_active\":\{c.intrusion_active()},\"front_panel_lockout\":\{c.front_panel_lockout()},\"drive_fault\":\{c.drive_fault()},\"cooling_fan_fault\":\{c.cooling_fan_fault()}}",
      )
    }
    _ => {
      let sensor : Byte = if scenario == "completion" { 0xfe } else { 0x2a }
      let s = client.read(GetSensorReading(sensor)).sensor_reading()
      let usable = match s.usable_raw_reading() {
        Some(value) => value.to_string()
        None => "null"
      }
      println(
        "{\"raw_reading\":\{s.raw_reading},\"reading_available\":\{s.reading_available},\"scanning_enabled\":\{s.scanning_enabled},\"events_enabled\":\{s.events_enabled},\"status_bits\":\{bytes_json(Some(s.status_bits))},\"usable_raw_reading\":\{usable}}",
      )
    }
  }
  client.close()
}

///|
async fn main {
  run_case() catch {
    @ipmi.ProtocolError(message) as error => {
      println("FAIL: \{message}")
      raise error
    }
    error => raise error
  }
}
