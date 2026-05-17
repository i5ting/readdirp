///|
test "join_path avoids duplicate separators" {
  inspect(join_path("/tmp/readdirp", "a.txt"), content="/tmp/readdirp/a.txt")
  inspect(join_path("/tmp/readdirp/", "a.txt"), content="/tmp/readdirp/a.txt")
  inspect(join_path("/", "a.txt"), content="/a.txt")
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
  inspect(
    relative_path("/tmp/readdirp/", "/tmp/readdirp/a.txt"),
    content="a.txt",
  )
  inspect(
    relative_path("/tmp/readdirp", "/tmp/readdirp-other/a.txt"),
    content="/tmp/readdirp-other/a.txt",
  )
  inspect(relative_path("/", "/tmp/a.txt"), content="tmp/a.txt")
}

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

///|
test "native read_dir_all includes dotfiles" {
  let root = "./_build/readdirp-ffi-dotfiles"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, ".hidden"), "hidden")
  test_write_file(join_path(root, "visible"), "visible")
  let names = read_dir_all(root)
  names.sort()
  inspect(names, content="[\".hidden\", \"visible\"]")
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
  assert_true(file_kind_from_mode(file_stat.mode) == File)
  inspect(file_stat.size, content="3")
  assert_true(file_kind_from_mode(dir_stat.mode) == Directory)
  test_remove_tree(root)
}
