# readdirp

Directory walking for MoonBit native/LLVM targets.

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

`basename_filter(name)` and `basename_filter_any(names)` are small helpers for
common `file_filter` or `directory_filter` checks. Set `always_stat: true` when
each `EntryInfo` should include `stats`; otherwise stats are omitted from
returned entries.
