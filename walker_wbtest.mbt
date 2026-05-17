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
test "readdirp_report returns entries with empty warnings for normal fixture" {
  let root = "./_build/readdirp-report-clean"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "a.txt"), "a")
  test_write_file(join_path(root, "b.txt"), "b")
  let report = readdirp_report(root)
  let names = report.entries.map(entry => entry.basename)
  names.sort()
  inspect(names, content="[\"a.txt\", \"b.txt\"]")
  inspect(report.warnings.length(), content="0")
  test_remove_tree(root)
}

///|
test "readdirp_report records missing child warnings and continues" {
  let root = "./_build/readdirp-warning-broken-link"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "keep.txt"), "keep")
  test_symlink("missing-target.txt", join_path(root, "broken-link"))
  let report = readdirp_report(root)
  let names = report.entries.map(entry => entry.basename)
  names.sort()
  inspect(names, content="[\"keep.txt\"]")
  inspect(report.warnings.length(), content="1")
  let warning = report.warnings[0]
  assert_true(warning.kind == Missing)
  assert_true(warning.path.has_suffix("/broken-link"))
  test_remove_tree(root)
}

///|
test "invalid roots and depth raise readdirp errors" {
  let empty_root_error = try {
    ignore(readdirp(""))
    ""
  } catch {
    ReaddirpError(message) => message
  }
  inspect(empty_root_error, content="root argument is required")
  let negative_depth_error = try {
    ignore(readdirp(".", options={ ..Options::default(), depth: -1 }))
    ""
  } catch {
    ReaddirpError(message) => message
  }
  inspect(negative_depth_error, content="depth must be non-negative")
  let root = "./_build/readdirp-invalid-root"
  test_remove_tree(root)
  test_create_dir(root)
  let file_root = join_path(root, "file.txt")
  test_write_file(file_root, "file")
  let file_root_error = try {
    ignore(readdirp(file_root))
    ""
  } catch {
    ReaddirpError(message) => message
  }
  inspect(file_root_error, content="root must be a directory")
  test_remove_tree(root)
}

///|
test "symlink to file follows stat by default and lstat preserves symlink" {
  let root = "./_build/readdirp-symlink-file"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "target.txt"), "target")
  test_symlink("target.txt", join_path(root, "link.txt"))
  let entries = readdirp(root)
  let links = entries.filter(entry => entry.path == "link.txt")
  inspect(links.length(), content="1")
  assert_true(links[0].kind == File)
  let lstat_entries = readdirp(root, options={
    ..Options::default(),
    lstat: true,
    type_: All,
  })
  let lstat_links = lstat_entries.filter(entry => entry.path == "link.txt")
  inspect(lstat_links.length(), content="1")
  assert_true(lstat_links[0].kind == Symlink)
  test_remove_tree(root)
}

///|
test "lstat with always_stat exposes symlink stats" {
  let root = "./_build/readdirp-lstat-stats"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "target.txt"), "target")
  test_symlink("target.txt", join_path(root, "link.txt"))
  let entries = readdirp(root, options={
    ..Options::default(),
    always_stat: true,
    lstat: true,
    type_: All,
  })
  let links = entries.filter(entry => entry.path == "link.txt")
  inspect(links.length(), content="1")
  assert_true(links[0].kind == Symlink)
  match links[0].stats {
    Some(stats) => assert_true(file_kind_from_mode(stats.mode) == Symlink)
    None => fail("expected symlink stats")
  }
  test_remove_tree(root)
}

///|
test "symlink to directory traverses by default" {
  let root = "./_build/readdirp-symlink-dir"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "real"))
  test_write_file(join_path(root, "real/a.txt"), "a")
  test_symlink("real", join_path(root, "linked"))
  let entries = readdirp(root)
  let paths = entries.map(entry => entry.path)
  inspect(paths.length(), content="2")
  assert_true(paths.search("linked/a.txt") != None)
  assert_true(paths.search("real/a.txt") != None)
  test_remove_tree(root)
}

///|
test "recursive directory symlink is skipped with warning" {
  let root = "./_build/readdirp-symlink-loop"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "real"))
  test_write_file(join_path(root, "real/a.txt"), "a")
  test_symlink("..", join_path(root, "real/loop"))
  let report = readdirp_report(root, options={ ..Options::default(), depth: 8 })
  let paths = report.entries.map(entry => entry.path)
  paths.sort()
  inspect(paths, content="[\"real/a.txt\"]")
  inspect(report.warnings.length(), content="1")
  let warning = report.warnings[0]
  assert_true(warning.kind == RecursiveSymlink)
  assert_true(warning.path.has_suffix("/real/loop"))
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
  test_write_file(join_path(root, "target.txt"), "target")
  test_symlink("target.txt", join_path(root, "link.txt"))
  let files_and_directories = readdirp(root, options={
    ..Options::default(),
    type_: FilesAndDirectories,
    lstat: true,
  })
  let file_and_directory_paths = files_and_directories.map(entry => entry.path)
  file_and_directory_paths.sort()
  inspect(
    file_and_directory_paths,
    content="[\"d\", \"a.txt\", \"target.txt\"]",
  )
  let all = readdirp(root, options={
    ..Options::default(),
    type_: All,
    lstat: true,
  })
  let all_paths = all.map(entry => entry.path)
  all_paths.sort()
  inspect(all_paths, content="[\"d\", \"a.txt\", \"link.txt\", \"target.txt\"]")
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

///|
test "file filters and basename helpers select files" {
  let root = "./_build/readdirp-filters"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "a.js"), "a")
  test_write_file(join_path(root, "b.txt"), "b")
  test_write_file(join_path(root, "c.js"), "c")
  let js_entries = readdirp(root, options={
    ..Options::default(),
    file_filter: entry => entry.basename.has_suffix(".js"),
  })
  let js_paths = js_entries.map(entry => entry.path)
  js_paths.sort()
  inspect(js_paths, content="[\"a.js\", \"c.js\"]")
  let a_entries = readdirp(root, options={
    ..Options::default(),
    file_filter: basename_filter(" a.js "),
  })
  let a_paths = a_entries.map(entry => entry.path)
  a_paths.sort()
  inspect(a_paths, content="[\"a.js\"]")
  let any_entries = readdirp(root, options={
    ..Options::default(),
    file_filter: basename_filter_any([" b.txt ", " c.js "]),
  })
  let any_paths = any_entries.map(entry => entry.path)
  any_paths.sort()
  inspect(any_paths, content="[\"c.js\", \"b.txt\"]")
  test_remove_tree(root)
}

///|
test "always_stat lets file filters inspect stats" {
  let root = "./_build/readdirp-filter-stats"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, "empty.txt"), "")
  test_write_file(join_path(root, "filled.txt"), "content")
  let entries = readdirp(root, options={
    ..Options::default(),
    always_stat: true,
    file_filter: entry => {
      match entry.stats {
        Some(stats) => stats.size > 0
        None => false
      }
    },
  })
  let paths = entries.map(entry => entry.path)
  paths.sort()
  inspect(paths, content="[\"filled.txt\"]")
  assert_true(entries.all(entry => entry.stats != None))
  test_remove_tree(root)
}

///|
test "directory filter prevents recursion" {
  let root = "./_build/readdirp-dir-filter"
  test_remove_tree(root)
  test_create_dir(root)
  test_create_dir(join_path(root, "keep"))
  test_create_dir(join_path(root, "skip"))
  test_write_file(join_path(root, "keep/a.txt"), "a")
  test_write_file(join_path(root, "skip/b.txt"), "b")
  let entries = readdirp(root, options={
    ..Options::default(),
    directory_filter: entry => entry.basename != "skip",
  })
  let paths = entries.map(entry => entry.path)
  paths.sort()
  inspect(paths, content="[\"keep/a.txt\"]")
  test_remove_tree(root)
}

///|
test "dotfiles are included and always_stat exposes size" {
  let root = "./_build/readdirp-dot-stats"
  test_remove_tree(root)
  test_create_dir(root)
  test_write_file(join_path(root, ".hidden"), "abc")
  let default_entries = readdirp(root)
  inspect(default_entries.length(), content="1")
  assert_true(default_entries[0].stats == None)
  let entries = readdirp(root, options={
    ..Options::default(),
    always_stat: true,
  })
  inspect(entries.length(), content="1")
  inspect(entries[0].basename, content=".hidden")
  match entries[0].stats {
    Some(stats) => inspect(stats.size, content="3")
    None => fail("expected stats")
  }
  test_remove_tree(root)
}
