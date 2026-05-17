///|
pub fn basename_filter(name : String) -> (EntryInfo) -> Bool {
  let expected = name.trim().to_owned()
  entry => entry.basename == expected
}

///|
pub fn basename_filter_any(names : Array[String]) -> (EntryInfo) -> Bool {
  let expected = names.map(name => name.trim().to_owned())
  entry => expected.any(name => entry.basename == name)
}

///|
#warnings("-unused_value")
fn wants_file(type_ : EntryType) -> Bool {
  match type_ {
    Files | FilesAndDirectories | All => true
    Directories => false
  }
}

///|
#warnings("-unused_value")
fn wants_directory(type_ : EntryType) -> Bool {
  match type_ {
    Directories | FilesAndDirectories | All => true
    Files => false
  }
}

///|
#warnings("-unused_value")
fn wants_other(type_ : EntryType) -> Bool {
  match type_ {
    All => true
    Files | Directories | FilesAndDirectories => false
  }
}
