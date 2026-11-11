///|
// Loopback-only example with public synthetic credentials. Never uses real BMCs.
async fn run_case() -> Unit {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: sdr <local mock port>") }
  let port = @string.parse_int(args[1])
  guard port > 0 && port <= 65535 else { fail("invalid local port") }
  let client = @ipmi.Client::connect(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    b"tester",
    b"synthetic-password",
    timeout_ms=1000,
  )
  defer client.abort()
  let records = client.sdr_records(max_records=64)
  for record in records {
    if record.sensor() is Some(sensor) {
      let reading = client.read_sensor(sensor)
      let (value, value_kind) : (Json, String) = match sensor.value(reading) {
        Numeric(value) => (Json::number(value), "numeric")
        Discrete => (Json::null(), "discrete")
        Unavailable => (Json::null(), "unavailable")
        ScanningDisabled => (Json::null(), "scanning-disabled")
        Unsupported(reason) => (Json::null(), reason)
      }
      let name = sensor.name.unwrap_or("unsupported-name")
      let unit = sensor.unit().unwrap_or("unsupported-unit")
      let state = sensor.state(reading)
      let status = state
        .threshold_status()
        .unwrap_or(
          match state {
            Discrete(_) => "discrete"
            _ => "unavailable"
          },
        )
      let bits : Json = match state {
        Threshold(mask) | Discrete(mask) => Json::number(mask.to_double())
        _ => Json::null()
      }
      // Json serialization escapes even unexpected printable sensor ID characters.
      let output : Json = {
        "record_id": record.record_id,
        "name": name,
        "unit": unit,
        "status": status,
        "value": value,
        "value_kind": value_kind,
        "state_bits": bits,
        "record_type": record.record_type,
      }
      println(output.stringify())
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
