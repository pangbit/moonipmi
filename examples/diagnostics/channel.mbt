///|
fn byte_json(data : Bytes) -> Json {
  Json::array(data.to_array().map(b => Json::number(b.to_int().to_double())))
}

///|
fn access_json(value : @ipmi.ChannelAccess) -> Json {
  {
    "mode": value.access_mode,
    "alerting": value.alerting_enabled,
    "per_message_auth": value.per_message_auth_enabled,
    "user_level_auth": value.user_level_auth_enabled,
    "privilege_limit": value.privilege_limit,
    "raw": byte_json(value.raw),
  }
}

///|
async fn run_channel_case(
  client : @ipmi.Client,
  parts : Array[StringView],
) -> Unit {
  guard parts.length() >= 2 else { fail("missing channel") }
  let channel = @string.parse_int(parts[1])
  match parts[0] {
    "channel-info" => {
      let info = client.channel_info(channel~)
      let settings : Array[Json] = []
      if info.medium == 4 || info.medium == 6 {
        settings.push(
          access_json(client.channel_access(Volatile, channel=info.channel)),
        )
        settings.push(
          access_json(client.channel_access(NonVolatile, channel=info.channel)),
        )
      }
      let output : Json = {
        "channel": info.channel,
        "medium": info.medium,
        "protocol": info.protocol,
        "session_support": info.session_support,
        "active_sessions": info.active_sessions,
        "vendor_id": info.vendor_id,
        "auxiliary": byte_json(info.auxiliary),
        "raw": byte_json(info.raw),
        "settings": Json::array(settings),
      }
      println(output.stringify())
    }
    "channel-access" => {
      guard parts.length() == 3 else { fail("missing setting selector") }
      let settings = if parts[2] == "volatile" {
        @ipmi.ChannelSettings::Volatile
      } else {
        @ipmi.ChannelSettings::NonVolatile
      }
      println(
        access_json(client.channel_access(settings, channel~)).stringify(),
      )
    }
    "ciphers" => {
      guard parts.length() == 5 else { fail("missing cipher list parameters") }
      let payload = if parts[2] == "ipmi" {
        @ipmi.CipherPayload::Ipmi
      } else {
        @ipmi.CipherPayload::Sol
      }
      let list = client.channel_cipher_suites(
        payload,
        channel~,
        max_bytes=@string.parse_int(parts[3]),
        timeout_ms=@string.parse_int(parts[4]),
      )
      let output : Json = {
        "raw": byte_json(list.raw),
        "terminated": list.terminated,
        "pages": Json::array(
          list.pages.map(page => {
            let value : Json = {
              "channel": page.channel,
              "raw_channel": page.raw_channel,
              "data": byte_json(page.data),
            }
            value
          }),
        ),
        "suites": Json::array(
          list.suites.map(suite => {
            let value : Json = {
              "id": suite.suite_id,
              "iana": optional_int(suite.iana),
              "authentication": suite.authentication,
              "integrity": suite.integrity,
              "confidentiality": suite.confidentiality,
              "raw": byte_json(suite.raw),
            }
            value
          }),
        ),
      }
      println(output.stringify())
    }
    _ => fail("unknown channel scenario")
  }
}
