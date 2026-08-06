///|
priv struct CommentsFakeHttpClient {
  requests : Array[@google_http.HttpRequest]
  responses : Array[@google_http.HttpResponse]
}

///|
impl @google_http.HttpClient for CommentsFakeHttpClient with fn request(
  self,
  request,
) {
  let index = self.requests.length()
  self.requests.push(request)
  self.responses[index]
}

///|
priv struct CommentsNetworkFailureClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for CommentsNetworkFailureClient with fn request(
  self,
  request,
) {
  self.requests.push(request)
  raise @google_http.HttpError::NetworkError("deterministic network failure")
}

///|
priv struct CommentsPagingCapClient {
  requests : Array[@google_http.HttpRequest]
}

///|
impl @google_http.HttpClient for CommentsPagingCapClient with fn request(
  self,
  request,
) {
  self.requests.push(request)
  @google_http.HttpResponse::new(200, {}, "{\"nextPageToken\":\"more\"}")
}

///|
fn comments_client(
  fake : &@google_http.HttpClient,
) -> @google_core.GoogleClient {
  @google_core.GoogleClient::new(fn() { "test-token" }, http=Some(fake))
}

///|
async test "comment inspection requests only required fields when no comments exist" {
  let fake = CommentsFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "{}")],
  }
  let result = inspect_comments(comments_client(fake), "doc-123")
  guard result is Ok(inspection) else { fail("expected an inspection") }
  assert_eq(inspection, { unresolved: 0, pages: 1 })
  assert_eq(fake.requests.length(), 1)
  assert_true(
    fake.requests[0].url.contains("fields=nextPageToken,comments(id,resolved)"),
  )
  assert_true(fake.requests[0].url.contains("pageSize=100"))
  assert_true(!fake.requests[0].url.contains("pageToken="))
}

///|
async test "comment inspection ignores resolved comments" {
  let fake = CommentsFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"comments\":[{\"id\":\"one\",\"resolved\":true},{\"id\":\"two\",\"resolved\":true}]}",
      ),
    ],
  }
  let result = inspect_comments(comments_client(fake), "doc-123")
  guard result is Ok(inspection) else { fail("expected an inspection") }
  assert_eq(inspection, { unresolved: 0, pages: 1 })
}

///|
async test "comment inspection counts false and absent resolved fields" {
  let fake = CommentsFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"comments\":[{\"id\":\"resolved\",\"resolved\":true},{\"id\":\"open\",\"resolved\":false},{\"id\":\"implicit-open\"}]}",
      ),
    ],
  }
  let result = inspect_comments(comments_client(fake), "doc-123")
  guard result is Ok(inspection) else { fail("expected an inspection") }
  assert_eq(inspection, { unresolved: 2, pages: 1 })
}

///|
async test "comment inspection follows a page token" {
  let fake = CommentsFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"comments\":[{\"id\":\"one\",\"resolved\":false}],\"nextPageToken\":\"next-token\"}",
      ),
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"comments\":[{\"id\":\"two\",\"resolved\":true},{\"id\":\"three\"}]}",
      ),
    ],
  }
  let result = inspect_comments(comments_client(fake), "doc-123")
  guard result is Ok(inspection) else { fail("expected an inspection") }
  assert_eq(inspection, { unresolved: 2, pages: 2 })
  assert_eq(fake.requests.length(), 2)
  assert_true(fake.requests[1].url.contains("pageToken=next-token"))
}

///|
async test "comment inspection returns HTTP statuses without classifying them" {
  let server_error = CommentsFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(500, {}, "server error")],
  }
  let forbidden = CommentsFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(403, {}, "forbidden")],
  }
  guard inspect_comments(comments_client(server_error), "doc-123")
    is Err(HttpStatus(status=500)) else {
    fail("expected HTTP 500")
  }
  guard inspect_comments(comments_client(forbidden), "doc-123")
    is Err(HttpStatus(status=403)) else {
    fail("expected HTTP 403")
  }
}

///|
async test "comment inspection returns transport and decode failures" {
  let network = CommentsNetworkFailureClient::{ requests: [] }
  guard inspect_comments(comments_client(network), "doc-123")
    is Err(Transport(_)) else {
    fail("expected a transport failure")
  }
  let malformed = CommentsFakeHttpClient::{
    requests: [],
    responses: [@google_http.HttpResponse::new(200, {}, "not-json")],
  }
  guard inspect_comments(comments_client(malformed), "doc-123")
    is Err(Decode(_)) else {
    fail("expected a decode failure")
  }
}

///|
async test "comment inspection never returns a partial result after a malformed later page" {
  let fake = CommentsFakeHttpClient::{
    requests: [],
    responses: [
      @google_http.HttpResponse::new(
        200,
        {},
        "{\"comments\":[{\"id\":\"one\",\"resolved\":false}],\"nextPageToken\":\"next\"}",
      ),
      @google_http.HttpResponse::new(200, {}, "not-json"),
    ],
  }
  guard inspect_comments(comments_client(fake), "doc-123") is Err(Decode(_)) else {
    fail("expected a later-page decode failure")
  }
  assert_eq(fake.requests.length(), 2)
}

///|
async test "comment inspection fails closed at the page limit" {
  let fake = CommentsPagingCapClient::{ requests: [] }
  guard inspect_comments(comments_client(fake), "doc-123")
    is Err(TooManyPages(50)) else {
    fail("expected the page safety limit")
  }
  assert_eq(fake.requests.length(), 50)
}
