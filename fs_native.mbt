///|
#external
priv type NativeNames

///|
#external
priv type NativeStat

///|
#borrow(path)
extern "C" fn native_read_dir_all(path : Bytes) -> NativeNames = "readdirp_read_dir_all"

///|
extern "C" fn native_names_is_null(names : NativeNames) -> Int = "readdirp_names_is_null"

///|
fn native_names_to_fixed_array(names : NativeNames) -> FixedArray[Bytes] = "%identity"

///|
#borrow(path)
extern "C" fn native_stat_path(
  path : Bytes,
  follow_symlink : Int,
) -> NativeStat = "readdirp_stat_path"

///|
extern "C" fn native_stat_is_null(stat : NativeStat) -> Int = "readdirp_stat_is_null"

///|
extern "C" fn native_stat_size(stat : NativeStat) -> Int64 = "readdirp_stat_size"

///|
extern "C" fn native_stat_mode(stat : NativeStat) -> Int = "readdirp_stat_mode"

///|
extern "C" fn native_last_error_message() -> Bytes = "readdirp_last_error_message"

///|
fn last_error_message() -> String {
  @utf8.decode_lossy(native_last_error_message())
}

///|
fn path_to_bytes(path : String) -> Bytes {
  @utf8.encode(path)
}

///|
#warnings("-unused_value")
fn read_dir_all(path : String) -> Array[String] raise ReaddirpError {
  let names = native_read_dir_all(path_to_bytes(path))
  guard native_names_is_null(names) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  Array::from_fixed_array(native_names_to_fixed_array(names)).map(name => {
    @utf8.decode_lossy(name)
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
  guard native_stat_is_null(stat) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  { size: native_stat_size(stat), mode: native_stat_mode(stat) }
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
pub fn test_create_dir(path : String) -> Unit raise ReaddirpError {
  guard native_test_create_dir(path_to_bytes(path)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
pub fn test_write_file(
  path : String,
  contents : String,
) -> Unit raise ReaddirpError {
  guard native_test_write_file(path_to_bytes(path), @utf8.encode(contents)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
pub fn test_remove_tree(path : String) -> Unit {
  ignore(native_test_remove_tree(path_to_bytes(path)))
}

///|
pub fn test_symlink(
  target : String,
  link_path : String,
) -> Unit raise ReaddirpError {
  guard native_test_symlink(path_to_bytes(target), path_to_bytes(link_path)) ==
    0 else {
    raise ReaddirpError(last_error_message())
  }
}
