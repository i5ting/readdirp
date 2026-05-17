///|
fn trim_trailing_slashes(path : String) -> String {
  if path == "/" {
    "/"
  } else {
    path.trim_end(chars="/").to_owned()
  }
}

///|
fn trim_leading_slashes(path : String) -> String {
  path.trim_start(chars="/").to_owned()
}

///|
fn normalize_path(path : String) -> String {
  let path = trim_trailing_slashes(path)
  if path == "" {
    "."
  } else {
    path
  }
}

///|
#warnings("-unused_value")
fn join_path(parent : String, child : String) -> String {
  let parent = trim_trailing_slashes(parent)
  let child = trim_leading_slashes(child)
  if parent == "" {
    child
  } else if parent == "/" {
    parent + child
  } else if child == "" {
    parent
  } else {
    parent + "/" + child
  }
}

///|
#warnings("-unused_value")
fn path_basename(path : String) -> String {
  let path = trim_trailing_slashes(path)
  if path == "" {
    "."
  } else if path == "/" {
    "/"
  } else {
    match path.rev_split_once("/") {
      Some((_, base)) => base.to_owned()
      None => path
    }
  }
}

///|
#warnings("-unused_value")
fn relative_path(root : String, full_path : String) -> String {
  let root = normalize_path(root)
  let full_path = normalize_path(full_path)
  match full_path.strip_prefix(root) {
    Some(path) =>
      if path == "" {
        ""
      } else if path.has_prefix("/") {
        path.trim_start(chars="/").to_owned()
      } else {
        full_path
      }
    None => full_path
  }
}
