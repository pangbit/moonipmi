///|
fn validate_user_id(user_id : Int32) -> Unit raise ProtocolError {
  guard user_id >= 1 && user_id <= 63 else {
    raise invalid("user ID must be in 1..63")
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct UserAccess {
  max_user_ids : Int32
  enabled_user_ids : Int32
  fixed_user_ids : Int32
  enable_status : Int32
  call_in_allowed : Bool
  link_authentication : Bool
  ipmi_messaging : Bool
  privilege_limit : Int32
  raw : Bytes
}

///|
pub fn Response::user_access(self : Response) -> UserAccess raise ProtocolError {
  let d = command_data(self, "Get User Access")
  guard d.length() == 4 else {
    raise invalid("User Access must contain 4 bytes")
  }
  let flags = d[3].to_int()
  {
    max_user_ids: d[0].to_int() & 63,
    enabled_user_ids: d[1].to_int() & 63,
    fixed_user_ids: d[2].to_int() & 63,
    enable_status: d[1].to_int() >> 6,
    call_in_allowed: (flags & 64) == 0,
    link_authentication: (flags & 32) != 0,
    ipmi_messaging: (flags & 16) != 0,
    privilege_limit: flags & 15,
    raw: d,
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct UserName {
  // Bytes before the first NUL; raw retains all 16 bytes, including padding.
  data : Bytes
  raw : Bytes
}

///|
pub fn Response::user_name(self : Response) -> UserName raise ProtocolError {
  let d = command_data(self, "Get User Name")
  guard d.length() == 16 else {
    raise invalid("User Name must contain 16 bytes")
  }
  let mut length = 0
  while length < 16 && d[length] != 0 {
    length += 1
  }
  { data: slice(d, 0, length), raw: d, }
}

///|
/// No implicit character encoding is assumed for non-ASCII names.
pub fn UserName::ascii_text(self : UserName) -> String? {
  if self.data.to_array().any(b => b.to_int() > 127) {
    None
  } else {
    Some(
      String::from_array(
        self.data.to_array().map(b => b.to_int().unsafe_to_char()),
      ),
    )
  }
}

///|
pub async fn Client::user_access(
  self : Client,
  user_id : Int32,
  channel~ : Int32 = 14,
) -> UserAccess {
  validate_user_id(user_id)
  validate_channel(channel)
  self
  .exchange(6, 0x44, Bytes::from_array([byte(channel), byte(user_id)]))
  .user_access()
}

///|
/// Unlike users(), this single-name read exposes completion 0xcc as an error.
pub async fn Client::user_name(self : Client, user_id : Int32) -> UserName {
  validate_user_id(user_id)
  self.exchange(6, 0x46, Bytes::from_array([byte(user_id)])).user_name()
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum UserListMode {
  // ipmitool user list uses the maximum reported by each successive access read.
  FollowMaximum
  // ipmitool channel getaccess uses the maximum reported by the first read.
  InitialMaximum
}

///|
#derive(Eq, @debug.Debug)
pub struct UserRecord {
  user_id : Int32
  access : UserAccess
  // None means Get User Name returned 0xcc, not a successful empty name.
  name : UserName?
}

///|
async fn Client::optional_user_name(
  self : Client,
  user_id : Int32,
) -> UserName? {
  let response = self.exchange(6, 0x46, Bytes::from_array([byte(user_id)]))
  if response.completion_code == 0xcc {
    None
  } else {
    Some(response.user_name())
  }
}

///|
/// Read one user's access and optional name under one overall deadline.
pub async fn Client::user_record(
  self : Client,
  user_id : Int32,
  channel~ : Int32 = 14,
  timeout_ms~ : Int32 = 10000,
) -> UserRecord {
  validate_user_id(user_id)
  validate_channel(channel)
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let access = self.user_access(user_id, channel~)
    let name = self.optional_user_name(user_id)
    { user_id, access, name, }
  })
}

///|
/// Enumerate IDs from 1, even if the first response reports maximum zero,
/// matching the reference's do/while behavior. This is not an atomic snapshot.
/// Name completion 0xcc is retained as None; all other failures abort the local
/// session and return no list. No password testing or user mutations occur.
pub async fn Client::users(
  self : Client,
  channel~ : Int32 = 14,
  mode~ : UserListMode = FollowMaximum,
  max_users~ : Int32 = 63,
  timeout_ms~ : Int32 = 10000,
) -> Array[UserRecord] {
  validate_channel(channel)
  guard max_users >= 1 && max_users <= 63 else {
    raise invalid("user limit must be in 1..63")
  }
  guard timeout_ms >= 1 && timeout_ms <= 60000 else {
    raise invalid("overall timeout must be in 1..60000 ms")
  }
  errdefer self.abort()
  @async.with_timeout(timeout_ms, async fn() {
    let records : Array[UserRecord] = []
    let mut initial_maximum = 0
    let mut user_id = 1
    while user_id <= 63 {
      let access = self.user_access(user_id, channel~)
      if user_id == 1 {
        initial_maximum = access.max_user_ids
      }
      let maximum = match mode {
        FollowMaximum => access.max_user_ids
        InitialMaximum => initial_maximum
      }
      guard maximum <= max_users else {
        raise invalid("user enumeration exceeds user limit")
      }
      let name = self.optional_user_name(user_id)
      records.push({ user_id, access, name, })
      user_id += 1
      if user_id > maximum {
        break
      }
    }
    records
  })
}

///|
pub extend UserAccess with Eq::{equal, not_equal}

///|
pub extend UserAccess with @debug.Debug::{to_repr}

///|
pub extend UserName with Eq::{equal, not_equal}

///|
pub extend UserName with @debug.Debug::{to_repr}

///|
pub extend UserListMode with Eq::{equal, not_equal}

///|
pub extend UserListMode with @debug.Debug::{to_repr}

///|
pub extend UserRecord with Eq::{equal, not_equal}

///|
pub extend UserRecord with @debug.Debug::{to_repr}
