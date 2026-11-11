///|
fn user_access_json(value : @ipmi.UserAccess) -> Json {
  {
    "maximum": value.max_user_ids,
    "enabled": value.enabled_user_ids,
    "fixed": value.fixed_user_ids,
    "enable_status": value.enable_status,
    "call_in_allowed": value.call_in_allowed,
    "link_authentication": value.link_authentication,
    "ipmi_messaging": value.ipmi_messaging,
    "privilege_limit": value.privilege_limit,
    "raw": byte_json(value.raw),
  }
}

///|
fn user_name_json(value : @ipmi.UserName) -> Json {
  {
    "data": byte_json(value.data),
    "raw": byte_json(value.raw),
    "ascii_text": optional_text(value.ascii_text()),
  }
}

///|
fn user_record_json(value : @ipmi.UserRecord) -> Json {
  let name = match value.name {
    Some(name) => user_name_json(name)
    None => Json::null()
  }
  {
    "id": value.user_id,
    "access": user_access_json(value.access),
    "name": name,
  }
}

///|
async fn run_user_case(
  client : @ipmi.Client,
  parts : Array[StringView],
) -> Unit {
  match parts[0] {
    "user-access" => {
      guard parts.length() == 3 else { fail("missing user access parameters") }
      let value = client.user_access(
        @string.parse_int(parts[2]),
        channel=@string.parse_int(parts[1]),
      )
      println(user_access_json(value).stringify())
    }
    "user-name" => {
      guard parts.length() == 2 else { fail("missing user ID") }
      println(
        user_name_json(client.user_name(@string.parse_int(parts[1]))).stringify(),
      )
    }
    "user-record" => {
      guard parts.length() == 4 else { fail("missing user record parameters") }
      let value = client.user_record(
        @string.parse_int(parts[2]),
        channel=@string.parse_int(parts[1]),
        timeout_ms=@string.parse_int(parts[3]),
      )
      println(user_record_json(value).stringify())
    }
    "users" => {
      guard parts.length() == 5 else { fail("missing user list parameters") }
      let mode = if parts[2] == "follow" {
        @ipmi.UserListMode::FollowMaximum
      } else {
        @ipmi.UserListMode::InitialMaximum
      }
      let values = client.users(
        channel=@string.parse_int(parts[1]),
        mode~,
        max_users=@string.parse_int(parts[3]),
        timeout_ms=@string.parse_int(parts[4]),
      )
      println(Json::array(values.map(user_record_json)).stringify())
    }
    _ => fail("unknown user scenario")
  }
}
