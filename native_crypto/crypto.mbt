///|
pub suberror CryptoError {
  CryptoError
}

///|
extern "C" fn version() -> Bool = "moonipmi_crypto_version"

///|
#borrow(out)
extern "C" fn random_ffi(out : FixedArray[Byte], length : Int32) -> Bool = "moonipmi_random"

///|
#borrow(key, message, out)
extern "C" fn hmac_ffi(
  key : Bytes,
  key_length : Int32,
  message : Bytes,
  message_length : Int32,
  out : FixedArray[Byte],
) -> Bool = "moonipmi_hmac"

///|
#borrow(key, iv, input, out)
extern "C" fn cbc_ffi(
  encrypt : Bool,
  key : Bytes,
  iv : Bytes,
  input : Bytes,
  length : Int32,
  out : FixedArray[Byte],
) -> Bool = "moonipmi_cbc"

///|
#borrow(a, b)
extern "C" fn equal_ffi(a : Bytes, b : Bytes, length : Int32) -> Bool = "moonipmi_equal"

///|
pub fn available() -> Bool {
  version()
}

///|
pub fn random(length : Int32) -> Bytes raise CryptoError {
  guard length >= 1 && length <= 1024 else { raise CryptoError }
  let out : FixedArray[Byte] = FixedArray::make(length, 0)
  guard random_ffi(out, length) else { raise CryptoError }
  Bytes::from_array(out)
}

///|
pub fn hmac_sha256(key : Bytes, data : Bytes) -> Bytes raise CryptoError {
  guard key.length() >= 1 && key.length() <= 64 && data.length() <= 2048 else {
    raise CryptoError
  }
  let out : FixedArray[Byte] = FixedArray::make(32, 0)
  guard hmac_ffi(key, key.length(), data, data.length(), out) else {
    raise CryptoError
  }
  Bytes::from_array(out)
}

///|
/// Raw CBC only: caller owns protocol padding and must authenticate before decrypting.
pub fn aes_cbc(
  encrypt : Bool,
  key : Bytes,
  iv : Bytes,
  data : Bytes,
) -> Bytes raise CryptoError {
  guard key.length() == 16 &&
    iv.length() == 16 &&
    data.length() >= 16 &&
    data.length() <= 2048 &&
    data.length() % 16 == 0 else {
    raise CryptoError
  }
  let out : FixedArray[Byte] = FixedArray::make(data.length() + 16, 0)
  guard cbc_ffi(encrypt, key, iv, data, data.length(), out) else {
    raise CryptoError
  }
  Bytes::from_array(Array::makei(data.length(), i => out[i]))
}

///|
pub fn constant_time_equal(a : Bytes, b : Bytes) -> Bool {
  a.length() == b.length() && equal_ffi(a, b, a.length())
}
