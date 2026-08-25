///|
pub fn publication_title_from_path(path : String) -> String {
  let slash_parts = path.split("/").collect()
  let after_slash = slash_parts[slash_parts.length() - 1].to_owned()
  let backslash_parts = after_slash.split("\\").collect()
  let file_name = backslash_parts[backslash_parts.length() - 1].to_owned()
  let extension_parts = file_name.split(".").collect()
  if extension_parts.length() <= 1 ||
    (extension_parts.length() == 2 && extension_parts[0].is_empty()) {
    return file_name
  }
  let title = StringBuilder()
  for i = 0; i < extension_parts.length() - 1; i = i + 1 {
    if i > 0 {
      title.write_char('.')
    }
    title.write_string(extension_parts[i].to_owned())
  }
  title.to_string()
}
