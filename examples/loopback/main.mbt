///|
// This example deliberately accepts only a port and always uses loopback with
// synthetic credentials. It cannot be pointed at a real BMC by an argument.
async fn run_demo() -> Unit {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: loopback <local mock port>") }
  let port = @string.parse_int(args[1])
  guard port >= 1 && port <= 65535 else { fail("invalid local port") }
  let client = @ipmi.Client::connect(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    b"tester",
    b"synthetic-password",
  )
  defer client.abort()
  let device = client.read(GetDeviceId).device_id()
  let chassis = client.read(GetChassisStatus).chassis_status()
  let sensor = client.read(GetSensorReading(0x2a)).sensor_reading()
  guard device.manufacturer_id == 343U &&
    device.product_id == 0x1234 &&
    chassis.power_on &&
    sensor.raw_reading == 42 &&
    sensor.reading_available else {
    fail("unexpected synthetic BMC result")
  }
  client.close()
  println(
    "PASS: authenticated suite 17, three read-only commands, graceful close",
  )
}

///|
async fn main {
  run_demo() catch {
    @ipmi.ProtocolError(message) as error => {
      println("FAIL: \{message}")
      raise error
    }
    error => raise error
  }
}
