///|
#external
priv type NativeNames

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
extern "C" fn native_stat_size() -> Int64 = "readdirp_stat_size"

///|
extern "C" fn native_stat_mode() -> Int = "readdirp_stat_mode"

///|
extern "C" fn native_last_error_message() -> Bytes = "readdirp_last_error_message"

///|
fn last_error_message() -> String {
  ascii_bytes_to_string(native_last_error_message())
}

///|
fn path_to_bytes(path : String) -> Bytes {
  ascii_string_to_bytes(path)
}

///|
fn ascii_string_to_bytes(value : String) -> Bytes {
  Bytes::makei(value.length(), i => value.unsafe_get(i).to_byte())
}

///|
fn ascii_bytes_to_string(value : Bytes) -> String {
  String::from_array(
    Array::makei(value.length(), i => {
      value.unsafe_get(i).to_int().unsafe_to_char()
    }),
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
    ascii_bytes_to_string(name)
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
      ascii_string_to_bytes(contents),
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
