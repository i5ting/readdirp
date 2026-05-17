# MoonBit readdirp Design

## Goal

Implement a MoonBit-native synchronous version of `readdirp`, using
`readdirp-master` as the behavioral reference. The first version targets
native/LLVM backends and returns a collected `Array[EntryInfo]`, not a Node-style
stream.

## Scope

The implementation will provide recursive directory traversal with:

- default file-only output
- selectable output type: files, directories, files plus directories, or all
- depth-limited recursion
- file and directory predicate filters
- relative path, full path, basename, and file kind in each entry
- optional stat metadata for callers that need file size or mode data
- recoverable traversal warnings through a report-returning API
- native/LLVM filesystem behavior close to `readdirp-master`, including dotfiles

The first version will not provide a streaming API, async API, JS backend, wasm
backend, glob matching, Node `Dirent` objects, or stream backpressure controls.

## Reference Comparison

Compared with `readdirp-master`, this design intentionally adapts the API shape
to MoonBit while keeping the non-stream traversal behavior:

- `readdirpPromise(root, options)` maps to `readdirp(root, options)`.
- stream `warn` events map to `readdirp_report(root, options).warnings`.
- `fileFilter` and `directoryFilter` function predicates map directly to
  `file_filter` and `directory_filter`.
- string and string-array filters map to `basename_filter` and
  `basename_filter_any`.
- `type`, `depth`, `lstat`, and `alwaysStat` map to `type_`, `depth`, `lstat`,
  and `always_stat`.
- Node `stats` maps to the smaller `FileStats` record.
- Node `dirent` maps to `EntryInfo.kind`, because MoonBit consumers should not
  depend on Node-specific objects.

## Public API

The primary function will be:

```moonbit
pub fn readdirp(
  root : String,
  options? : Options = Options::default(),
) -> Array[EntryInfo] raise ReaddirpError
```

For callers that need the reference library's `warn` event equivalent, a second
API returns both entries and recoverable warnings:

```moonbit
pub fn readdirp_report(
  root : String,
  options? : Options = Options::default(),
) -> ReaddirpReport raise ReaddirpError
```

Core public types:

```moonbit
pub(all) enum EntryType {
  Files
  Directories
  FilesAndDirectories
  All
}

pub(all) enum FileKind {
  File
  Directory
  Symlink
  Other
}

pub(all) struct FileStats {
  size : Int64
  mode : Int
}

pub(all) struct EntryInfo {
  path : String
  full_path : String
  basename : String
  kind : FileKind
  stats : Option[FileStats]
}

pub(all) struct Options {
  file_filter : (EntryInfo) -> Bool
  directory_filter : (EntryInfo) -> Bool
  type_ : EntryType
  lstat : Bool
  always_stat : Bool
  depth : Int
}

pub(all) enum WarningKind {
  Missing
  PermissionDenied
  TooManySymlinks
  RecursiveSymlink
  Other
}

pub(all) struct ReaddirpWarning {
  path : String
  kind : WarningKind
  message : String
}

pub(all) struct ReaddirpReport {
  entries : Array[EntryInfo]
  warnings : Array[ReaddirpWarning]
}
```

Defaults:

- `type_ = Files`
- `lstat = false`
- `always_stat = false`
- `depth = 2147483647`
- both filters return `true`

Filter helper functions will cover the reference library's string and string
array predicates without complicating `Options`:

```moonbit
pub fn basename_filter(name : String) -> (EntryInfo) -> Bool
pub fn basename_filter_any(names : Array[String]) -> (EntryInfo) -> Bool
```

Both helpers trim names before comparing with `EntryInfo.basename`, matching
`readdirp-master`'s `normalizeFilter`.

## Behavior

Traversal starts at `root` and visits children recursively. The root directory
itself is not emitted, matching `readdirp-master`.

`EntryInfo.path` is relative to `root`. `EntryInfo.full_path` is an absolute path.
`EntryInfo.basename` is the final path segment. `EntryInfo.kind` is based on
`stat` by default, and on `lstat` when `options.lstat` is true.

`EntryInfo.stats` is `None` by default. When `always_stat = true`, it is
populated from the same stat call used to classify the entry. The first version
will expose `size` and `mode`, enough to support the reference test behavior
that filters entries by non-zero size and to distinguish file type bits in
white-box tests. More stat fields can be added later without changing traversal
semantics.

When `lstat = false`, symbolic links are followed by `stat`, so symlinks to files
are treated as files and symlinks to directories can be traversed. Recursive
directory symlinks are detected with `realpath` and skipped.

When `lstat = true`, symbolic links remain `Symlink` and are not traversed as
directories.

Directories are tested with `directory_filter` before recursion. A directory
that fails the filter is neither emitted nor traversed. Non-directory entries are
tested with `file_filter` before inclusion.

`depth = 0` means only root-level matching entries are returned. Each nested
directory level increments depth by one.

## Error Handling

`ReaddirpError` is used for fatal errors:

- empty root
- root does not exist
- root is not a directory
- invalid options such as negative depth
- unexpected filesystem errors that prevent starting traversal

Recoverable traversal errors are skipped by `readdirp` and captured in
`readdirp_report().warnings`:

- permission denied while entering a child directory
- child entry removed between directory read and stat
- symlink loops reported by the operating system
- recursive symlink detected

This mirrors the reference library's distinction between fatal errors and
warnings, but uses a collected report instead of a stream event channel.

## Implementation Structure

- `types.mbt`: public types, default options, and error type
- `path.mbt`: path joining, basename, relative path, and normalization helpers
- `fs_native.mbt`: MoonBit declarations for native/LLVM filesystem FFI
- `fs_native.c`: thin native filesystem FFI for `read_dir_all`, `stat`, `lstat`,
  `realpath`, and stat metadata
- `walker.mbt`: recursive traversal, depth control, filtering, symlink handling,
  and result selection
- `readdirp_test.mbt`: public behavior tests
- `readdirp_wbtest.mbt`: focused tests for internal helpers

## Testing

Tests will be derived from `readdirp-master/test/index.test.js`, adapted to the
MoonBit synchronous array API.

Black-box tests will cover:

- reading files from a directory
- default files-only behavior with sibling directories present
- `EntryType::Files`
- `EntryType::Directories`
- `EntryType::FilesAndDirectories`
- `EntryType::All`
- `depth = 0`
- `depth = 1`
- `depth = 2`
- default depth recurses through all nested test fixtures
- `file_filter` by basename suffix
- `file_filter` by full path suffix
- `basename_filter` trims and matches one basename
- `basename_filter_any` trims and matches any basename
- `always_stat = true` populates `EntryInfo.stats`
- filtering can use `stats.size`
- `directory_filter` excludes both emitted directories and recursion into them
- dotfiles are included, because the native FFI must not copy
  `moonbitlang/x/fs.read_dir`'s hidden-file filtering behavior
- invalid root and negative depth errors
- `readdirp_report` returns recoverable warnings while still returning entries

White-box tests will cover:

- path joining without duplicate separators
- basename extraction
- relative path extraction from an absolute root
- output inclusion decisions for each `EntryType` and `FileKind`
- recoverable filesystem error classification into `WarningKind`
- stat mode to `FileKind` conversion

Native-only symlink tests will cover:

- symlink to a file is emitted as `File` when `lstat = false`
- symlink to a directory is traversed when `lstat = false`
- symlink is emitted as `Symlink` and not traversed when `lstat = true`
- recursive directory symlink is skipped and reported as `RecursiveSymlink`

Reference tests that will not be ported directly:

- stream instance checks, because this design has no stream API
- promise API exposure checks, because `readdirp` directly returns an array
- invalid string `type`, because `EntryType` is a MoonBit enum and prevents that
  class of invalid value at compile time
- `highWaterMark`, warning timing, and "no warning after end" tests, because
  those are stream-specific; synchronous recoverable errors will instead be
  tested through `readdirp_report`

## Validation

Before handoff, run:

```sh
moon test --target native
moon check --target native
moon info
moon fmt
```

Review generated `pkg.generated.mbti` changes to confirm the public API matches
this design.
