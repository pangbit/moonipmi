///|
async fn run_network_status_case(
  client : @ipmi.Client,
  parts : Array[StringView],
) -> Unit {
  if parts[0] == "authcap" {
    guard parts.length() == 4 else {
      fail("missing authentication capability query parameters")
    }
    let c = client.channel_auth_capabilities(
      @string.parse_int(parts[2]),
      channel=@string.parse_int(parts[1]),
      version2=parts[3] == "v2",
    )
    let value : Json = {
      "channel": c.channel,
      "auth_types": c.auth_types,
      "v20_data_available": c.v20_data_available,
      "kg_nonzero": c.kg_nonzero,
      "per_message_auth_enabled": c.per_message_auth_enabled,
      "user_level_auth_enabled": c.user_level_auth_enabled,
      "non_null_usernames": c.non_null_usernames,
      "null_usernames": c.null_usernames,
      "anonymous_login": c.anonymous_login,
      "ipmi15_supported": c.ipmi15_supported,
      "ipmi20_supported": c.ipmi20_supported,
      "oem_id": c.oem_id,
      "oem_auxiliary": c.oem_auxiliary,
      "raw": byte_json(c.raw),
    }
    println(value.stringify())
  } else {
    guard parts.length() == 3 else { fail("missing LAN statistics parameters") }
    let c = client.lan_statistics(
      @string.parse_int(parts[1]),
      timeout_ms=@string.parse_int(parts[2]),
    )
    let value : Json = {
      "ip_received": c.ip_received,
      "ip_header_errors": c.ip_header_errors,
      "ip_address_errors": c.ip_address_errors,
      "ip_fragmented": c.ip_fragmented,
      "ip_transmitted": c.ip_transmitted,
      "udp_received": c.udp_received,
      "rmcp_received": c.rmcp_received,
      "udp_proxy_received": c.udp_proxy_received,
      "udp_proxy_dropped": c.udp_proxy_dropped,
      "raw": byte_json(c.raw),
    }
    println(value.stringify())
  }
}
