///|
fn optional_int(value : Int32?) -> Json {
  match value {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
}

///|
fn optional_text(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
// Synthetic loopback-only example. The command chooses bounded read-only flows.
async fn run_case() -> Unit {
  let args = @env.args()
  guard args.length() == 3 else {
    fail(
      "usage: diagnostics <local mock port> <chassis|fru|sel|fru-timeout|sel-timeout>",
    )
  }
  let port = @string.parse_int(args[1])
  guard port > 0 && port <= 65535 else { fail("invalid local port") }
  let client = @ipmi.Client::connect(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    b"tester",
    b"synthetic-password",
    timeout_ms=1000,
  )
  defer client.abort()
  match args[2] {
    "chassis" => {
      let c = client.chassis_capabilities()
      let status = client.read(GetChassisStatus).chassis_status()
      let cause = client.restart_cause()
      let output : Json = {
        "flags": c.flags,
        "fru_address": c.fru_address,
        "sdr_address": c.sdr_address,
        "sel_address": c.sel_address,
        "system_management_address": c.system_management_address,
        "bridge_address": optional_int(c.bridge_address),
        "power_on": status.power_on,
        "restart_cause": cause.cause,
        "restart_channel": cause.channel,
      }
      println(output.stringify())
    }
    "fru" | "fru-timeout" => {
      let inventory = client.fru_inventory(
        0,
        max_bytes=1024,
        timeout_ms=if args[2] == "fru-timeout" { 200 } else { 10000 },
      )
      for
        (kind, selected) in [
          ("chassis", inventory.chassis),
          ("board", inventory.board),
          ("product", inventory.product),
        ] {
        if selected is Some(area) {
          let fields = area.fields.map(field => {
            match field.text {
              Some(text) => Json::string(text)
              None => Json::null()
            }
          })
          let output : Json = {
            "area": kind,
            "fields": Json::array(fields),
            "chassis_type": optional_int(area.chassis_type),
            "manufacturing_minutes": optional_int(area.manufacturing_minutes),
            "size_bytes": inventory.raw.length(),
          }
          println(output.stringify())
        }
      }
    }
    "sel" | "sel-timeout" => {
      let records = client.sel_records(
        max_records=8,
        timeout_ms=if args[2] == "sel-timeout" { 200 } else { 10000 },
      )
      for record in records {
        let output : Json = match record.event() {
          Some(event) =>
            {
              "id": record.record_id,
              "type": record.record_type,
              "timestamp": event.timestamp.to_double(),
              "generator_id": event.generator_id,
              "revision": event.revision,
              "sensor_type": event.sensor_type,
              "sensor_number": event.sensor_number,
              "event_type": event.event_type,
              "deassertion": event.deassertion,
              "event_data": Json::array(
                event.event_data
                .to_array()
                .map(b => Json::number(b.to_int().to_double())),
              ),
              "threshold": optional_text(event.threshold_description()),
            }
          None =>
            {
              "id": record.record_id,
              "type": record.record_type,
              "raw": Json::array(
                record.raw
                .to_array()
                .map(b => Json::number(b.to_int().to_double())),
              ),
            }
        }
        println(output.stringify())
      }
    }
    _ => fail("unknown read-only scenario")
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
    error => {
      println("FAIL: operation did not complete")
      raise error
    }
  }
}
