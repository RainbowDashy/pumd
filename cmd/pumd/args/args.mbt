///|
pub fn parse_publish_path(args : Array[String]) -> Result[String, String] {
  if args.length() == 3 && args[1] == "publish" {
    Ok(args[2])
  } else {
    Err("usage: pumd publish <markdown-path>")
  }
}
