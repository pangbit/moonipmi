///|
/// A FRU type/length field. Unsupported encodings remain available in raw.
#derive(Eq, @debug.Debug)
pub struct FruField {
  encoding : Int32
  raw : Bytes
  text : String?
}

///|
pub extend FruField with Eq::{equal, not_equal}

///|
pub extend FruField with @debug.Debug::{to_repr}

///|
/// Fields retain the standard FRU positional order, followed by custom fields.
/// Manufacturing time is minutes since 1996-01-01, with zero meaning unspecified.
#derive(Eq, @debug.Debug)
pub struct FruArea {
  raw : Bytes
  fields : Array[FruField]
  language_code : Int32?
  chassis_type : Int32?
  manufacturing_minutes : Int32?
}

///|
pub extend FruArea with Eq::{equal, not_equal}

///|
pub extend FruArea with @debug.Debug::{to_repr}

///|
/// Internal-use and multirecord contents are preserved, not semantically decoded.
#derive(Eq, @debug.Debug)
pub struct FruInventory {
  raw : Bytes
  chassis : FruArea?
  board : FruArea?
  product : FruArea?
  internal_use : Bytes?
  multirecord : Bytes?
}

///|
pub extend FruInventory with Eq::{equal, not_equal}

///|
pub extend FruInventory with @debug.Debug::{to_repr}

///|
fn fru_sum(data : Bytes, start : Int32, end : Int32) -> Int32 {
  let mut sum = 0
  for i in start..<end {
    sum = (sum + data[i].to_int()) & 255
  }
  sum
}

///|
fn fru_area(
  data : Bytes,
  start : Int32,
  limit : Int32,
  kind : Int32,
) -> FruArea raise ProtocolError {
  guard limit - start >= 2 && data[start] == 1 else {
    raise invalid("invalid FRU area format")
  }
  let length = data[start + 1].to_int() * 8
  let first_field = if kind == 3 { 6 } else { 3 }
  guard length >= 8 && length <= limit - start else {
    raise invalid("FRU area exceeds boundary")
  }
  let end = start + length
  guard fru_sum(data, start, end) == 0 else {
    raise invalid("invalid FRU area checksum")
  }
  let language = if kind == 2 { None } else { Some(data[start + 2].to_int()) }
  let fields : Array[FruField] = []
  let mut at = start + first_field
  let mut terminated = false
  while at < end - 1 {
    let code = data[at].to_int()
    at += 1
    if code == 0xc1 {
      terminated = true
      break
    }
    let length = code & 63
    guard length <= end - 1 - at else { raise invalid("truncated FRU field") }
    let raw = slice(data, at, at + length)
    let encoding = code >> 6
    let text = if encoding == 3 &&
      (language == None || language == Some(0)) &&
      raw.to_array().all(b => b >= 0x20 && b <= 0x7e) {
      Some(
        String::from_array(raw.to_array().map(b => b.to_int().unsafe_to_char())),
      )
    } else {
      None
    }
    fields.push({ encoding, raw, text, })
    at += length
  }
  guard terminated else { raise invalid("missing FRU area terminator") }
  let required_fields = if kind == 2 { 2 } else if kind == 3 { 5 } else { 7 }
  guard fields.length() >= required_fields else {
    raise invalid("missing required FRU fields")
  }
  for i in at..<(end - 1) {
    guard data[i] == 0 else { raise invalid("nonzero FRU area padding") }
  }
  {
    raw: slice(data, start, end),
    fields,
    language_code: language,
    chassis_type: if kind == 2 {
      Some(data[start + 2].to_int())
    } else {
      None
    },
    manufacturing_minutes: if kind == 3 {
      Some(
        data[start + 3].to_int() |
        (data[start + 4].to_int() << 8) |
        (data[start + 5].to_int() << 16),
      )
    } else {
      None
    },
  }
}

///|
fn fru_multirecord(
  data : Bytes,
  start : Int32,
  end : Int32,
) -> Unit raise ProtocolError {
  let mut at = start
  while at < end {
    guard end - at >= 5 else {
      raise invalid("truncated FRU multirecord header")
    }
    let flags = data[at + 1].to_int()
    guard (flags & 0x7f) == 2 else {
      raise invalid("unsupported FRU multirecord format")
    }
    guard fru_sum(data, at, at + 5) == 0 else {
      raise invalid("invalid FRU multirecord header checksum")
    }
    let length = data[at + 2].to_int()
    guard length <= end - at - 5 else {
      raise invalid("truncated FRU multirecord payload")
    }
    guard (
        (fru_sum(data, at + 5, at + 5 + length) + data[at + 3].to_int()) & 255
      ) ==
      0 else {
      raise invalid("invalid FRU multirecord payload checksum")
    }
    at += 5 + length
    if (flags & 0x80) != 0 {
      return
    }
  }
  raise invalid("missing FRU multirecord end marker")
}

///|
/// Decode a complete byte-addressed FRU image. Header, area boundaries and
/// checksums are checked before returning any inventory. Only printable ASCII in type-3
/// fields in chassis or language-code-zero areas are converted to text.
pub fn decode_fru_inventory(data : Bytes) -> FruInventory raise ProtocolError {
  guard data.length() >= 8 else { raise invalid("truncated FRU common header") }
  guard data[0] == 1 && data[6] == 0 else {
    raise invalid("unsupported FRU common header format")
  }
  guard fru_sum(data, 0, 8) == 0 else {
    raise invalid("invalid FRU common header checksum")
  }
  let offsets = [0, 0, 0, 0, 0, 0]
  for i in 1..<6 {
    offsets[i] = data[i].to_int() * 8
    guard offsets[i] == 0 || (offsets[i] >= 8 && offsets[i] < data.length()) else {
      raise invalid("FRU area offset out of bounds")
    }
    for j in 1..<i {
      guard offsets[i] == 0 || offsets[i] != offsets[j] else {
        raise invalid("overlapping FRU area offsets")
      }
    }
  }
  let mut chassis = None
  let mut board = None
  let mut product = None
  let mut internal_use = None
  let mut multirecord = None
  for i in 1..<6 {
    let start = offsets[i]
    if start == 0 {
      continue
    }
    let mut end = data.length()
    for j in 1..<6 {
      if offsets[j] > start && offsets[j] < end {
        end = offsets[j]
      }
    }
    match i {
      1 => {
        guard data[start] == 1 else {
          raise invalid("unsupported FRU internal-use format")
        }
        internal_use = Some(slice(data, start, end))
      }
      2 => chassis = Some(fru_area(data, start, end, i))
      3 => board = Some(fru_area(data, start, end, i))
      4 => product = Some(fru_area(data, start, end, i))
      _ => {
        fru_multirecord(data, start, end)
        multirecord = Some(slice(data, start, end))
      }
    }
  }
  { raw: data, chassis, board, product, internal_use, multirecord, }
}
