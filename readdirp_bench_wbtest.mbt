///|
fn create_bench_fixture(
  root : String,
  dir_count : Int,
  files_per_dir : Int,
) -> Unit raise ReaddirpError {
  test_remove_tree(root)
  test_create_dir(root)
  for dir_index in 0..<dir_count {
    let dir = join_path(root, "dir-\{dir_index}")
    test_create_dir(dir)
    for file_index in 0..<files_per_dir {
      test_write_file(join_path(dir, "file-\{file_index}.txt"), "content")
    }
  }
}

///|
test "bench recursive readdirp all entries" (b : @bench.T) {
  let root = "./_build/readdirp-bench"
  create_bench_fixture(root, 20, 50)
  b.bench(
    name="readdirp_all_1020_entries",
    fn() {
      try readdirp(root, options={ ..Options::default(), type_: All }) catch {
        _ => b.keep(0)
      } noraise {
        entries => b.keep(entries.length())
      }
    },
    count=1,
  )
  b.bench(
    name="readdirp_files_always_stat_1000_entries",
    fn() {
      try
        readdirp(root, options={ ..Options::default(), always_stat: true })
      catch {
        _ => b.keep(0)
      } noraise {
        entries => b.keep(entries.length())
      }
    },
    count=1,
  )
  test_remove_tree(root)
}
