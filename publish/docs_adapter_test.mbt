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
priv struct DocsAdapterNetworkFailureClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for DocsAdapterNetworkFailureClient with fn request(
  self,
  request,
) {
  self.requests.push(request)
  raise @google_http.HttpError::NetworkError("deterministic network failure")
}

///|
fn docs_adapter_revision_plan() -> DocsUpdatePlan {
  let markdown =
    #|- body
    #|
    #|| Header |
    #|| --- |
    #|| cell |
  let plan = match @pumd.render_markdown(markdown) {
    Ok(document) => compile_docs_update_plan(document)
    Err(_) => abort("fixture must render")
  }
  plan.append_delete_content_range(start_index=1, end_index=2)
  plan
}

///|
fn count_occurrences(body : String, needle : String) -> Int {
  let mut count = 0
  for _ in body.split(needle) {
    count = count + 1
  }
  count - 1
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
async test "batch update applies table cell alignment after paragraph style" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  let markdown =
    #|| Head |
    #|| ---: |
    #|| Cell |
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
  let paragraph_style = "\"range\":{\"startIndex\":5,\"endIndex\":10},\"paragraphStyle\":{\"namedStyleType\":\"NORMAL_TEXT\""
  let alignment = "\"range\":{\"startIndex\":5,\"endIndex\":10},\"paragraphStyle\":{\"alignment\":\"END\"},\"fields\":\"alignment\""
  match (body.find(paragraph_style), body.find(alignment)) {
    (Some(paragraph_style_index), Some(alignment_index)) =>
      assert_true(paragraph_style_index < alignment_index)
    _ => assert_true(false)
  }
  assert_true(body.contains("\"backgroundColor\""))
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
async test "batch update reapplies quoted list decoration after native bullets" {
  let profile = @pumd.builtin_style_profile()
  let document : @pumd.DesiredDocument = {
    metadata: { title: None, locale: None },
    render_metadata: {
      style_profile_id: profile.id,
      style_profile_version: profile.version,
    },
    content: [
      @pumd.StructuralElement::Paragraph({
        runs: [
          {
            content: "zero",
            style: profile.body_text,
            link: None,
            provenance: None,
          },
        ],
        style: {
          ..profile.body,
          indent_start_points: Some(54),
          indent_first_line_points: Some(36),
          border_left: Some(profile.quote_border),
        },
        bullet: Some({ kind: @pumd.ListKind::Bullet, nesting_level: 0 }),
        provenance: None,
      }),
      @pumd.StructuralElement::Paragraph({
        runs: [
          {
            content: "one",
            style: profile.body_text,
            link: None,
            provenance: None,
          },
        ],
        style: {
          ..profile.body,
          indent_start_points: Some(90),
          indent_first_line_points: Some(72),
          border_left: Some(profile.quote_border),
        },
        bullet: Some({ kind: @pumd.ListKind::Bullet, nesting_level: 1 }),
        provenance: None,
      }),
      @pumd.StructuralElement::Paragraph({
        runs: [
          {
            content: "two",
            style: profile.body_text,
            link: None,
            provenance: None,
          },
        ],
        style: {
          ..profile.body,
          indent_start_points: Some(126),
          indent_first_line_points: Some(108),
          border_left: Some(profile.quote_border),
        },
        bullet: Some({ kind: @pumd.ListKind::Bullet, nesting_level: 2 }),
        provenance: None,
      }),
    ],
    provenance: None,
  }
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  match
    batch_update_document(
      docs_adapter_client(fake),
      "doc-123",
      compile_docs_update_plan(document),
    ) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  let body = match fake.requests[0].body {
    Some(body) => body
    None => abort("batch update must have JSON")
  }
  assert_true(@json.valid(body))
  assert_true(
    body.contains(
      "\"fields\":\"namedStyleType,lineSpacing,spaceAbove,spaceBelow,indentStart,indentFirstLine,borderLeft\"",
    ),
  )
  let bullets0 = "\"createParagraphBullets\":{\"range\":{\"startIndex\":1,\"endIndex\":6}"
  let decoration0 = "\"range\":{\"startIndex\":1,\"endIndex\":6},\"paragraphStyle\":{\"indentStart\":{\"magnitude\":54,\"unit\":\"PT\"}"
  let bullets1 = "\"createParagraphBullets\":{\"range\":{\"startIndex\":6,\"endIndex\":11}"
  let decoration1 = "\"range\":{\"startIndex\":6,\"endIndex\":10},\"paragraphStyle\":{\"indentStart\":{\"magnitude\":90,\"unit\":\"PT\"},\"indentFirstLine\":{\"magnitude\":72,\"unit\":\"PT\"},\"borderLeft\":{\"color\":{\"color\":{\"rgbColor\":{\"red\":0.7176470588235294,\"green\":0.7176470588235294,\"blue\":0.7176470588235294}}},\"width\":{\"magnitude\":1,\"unit\":\"PT\"},\"padding\":{\"magnitude\":6,\"unit\":\"PT\"},\"dashStyle\":\"SOLID\"}},\"fields\":\"indentStart,indentFirstLine,borderLeft\""
  let bullets2 = "\"createParagraphBullets\":{\"range\":{\"startIndex\":10,\"endIndex\":16}"
  let decoration2 = "\"range\":{\"startIndex\":10,\"endIndex\":14},\"paragraphStyle\":{\"indentStart\":{\"magnitude\":126,\"unit\":\"PT\"}"
  match (body.find(bullets0), body.find(decoration0)) {
    (Some(bullets_index), Some(decoration_index)) =>
      assert_true(bullets_index < decoration_index)
    _ => assert_true(false)
  }
  match (body.find(bullets1), body.find(decoration1)) {
    (Some(bullets_index), Some(decoration_index)) =>
      assert_true(bullets_index < decoration_index)
    _ => assert_true(false)
  }
  match (body.find(bullets2), body.find(decoration2)) {
    (Some(bullets_index), Some(decoration_index)) =>
      assert_true(bullets_index < decoration_index)
    _ => assert_true(false)
  }
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
        AdapterHttpStatus(status=403, kind=Some(PermissionDenied)) =>
          assert_true(error.message().contains("drive.file"))
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
async test "adapter classifies Google permission errors without exposing response details" {
  let response_body = "{\"error\":{\"code\":403,\"message\":\"Bearer secret-token must never be printed\",\"status\":\"PERMISSION_DENIED\"}}"
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, response_body)],
  }
  match create_document(docs_adapter_client(fake), "title") {
    Err(error) => {
      guard error is AdapterHttpStatus(status=403, kind=Some(PermissionDenied)) else {
        assert_true(false)
      }
      assert_true(error.message().contains("drive.file"))
      assert_true(!error.message().contains("secret-token"))
    }
    _ => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
}

///|
async test "googleapis error parsing classifies a neutral HTTP status" {
  let response_body = "{\"error\":{\"code\":400,\"message\":\"private permission detail\",\"status\":\"PERMISSION_DENIED\"}}"
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(400, {}, response_body)],
  }
  match create_document(docs_adapter_client(fake), "title") {
    Err(error) => {
      guard error is AdapterHttpStatus(status=400, kind=Some(PermissionDenied)) else {
        fail("googleapis error status must classify permission denial")
      }
      assert_true(!error.message().contains("private permission detail"))
    }
    Ok(_) => fail("permission error must not create a document")
  }
  assert_eq(fake.requests.length(), 1)
}

///|
async test "adapter classifies throttling and hides malformed response bodies" {
  let throttled_body = "{\"error\":{\"code\":429,\"message\":\"private quota detail\",\"status\":\"RESOURCE_EXHAUSTED\"}}"
  let throttled = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(429, {}, throttled_body)],
  }
  match create_document(docs_adapter_client(throttled), "title") {
    Err(error) => {
      guard error is AdapterHttpStatus(status=429, kind=Some(Throttled)) else {
        assert_true(false)
      }
      assert_true(error.message().contains("wait and retry"))
      assert_true(!error.message().contains("private quota detail"))
    }
    _ => assert_true(false)
  }
  let malformed = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(500, {}, "credential=must-not-leak"),
    ],
  }
  match create_document(docs_adapter_client(malformed), "title") {
    Err(error) => {
      guard error is AdapterHttpStatus(status=500, kind=None) else {
        assert_true(false)
      }
      assert_true(!error.message().contains("must-not-leak"))
    }
    _ => assert_true(false)
  }
}

///|
async test "adapter recognizes legacy Google rate-limit reasons" {
  let response_body = "{\"error\":{\"code\":403,\"message\":\"quota detail\",\"errors\":[{\"reason\":\"rateLimitExceeded\"}]}}"
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, response_body)],
  }
  match create_document(docs_adapter_client(fake), "title") {
    Err(error) => {
      guard error is AdapterHttpStatus(status=403, kind=Some(Throttled)) else {
        assert_true(false)
      }
      assert_true(error.message().contains("wait and retry"))
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
async test "revision-controlled batch updates lower every location into the managed tab" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  match
    batch_update_document_with_revision(
      docs_adapter_client(fake),
      "doc-123",
      "tab-7",
      docs_adapter_revision_plan(),
      "revision-9",
    ) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  let body = match fake.requests[0].body {
    Some(body) => body
    None => abort("revision-controlled batch update must have JSON")
  }
  assert_true(@json.valid(body))
  assert_true(body.contains("\"writeControl\":{\"requiredRevisionId\":\"revision-9\"}"))
  assert_true(body.contains("\"insertText\""))
  assert_true(body.contains("\"updateParagraphStyle\""))
  assert_true(body.contains("\"updateTextStyle\""))
  assert_true(body.contains("\"createParagraphBullets\""))
  assert_true(body.contains("\"insertTable\""))
  assert_true(body.contains("\"updateTableCellStyle\""))
  assert_true(body.contains("\"deleteContentRange\""))
  let tab_count = count_occurrences(body, "\"tabId\":\"tab-7\"")
  assert_eq(
    tab_count,
    count_occurrences(body, "\"index\":") +
    count_occurrences(body, "\"startIndex\":"),
  )
  assert_true(tab_count >= 13)
}

///|
async test "revision-controlled batch updates classify conflicts and adapter failures" {
  let conflict = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(400, {}, "stale revision")],
  }
  match
    batch_update_document_with_revision(
      docs_adapter_client(conflict),
      "doc-123",
      "tab-7",
      docs_adapter_revision_plan(),
      "revision-9",
    ) {
    Err(RevisionConflict) => ()
    _ => assert_true(false)
  }
  let forbidden = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, "forbidden")],
  }
  match
    batch_update_document_with_revision(
      docs_adapter_client(forbidden),
      "doc-123",
      "tab-7",
      docs_adapter_revision_plan(),
      "revision-9",
    ) {
    Err(Adapter(AdapterHttpStatus(status=403, kind=Some(PermissionDenied)))) =>
      ()
    _ => assert_true(false)
  }
  let network = DocsAdapterNetworkFailureClient::{ requests: [] }
  let network_client = @google_core.GoogleClient::new(
    fn() { "test-token" },
    http=Some(network),
  )
  match
    batch_update_document_with_revision(
      network_client,
      "doc-123",
      "tab-7",
      docs_adapter_revision_plan(),
      "revision-9",
    ) {
    Err(Adapter(AdapterTransport("deterministic network failure"))) => ()
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

///|
async test "suggestion-aware document reads retain the raw body" {
  let response_body = "{\"documentId\":\"doc-123\",\"body\":{\"content\":[]}}"
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, response_body)],
  }
  match get_remote_document_body(docs_adapter_client(fake), "doc-123") {
    Ok(document) => {
      inspect(document.document_id, content="doc-123")
      inspect(document.body, content=response_body)
    }
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  assert_eq(fake.requests[0].method_, @google_http.HttpMethod::GET)
  assert_true(fake.requests[0].url.contains("includeTabsContent=true"))
  assert_true(
    fake.requests[0].url.contains("suggestionsViewMode=SUGGESTIONS_INLINE"),
  )
}

///|
async test "suggestion-aware document reads reject an empty document ID" {
  let fake = DocsAdapterFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"\"}"),
    ],
  }
  match get_remote_document_body(docs_adapter_client(fake), "doc-123") {
    Err(AdapterDecode(message)) =>
      assert_true(message.contains("empty documentId"))
    _ => assert_true(false)
  }
}
