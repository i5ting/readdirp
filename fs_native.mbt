///|
#external
priv type NativeNames

///|
priv type NativePath

///|
#borrow(path)
extern "C" fn native_read_dir_all(path : Bytes) -> NativeNames = "readdirp_read_dir_all"

///|
extern "C" fn native_names_is_null(names : NativeNames) -> Int = "readdirp_names_is_null"

///|
fn native_names_to_fixed_array(names : NativeNames) -> FixedArray[Bytes] = "%identity"

///|
#borrow(path)
extern "C" fn native_stat_path(path : Bytes, follow_symlink : Int) -> Int = "readdirp_stat_path"

///|
#borrow(path)
extern "C" fn native_real_path(path : Bytes) -> NativePath = "readdirp_real_path"

///|
#borrow(path)
extern "C" fn native_path_is_null(path : NativePath) -> Int = "readdirp_names_is_null"

///|
fn native_path_to_bytes(path : NativePath) -> Bytes = "%identity"

///|
extern "C" fn native_stat_size() -> Int64 = "readdirp_stat_size"

///|
extern "C" fn native_stat_mode() -> Int = "readdirp_stat_mode"

///|
extern "C" fn native_last_error_message() -> Bytes = "readdirp_last_error_message"

///|
extern "C" fn native_last_errno() -> Int = "readdirp_last_errno_value"

///|
extern "C" fn native_errno_enoent() -> Int = "readdirp_errno_enoent"

///|
extern "C" fn native_errno_eacces() -> Int = "readdirp_errno_eacces"

///|
extern "C" fn native_errno_eperm() -> Int = "readdirp_errno_eperm"

///|
extern "C" fn native_errno_eloop() -> Int = "readdirp_errno_eloop"

///|
fn last_error_message() -> String {
  bytes_to_string(native_last_error_message())
}

///|
fn last_errno() -> Int {
  native_last_errno()
}

///|
fn errno_enoent() -> Int {
  native_errno_enoent()
}

///|
fn errno_eacces() -> Int {
  native_errno_eacces()
}

///|
fn errno_eperm() -> Int {
  native_errno_eperm()
}

///|
fn errno_eloop() -> Int {
  native_errno_eloop()
}

///|
fn warning_kind_from_errno(errno : Int) -> WarningKind {
  if errno == errno_enoent() {
    Missing
  } else if errno == errno_eacces() || errno == errno_eperm() {
    PermissionDenied
  } else if errno == errno_eloop() {
    TooManySymlinks
  } else {
    Other
  }
}

///|
fn warning_for(
  path : String,
  kind : WarningKind,
  message : String,
) -> ReaddirpWarning {
  { path, kind, message }
}

///|
fn path_to_bytes(path : String) -> Bytes {
  string_to_utf8_bytes(path)
}

///|
fn bytes_to_string(value : Bytes) -> String {
  utf8_decode_lossy(value)
}

///|
fn string_to_utf8_bytes(value : String) -> Bytes {
  let byte_length = value
    .iter()
    .fold(init=0, (length, char) => {
      let code = char.to_int()
      if code < 0x80 {
        length + 1
      } else if code < 0x800 {
        length + 2
      } else if code < 0x10000 {
        length + 3
      } else {
        length + 4
      }
    })
  let bytes = FixedArray::make(byte_length, b'\x00')
  ignore(
    value
    .iter()
    .fold(init=0, (offset, char) => offset + bytes.set_utf8_char(offset, char)),
  )
  fixed_byte_array_to_bytes(bytes)
}

///|
fn fixed_byte_array_to_bytes(bytes : FixedArray[Byte]) -> Bytes = "%identity"

///|
fn utf8_decode_lossy(value : Bytes) -> String {
  let chars : Array[Char] = []
  let length = value.length()
  for i = 0; i < length; {
    let b0 = value.unsafe_get(i).to_int()
    if b0 <= 0x7F {
      chars.push(b0.unsafe_to_char())
      continue i + 1
    } else if b0 >= 0xC2 &&
      b0 <= 0xDF &&
      i + 1 < length &&
      is_utf8_continuation(value.unsafe_get(i + 1).to_int()) {
      let b1 = value.unsafe_get(i + 1).to_int()
      let code = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      chars.push(code.unsafe_to_char())
      continue i + 2
    } else if is_valid_utf8_three_byte(value, i, length) {
      let b1 = value.unsafe_get(i + 1).to_int()
      let b2 = value.unsafe_get(i + 2).to_int()
      let code = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      chars.push(code.unsafe_to_char())
      continue i + 3
    } else if is_valid_utf8_four_byte(value, i, length) {
      let b1 = value.unsafe_get(i + 1).to_int()
      let b2 = value.unsafe_get(i + 2).to_int()
      let b3 = value.unsafe_get(i + 3).to_int()
      let code = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      chars.push(code.unsafe_to_char())
      continue i + 4
    } else {
      chars.push((0xFFFD).unsafe_to_char())
      continue i + 1
    }
  }
  String::from_array(chars)
}

///|
fn is_utf8_continuation(byte : Int) -> Bool {
  byte >= 0x80 && byte <= 0xBF
}

///|
fn is_valid_utf8_three_byte(value : Bytes, index : Int, length : Int) -> Bool {
  guard index + 2 < length else { false }
  let b0 = value.unsafe_get(index).to_int()
  let b1 = value.unsafe_get(index + 1).to_int()
  let b2 = value.unsafe_get(index + 2).to_int()
  is_utf8_continuation(b2) &&
  (
    (b0 == 0xE0 && b1 >= 0xA0 && b1 <= 0xBF) ||
    (b0 >= 0xE1 && b0 <= 0xEC && is_utf8_continuation(b1)) ||
    (b0 == 0xED && b1 >= 0x80 && b1 <= 0x9F) ||
    (b0 >= 0xEE && b0 <= 0xEF && is_utf8_continuation(b1))
  )
}

///|
fn is_valid_utf8_four_byte(value : Bytes, index : Int, length : Int) -> Bool {
  guard index + 3 < length else { false }
  let b0 = value.unsafe_get(index).to_int()
  let b1 = value.unsafe_get(index + 1).to_int()
  let b2 = value.unsafe_get(index + 2).to_int()
  let b3 = value.unsafe_get(index + 3).to_int()
  is_utf8_continuation(b2) &&
  is_utf8_continuation(b3) &&
  (
    (b0 == 0xF0 && b1 >= 0x90 && b1 <= 0xBF) ||
    (b0 >= 0xF1 && b0 <= 0xF3 && is_utf8_continuation(b1)) ||
    (b0 == 0xF4 && b1 >= 0x80 && b1 <= 0x8F)
  )
}

///|
#warnings("-unused_value")
fn read_dir_all(path : String) -> Array[String] raise ReaddirpError {
  let names = native_read_dir_all(path_to_bytes(path))
  guard native_names_is_null(names) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  Array::from_fixed_array(native_names_to_fixed_array(names)).map(name => {
    bytes_to_string(name)
  })
}

///|
#warnings("-unused_value")
fn stat_path(
  path : String,
  follow_symlink~ : Bool,
) -> FileStats raise ReaddirpError {
  let stat = native_stat_path(
    path_to_bytes(path),
    if follow_symlink {
      1
    } else {
      0
    },
  )
  guard stat == 0 else { raise ReaddirpError(last_error_message()) }
  { size: native_stat_size(), mode: native_stat_mode() }
}

///|
#warnings("-unused_value")
fn real_path(path : String) -> String raise ReaddirpError {
  let resolved = native_real_path(path_to_bytes(path))
  guard native_path_is_null(resolved) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  bytes_to_string(native_path_to_bytes(resolved))
}

///|
#warnings("-unused_value")
fn file_kind_from_mode(mode : Int) -> FileKind {
  let type_bits = mode & 0xF000
  if type_bits == 0x8000 {
    File
  } else if type_bits == 0x4000 {
    Directory
  } else if type_bits == 0xA000 {
    Symlink
  } else {
    Other
  }
}

///|
#borrow(path)
extern "C" fn native_test_create_dir(path : Bytes) -> Int = "readdirp_test_create_dir"

///|
#borrow(path, contents)
extern "C" fn native_test_write_file(path : Bytes, contents : Bytes) -> Int = "readdirp_test_write_file"

///|
#borrow(path)
extern "C" fn native_test_remove_tree(path : Bytes) -> Int = "readdirp_test_remove_tree"

///|
#borrow(target, link_path)
extern "C" fn native_test_symlink(target : Bytes, link_path : Bytes) -> Int = "readdirp_test_symlink"

///|
#warnings("-unused_value")
fn test_create_dir(path : String) -> Unit raise ReaddirpError {
  guard native_test_create_dir(path_to_bytes(path)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
#warnings("-unused_value")
fn test_write_file(
  path : String,
  contents : String,
) -> Unit raise ReaddirpError {
  guard native_test_write_file(
      path_to_bytes(path),
      string_to_utf8_bytes(contents),
    ) ==
    0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
#warnings("-unused_value")
fn test_remove_tree(path : String) -> Unit raise ReaddirpError {
  guard native_test_remove_tree(path_to_bytes(path)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
#warnings("-unused_value")
fn test_symlink(
  target : String,
  link_path : String,
) -> Unit raise ReaddirpError {
  guard native_test_symlink(path_to_bytes(target), path_to_bytes(link_path)) ==
    0 else {
    raise ReaddirpError(last_error_message())
  }
}
