///|
pub(all) struct CommentInspection {
  unresolved : Int
  pages : Int
} derive(Eq, @debug.Debug)

///|
pub(all) enum CommentsError {
  Transport(String)
  HttpStatus(status~ : Int)
  Decode(String)
  TooManyPages(Int)
} derive(Eq, @debug.Debug)

///|
pub fn CommentsError::user_message(self : CommentsError) -> String {
  match self {
    Transport(message) =>
      "Google Drive comment inspection could not reach Google: " + message
    HttpStatus(status~) =>
      "Google Drive comment inspection was rejected with HTTP " +
      status.to_string() +
      "."
    Decode(message) =>
      "Google Drive comment inspection received an invalid response: " + message
    TooManyPages(limit) =>
      "Google Drive comment inspection exceeded the " +
      limit.to_string() +
      "-page safety limit."
  }
}

///|
priv struct DriveCommentResponse {
  id : String
  resolved : Bool?
} derive(@json.FromJson)

///|
priv struct DriveCommentsPageResponse {
  comments : Array[DriveCommentResponse]?
  nextPageToken : String?
} derive(@json.FromJson)

///|
fn percent_encode_page_token(token : String) -> String {
  let encoded = StringBuilder()
  for char in token {
    match char {
      'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '.' | '_' | '~' =>
        encoded.write_char(char)
      _ => {
        encoded.write_char('%')
        encoded.write_string(char.to_int().to_byte().to_hex())
      }
    }
  }
  encoded.to_string()
}

///|
async fn CommentsError::send_get(
  client : @google_core.GoogleClient,
  url : String,
) -> Result[@google_http.HttpResponse, CommentsError] {
  let request = @google_http.HttpRequest::new(
    url,
    @google_http.HttpMethod::GET,
    {},
  )
  let response = client.request(request) catch {
    @google_http.HttpError::NetworkError(message) =>
      return Err(Transport(message))
    @google_http.HttpError::TimeoutError(message) =>
      return Err(Transport(message))
    @google_http.HttpError::InvalidUrl(message) =>
      return Err(Transport(message))
  }
  if response.status_code < 200 || response.status_code >= 300 {
    Err(HttpStatus(status=response.status_code))
  } else {
    Ok(response)
  }
}

///|
pub async fn inspect_comments(
  client : @google_core.GoogleClient,
  document_id : String,
) -> Result[CommentInspection, CommentsError] {
  let base_url = "https://www.googleapis.com/drive/v3/files/" +
    document_id +
    "/comments?fields=nextPageToken,comments(id,resolved)&pageSize=100"
  let mut next_page_token = None
  let mut unresolved = 0
  let mut pages = 0
  while true {
    if pages >= 50 {
      return Err(TooManyPages(50))
    }
    let url = match next_page_token {
      Some(token) => base_url + "&pageToken=" + percent_encode_page_token(token)
      None => base_url
    }
    let response = match CommentsError::send_get(client, url) {
      Ok(response) => response
      Err(error) => return Err(error)
    }
    let json = @json.parse(response.body) catch {
      error => return Err(Decode(error.to_string()))
    }
    let page : DriveCommentsPageResponse = @json.from_json(json) catch {
      error => return Err(Decode(error.to_string()))
    }
    pages = pages + 1
    match page.comments {
      Some(comments) =>
        for comment in comments {
          let _ = comment.id
          match comment.resolved {
            Some(true) => ()
            Some(false) | None => unresolved = unresolved + 1
          }
        }
      None => ()
    }
    match page.nextPageToken {
      Some(token) if !token.is_empty() => next_page_token = Some(token)
      _ => return Ok({ unresolved, pages })
    }
  } nobreak {
    abort("comment pagination loop must return")
  }
}
