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
