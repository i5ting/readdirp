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
    stats: if include_stats {
      Some(stats)
    } else {
      None
    },
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
fn add_warning(
  warnings : Array[ReaddirpWarning],
  path : String,
  message : String,
) -> Unit {
  warnings.push(
    warning_for(path, warning_kind_from_errno(last_errno()), message),
  )
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
    try {
      let entry = make_entry(
        root,
        full_path,
        name,
        !options.lstat,
        options.always_stat,
      )
      if entry.kind == Directory {
        if (options.directory_filter)(entry) {
          if should_emit(entry, options.type_) {
            entries.push(entry)
          }
          if current_depth < options.depth {
            walk_dir(
              root,
              full_path,
              current_depth + 1,
              options,
              entries,
              warnings,
            ) catch {
              ReaddirpError(message) =>
                add_warning(warnings, full_path, message)
            }
          }
        }
      } else if (options.file_filter)(entry) &&
        should_emit(entry, options.type_) {
        entries.push(entry)
      }
    } catch {
      ReaddirpError(message) => add_warning(warnings, full_path, message)
    }
  }
}

///|
pub fn readdirp_report(
  root : String,
  options? : Options = Options::default(),
) -> ReaddirpReport raise ReaddirpError {
  guard root != "" else { raise ReaddirpError("root argument is required") }
  guard options.depth >= 0 else {
    raise ReaddirpError("depth must be non-negative")
  }
  let normalized_root = normalize_path(root)
  let absolute_root = real_path(normalized_root)
  let root_stats = stat_path(absolute_root, follow_symlink=true)
  guard file_kind_from_mode(root_stats.mode) == Directory else {
    raise ReaddirpError("root must be a directory")
  }
  let entries = []
  let warnings = []
  walk_dir(absolute_root, absolute_root, 0, options, entries, warnings)
  { entries, warnings }
}

///|
pub fn readdirp(
  root : String,
  options? : Options = Options::default(),
) -> Array[EntryInfo] raise ReaddirpError {
  readdirp_report(root, options~).entries
}
