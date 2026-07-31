///|
priv struct DocsAdapterFakeHttpClient {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for DocsAdapterFakeHttpClient with fn request(
  self,
  request,
) {
  let response_index = self.requests.length()
  self.requests.push(request)
  self.responses[response_index]
}

///|
fn docs_adapter_client(
  fake : DocsAdapterFakeHttpClient,
) -> @google_core.GoogleClient {
  @google_core.GoogleClient::new(fn() { "test-token" }, http=Some(fake))
}

///|
async test "create document uses a title-only Docs REST request" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"doc-123\"}"),
    ],
  }
  match create_document(docs_adapter_client(fake), "A \"quoted\" title") {
    Ok(document_id) => inspect(document_id, content="doc-123")
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  inspect(
    fake.requests[0].url,
    content="https://docs.googleapis.com/v1/documents",
  )
  assert_eq(
    fake.requests[0].body,
    Some("{\"title\":\"A \\\"quoted\\\" title\"}"),
  )
  inspect(fake.requests[0].headers["Content-Type"], content="application/json")
}

///|
async test "batch update lowers a table then following paragraph at final Docs indexes" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  let markdown =
    #|| Head |
    #|| --- |
    #|| Cell |
    #|
    #|after
  let plan = match @pumd.render_markdown(markdown) {
    Ok(document) => compile_docs_update_plan(document)
    Err(_) => abort("fixture must render")
  }
  match batch_update_document(docs_adapter_client(fake), "doc-123", plan) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  let request = fake.requests[0]
  inspect(
    request.url,
    content="https://docs.googleapis.com/v1/documents/doc-123:batchUpdate",
  )
  let body = match request.body {
    Some(body) => body
    None => abort("batch update must have JSON")
  }
  assert_true(@json.valid(body))
  // First-cell index is L + 4. The second row adds two cell positions plus
  // one row separator, then the first cell's four UTF-16 units shift it.
  assert_true(body.contains("\"location\":{\"index\":5}"))
  assert_true(body.contains("\"location\":{\"index\":12}"))
  // docs_plan already advanced the body cursor to the final table width.
  assert_true(body.contains("\"location\":{\"index\":18}"))
  assert_true(body.contains("\"weightedFontFamily\""))
  assert_true(body.contains("\"backgroundColor\""))
  assert_true(body.contains("\"updateTableCellStyle\""))
}

///|
async test "batch update preserves UTF-16 ranges, links, list presets, and colors" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  let markdown =
    #|- [🚀](https://example.test "rocket")
    #|
    #|`code`
  let plan = match @pumd.render_markdown(markdown) {
    Ok(document) => compile_docs_update_plan(document)
    Err(_) => abort("fixture must render")
  }
  match batch_update_document(docs_adapter_client(fake), "doc-123", plan) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  let body = match fake.requests[0].body {
    Some(body) => body
    None => abort("batch update must have JSON")
  }
  assert_true(@json.valid(body))
  assert_true(body.contains("\"endIndex\":3"))
  assert_true(body.contains("\"link\":{\"url\":\"https://example.test\"}"))
  assert_true(body.contains("\"BULLET_DISC_CIRCLE_SQUARE\""))
  assert_true(body.contains("\"foregroundColor\""))
  assert_true(body.contains("\"backgroundColor\""))
}

///|
async test "create document separates malformed responses from HTTP status" {
  let malformed = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  match create_document(docs_adapter_client(malformed), "title") {
    Err(AdapterDecode(_)) => ()
    _ => assert_true(false)
  }
  let failed = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, "forbidden")],
  }
  match create_document(docs_adapter_client(failed), "title") {
    Err(error) =>
      match error {
        AdapterHttpStatus(status=403, body="forbidden") =>
          assert_true(error.message().contains("drive.file"))
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
async test "batch update rejects a malformed success response" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "not-json")],
  }
  let plan = match @pumd.render_markdown("Hello") {
    Ok(document) => compile_docs_update_plan(document)
    Err(_) => abort("fixture must render")
  }
  match batch_update_document(docs_adapter_client(fake), "doc-123", plan) {
    Err(AdapterDecode(_)) => ()
    _ => assert_true(false)
  }
}

///|
async test "get document reads back the ID and unmodified Docs response body" {
  let response_body = "{\"documentId\":\"doc-123\",\"body\":{\"content\":[]}}"
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, response_body)],
  }
  match get_document(docs_adapter_client(fake), "doc-123") {
    Ok(document) => {
      inspect(document.document_id, content="doc-123")
      inspect(
        document.body,
        content="{\"documentId\":\"doc-123\",\"body\":{\"content\":[]}}",
      )
    }
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  assert_eq(fake.requests[0].method_, @google_http.HttpMethod::GET)
  inspect(
    fake.requests[0].url,
    content="https://docs.googleapis.com/v1/documents/doc-123?includeTabsContent=true",
  )
}
