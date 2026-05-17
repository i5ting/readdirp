# readdirp

Directory walking for MoonBit native/LLVM targets.

This package is a synchronous MoonBit port inspired by
[`readdirp`](./readdirp-master). It returns arrays instead of exposing a stream
API, and its filesystem implementation is available on native/LLVM backends.

## Usage

Use `readdirp` when you only need matching entries, or `readdirp_report`
when you also want non-fatal warning details for paths skipped while walking.
Start from `Options::default()` and override the fields you need.

```moonbit nocheck
let options = @readdirp.Options::{
  ..@readdirp.Options::default(),
  type_: @readdirp.FilesAndDirectories,
  depth: 2,
  always_stat: true,
  file_filter: @readdirp.basename_filter_any(["README.mbt.md", "moon.pkg"]),
  directory_filter: entry => entry.basename != "_build",
}

let report = @readdirp.readdirp_report(".", options~)
for entry in report.entries {
  println(entry.path)
}
for warning in report.warnings {
  println(warning.path + ": " + warning.message)
}

let entries = @readdirp.readdirp(".", options~)
```

## API

`readdirp(root, options~)` returns `Array[EntryInfo]`.

`readdirp_report(root, options~)` returns `ReaddirpReport`, which contains both
`entries` and recoverable `warnings`.

`EntryInfo` contains:

- `path`: path relative to the root
- `full_path`: absolute path
- `basename`: final path segment
- `kind`: `File`, `Directory`, `Symlink`, or `Other`
- `stats`: `Some(FileStats)` when `always_stat` is enabled, otherwise `None`

`Options` fields:

- `file_filter`: predicate for files, symlinks, and other non-directory entries
- `directory_filter`: predicate for directories before emitting or recursing
- `type_`: `Files`, `Directories`, `FilesAndDirectories`, or `All`
- `lstat`: preserve symlinks as `Symlink` instead of following them
- `always_stat`: include `FileStats` in each returned entry
- `depth`: maximum recursion depth, where `0` reads only direct children

`basename_filter(name)` and `basename_filter_any(names)` are small helpers for
common `file_filter` or `directory_filter` checks. Helper inputs are trimmed, so
`basename_filter(" a.js ")` matches `a.js`.

## Behavior

By default, `readdirp` emits files, traverses directories, includes dotfiles, and
omits stats from returned entries. Directory entries are only emitted when
`type_` includes directories.

With `lstat: false`, symlinks are followed: symlinks to files are emitted as
`File`, and symlinks to directories are traversed. Recursive directory symlinks
are skipped and reported as `RecursiveSymlink` warnings.

With `lstat: true`, symlinks are preserved as `Symlink`. Use `type_: All` if you
want symlink entries included in the result.

Recoverable filesystem errors while walking are collected by `readdirp_report`.
Warning kinds include `Missing`, `PermissionDenied`, `TooManySymlinks`,
`RecursiveSymlink`, and `Other`. Invalid roots and invalid options raise
`ReaddirpError`.

## Examples

The `examples/basic/readdirp.mbtx` script is a copyable native example. It scans
`examples` by default, or a directory you pass as the final argument.

```bash
moon run --target native examples/basic/readdirp.mbtx -- scan
moon run --target native examples/basic/readdirp.mbtx -- scan .
moon run --target native examples/basic/readdirp.mbtx -- report .
```

If the script cannot resolve `i5ting/readdirp@0.1.1`, refresh the local registry
first with `moon update`.

The script uses `Options::default()` with `type_: FilesAndDirectories`,
`always_stat: true`, and a `directory_filter` that skips `.git`, `_build`, and
`.mooncakes`.

## Development

Run the native test suite:

```bash
moon test --target native
```

Run all backend checks:

```bash
moon test --target all
moon check --target all --warn-list +73
```

Run benchmarks:

```bash
moon bench --target native
```
