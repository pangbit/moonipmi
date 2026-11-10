///|
test "OpenSSL3 provider, RFC4231 HMAC and NIST SP800-38A raw CBC" {
  assert_true(@native_crypto.available())
  assert_eq(
    @native_crypto.hmac_sha256(Bytes::make(20, 0x0b), b"Hi There"),
    b"\xb0\x34\x4c\x61\xd8\xdb\x38\x53\x5c\xa8\xaf\xce\xaf\x0b\xf1\x2b\x88\x1d\xc2\x00\xc9\x83\x3d\xa7\x26\xe9\x37\x6c\x2e\x32\xcf\xf7",
  )
  let key = b"\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c"
  let iv = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
  let plain = b"\x6b\xc1\xbe\xe2\x2e\x40\x9f\x96\xe9\x3d\x7e\x11\x73\x93\x17\x2a"
  let cipher = b"\x76\x49\xab\xac\x81\x19\xb2\x46\xce\xe9\x8e\x9b\x12\xe9\x19\x7d"
  assert_eq(@native_crypto.aes_cbc(true, key, iv, plain), cipher)
  assert_eq(@native_crypto.aes_cbc(false, key, iv, cipher), plain)
  assert_true(@native_crypto.constant_time_equal(plain, plain))
  assert_false(@native_crypto.constant_time_equal(plain, cipher))
  assert_false(@native_crypto.constant_time_equal(plain, b""))
  assert_eq(@native_crypto.random(16).length(), 16)
}
