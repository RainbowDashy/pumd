///|
/// This test is run only by `scripts/live-smoke.ps1`. The script creates a
/// temporary Markdown file and publishes it with the native CLI first, then
/// supplies the exact document identity for this readback assertion.

///|
fn compact_json(value : String) -> String {
  let result = StringBuilder::new()
  let mut inside_string = false
  let mut escaped = false
  for char in value {
    if inside_string {
      result.write_char(char)
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        inside_string = false
      }
    } else {
      match char {
        ' ' | '\n' | '\r' | '\t' => ()
        '"' => {
          result.write_char(char)
          inside_string = true
        }
        _ => result.write_char(char)
      }
    }
  }
  result.to_string()
}

///|
test "live readback compacts JSON without changing string values" {
  let response =
    #|{
    #|  "weightedFontFamily": {
    #|    "fontFamily": "Roboto Mono"
    #|  }
    #|}
  assert_eq(
    compact_json(response),
    "{\"weightedFontFamily\":{\"fontFamily\":\"Roboto Mono\"}}",
  )
}

///|
#skip("run scripts/live-smoke.ps1 after configuring ADC")
async test "live smoke reads the CLI-created document" {
  let document_id = match @sys.get_env_var("PUMD_LIVE_SMOKE_DOCUMENT_ID") {
    Some(value) => value
    None => abort("PUMD_LIVE_SMOKE_DOCUMENT_ID is required")
  }
  let url = match @sys.get_env_var("PUMD_LIVE_SMOKE_DOCUMENT_URL") {
    Some(value) => value
    None => abort("PUMD_LIVE_SMOKE_DOCUMENT_URL is required")
  }
  let title = match @sys.get_env_var("PUMD_LIVE_SMOKE_DOCUMENT_TITLE") {
    Some(value) => value
    None => abort("PUMD_LIVE_SMOKE_DOCUMENT_TITLE is required")
  }
  assert_eq(url, canonical_document_url(document_id))
  let token = match application_default_access_token() {
    Ok(token) => token
    Err(error) => abort(error.user_message())
  }
  let http = @google_http.DefaultHttpClient::new()
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let document = match get_document(client, document_id) {
    Ok(document) => document
    Err(error) => abort(error.message())
  }
  assert_eq(document.document_id, document_id)
  let required_content = [
    title, "Pumd live smoke heading 1", "Pumd live smoke heading 2", "Pumd live smoke heading 3",
    "Pumd live smoke heading 4", "Pumd live smoke heading 5", "Pumd live smoke heading 6",
    "strong", "emphasized", "https://example.com/direct", "reference link", "https://example.com/reference",
    "inline code", "fenced code", "第二行", "ordered item", "nested item", "bullet item",
    "Header", "linked",
  ]
  for fragment in required_content {
    assert_true(document.body.contains(fragment))
  }
  let compact_response = compact_json(document.body)
  let required_structure = [
    "\"namedStyleType\":\"HEADING_1\"", "\"namedStyleType\":\"HEADING_2\"", "\"namedStyleType\":\"HEADING_3\"",
    "\"namedStyleType\":\"HEADING_4\"", "\"namedStyleType\":\"HEADING_5\"", "\"namedStyleType\":\"HEADING_6\"",
    "\"bold\":true", "\"italic\":true", "Roboto Mono", "\"bullet\"", "\"table\"",
    "\"backgroundColor\"", "\"alignment\":\"END\"",
  ]
  for fragment in required_structure {
    assert_true(compact_response.contains(fragment))
  }
  println(url)
}
