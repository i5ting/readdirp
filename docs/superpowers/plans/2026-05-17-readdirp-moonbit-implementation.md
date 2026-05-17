# MoonBit readdirp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native/LLVM-first MoonBit synchronous `readdirp` that matches the approved design and the non-stream behavior of `readdirp-master`.

**Architecture:** Keep public types and option helpers in small MoonBit files, isolate native filesystem calls behind a thin FFI layer, and implement traversal in a pure MoonBit walker. Tests are written first and grouped by behavior: path helpers, filters/types, native FFI, basic walking, depth/type/filter/stats, warnings, and symlinks.

**Tech Stack:** MoonBit, native/LLVM backend, C native stubs, `moon test --target native`, `moon check --target native`, `moon info`, `moon fmt`.

---

## File Structure

- Create `types.mbt`: public enums, structs, defaults, and `ReaddirpError`.
- Create `filters.mbt`: `basename_filter`, `basename_filter_any`, and default predicates.
- Create `path.mbt`: path normalization, joining, basename, dirname, and relative path helpers.
- Create `fs_native.mbt`: MoonBit declarations and wrappers for native FFI.
- Create `fs_native.c`: native filesystem functions for directory reading, stat/lstat, realpath, mkdir/write/symlink test support, and error details.
- Create `walker.mbt`: `readdirp`, `readdirp_report`, recursion, filtering, stats, warnings.
- Modify `moon.pkg`: add native/LLVM target mapping and native stubs.
- Modify `readdirp_test.mbt`: black-box behavior tests.
- Modify `readdirp_wbtest.mbt`: white-box helper and FFI tests.
- Modify `README.mbt.md`: minimal public usage example after implementation passes.

---

### Task 1: Path Helpers

**Files:**
- Create: `path.mbt`
- Modify: `readdirp_wbtest.mbt`

- [ ] **Step 1: Write failing white-box tests**

Replace the template-only content in `readdirp_wbtest.mbt` with:

```moonbit
///|
test "join_path avoids duplicate separators" {
  inspect(join_path("/tmp/readdirp", "a.txt"), content="/tmp/readdirp/a.txt")
  inspect(join_path("/tmp/readdirp/", "a.txt"), content="/tmp/readdirp/a.txt")
  inspect(join_path("", "a.txt"), content="a.txt")
}

///|
test "basename extracts final segment" {
  inspect(path_basename("/tmp/readdirp/a.txt"), content="a.txt")
  inspect(path_basename("a.txt"), content="a.txt")
  inspect(path_basename("/tmp/readdirp/"), content="readdirp")
}

///|
test "relative_path strips normalized root prefix" {
  inspect(
    relative_path("/tmp/readdirp", "/tmp/readdirp/a/b.txt"),
    content="a/b.txt",
  )
  inspect(relative_path("/tmp/readdirp/", "/tmp/readdirp/a.txt"), content="a.txt")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: FAIL with unknown identifiers such as `join_path`, `path_basename`, or `relative_path`.

- [ ] **Step 3: Add minimal path helpers**

Create `path.mbt`:

```moonbit
///|
fn trim_trailing_slashes(path : String) -> String {
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  path.substring(0, end)
}

///|
fn trim_leading_slashes(path : String) -> String {
  let mut start = 0
  while start < path.length() && path[start] == '/' {
    start += 1
  }
  path.substring(start, path.length())
}

///|
fn normalize_path(path : String) -> String {
  if path == "" {
    "."
  } else {
    trim_trailing_slashes(path)
  }
}

///|
fn join_path(parent : String, child : String) -> String {
  if parent == "" {
    trim_leading_slashes(child)
  } else if child == "" {
    trim_trailing_slashes(parent)
  } else {
    "\{trim_trailing_slashes(parent)}/\{trim_leading_slashes(child)}"
  }
}

///|
fn path_basename(path : String) -> String {
  let path = trim_trailing_slashes(path)
  let mut i = path.length() - 1
  while i >= 0 && path[i] != '/' {
    i -= 1
  }
  path.substring(i + 1, path.length())
}

///|
fn relative_path(root : String, full_path : String) -> String {
  let root = trim_trailing_slashes(root)
  if full_path.length() <= root.length() {
    ""
  } else {
    let start = if full_path[root.length()] == '/' {
      root.length() + 1
    } else {
      root.length()
    }
    full_path.substring(start, full_path.length())
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: PASS for the three path helper tests.

- [ ] **Step 5: Commit**

```bash
git add path.mbt readdirp_wbtest.mbt
git commit -m "feat: add path helpers"
```

---

### Task 2: Public Types And Filter Helpers

**Files:**
- Create: `types.mbt`
- Create: `filters.mbt`
- Modify: `readdirp_wbtest.mbt`

- [ ] **Step 1: Write failing filter and type tests**

Append to `readdirp_wbtest.mbt`:

```moonbit
///|
test "basename filters trim names" {
  let entry = EntryInfo::{
    path: "src/a.mbt",
    full_path: "/tmp/root/src/a.mbt",
    basename: "a.mbt",
    kind: File,
    stats: None,
  }
  assert_true(basename_filter(" a.mbt ")(entry))
  assert_false(basename_filter("b.mbt")(entry))
}

///|
test "basename_filter_any matches any trimmed name" {
  let entry = EntryInfo::{
    path: "src/a.mbt",
    full_path: "/tmp/root/src/a.mbt",
    basename: "a.mbt",
    kind: File,
    stats: None,
  }
  assert_true(basename_filter_any([" x.mbt ", " a.mbt "])(entry))
  assert_false(basename_filter_any(["x.mbt", "y.mbt"])(entry))
}

///|
test "entry_type inclusion rules" {
  assert_true(wants_file(Files))
  assert_false(wants_directory(Files))
  assert_true(wants_directory(Directories))
  assert_false(wants_file(Directories))
  assert_true(wants_file(FilesAndDirectories))
  assert_true(wants_directory(FilesAndDirectories))
  assert_true(wants_file(All))
  assert_true(wants_directory(All))
  assert_true(wants_other(All))
  assert_false(wants_other(FilesAndDirectories))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: FAIL with unknown identifiers such as `EntryInfo`, `basename_filter`, `Files`, and `wants_file`.

- [ ] **Step 3: Add public types**

Create `types.mbt`:

```moonbit
///|
pub(all) suberror ReaddirpError String derive(Show)

///|
pub(all) enum EntryType {
  Files
  Directories
  FilesAndDirectories
  All
} derive(Eq, Show)

///|
pub(all) enum FileKind {
  File
  Directory
  Symlink
  Other
} derive(Eq, Show)

///|
pub(all) struct FileStats {
  size : Int64
  mode : Int
} derive(Eq, Show)

///|
pub(all) struct EntryInfo {
  path : String
  full_path : String
  basename : String
  kind : FileKind
  stats : Option[FileStats]
} derive(Eq, Show)

///|
pub(all) enum WarningKind {
  Missing
  PermissionDenied
  TooManySymlinks
  RecursiveSymlink
  Other
} derive(Eq, Show)

///|
pub(all) struct ReaddirpWarning {
  path : String
  kind : WarningKind
  message : String
} derive(Eq, Show)

///|
pub(all) struct ReaddirpReport {
  entries : Array[EntryInfo]
  warnings : Array[ReaddirpWarning]
} derive(Eq, Show)

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
```

- [ ] **Step 4: Add filter and inclusion helpers**

Create `filters.mbt`:

```moonbit
///|
pub fn basename_filter(name : String) -> (EntryInfo) -> Bool {
  let expected = name.trim()
  entry => entry.basename == expected
}

///|
pub fn basename_filter_any(names : Array[String]) -> (EntryInfo) -> Bool {
  let expected = names.map(name => name.trim())
  entry => expected.any(name => entry.basename == name)
}

///|
fn wants_file(type_ : EntryType) -> Bool {
  match type_ {
    Files | FilesAndDirectories | All => true
    Directories => false
  }
}

///|
fn wants_directory(type_ : EntryType) -> Bool {
  match type_ {
    Directories | FilesAndDirectories | All => true
    Files => false
  }
}

///|
fn wants_other(type_ : EntryType) -> Bool {
  match type_ {
    All => true
    Files | Directories | FilesAndDirectories => false
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: PASS for path, filter, and inclusion tests.

- [ ] **Step 6: Commit**

```bash
git add types.mbt filters.mbt readdirp_wbtest.mbt
git commit -m "feat: add readdirp public types"
```

---

### Task 3: Native Filesystem FFI

**Files:**
- Create: `fs_native.mbt`
- Create: `fs_native.c`
- Modify: `moon.pkg`
- Modify: `readdirp_wbtest.mbt`

- [ ] **Step 1: Write failing FFI tests**

Append to `readdirp_wbtest.mbt`:

```moonbit
///|
test "native read_dir_all includes dotfiles" {
  let root = "./_build/readdirp-ffi-dotfiles"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, ".hidden"), "hidden")
  test_write_file(join_path(root, "visible"), "visible")
  let names = read_dir_all(root)
  names.sort()
  inspect(names, content=("[.hidden, visible]"))
  test_remove_tree(root)
}

///|
test "native stat classifies files and directories" {
  let root = "./_build/readdirp-ffi-stat"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "a.txt"), "abc")
  let file_stat = stat_path(join_path(root, "a.txt"), follow_symlink=true)
  let dir_stat = stat_path(root, follow_symlink=true)
  inspect(file_kind_from_mode(file_stat.mode), content="File")
  inspect(file_stat.size, content="3")
  inspect(file_kind_from_mode(dir_stat.mode), content="Directory")
  test_remove_tree(root)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: FAIL with unknown identifiers such as `read_dir_all`, `stat_path`, and `test_create_dir`.

- [ ] **Step 3: Configure native stubs**

Replace `moon.pkg` with:

```moonbit
{
  "targets": {
    "fs_native.mbt": ["native", "llvm"]
  },
  "native-stub": ["fs_native.c"]
}
```

- [ ] **Step 4: Add MoonBit FFI wrappers**

Create `fs_native.mbt`:

```moonbit
///|
#external
type NativeNames

///|
#external
type NativeStat

///|
#borrow(path)
extern "C" fn native_read_dir_all(path : Bytes) -> NativeNames = "readdirp_read_dir_all"

///|
extern "C" fn native_names_is_null(names : NativeNames) -> Int = "readdirp_names_is_null"

///|
fn native_names_to_fixed_array(names : NativeNames) -> FixedArray[Bytes] = "%identity"

///|
#borrow(path)
extern "C" fn native_stat_path(path : Bytes, follow_symlink : Int) -> NativeStat = "readdirp_stat_path"

///|
extern "C" fn native_stat_is_null(stat : NativeStat) -> Int = "readdirp_stat_is_null"

///|
extern "C" fn native_stat_size(stat : NativeStat) -> Int64 = "readdirp_stat_size"

///|
extern "C" fn native_stat_mode(stat : NativeStat) -> Int = "readdirp_stat_mode"

///|
extern "C" fn native_stat_errno(stat : NativeStat) -> Int = "readdirp_stat_errno"

///|
extern "C" fn native_last_error_message() -> Bytes = "readdirp_last_error_message"

///|
fn last_error_message() -> String {
  @ffi.utf8_bytes_to_mbt_string(native_last_error_message())
}

///|
fn path_to_bytes(path : String) -> Bytes {
  @ffi.mbt_string_to_utf8_bytes(path, true)
}

///|
fn read_dir_all(path : String) -> Array[String] raise ReaddirpError {
  let names = native_read_dir_all(path_to_bytes(path))
  guard native_names_is_null(names) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  Array::from_fixed_array(native_names_to_fixed_array(names)).map(
    @ffi.utf8_bytes_to_mbt_string,
  )
}

///|
fn stat_path(path : String, follow_symlink~ : Bool) -> FileStats raise ReaddirpError {
  let stat = native_stat_path(path_to_bytes(path), if follow_symlink { 1 } else { 0 })
  guard native_stat_is_null(stat) == 0 else {
    raise ReaddirpError(last_error_message())
  }
  { size: native_stat_size(stat), mode: native_stat_mode(stat) }
}

///|
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
fn test_create_dir(path : String) -> Unit raise ReaddirpError {
  guard native_test_create_dir(path_to_bytes(path)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
fn test_write_file(path : String, contents : String) -> Unit raise ReaddirpError {
  guard native_test_write_file(path_to_bytes(path), @ffi.mbt_string_to_utf8_bytes(contents, false)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}

///|
fn test_remove_tree(path : String) -> Unit {
  ignore(native_test_remove_tree(path_to_bytes(path)))
}

///|
fn test_symlink(target : String, link_path : String) -> Unit raise ReaddirpError {
  guard native_test_symlink(path_to_bytes(target), path_to_bytes(link_path)) == 0 else {
    raise ReaddirpError(last_error_message())
  }
}
```

- [ ] **Step 5: Add C FFI implementation**

Create `fs_native.c` with native functions for POSIX and macOS:

```c
#include "moonbit.h"
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  int err;
  int64_t size;
  int mode;
} readdirp_stat_result_t;

static int readdirp_last_errno = 0;

static moonbit_bytes_t bytes_from_cstr(const char *text) {
  size_t len = strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, len);
  return bytes;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t readdirp_last_error_message(void) {
  return bytes_from_cstr(strerror(readdirp_last_errno == 0 ? errno : readdirp_last_errno));
}

MOONBIT_FFI_EXPORT int readdirp_names_is_null(void *names) {
  return names == NULL;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t *readdirp_read_dir_all(moonbit_bytes_t path) {
  DIR *dir = opendir((const char *)path);
  if (dir == NULL) {
    readdirp_last_errno = errno;
    return NULL;
  }

  int count = 0;
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
      count++;
    }
  }
  rewinddir(dir);

  moonbit_bytes_t *result = moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    closedir(dir);
    readdirp_last_errno = ENOMEM;
    return NULL;
  }

  int index = 0;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    result[index++] = bytes_from_cstr(entry->d_name);
  }
  closedir(dir);
  readdirp_last_errno = 0;
  return result;
}

MOONBIT_FFI_EXPORT readdirp_stat_result_t *readdirp_stat_path(moonbit_bytes_t path, int follow_symlink) {
  struct stat st;
  int status = follow_symlink ? stat((const char *)path, &st) : lstat((const char *)path, &st);
  if (status != 0) {
    readdirp_last_errno = errno;
    return NULL;
  }
  readdirp_stat_result_t *result = malloc(sizeof(readdirp_stat_result_t));
  if (result == NULL) {
    readdirp_last_errno = ENOMEM;
    return NULL;
  }
  result->err = 0;
  result->size = (int64_t)st.st_size;
  result->mode = (int)st.st_mode;
  readdirp_last_errno = 0;
  return result;
}

MOONBIT_FFI_EXPORT int readdirp_stat_is_null(void *stat_result) {
  return stat_result == NULL;
}

MOONBIT_FFI_EXPORT int64_t readdirp_stat_size(readdirp_stat_result_t *stat_result) {
  return stat_result->size;
}

MOONBIT_FFI_EXPORT int readdirp_stat_mode(readdirp_stat_result_t *stat_result) {
  return stat_result->mode;
}

MOONBIT_FFI_EXPORT int readdirp_stat_errno(readdirp_stat_result_t *stat_result) {
  return stat_result == NULL ? readdirp_last_errno : stat_result->err;
}

MOONBIT_FFI_EXPORT int readdirp_test_create_dir(moonbit_bytes_t path) {
  int status = mkdir((const char *)path, 0777);
  if (status != 0 && errno != EEXIST) {
    readdirp_last_errno = errno;
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int readdirp_test_write_file(moonbit_bytes_t path, moonbit_bytes_t contents) {
  FILE *file = fopen((const char *)path, "wb");
  if (file == NULL) {
    readdirp_last_errno = errno;
    return -1;
  }
  size_t len = Moonbit_array_length(contents);
  size_t written = fwrite(contents, 1, len, file);
  fclose(file);
  if (written != len) {
    readdirp_last_errno = errno;
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int readdirp_test_remove_tree(moonbit_bytes_t path) {
  char command[4096];
  snprintf(command, sizeof(command), "rm -rf -- '%s'", (const char *)path);
  return system(command);
}

MOONBIT_FFI_EXPORT int readdirp_test_symlink(moonbit_bytes_t target, moonbit_bytes_t link_path) {
  if (symlink((const char *)target, (const char *)link_path) != 0) {
    readdirp_last_errno = errno;
    return -1;
  }
  return 0;
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: PASS for path, types, filters, and native FFI tests.

- [ ] **Step 7: Commit**

```bash
git add fs_native.mbt fs_native.c moon.pkg readdirp_wbtest.mbt
git commit -m "feat: add native filesystem layer"
```

---

### Task 4: Basic Recursive Walker

**Files:**
- Create: `walker.mbt`
- Modify: `readdirp_test.mbt`

- [ ] **Step 1: Write failing basic black-box tests**

Replace the template-only content in `readdirp_test.mbt` with:

```moonbit
///|
test "readdirp reads files from a directory" {
  let root = "./_build/readdirp-basic"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_write_file(@readdirp.join_path(root, "a.txt"), "a")
  @readdirp.test_write_file(@readdirp.join_path(root, "b.txt"), "b")
  @readdirp.test_write_file(@readdirp.join_path(root, "c.txt"), "c")
  let entries = @readdirp.readdirp(root)
  let names = entries.map(entry => entry.basename)
  names.sort()
  inspect(names, content=("[a.txt, b.txt, c.txt]"))
  inspect(entries[0].stats, content="None")
  @readdirp.test_remove_tree(root)
}

///|
test "default output skips sibling directories but traverses them" {
  let root = "./_build/readdirp-default"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_create_dir(@readdirp.join_path(root, "sub"))
  @readdirp.test_write_file(@readdirp.join_path(root, "root.txt"), "root")
  @readdirp.test_write_file(@readdirp.join_path(root, "sub/child.txt"), "child")
  let entries = @readdirp.readdirp(root)
  let paths = entries.map(entry => entry.path)
  paths.sort()
  inspect(paths, content=("[root.txt, sub/child.txt]"))
  @readdirp.test_remove_tree(root)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: FAIL with unknown public function `readdirp`.

- [ ] **Step 3: Add basic walker**

Create `walker.mbt`:

```moonbit
///|
fn make_entry(
  root : String,
  full_path : String,
  basename : String,
  follow_symlink : Bool,
  include_stats : Bool,
) -> EntryInfo raise ReaddirpError {
  let stats = stat_path(full_path, follow_symlink~)
  {
    path: relative_path(root, full_path),
    full_path,
    basename,
    kind: file_kind_from_mode(stats.mode),
    stats: if include_stats { Some(stats) } else { None },
  }
}

///|
fn should_emit(entry : EntryInfo, type_ : EntryType) -> Bool {
  match entry.kind {
    File => wants_file(type_)
    Directory => wants_directory(type_)
    Symlink | Other => wants_other(type_)
  }
}

///|
fn walk_dir(
  root : String,
  dir : String,
  current_depth : Int,
  options : Options,
  entries : Array[EntryInfo],
  warnings : Array[ReaddirpWarning],
) -> Unit raise ReaddirpError {
  let names = read_dir_all(dir)
  for name in names {
    let full_path = join_path(dir, name)
    let entry = make_entry(
      root,
      full_path,
      name,
      follow_symlink=!options.lstat,
      include_stats=options.always_stat,
    )
    if entry.kind == Directory {
      if options.directory_filter(entry) {
        if should_emit(entry, options.type_) {
          entries.push(entry)
        }
        if current_depth < options.depth {
          walk_dir(root, full_path, current_depth + 1, options, entries, warnings)
        }
      }
    } else if options.file_filter(entry) && should_emit(entry, options.type_) {
      entries.push(entry)
    }
  }
}

///|
pub fn readdirp_report(
  root : String,
  options? : Options = Options::default(),
) -> ReaddirpReport raise ReaddirpError {
  guard root != "" else { raise ReaddirpError("root argument is required") }
  guard options.depth >= 0 else { raise ReaddirpError("depth must be non-negative") }
  let normalized_root = normalize_path(root)
  let root_stats = stat_path(normalized_root, follow_symlink=true)
  guard file_kind_from_mode(root_stats.mode) == Directory else {
    raise ReaddirpError("root must be a directory")
  }
  let entries = []
  let warnings = []
  walk_dir(normalized_root, normalized_root, 0, options, entries, warnings)
  { entries, warnings }
}

///|
pub fn readdirp(
  root : String,
  options? : Options = Options::default(),
) -> Array[EntryInfo] raise ReaddirpError {
  readdirp_report(root, options~).entries
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: PASS for basic and default recursive file tests.

- [ ] **Step 5: Commit**

```bash
git add walker.mbt readdirp_test.mbt
git commit -m "feat: add basic recursive walker"
```

---

### Task 5: Entry Types And Depth

**Files:**
- Modify: `readdirp_test.mbt`
- Modify: `walker.mbt`

- [ ] **Step 1: Write failing type and depth tests**

Append to `readdirp_test.mbt`:

```moonbit
///|
test "entry type controls emitted entries" {
  let root = "./_build/readdirp-types"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_create_dir(@readdirp.join_path(root, "d"))
  @readdirp.test_write_file(@readdirp.join_path(root, "a.txt"), "a")
  let files = @readdirp.readdirp(root, options={ @readdirp.Options::default() with type_: Files })
  let dirs = @readdirp.readdirp(root, options={ @readdirp.Options::default() with type_: Directories })
  let both = @readdirp.readdirp(root, options={ @readdirp.Options::default() with type_: FilesAndDirectories })
  inspect(files.map(e => e.basename), content=("[a.txt]"))
  inspect(dirs.map(e => e.basename), content=("[d]"))
  let both_names = both.map(e => e.basename)
  both_names.sort()
  inspect(both_names, content=("[a.txt, d]"))
  @readdirp.test_remove_tree(root)
}

///|
test "depth limits recursion" {
  let root = "./_build/readdirp-depth"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_create_dir(@readdirp.join_path(root, "subdir"))
  @readdirp.test_create_dir(@readdirp.join_path(root, "subdir/s1"))
  @readdirp.test_write_file(@readdirp.join_path(root, "a.js"), "a")
  @readdirp.test_write_file(@readdirp.join_path(root, "subdir/d.js"), "d")
  @readdirp.test_write_file(@readdirp.join_path(root, "subdir/s1/f.js"), "f")
  let depth0 = @readdirp.readdirp(root, options={ @readdirp.Options::default() with depth: 0 })
  let depth1 = @readdirp.readdirp(root, options={ @readdirp.Options::default() with depth: 1 })
  let depth2 = @readdirp.readdirp(root, options={ @readdirp.Options::default() with depth: 2 })
  inspect(depth0.map(e => e.path), content=("[a.js]"))
  let depth1_paths = depth1.map(e => e.path)
  depth1_paths.sort()
  inspect(depth1_paths, content=("[a.js, subdir/d.js]"))
  let depth2_paths = depth2.map(e => e.path)
  depth2_paths.sort()
  inspect(depth2_paths, content=("[a.js, subdir/d.js, subdir/s1/f.js]"))
  @readdirp.test_remove_tree(root)
}
```

- [ ] **Step 2: Run tests to verify they fail or expose gaps**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: FAIL if option record update syntax or type/depth behavior needs adjustment. If syntax fails, rewrite tests to construct `Options::{ ... }` explicitly using the same values as `Options::default()`.

- [ ] **Step 3: Fix walker type/depth behavior minimally**

If Task 4 code already passes, do not change it. If `depth = 0` traverses one level too deep, change the recursion guard in `walker.mbt` to:

```moonbit
if current_depth < options.depth {
  walk_dir(root, full_path, current_depth + 1, options, entries, warnings)
}
```

If `All` does not include `Other`, keep `should_emit` exactly as:

```moonbit
fn should_emit(entry : EntryInfo, type_ : EntryType) -> Bool {
  match entry.kind {
    File => wants_file(type_)
    Directory => wants_directory(type_)
    Symlink | Other => wants_other(type_)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: PASS for basic, type, and depth tests.

- [ ] **Step 5: Commit**

```bash
git add walker.mbt readdirp_test.mbt
git commit -m "feat: support entry types and depth"
```

---

### Task 6: Filters, Dotfiles, And Stats

**Files:**
- Modify: `readdirp_test.mbt`
- Modify: `walker.mbt`

- [ ] **Step 1: Write failing behavior tests**

Append to `readdirp_test.mbt`:

```moonbit
///|
test "file filters and basename helpers select files" {
  let root = "./_build/readdirp-filters"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_write_file(@readdirp.join_path(root, "a.js"), "a")
  @readdirp.test_write_file(@readdirp.join_path(root, "b.txt"), "b")
  @readdirp.test_write_file(@readdirp.join_path(root, "c.js"), "c")
  let js_only = @readdirp.readdirp(
    root,
    options={ @readdirp.Options::default() with file_filter: entry => entry.basename.ends_with(".js") },
  )
  let one = @readdirp.readdirp(
    root,
    options={ @readdirp.Options::default() with file_filter: @readdirp.basename_filter(" a.js ") },
  )
  let many = @readdirp.readdirp(
    root,
    options={ @readdirp.Options::default() with file_filter: @readdirp.basename_filter_any([" b.txt ", " c.js "]) },
  )
  let js_names = js_only.map(e => e.basename)
  js_names.sort()
  inspect(js_names, content=("[a.js, c.js]"))
  inspect(one.map(e => e.basename), content=("[a.js]"))
  let many_names = many.map(e => e.basename)
  many_names.sort()
  inspect(many_names, content=("[b.txt, c.js]"))
  @readdirp.test_remove_tree(root)
}

///|
test "directory filter prevents recursion" {
  let root = "./_build/readdirp-dir-filter"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_create_dir(@readdirp.join_path(root, "keep"))
  @readdirp.test_create_dir(@readdirp.join_path(root, "skip"))
  @readdirp.test_write_file(@readdirp.join_path(root, "keep/a.txt"), "a")
  @readdirp.test_write_file(@readdirp.join_path(root, "skip/b.txt"), "b")
  let entries = @readdirp.readdirp(
    root,
    options={ @readdirp.Options::default() with directory_filter: entry => entry.basename != "skip" },
  )
  inspect(entries.map(e => e.path), content=("[keep/a.txt]"))
  @readdirp.test_remove_tree(root)
}

///|
test "dotfiles are included and always_stat exposes size" {
  let root = "./_build/readdirp-dot-stats"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_write_file(@readdirp.join_path(root, ".hidden"), "abc")
  let entries = @readdirp.readdirp(root, options={ @readdirp.Options::default() with always_stat: true })
  inspect(entries.length(), content="1")
  inspect(entries[0].basename, content=".hidden")
  inspect(entries[0].stats.map(s => s.size), content="Some(3)")
  @readdirp.test_remove_tree(root)
}
```

- [ ] **Step 2: Run tests to verify they fail or expose gaps**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: FAIL if string helpers are not public, stats are not populated, or dotfiles are filtered accidentally.

- [ ] **Step 3: Fix implementation minimally**

Keep `read_dir_all` as the only directory enumeration API. Do not call `moonbitlang/x/fs.read_dir`.

In `make_entry`, ensure stats are retained only when requested:

```moonbit
let stats = stat_path(full_path, follow_symlink~)
{
  path: relative_path(root, full_path),
  full_path,
  basename,
  kind: file_kind_from_mode(stats.mode),
  stats: if include_stats { Some(stats) } else { None },
}
```

In `walk_dir`, ensure `directory_filter` gates recursion and directory emission:

```moonbit
if entry.kind == Directory {
  if options.directory_filter(entry) {
    if should_emit(entry, options.type_) {
      entries.push(entry)
    }
    if current_depth < options.depth {
      walk_dir(root, full_path, current_depth + 1, options, entries, warnings)
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: PASS for filters, directory filter, dotfile, and stats tests.

- [ ] **Step 5: Commit**

```bash
git add walker.mbt readdirp_test.mbt
git commit -m "feat: add filters and stat output"
```

---

### Task 7: Recoverable Warnings

**Files:**
- Modify: `fs_native.mbt`
- Modify: `fs_native.c`
- Modify: `walker.mbt`
- Modify: `readdirp_test.mbt`
- Modify: `readdirp_wbtest.mbt`

- [ ] **Step 1: Write failing warning classification tests**

Append to `readdirp_wbtest.mbt`:

```moonbit
///|
test "errno maps to warning kinds" {
  inspect(warning_kind_from_errno(2), content="Missing")
  inspect(warning_kind_from_errno(13), content="PermissionDenied")
  inspect(warning_kind_from_errno(40), content="TooManySymlinks")
  inspect(warning_kind_from_errno(9999), content="Other")
}
```

Append to `readdirp_test.mbt`:

```moonbit
///|
test "readdirp_report records missing child warnings and continues" {
  let root = "./_build/readdirp-warnings"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_write_file(@readdirp.join_path(root, "keep.txt"), "keep")
  let report = @readdirp.readdirp_report(root)
  inspect(report.entries.map(e => e.basename), content=("[keep.txt]"))
  inspect(report.warnings.length(), content="0")
  @readdirp.test_remove_tree(root)
}
```

The black-box warning test starts with no warning because race-based missing child tests are not deterministic in a synchronous test. The implementation still needs warning accumulation for symlink recursion and permission failures.

- [ ] **Step 2: Run tests to verify white-box test fails**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
```

Expected: FAIL with unknown `warning_kind_from_errno`.

- [ ] **Step 3: Add warning helpers**

In `fs_native.mbt`, add:

```moonbit
///|
extern "C" fn native_last_errno() -> Int = "readdirp_last_errno_value"

///|
fn last_errno() -> Int {
  native_last_errno()
}

///|
fn warning_kind_from_errno(errno : Int) -> WarningKind {
  if errno == 2 {
    Missing
  } else if errno == 1 || errno == 13 {
    PermissionDenied
  } else if errno == 40 {
    TooManySymlinks
  } else {
    Other
  }
}

///|
fn warning_for(path : String, kind : WarningKind, message : String) -> ReaddirpWarning {
  { path, kind, message }
}
```

In `fs_native.c`, add:

```c
MOONBIT_FFI_EXPORT int readdirp_last_errno_value(void) {
  return readdirp_last_errno;
}
```

- [ ] **Step 4: Convert recoverable child failures to warnings**

In `walker.mbt`, wrap child stat and directory read operations with `try`/`catch` so child failures append warnings and continue:

```moonbit
fn add_warning(
  warnings : Array[ReaddirpWarning],
  path : String,
  kind : WarningKind,
  message : String,
) -> Unit {
  warnings.push({ path, kind, message })
}
```

Use this pattern in `walk_dir`:

```moonbit
try {
  let entry = make_entry(
    root,
    full_path,
    name,
    follow_symlink=!options.lstat,
    include_stats=options.always_stat,
  )
  // existing entry handling remains here
} catch {
  ReaddirpError(message) => {
    add_warning(warnings, full_path, warning_kind_from_errno(last_errno()), message)
  }
}
```

Use the same pattern around recursive `walk_dir` calls so unreadable directories become warnings rather than fatal errors.

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_wbtest.mbt
moon test --target native readdirp_test.mbt
```

Expected: PASS. `readdirp_report` returns entries and an empty warnings array in deterministic non-error fixtures.

- [ ] **Step 6: Commit**

```bash
git add fs_native.mbt fs_native.c walker.mbt readdirp_test.mbt readdirp_wbtest.mbt
git commit -m "feat: collect recoverable readdirp warnings"
```

---

### Task 8: Symlink Behavior

**Files:**
- Modify: `fs_native.mbt`
- Modify: `fs_native.c`
- Modify: `walker.mbt`
- Modify: `readdirp_test.mbt`

- [ ] **Step 1: Write failing symlink tests**

Append to `readdirp_test.mbt`:

```moonbit
///|
test "symlink to file follows stat by default and lstat preserves symlink" {
  let root = "./_build/readdirp-symlink-file"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_write_file(@readdirp.join_path(root, "target.txt"), "target")
  @readdirp.test_symlink("target.txt", @readdirp.join_path(root, "link.txt"))
  let default_entries = @readdirp.readdirp(root)
  let link_default = default_entries.filter(e => e.basename == "link.txt")[0]
  inspect(link_default.kind, content="File")
  let lstat_entries = @readdirp.readdirp(root, options={ @readdirp.Options::default() with lstat: true, type_: All })
  let link_lstat = lstat_entries.filter(e => e.basename == "link.txt")[0]
  inspect(link_lstat.kind, content="Symlink")
  @readdirp.test_remove_tree(root)
}

///|
test "symlink to directory traverses by default" {
  let root = "./_build/readdirp-symlink-dir"
  @readdirp.test_remove_tree(root)
  @readdirp.test_create_dir(root)
  @readdirp.test_create_dir(@readdirp.join_path(root, "real"))
  @readdirp.test_write_file(@readdirp.join_path(root, "real/a.txt"), "a")
  @readdirp.test_symlink("real", @readdirp.join_path(root, "linked"))
  let entries = @readdirp.readdirp(root)
  let paths = entries.map(e => e.path)
  paths.sort()
  inspect(paths, content=("[linked/a.txt, real/a.txt]"))
  @readdirp.test_remove_tree(root)
}
```

- [ ] **Step 2: Run tests to verify they fail if symlink handling is incomplete**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: FAIL if `lstat` does not preserve `Symlink`, default traversal does not follow directory symlinks, or relative symlink targets are not handled by the OS `stat` call.

- [ ] **Step 3: Add realpath support for recursive symlink detection**

In `fs_native.mbt`, add:

```moonbit
///|
#borrow(path)
extern "C" fn native_realpath(path : Bytes) -> Bytes = "readdirp_realpath"

///|
fn real_path(path : String) -> String raise ReaddirpError {
  let resolved = native_realpath(path_to_bytes(path))
  guard resolved.length() > 0 else {
    raise ReaddirpError(last_error_message())
  }
  @ffi.utf8_bytes_to_mbt_string(resolved)
}
```

In `fs_native.c`, add:

```c
MOONBIT_FFI_EXPORT moonbit_bytes_t readdirp_realpath(moonbit_bytes_t path) {
  char resolved[4096];
  if (realpath((const char *)path, resolved) == NULL) {
    readdirp_last_errno = errno;
    return moonbit_make_bytes(0, 0);
  }
  return bytes_from_cstr(resolved);
}
```

- [ ] **Step 4: Skip recursive symlinks**

In `walker.mbt`, before recursing into a directory whose lstat kind is `Symlink`, compare real paths:

```moonbit
fn is_recursive_symlink(full_path : String) -> Bool raise ReaddirpError {
  let resolved = real_path(full_path)
  full_path.starts_with(resolved + "/")
}
```

When a recursive symlink is detected, append:

```moonbit
warnings.push({
  path: full_path,
  kind: RecursiveSymlink,
  message: "recursive symlink detected",
})
```

Do not recurse into that entry.

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
moon test --target native readdirp_test.mbt
```

Expected: PASS for symlink file and symlink directory tests.

- [ ] **Step 6: Commit**

```bash
git add fs_native.mbt fs_native.c walker.mbt readdirp_test.mbt
git commit -m "feat: support symlink traversal"
```

---

### Task 9: Public Docs And Final Verification

**Files:**
- Modify: `README.mbt.md`
- Generated: `pkg.generated.mbti`

- [ ] **Step 1: Add README example**

Replace the minimal README with:

```markdown
# i5ting/readdirp

Recursive directory reader for MoonBit native/LLVM targets, inspired by
`readdirp`.

```mbt
test "read files recursively" {
  let options = @readdirp.Options::default()
  let entries = @readdirp.readdirp(".", options~)
  ignore(entries)
}
```
```

- [ ] **Step 2: Run full native tests**

Run:

```bash
moon test --target native
```

Expected: all tests pass.

- [ ] **Step 3: Run native check**

Run:

```bash
moon check --target native
```

Expected: check succeeds with no errors.

- [ ] **Step 4: Format and generate interfaces**

Run:

```bash
moon fmt
moon info
```

Expected: formatting completes and `pkg.generated.mbti` is generated or updated.

- [ ] **Step 5: Review public API diff**

Run:

```bash
git diff -- pkg.generated.mbti README.mbt.md types.mbt filters.mbt walker.mbt fs_native.mbt
```

Expected: public API contains `EntryType`, `FileKind`, `FileStats`, `EntryInfo`, `Options`, `WarningKind`, `ReaddirpWarning`, `ReaddirpReport`, `basename_filter`, `basename_filter_any`, `readdirp_report`, and `readdirp`.

- [ ] **Step 6: Commit**

```bash
git add README.mbt.md pkg.generated.mbti
git commit -m "docs: add readdirp usage"
```

---

## Plan Self-Review

- Spec coverage: recursive traversal, default files, entry types, depth, filters, stat metadata, warnings, symlinks, native/LLVM FFI, dotfiles, and validation all have tasks.
- Intentional non-goals: stream API, async API, JS/wasm backends, glob matching, Node `Dirent`, and `highWaterMark` remain out of scope.
- Type consistency: the plan consistently uses `EntryInfo`, `Options`, `FileStats`, `ReaddirpReport`, `ReaddirpWarning`, `WarningKind`, `readdirp`, and `readdirp_report`.
- Test-first order: each implementation task starts with failing tests and a command that must fail for the expected reason.
