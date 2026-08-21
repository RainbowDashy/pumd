///|
async test "atomic source replacement preserves the old file until replacement" {
  let directory = "_build/source-replace-success"
  @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  @async_fs.mkdir(directory, permission=0o700, recursive=true)
  let path = directory + "/notes.md"
  @async_fs.write_file(path, "old\r\nbytes", create_mode=@async_fs.CreateNew)

  assert_eq(atomic_replace_source(path, "new\r\nbytes"), Ok(()))
  assert_eq(@async_fs.read_file(path).text(), "new\r\nbytes")
  @async_fs.rmdir(directory, recursive=true)
}
