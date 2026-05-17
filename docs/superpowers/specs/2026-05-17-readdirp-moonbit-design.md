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
- native/LLVM filesystem behavior close to `readdirp-master`, including dotfiles

The first version will not provide a streaming API, async API, JS backend, wasm
backend, glob matching, file metadata fields such as size or mtime, or a warning
event channel.

## Public API

The primary function will be:

```moonbit
pub fn readdirp(
  root : String,
  options? : Options = Options::default(),
) -> Array[EntryInfo] raise ReaddirpError
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

pub(all) struct EntryInfo {
  path : String
  full_path : String
  basename : String
  kind : FileKind
}

pub(all) struct Options {
  file_filter : (EntryInfo) -> Bool
  directory_filter : (EntryInfo) -> Bool
  type_ : EntryType
  lstat : Bool
  depth : Int
}
```

Defaults:

- `type_ = Files`
- `lstat = false`
- `depth = 2147483647`
- both filters return `true`

## Behavior

Traversal starts at `root` and visits children recursively. The root directory
itself is not emitted, matching `readdirp-master`.

`EntryInfo.path` is relative to `root`. `EntryInfo.full_path` is an absolute path.
`EntryInfo.basename` is the final path segment. `EntryInfo.kind` is based on
`stat` by default, and on `lstat` when `options.lstat` is true.

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

Recoverable traversal errors are skipped in the first version:

- permission denied while entering a child directory
- child entry removed between directory read and stat
- recursive symlink detected

This mirrors the reference library's distinction between fatal errors and
warnings, but omits an event channel because this API returns a plain array.

## Implementation Structure

- `types.mbt`: public types, default options, and error type
- `path.mbt`: path joining, basename, relative path, and normalization helpers
- `fs_native.mbt`: MoonBit declarations for native/LLVM filesystem FFI
- `fs_native.c`: thin native filesystem FFI for `read_dir_all`, `stat`, `lstat`,
  and `realpath`
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
- `directory_filter` excludes both emitted directories and recursion into them
- dotfiles are included, because the native FFI must not copy
  `moonbitlang/x/fs.read_dir`'s hidden-file filtering behavior
- invalid root and negative depth errors

White-box tests will cover:

- path joining without duplicate separators
- basename extraction
- relative path extraction from an absolute root
- output inclusion decisions for each `EntryType` and `FileKind`
- recoverable filesystem error classification

Native-only symlink tests will cover:

- symlink to a file is emitted as `File` when `lstat = false`
- symlink to a directory is traversed when `lstat = false`
- symlink is emitted as `Symlink` and not traversed when `lstat = true`
- recursive directory symlink is skipped rather than recursing forever

Reference tests that will not be ported directly:

- stream instance checks, because this design has no stream API
- promise API exposure checks, because `readdirp` directly returns an array
- `alwaysStat` and stats-size filtering, because this first version exposes
  `FileKind` but not full metadata
- invalid string `type`, because `EntryType` is a MoonBit enum and prevents that
  class of invalid value at compile time
- `highWaterMark`, warning timing, and "no warning after end" tests, because
  those are stream-specific; synchronous recoverable errors will instead be
  tested as skipped entries

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
