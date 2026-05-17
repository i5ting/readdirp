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

///|
test "native test_remove_tree rejects unsafe paths" {
  let raised = try {
    test_remove_tree("./_build/not-readdirp")
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
test "native test_remove_tree rejects traversal paths" {
  let raised = try {
    test_remove_tree("./_build/readdirp-/../../should-not-delete")
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
test "native read_dir_all preserves unicode filenames" {
  let root = "./_build/readdirp-ffi-unicode"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "你好.txt"), "你好")
  let names = read_dir_all(root)
  names.sort()
  inspect(names, content="[\"你好.txt\"]")
  test_remove_tree(root)
}

///|
test "errno maps to warning kinds" {
  assert_true(warning_kind_from_errno(2) == Missing)
  assert_true(warning_kind_from_errno(13) == PermissionDenied)
  assert_true(warning_kind_from_errno(errno_eperm()) == PermissionDenied)
  assert_true(warning_kind_from_errno(errno_eloop()) == TooManySymlinks)
  assert_true(warning_kind_from_errno(9999) == Other)
}
