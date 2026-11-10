///|
fn main raise {
  let request = @ipmi.ReadCommand::GetDeviceId.encode(0)
  println("Offline Get Device ID request (no network I/O):")
  println(request)
  let open = @ipmi.open_session_request(7, 0x11223344U)
  let packet = @ipmi.encode_handshake(0x10, open)
  let decoded = @ipmi.decode_handshake(packet)
  println("RMCP+ Open Session payload bytes: \{decoded.payload.length()}")
  println("Cipher suite 17, User privilege. No session has been authenticated.")
}
