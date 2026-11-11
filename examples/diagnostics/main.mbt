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
    fail("usage: diagnostics <local mock port> <read-only scenario>")
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
    "self-test" => {
      let result = client.self_test()
      let status = match result.status() {
        Passed => "passed"
        NotImplemented => "not-implemented"
        Corrupted => "corrupted"
        FatalError => "fatal"
        Reserved => "reserved"
        DeviceSpecific => "device-specific"
      }
      let output : Json = {
        "code": result.code,
        "detail": result.detail,
        "status": status,
        "corruption_flags": optional_int(result.corruption_flags()),
      }
      println(output.stringify())
    }
    "enables" => {
      let e = client.global_enables()
      let output : Json = {
        "flags": e.flags,
        "receive_message_queue_interrupt": e.receive_message_queue_interrupt,
        "event_message_buffer_full_interrupt": e.event_message_buffer_full_interrupt,
        "event_message_buffer": e.event_message_buffer,
        "system_event_logging": e.system_event_logging,
        "oem0": e.oem0,
        "oem1": e.oem1,
        "oem2": e.oem2,
      }
      println(output.stringify())
    }
    "watchdog" => {
      let timer = client.watchdog_timer()
      let output : Json = {
        "timer_use": timer.timer_use,
        "timer_use_description": timer.timer_use_description(),
        "running": timer.running,
        "logging_enabled": timer.logging_enabled,
        "timeout_action": timer.timeout_action,
        "timeout_action_description": timer.timeout_action_description(),
        "pre_timeout_interrupt": timer.pre_timeout_interrupt,
        "pre_timeout_interrupt_description": timer.pre_timeout_interrupt_description(),
        "pre_timeout_seconds": timer.pre_timeout_seconds,
        "expiration_flags": timer.expiration_flags,
        "initial_countdown_tenths": timer.initial_countdown_tenths,
        "present_countdown_tenths": timer.present_countdown_tenths,
        "initial_countdown_seconds": timer.initial_countdown_seconds(),
        "present_countdown_seconds": timer.present_countdown_seconds(),
        "raw": Json::array(
          timer.raw.to_array().map(b => Json::number(b.to_int().to_double())),
        ),
      }
      println(output.stringify())
    }
    "poh" => {
      let counter = client.power_on_hours()
      let output : Json = {
        "minutes_per_count": counter.minutes_per_count,
        "count": counter.count.to_double(),
        "total_minutes": counter.total_minutes().to_double(),
      }
      println(output.stringify())
    }
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
        "power_overload": status.power_overload,
        "power_interlock": status.power_interlock,
        "power_fault": status.power_fault,
        "power_control_fault": status.power_control_fault,
        "restore_policy": status.restore_policy,
        "last_power_event": status.last_power_event,
        "misc_status": status.misc_status,
        "front_panel_buttons": optional_int(status.front_panel_buttons),
        "restart_cause": cause.cause,
        "restart_channel": cause.channel,
        "restart_description": optional_text(cause.description()),
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
    "sel-info" => {
      let info = client.sel_info()
      let output : Json = {
        "version": info.version,
        "entries": info.entries,
        "free_space": info.free_space,
        "last_addition": info.last_addition.to_double(),
        "last_erase": info.last_erase.to_double(),
        "operations": info.operations,
      }
      println(output.stringify())
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
    mode => {
      let parts = mode.split(":").to_array()
      if parts.length() == 3 && parts[0] == "guid" {
        let guid = client.device_guid()
        let decoded = match parts[1] {
          "auto" => guid.detect(@string.parse_int(parts[2]))
          "ipmi" => guid.decode(Ipmi)
          "rfc" => guid.decode(Rfc4122)
          "smbios" => guid.decode(Smbios)
          "dump" => guid.decode(Dump)
          _ => fail("unknown GUID encoding")
        }
        let encoding = match decoded.encoding {
          Ipmi => "ipmi"
          Rfc4122 => "rfc"
          Smbios => "smbios"
          Dump => "dump"
        }
        let timestamp = match decoded.unix_seconds {
          Some(seconds) => Json::number(seconds.to_double())
          None => Json::null()
        }
        let output : Json = {
          "raw": Json::array(
            guid.raw.to_array().map(b => Json::number(b.to_int().to_double())),
          ),
          "encoding": encoding,
          "value": decoded.value,
          "raw_version": optional_int(decoded.raw_version),
          "version": optional_int(decoded.version),
          "unix_seconds": timestamp,
        }
        println(output.stringify())
      } else if parts.length() == 4 && parts[0] == "sysinfo" {
        let parameter = match parts[1] {
          "1" => @ipmi.SystemInfoParameter::FirmwareVersion
          "2" => @ipmi.SystemInfoParameter::SystemName
          "3" => @ipmi.SystemInfoParameter::PrimaryOsName
          "4" => @ipmi.SystemInfoParameter::OsName
          "228" => @ipmi.SystemInfoParameter::DellOsVersion
          "222" => @ipmi.SystemInfoParameter::DellUrl
          _ => fail("unknown system information parameter")
        }
        let info = client.system_info(
          parameter,
          max_bytes=@string.parse_int(parts[2]),
          timeout_ms=@string.parse_int(parts[3]),
        )
        let output : Json = {
          "parameter": parameter.selector().to_int(),
          "revision": info.revision,
          "encoding_byte": info.encoding_byte,
          "encoding": info.encoding,
          "data": Json::array(
            info.data.to_array().map(b => Json::number(b.to_int().to_double())),
          ),
          "ascii_text": optional_text(info.ascii_text()),
          "blocks": Json::array(
            info.blocks.map(block => {
              let value : Json = {
                "revision": block.revision,
                "selector": block.selector,
                "data": Json::array(
                  block.data
                  .to_array()
                  .map(b => Json::number(b.to_int().to_double())),
                ),
              }
              value
            }),
          ),
        }
        println(output.stringify())
      } else {
        fail("unknown read-only scenario")
      }
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
    error => {
      println("FAIL: operation did not complete")
      raise error
    }
  }
}
