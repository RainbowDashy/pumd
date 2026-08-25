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
  raise @google_http.HttpError::NetworkError(
    "Bearer creation-secret must not be printed",
  )
}

///|
priv struct PopulationNetworkFailureClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for PopulationNetworkFailureClient with fn request(
  self,
  request,
) {
  let request_index = self.requests.length()
  self.requests.push(request)
  if request_index == 0 {
    @google_http.HttpResponse::new(
      200,
      {},
      "{\"documentId\":\"ambiguous-update-1\"}",
    )
  } else {
    raise @google_http.HttpError::NetworkError(
      "Bearer transport-secret must not be printed",
    )
  }
}

///|
priv struct PopulationTimeoutClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for PopulationTimeoutClient with fn request(
  self,
  request,
) {
  let request_index = self.requests.length()
  self.requests.push(request)
  if request_index == 0 {
    @google_http.HttpResponse::new(
      200,
      {},
      "{\"documentId\":\"ambiguous-timeout-1\"}",
    )
  } else {
    raise @google_http.HttpError::TimeoutError(
      "Bearer timeout-secret must not be printed",
    )
  }
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
async test "Project Authorization selects only its provider and reaches HTTP" {
  let project_calls : Array[Unit] = []
  let adc_calls : Array[Unit] = []
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"project-1\"}"),
      @google_http.HttpResponse::new(200, {}, "{}"),
    ],
  }
  let result = publish_markdown_with_authorization(
    "Hello",
    "proposal",
    Project,
    fn() {
      project_calls.push(())
      Ok("project-token")
    },
    fn() {
      adc_calls.push(())
      Ok("adc-token")
    },
    fake,
  )
  guard result is Ok(success) else { fail("project publishing must succeed") }
  inspect(success.document_id, content="project-1")
  assert_eq(project_calls.length(), 1)
  assert_eq(adc_calls.length(), 0)
  assert_eq(fake.requests.length(), 2)
  inspect(
    fake.requests[0].headers.get("Authorization").unwrap(),
    content="Bearer project-token",
  )
}

///|
async test "ADC selects only its provider and reaches HTTP" {
  let project_calls : Array[Unit] = []
  let adc_calls : Array[Unit] = []
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"adc-1\"}"),
      @google_http.HttpResponse::new(200, {}, "{}"),
    ],
  }
  let result = publish_markdown_with_authorization(
    "Hello",
    "proposal",
    Adc,
    fn() {
      project_calls.push(())
      Ok("project-token")
    },
    fn() {
      adc_calls.push(())
      Ok("adc-token")
    },
    fake,
  )
  guard result is Ok(success) else { fail("ADC publishing must succeed") }
  inspect(success.document_id, content="adc-1")
  assert_eq(project_calls.length(), 0)
  assert_eq(adc_calls.length(), 1)
  assert_eq(fake.requests.length(), 2)
  inspect(
    fake.requests[0].headers.get("Authorization").unwrap(),
    content="Bearer adc-token",
  )
}

///|
async test "authorization provider failures never fall back and give mode-specific guidance" {
  let project_calls : Array[Unit] = []
  let adc_calls : Array[Unit] = []
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let project_failure = publish_markdown_with_authorization(
    "Hello",
    "proposal",
    Project,
    fn() {
      project_calls.push(())
      Err(CredentialsRefreshFailed)
    },
    fn() {
      adc_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard project_failure is Err(project_error) else {
    fail("expected project failure")
  }
  assert_eq(project_calls.length(), 1)
  assert_eq(adc_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
  let project_message = project_error.user_message()
  assert_true(project_message.contains("Project Authorization"))
  assert_true(project_message.contains("pumd auth setup"))

  let project_rejection = publish_markdown_with_authorization(
    "Hello",
    "proposal",
    Project,
    fn() { Err(CredentialsRejected) },
    fn() {
      adc_calls.push(())
      Err(CredentialsUnavailable)
    },
    fake,
  )
  guard project_rejection is Err(rejection_error) else {
    fail("expected rejection")
  }
  assert_eq(adc_calls.length(), 0)
  assert_true(rejection_error.user_message().contains("Project Authorization"))
  assert_true(rejection_error.user_message().contains("pumd auth setup"))

  let adc_failure = publish_markdown_with_authorization(
    "Hello",
    "proposal",
    Adc,
    fn() {
      project_calls.push(())
      Ok("must-not-be-used")
    },
    fn() {
      adc_calls.push(())
      Err(CredentialsRejected)
    },
    fake,
  )
  guard adc_failure is Err(adc_error) else { fail("expected ADC failure") }
  assert_eq(project_calls.length(), 1)
  assert_eq(adc_calls.length(), 1)
  assert_eq(fake.requests.length(), 0)
  assert_true(
    adc_error.user_message().contains("Application Default Credentials"),
  )
  assert_true(adc_error.user_message().contains("gcloud auth"))
}

///|
async test "preflight failures do not invoke either authorization provider" {
  let project_calls : Array[Unit] = []
  let adc_calls : Array[Unit] = []
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let result = publish_path_with_authorization(
    "missing.md",
    fn(_) { Err("private source error") },
    Project,
    fn() {
      project_calls.push(())
      Ok("must-not-be-used")
    },
    fn() {
      adc_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard result is Err(SourceAccess(path="missing.md")) else {
    fail("expected source error")
  }
  assert_eq(project_calls.length(), 0)
  assert_eq(adc_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)

  let render_result = publish_markdown_with_authorization(
    "![diagram](diagram.png)",
    "proposal",
    Adc,
    fn() {
      project_calls.push(())
      Ok("must-not-be-used")
    },
    fn() {
      adc_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard render_result is Err(Rendering(_)) else {
    fail("expected rendering error")
  }
  assert_eq(project_calls.length(), 0)
  assert_eq(adc_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)

  let invalid_document = @pumd.DesiredDocument::{
    metadata: { title: None, locale: None },
    render_metadata: {
      style_profile_id: "pumd.default",
      style_profile_version: 3,
    },
    content: [@pumd.StructuralElement::Table({ rows: [], provenance: None })],
    provenance: None,
  }
  let planning_result = publish_desired_document_with_authorization(
    invalid_document,
    "proposal",
    Project,
    fn() {
      project_calls.push(())
      Ok("must-not-be-used")
    },
    fn() {
      adc_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard planning_result is Err(Planning(_)) else {
    fail("expected planning error")
  }
  assert_eq(project_calls.length(), 0)
  assert_eq(adc_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "prepared first publish offers setup only after local preflight and resumes once accepted" {
  let effects : Array[String] = []
  let prepared = prepare_publication_path("proposal.md", fn(_) {
    effects.push("read")
    Ok("Hello")
  })
  guard prepared is Ok(publication) else { fail("preflight must succeed") }
  assert_eq(effects.length(), 1)
  assert_eq(effects[0], "read")
  let token_attempts = [0]
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"onboard-1\"}"),
      @google_http.HttpResponse::new(200, {}, "{}"),
    ],
  }
  let result = publish_prepared_with_project_onboarding(
    publication,
    true,
    fn() {
      token_attempts[0] = token_attempts[0] + 1
      effects.push("token")
      if token_attempts[0] == 1 {
        Err(CredentialsNotConfigured)
      } else {
        Ok("project-token")
      }
    },
    fn() {
      effects.push("offer")
      true
    },
    fn() {
      effects.push("setup")
      Ok(())
    },
    fake,
  )
  guard result is Ok(success) else {
    fail("accepted setup must resume publish")
  }
  inspect(success.document_id, content="onboard-1")
  assert_eq(effects.length(), 5)
  assert_eq(effects[0], "read")
  assert_eq(effects[1], "token")
  assert_eq(effects[2], "offer")
  assert_eq(effects[3], "setup")
  assert_eq(effects[4], "token")
  assert_eq(fake.requests.length(), 2)
}

///|
async test "first publish decline and noninteractive mode never start setup" {
  let prepared = prepare_publication_markdown("Hello", "proposal")
  guard prepared is Ok(publication) else { fail("preflight must succeed") }
  let offers = [0]
  let setups = [0]
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let declined = publish_prepared_with_project_onboarding(
    publication,
    true,
    fn() { Err(CredentialsNotConfigured) },
    fn() {
      offers[0] = offers[0] + 1
      false
    },
    fn() {
      setups[0] = setups[0] + 1
      Ok(())
    },
    fake,
  )
  guard declined is Err(Authentication(problem=CredentialsNotConfigured, ..)) else {
    fail("decline must preserve the missing-setup failure")
  }
  assert_eq(offers[0], 1)
  assert_eq(setups[0], 0)
  let noninteractive = publish_prepared_with_project_onboarding(
    publication,
    false,
    fn() { Err(CredentialsNotConfigured) },
    fn() {
      offers[0] = offers[0] + 1
      true
    },
    fn() {
      setups[0] = setups[0] + 1
      Ok(())
    },
    fake,
  )
  guard noninteractive
    is Err(Authentication(problem=CredentialsNotConfigured, ..)) else {
    fail("noninteractive publish must return stable setup guidance")
  }
  assert_eq(offers[0], 1)
  assert_eq(setups[0], 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "first publish never offers setup for revoked or transient refresh failures" {
  let prepared = prepare_publication_markdown("Hello", "proposal")
  guard prepared is Ok(publication) else { fail("preflight must succeed") }
  let offers = [0]
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  for
    problem in [
      AuthenticationProblem::CredentialsRejected,
      AuthenticationProblem::CredentialsRefreshFailed,
    ] {
    let result = publish_prepared_with_project_onboarding(
      publication,
      true,
      fn() { Err(problem) },
      fn() {
        offers[0] = offers[0] + 1
        true
      },
      fn() { Ok(()) },
      fake,
    )
    guard result is Err(Authentication(problem=actual, ..)) else {
      fail("token failure must remain structured")
    }
    assert_eq(actual, problem)
  }
  assert_eq(offers[0], 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "ephemeral token publishing has distinct secret-free guidance" {
  let prepared = prepare_publication_markdown("Hello", "proposal")
  guard prepared is Ok(publication) else { fail("preflight must succeed") }
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let result = publish_prepared(
    publication,
    Ephemeral,
    fn() { Err(CredentialsNotConfigured) },
    fake,
  )
  guard result is Err(error) else { fail("missing token must fail") }
  let message = error.user_message()
  assert_true(message.contains("PUMD_ACCESS_TOKEN"))
  assert_false(message.contains("token-secret"))
  assert_eq(fake.requests.length(), 0)
}

///|
async test "complete supported document still publishes through the public seam" {
  let source =
    #|# Heading 🚀
    #|
    #|## Section
    #|
    #|A **strong** *emphasis* [link](https://example.test) with `inline code`.
    #|
    #|```text
    #|fenced code
    #|```
    #|
    #|1. ordered
    #|   - nested
    #|
    #|| Header | Right |
    #|| --- | ---: |
    #|| 世界 | Cell |
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"full-1\"}"),
      @google_http.HttpResponse::new(200, {}, "{}"),
    ],
  }
  let result = publish_markdown(
    source,
    "complete",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Ok(success) else { assert_true(false) }
  inspect(success.document_id, content="full-1")
  assert_eq(fake.requests.length(), 2)
  let body = fake.requests[1].body.unwrap()
  assert_true(body.contains("\"namedStyleType\":\"TITLE\""))
  assert_true(body.contains("HEADING_1"))
  assert_true(body.contains("\"bold\":true"))
  assert_true(body.contains("\"italic\":true"))
  assert_true(body.contains("https://example.test"))
  assert_true(body.contains("Roboto Mono"))
  assert_true(body.contains("NUMBERED_DECIMAL_ALPHA_ROMAN"))
  assert_true(body.contains("BULLET_DISC_CIRCLE_SQUARE"))
  assert_true(body.contains("\"insertTable\""))
  assert_true(body.contains("世界"))
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
async test "source access failure stops before authentication and HTTP" {
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let token_calls : Array[Unit] = []
  let result = publish_path(
    "missing.md",
    fn(_) { Err("credential=reader-secret") },
    fn() {
      token_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is SourceAccess(path="missing.md") else { assert_true(false) }
  let message = error.user_message()
  assert_true(message.contains("source access failed"))
  assert_true(message.contains("missing.md"))
  assert_true(!message.contains("reader-secret"))
  assert_eq(token_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "Desired Document planning failure stops before authentication and HTTP" {
  let invalid_document = @pumd.DesiredDocument::{
    metadata: { title: None, locale: None },
    render_metadata: {
      style_profile_id: "pumd.default",
      style_profile_version: 3,
    },
    content: [@pumd.StructuralElement::Table({ rows: [], provenance: None })],
    provenance: None,
  }
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let token_calls : Array[Unit] = []
  let result = publish_desired_document(
    invalid_document,
    "proposal",
    fn() {
      token_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is Planning(_) else { assert_true(false) }
  assert_true(error.user_message().contains("planning failed"))
  assert_eq(token_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "unwritable ordered-list starts stop before authentication and HTTP" {
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let token_calls : Array[Unit] = []
  let result = publish_markdown(
    "3. third",
    "proposal",
    fn() {
      token_calls.push(())
      Ok("must-not-be-used")
    },
    fake,
  )
  guard result is Err(error) else { fail("publish must reject list start") }
  guard error is Planning(_) else { fail("list start must fail in planning") }
  assert_true(error.user_message().contains("starting at 3"))
  assert_eq(token_calls.length(), 0)
  assert_eq(fake.requests.length(), 0)
}

///|
async test "authentication failure produces zero HTTP" {
  let fake = FakeHttpClient::{ requests: [], responses: [] }
  let result = @publish.publish_markdown(
    "Hello",
    "proposal",
    fn() { Err(CredentialsUnavailable) },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error
    is Authentication(problem=CredentialsUnavailable, created_document=None, ..) else {
    assert_true(false)
  }
  assert_true(error.user_message().contains("Application Default Credentials"))
  assert_true(error.user_message().contains("gcloud auth"))
  assert_eq(fake.requests.length(), 0)
}

///|
test "authentication guidance distinguishes invalid and unrefreshable ADC" {
  let invalid_error : PublishError = Authentication(
    authorization_mode=Adc,
    problem=CredentialsInvalid,
    created_document=None,
  )
  let refresh_error : PublishError = Authentication(
    authorization_mode=Adc,
    problem=CredentialsRefreshFailed,
    created_document=None,
  )
  let invalid = invalid_error.user_message()
  let refresh = refresh_error.user_message()
  assert_true(invalid.contains("invalid"))
  assert_true(refresh.contains("expired or could not be refreshed"))
  assert_true(invalid != refresh)
  assert_true(invalid.contains("gcloud auth"))
  assert_true(refresh.contains("gcloud auth"))
}

///|
async test "creation permission failure is actionable and never populates" {
  let response_body = "{\"error\":{\"code\":403,\"message\":\"Bearer private-token\",\"status\":\"PERMISSION_DENIED\"}}"
  let fake = FakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, response_body)],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is Permission(stage=DocumentCreation, created_document=None, ..) else {
    assert_true(false)
  }
  let message = error.user_message()
  assert_true(message.contains("permission"))
  assert_true(message.contains("drive.file"))
  assert_true(!message.contains("private-token"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "creation throttling is safe to retry later and never populates" {
  let response_body = "{\"error\":{\"code\":403,\"message\":\"private quota name\",\"errors\":[{\"reason\":\"rateLimitExceeded\"}]}}"
  let fake = FakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, response_body)],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is Throttled(stage=DocumentCreation, created_document=None) else {
    assert_true(false)
  }
  let message = error.user_message()
  assert_true(message.contains("wait and retry later"))
  assert_true(!message.contains("private quota name"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "creation rejects expired credentials as authentication failure" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        401,
        {},
        "{\"error\":{\"code\":401,\"message\":\"Bearer expired-secret\",\"status\":\"UNAUTHENTICATED\"}}",
      ),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error
    is Authentication(problem=CredentialsRejected, created_document=None, ..) else {
    assert_true(false)
  }
  let message = error.user_message()
  assert_true(message.contains("refresh"))
  assert_true(message.contains("Application Default Credentials"))
  assert_true(!message.contains("expired-secret"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "malformed creation response never guesses an ID or populates" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "Bearer decode-secret")],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error
    is ResponseDecode(stage=DocumentCreation, message~, created_document=None) else {
    assert_true(false)
  }
  assert_true(!message.contains("decode-secret"))
  let user_message = error.user_message()
  assert_true(user_message.contains("remote mutation may have succeeded"))
  assert_true(user_message.contains("inspect Google Drive before retrying"))
  assert_true(user_message.contains("will not retry automatically"))
  assert_true(!user_message.contains("decode-secret"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "empty creation document ID never constructs publication identity" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"\"}"),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result
    is Err(ResponseDecode(stage=DocumentCreation, created_document=None, ..)) else {
    assert_true(false)
  }
  assert_eq(fake.requests.length(), 1)
  assert_true(!fake.requests[0].url.has_suffix(":batchUpdate"))
}

///|
async test "generic creation HTTP failure is sanitized and never populates" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(500, {}, "credential=server-secret"),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is Creation(_) else { assert_true(false) }
  let user_message = error.user_message()
  assert_true(user_message.contains("HTTP 500"))
  assert_true(user_message.contains("for a 5xx response, wait and retry later"))
  assert_true(user_message.contains("report the status to the pumd maintainer"))
  assert_true(!user_message.contains("server-secret"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "generic population HTTP failure retains publication identity" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"server-1\"}"),
      @google_http.HttpResponse::new(500, {}, "credential=server-secret"),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is Population(created_document~, message~) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="server-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/server-1/edit",
  )
  assert_true(message.contains("HTTP 500"))
  let user_message = error.user_message()
  assert_true(user_message.contains("for a 5xx response, wait and retry later"))
  assert_true(user_message.contains("report the status to the pumd maintainer"))
  assert_true(!message.contains("server-secret"))
  assert_true(!user_message.contains("server-secret"))
  assert_eq(fake.requests.length(), 2)
  assert_true(fake.requests[1].url.has_suffix(":batchUpdate"))
}

///|
async test "population permission failure retains the created document identity" {
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
  guard result is Err(error) else { assert_true(false) }
  guard error
    is Permission(
      stage=DocumentPopulation,
      created_document=Some(created_document),
      ..
    ) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="orphan-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/orphan-1/edit",
  )
  assert_true(error.user_message().contains("drive.file"))
  assert_true(!error.user_message().contains("missing scope"))
  assert_eq(fake.requests.length(), 2)
}

///|
async test "population throttling retains identity and uses one batch request" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"quota-1\"}"),
      @google_http.HttpResponse::new(
        429,
        {},
        "{\"error\":{\"code\":429,\"message\":\"private quota name\",\"status\":\"RESOURCE_EXHAUSTED\"}}",
      ),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error
    is Throttled(
      stage=DocumentPopulation,
      created_document=Some(created_document)
    ) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="quota-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/quota-1/edit",
  )
  assert_true(error.user_message().contains("wait and retry later"))
  assert_true(!error.user_message().contains("private quota name"))
  assert_eq(fake.requests.length(), 2)
  assert_true(fake.requests[1].url.has_suffix(":batchUpdate"))
}

///|
async test "population authentication rejection retains created identity" {
  let fake = FakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(200, {}, "{\"documentId\":\"auth-1\"}"),
      @google_http.HttpResponse::new(
        401,
        {},
        "{\"error\":{\"code\":401,\"message\":\"Bearer expired-secret\",\"status\":\"UNAUTHENTICATED\"}}",
      ),
    ],
  }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error
    is Authentication(
      problem=CredentialsRejected,
      created_document=Some(created_document),
      ..
    ) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="auth-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/auth-1/edit",
  )
  assert_true(error.user_message().contains("refresh ADC"))
  assert_true(!error.user_message().contains("expired-secret"))
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
  guard result is Err(error) else { assert_true(false) }
  guard error
    is ResponseDecode(
      stage=DocumentPopulation,
      message~,
      created_document=Some(created_document)
    ) else {
    assert_true(false)
  }
  assert_true(!message.is_empty())
  inspect(created_document.document_id, content="decode-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/decode-1/edit",
  )
  let user_message = error.user_message()
  assert_true(user_message.contains("remote mutation may have succeeded"))
  assert_true(
    user_message.contains(
      "inspect Google Drive and the created document before retrying",
    ),
  )
  assert_true(user_message.contains("will not retry automatically"))
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
  guard result is Err(error) else { assert_true(false) }
  guard error is AmbiguousCreation else { assert_true(false) }
  let message = error.user_message()
  assert_true(message.contains("inspect Google Drive"))
  assert_true(message.contains("will not retry automatically"))
  assert_true(!message.contains("creation-secret"))
  assert_eq(fake.requests.length(), 1)
}

///|
async test "ambiguous population retains identity and requires Drive inspection" {
  let fake = PopulationNetworkFailureClient::{ requests: [] }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is AmbiguousPopulation(created_document) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="ambiguous-update-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/ambiguous-update-1/edit",
  )
  let message = error.user_message()
  assert_true(message.contains("inspect Google Drive"))
  assert_true(message.contains("will not retry automatically"))
  assert_true(!message.contains("transport-secret"))
  assert_eq(fake.requests.length(), 2)
  assert_true(fake.requests[1].url.has_suffix(":batchUpdate"))
}

///|
async test "population timeout remains ambiguous and retains identity" {
  let fake = PopulationTimeoutClient::{ requests: [] }
  let result = publish_markdown(
    "Hello",
    "proposal",
    fn() { Ok("test-token") },
    fake,
  )
  guard result is Err(error) else { assert_true(false) }
  guard error is AmbiguousPopulation(created_document) else {
    assert_true(false)
  }
  inspect(created_document.document_id, content="ambiguous-timeout-1")
  inspect(
    created_document.url,
    content="https://docs.google.com/document/d/ambiguous-timeout-1/edit",
  )
  let message = error.user_message()
  assert_true(message.contains("inspect Google Drive"))
  assert_true(message.contains("will not retry automatically"))
  assert_true(!message.contains("timeout-secret"))
  assert_eq(fake.requests.length(), 2)
  assert_true(fake.requests[1].url.has_suffix(":batchUpdate"))
}
