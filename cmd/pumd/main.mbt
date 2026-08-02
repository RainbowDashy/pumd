///|
async fn report_failure(message : String) -> Unit {
  @stdio.stderr.write("pumd: " + message + "\n")
  @sys.exit(1)
}

///|
async fn publish_file(path : String) -> Unit {
  match
    @publish.publish_path_with_adc(path, fn(source_path) {
      let source = @fs.read_file_to_string(source_path) catch {
        @fs.IOError(message) => return Err(message)
      }
      Ok(source)
    }) {
    Ok(success) => {
      @stdio.stdout.write("document ID: " + success.document_id + "\n")
      @stdio.stdout.write("edit URL: " + success.url + "\n")
    }
    Err(error) => report_failure(error.user_message())
  }
}

///|
async fn main {
  match @args.parse_publish_path(@sys.get_cli_args()) {
    Ok(path) => publish_file(path)
    Err(message) => report_failure(message)
  }
}
