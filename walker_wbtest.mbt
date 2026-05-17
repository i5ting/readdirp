///|
test "readdirp reads files from a directory" {
  let root = "./_build/readdirp-basic"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "a.txt"), "a")
  test_write_file(join_path(root, "b.txt"), "b")
  test_write_file(join_path(root, "c.txt"), "c")
  let entries = readdirp(root)
  let names = entries.map(entry => entry.basename)
  names.sort()
  inspect(names, content="[\"a.txt\", \"b.txt\", \"c.txt\"]")
  assert_true(entries.all(entry => entry.stats == None))
  assert_true(entries.all(entry => entry.full_path.has_prefix("/")))
  test_remove_tree(root)
}

///|
test "default output skips sibling directories but traverses them" {
  let root = "./_build/readdirp-default"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "sub"))
  test_write_file(join_path(root, "root.txt"), "root")
  test_write_file(join_path(root, "sub/child.txt"), "child")
  let entries = readdirp(root)
  let paths = entries.map(entry => entry.path)
  paths.sort()
  inspect(paths, content="[\"root.txt\", \"sub/child.txt\"]")
  test_remove_tree(root)
}

///|
test "entry type controls emitted entries" {
  let root = "./_build/readdirp-types"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "d"))
  test_write_file(join_path(root, "a.txt"), "a")
  let files = readdirp(root, options={ ..Options::default(), type_: Files })
  let file_paths = files.map(entry => entry.path)
  file_paths.sort()
  inspect(file_paths, content="[\"a.txt\"]")
  let directories = readdirp(root, options={
    ..Options::default(),
    type_: Directories,
  })
  let directory_paths = directories.map(entry => entry.path)
  directory_paths.sort()
  inspect(directory_paths, content="[\"d\"]")
  let files_and_directories = readdirp(root, options={
    ..Options::default(),
    type_: FilesAndDirectories,
  })
  let file_and_directory_paths = files_and_directories.map(entry => entry.path)
  file_and_directory_paths.sort()
  inspect(file_and_directory_paths, content="[\"d\", \"a.txt\"]")
  let all = readdirp(root, options={ ..Options::default(), type_: All })
  let all_paths = all.map(entry => entry.path)
  all_paths.sort()
  inspect(all_paths, content="[\"d\", \"a.txt\"]")
  test_remove_tree(root)
}

///|
test "depth limits recursion" {
  let root = "./_build/readdirp-depth"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "subdir"))
  test_create_dir(join_path(root, "subdir/s1"))
  test_write_file(join_path(root, "a.js"), "a")
  test_write_file(join_path(root, "subdir/d.js"), "d")
  test_write_file(join_path(root, "subdir/s1/f.js"), "f")
  let depth0 = readdirp(root, options={ ..Options::default(), depth: 0 })
  let depth0_paths = depth0.map(entry => entry.path)
  depth0_paths.sort()
  inspect(depth0_paths, content="[\"a.js\"]")
  let depth1 = readdirp(root, options={ ..Options::default(), depth: 1 })
  let depth1_paths = depth1.map(entry => entry.path)
  depth1_paths.sort()
  inspect(depth1_paths, content="[\"a.js\", \"subdir/d.js\"]")
  let depth2 = readdirp(root, options={ ..Options::default(), depth: 2 })
  let depth2_paths = depth2.map(entry => entry.path)
  depth2_paths.sort()
  inspect(
    depth2_paths,
    content="[\"a.js\", \"subdir/d.js\", \"subdir/s1/f.js\"]",
  )
  let default_depth = readdirp(root)
  let default_depth_paths = default_depth.map(entry => entry.path)
  default_depth_paths.sort()
  inspect(
    default_depth_paths,
    content="[\"a.js\", \"subdir/d.js\", \"subdir/s1/f.js\"]",
  )
  test_remove_tree(root)
}
