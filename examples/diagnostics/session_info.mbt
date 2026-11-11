///|
fn session_info_json(info : @ipmi.SessionInfo) -> Json {
  let details = match info.details {
    None => Json::null()
    Some(d) => {
      let connection : Json = match d.connection {
        HeaderOnly => { "kind": "header-only" }
        Lan(console_ip~, console_mac~, console_port~) =>
          {
            "kind": "lan",
            "ip": byte_json(console_ip),
            "mac": byte_json(console_mac),
            "port": console_port,
          }
        Serial(activity~, destination~, console_ip~, console_port~) =>
          {
            "kind": "serial",
            "activity": activity,
            "destination": destination,
            "ip": byte_json(console_ip),
            "port": optional_int(console_port),
          }
      }
      {
        "user_id": d.user_id,
        "privilege": d.privilege_level,
        "channel": d.channel,
        "auxiliary": d.auxiliary,
        "connection": connection,
      }
    }
  }
  {
    "handle": info.handle,
    "slots": info.slot_count,
    "active": info.active_count,
    "details": details,
    "raw": byte_json(info.raw),
  }
}

///|
async fn run_session_case(
  client : @ipmi.Client,
  parts : Array[StringView],
) -> Unit {
  if parts[0] == "sessions" {
    guard parts.length() == 3 else { fail("missing session list parameters") }
    let entries = client.sessions(
      max_slots=@string.parse_int(parts[1]),
      timeout_ms=@string.parse_int(parts[2]),
    )
    println(
      Json::array(
        entries.map(entry => {
          let value : Json = {
            "slot": entry.slot,
            "completion": entry.completion_code,
            "info": session_info_json(entry.info),
          }
          value
        }),
      ).stringify(),
    )
  } else {
    guard parts.length() == 3 else { fail("missing session selector") }
    let selector = match parts[1] {
      "active" => @ipmi.SessionSelector::Current
      "id" => @ipmi.SessionSelector::Id(@string.parse_uint(parts[2]))
      "handle" => @ipmi.SessionSelector::Handle(@string.parse_int(parts[2]))
      "slot" => @ipmi.SessionSelector::Slot(@string.parse_int(parts[2]))
      _ => fail("unknown session selector")
    }
    println(session_info_json(client.session_info(selector~)).stringify())
  }
}
