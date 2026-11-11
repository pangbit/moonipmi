///|
fn fru_test_checksum(d : Array[Byte], start : Int32, end : Int32) -> Unit {
  d[end - 1] = 0
  d[end - 1] = checksum(d[start:end])
}

///|
fn fru_test_image(kind : Int32, language~ : Int32 = 0) -> Array[Byte] {
  let d : Array[Byte] = Array::make(32, 0)
  d[0] = 1
  d[kind] = 1
  fru_test_checksum(d, 0, 8)
  d[8] = 1
  d[9] = 3
  d[10] = byte(if kind == 2 { 23 } else { language })
  let start = if kind == 3 { 14 } else { 11 }
  if kind == 3 {
    d[11] = 0x34
    d[12] = 0x12
  }
  d[start] = 0xc2
  d[start + 1] = 0x41
  d[start + 2] = 0x42
  let fields = if kind == 2 { 2 } else if kind == 3 { 5 } else { 7 }
  for i in 1..<fields {
    d[start + 2 + i] = 0xc0
  }
  d[start + 2 + fields] = 0xc1
  fru_test_checksum(d, 8, 32)
  d
}

///|
fn fru_test_reject(d : Array[Byte]) -> Unit raise {
  rejected(() => ignore(decode_fru_inventory(Bytes::from_array(d))))
}

///|
test "FRU chassis board product retain fields and raw image" {
  for kind in [2, 3, 4] {
    let bytes = Bytes::from_array(fru_test_image(kind))
    let inventory = decode_fru_inventory(bytes)
    assert_eq(inventory.raw, bytes)
    let selected = if kind == 2 {
      inventory.chassis
    } else if kind == 3 {
      inventory.board
    } else {
      inventory.product
    }
    guard selected is Some(area) else { fail("missing FRU area") }
    assert_eq(area.fields[0].text, Some("AB"))
    assert_eq(area.fields[0].raw, b"AB")
    assert_eq(area.fields[0].encoding, 3)
    if kind == 2 {
      assert_eq(area.chassis_type, Some(23))
    }
    if kind == 3 {
      assert_eq(area.manufacturing_minutes, Some(0x1234))
    }
  }
}

///|
test "FRU unsupported field encodings and language remain raw" {
  for encoding in [0, 1, 2, 3] {
    let d = fru_test_image(4, language=1)
    d[11] = byte((encoding << 6) | 2)
    fru_test_checksum(d, 8, 32)
    guard decode_fru_inventory(Bytes::from_array(d)).product is Some(area) else {
      fail("missing product")
    }
    assert_eq(area.fields[0].text, None)
    assert_eq(area.fields[0].raw, b"AB")
  }
  let d = fru_test_image(4)
  d[12] = 0xff
  fru_test_checksum(d, 8, 32)
  guard decode_fru_inventory(Bytes::from_array(d)).product is Some(area) else {
    fail("missing product")
  }
  assert_eq(area.fields[0].text, None)
}

///|
test "FRU invalid common headers offsets lengths and checksums are rejected" {
  fru_test_reject([])
  for offset in [0, 6, 7, 9, 12, 31] {
    let d = fru_test_image(4)
    d[offset] = byte(d[offset].to_int() + 1)
    fru_test_reject(d)
  }
  for value in [1, 4, 255] {
    let d = fru_test_image(4)
    d[3] = byte(value)
    fru_test_checksum(d, 0, 8)
    fru_test_reject(d)
  }
  let overlap = fru_test_image(4)
  overlap[3] = 2
  fru_test_checksum(overlap, 0, 8)
  fru_test_reject(overlap)
}

///|
test "FRU malformed fields terminators and padding are rejected" {
  for mutation in [0, 1, 2, 3] {
    let d = fru_test_image(4)
    match mutation {
      0 => d[11] = 0xff
      1 => d[20] = 0xc0
      2 => d[11] = 0xc1
      _ => d[30] = 1
    }
    fru_test_checksum(d, 8, 32)
    fru_test_reject(d)
  }
}

///|
test "FRU raw internal-use and checksummed multirecord are retained" {
  let d : Array[Byte] = Array::make(24, 0)
  d[0] = 1
  d[1] = 1
  d[5] = 2
  fru_test_checksum(d, 0, 8)
  d[8] = 1
  d[9] = 0xab
  d[16] = 0xc0
  d[17] = 0x82
  d[18] = 2
  d[19] = 0xfd
  fru_test_checksum(d, 16, 21)
  d[21] = 1
  d[22] = 2
  let inventory = decode_fru_inventory(Bytes::from_array(d))
  assert_eq(inventory.internal_use, Some(b"\x01\xab\x00\x00\x00\x00\x00\x00"))
  assert_eq(inventory.multirecord, Some(Bytes::from_array(d[16:24].to_owned())))
  for index in [8, 17, 20, 21] {
    let changed = d.copy()
    changed[index] = byte(changed[index].to_int() + 1)
    fru_test_reject(changed)
  }
  d[17] = 2
  fru_test_checksum(d, 16, 21)
  fru_test_reject(d)
}
