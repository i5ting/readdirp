// Blackbox tests run against the package's public API. Use `@readdirp` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "native consumers can call readdirp" {
  let options = @readdirp.Options::{ ..@readdirp.Options::default(), depth: 0 }
  let entries = @readdirp.readdirp(".", options~)
  assert_true(
    entries.any(entry => {
      entry.path == "README.mbt.md" || entry.path == "moon.mod.json"
    }),
  )
}
