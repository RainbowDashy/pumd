///|
async fn report_failure(message : String) -> Unit {
  @stdio.stderr.write("pumd: " + message + "\n")
  @sys.exit(1)
}

///|
async fn publish_file(path : String) -> Unit {
  let source = @fs.read_file(path).text() catch {
    error => {
      report_failure(
        "could not read or decode Markdown file `" +
        path +
        "`: " +
        error.to_string(),
      )
      return
    }
  }
  let title = @publish.publication_title_from_path(path)
  match @publish.publish_markdown_with_adc(source, title) {
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
