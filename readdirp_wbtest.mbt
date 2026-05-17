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
}
