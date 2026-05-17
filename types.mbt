///|
pub(all) suberror ReaddirpError {
  ReaddirpError(String)
} derive(Debug)

///|
pub(all) enum EntryType {
  Files
  Directories
  FilesAndDirectories
  All
} derive(Eq, Debug)

///|
pub(all) enum FileKind {
  File
  Directory
  Symlink
  Other
} derive(Eq, Debug)

///|
pub(all) struct FileStats {
  size : Int64
  mode : Int
} derive(Eq, Debug)

///|
pub(all) struct EntryInfo {
  path : String
  full_path : String
  basename : String
  kind : FileKind
  stats : FileStats?
} derive(Eq, Debug)

///|
pub(all) enum WarningKind {
  Missing
  PermissionDenied
  TooManySymlinks
  RecursiveSymlink
  Other
} derive(Eq, Debug)

///|
pub(all) struct ReaddirpWarning {
  path : String
  kind : WarningKind
  message : String
} derive(Eq, Debug)

///|
pub(all) struct ReaddirpReport {
  entries : Array[EntryInfo]
  warnings : Array[ReaddirpWarning]
} derive(Eq, Debug)

///|
pub(all) struct Options {
  file_filter : (EntryInfo) -> Bool
  directory_filter : (EntryInfo) -> Bool
  type_ : EntryType
  lstat : Bool
  always_stat : Bool
  depth : Int
}

///|
fn accept_entry(_entry : EntryInfo) -> Bool {
  true
}

///|
pub fn Options::default() -> Options {
  {
    file_filter: accept_entry,
    directory_filter: accept_entry,
    type_: Files,
    lstat: false,
    always_stat: false,
    depth: 2147483647,
  }
}
