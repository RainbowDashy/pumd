///|
priv struct FakeHttpClient {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for FakeHttpClient with fn request(self, request) {
  let response_index = self.requests.length()
  self.requests.push(request)
  self.responses[response_index]
}

///|
priv struct NetworkFailureClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for NetworkFailureClient with fn request(
  self,
  request,
) {
  self.requests.push(request)
  raise @google_http.HttpError::NetworkError("connection outcome is unknown")
}

///|
async test "publish creates then populates one document through injected HTTP" {
  let responses = [
    @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"doc-123\"}"),
    @google_http.HttpResponse::new(200, {}, "{}"),
  ]
  let fake = FakeHttpClient::{ requests: [], responses }
  let result = @publish.publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  match result {
    Ok(success) => {
      inspect(success.document_id, content="doc-123")
      inspect(
        success.url,
        content="https://docs.google.com/document/d/doc-123/edit",
      )
    }
    Err(_) => assert_true(false)
  }
  assert_eq(fake.requests.length(), 2)
  inspect(
    fake.requests[0].url,
    content="https://docs.googleapis.com/v1/documents",
  )
  inspect(
    fake.requests[1].url,
    content="https://docs.googleapis.com/v1/documents/doc-123:batchUpdate",
  )
  inspect(fake.requests[0].body.unwrap(), content="{\"title\":\"proposal\"}")
  assert_true(
    fake.requests[1].body
    .unwrap()
    .contains(
      "{\"insertText\":{\"location\":{\"index\":1},\"text\":\"Hello\\n\"}}",
    ),
  )
  inspect(
    fake.requests[0].headers.get("Authorization").unwrap(),
    content="Bearer test-token",
  )
}

///|
async test "rendering diagnostics stop before authentication and HTTP" {
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let token_calls : Array[Unit] = []
  let result = @publish.publish_markdown(
    "![diagram](diagram.png)",
    "proposal",
    fn() {
      token_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard result is Err(@publish.PublishError::Rendering(_)) else {
    assert_true(false)
  }
  assert_eq(token_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "authentication failure produces zero HTTP" {
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let result = @publish.publish_markdown(
    "Hello",
    "proposal",
    fn() { Err("ADC is unavailable") },
    fake,
  )
  guard result is Err(@publish.PublishError::Authentication(message)) else {
    assert_true(false)
  }
  inspect(message, content="ADC is unavailable")
  assert_eq(fake.requests.length(), 0)
}

///|
async test "population failure retains the created document identity" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"orphan-1\"}"),
      @google_http.HttpResponse::new(403, {}, "missing scope"),
    ],
  }
  let result = @publish.publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result
    is Err(@publish.PublishError::Population(document_id~, url~, message~)) else {
    assert_true(false)
  }
  inspect(document_id, content="orphan-1")
  inspect(url, content="https://docs.google.com/document/d/orphan-1/edit")
  assert_true(message.contains("403"))
  assert_eq(fake.requests.length(), 2)
}

///|
async test "batch response decoding failure keeps its own stage" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"decode-1\"}"),
      @google_http.HttpResponse::new(200, {}, "not-json"),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result
    is Err(
      ResponseDecode(
        stage="population",
        message~,
        document_id=Some(document_id),
        url=Some(url)
      )
    ) else {
    assert_true(false)
  }
  assert_true(!message.is_empty())
  inspect(document_id, content="decode-1")
  inspect(url, content="https://docs.google.com/document/d/decode-1/edit")
  assert_eq(fake.requests.length(), 2)
}

///|
async test "ambiguous creation transport failure is not retried" {
  let fake = NetworkFailureClient::{ requests: [] }
  let result = @publish.publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(@publish.PublishError::AmbiguousCreation(message)) else {
    assert_true(false)
  }
  inspect(message, content="connection outcome is unknown")
  assert_eq(fake.requests.length(), 1)
}
