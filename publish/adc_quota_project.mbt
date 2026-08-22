///|
priv struct AdcQuotaProjectFile {
  quota_project_id : String?
} derive(@json.FromJson)

///|
pub struct AdcQuotaHttpClient {
  inner : &@google_http.HttpClient
  quota_project_id : String
}

///|
pub impl @google_http.HttpClient for AdcQuotaHttpClient with request(
  self,
  request,
) {
  let headers : Map[String, String] = Map([])
  for key, value in request.headers {
    headers[key] = value
  }
  headers["x-goog-user-project"] = self.quota_project_id
  self.inner.request(
    @google_http.HttpRequest::{
      url: request.url,
      method_: request.method_,
      headers,
      body: request.body,
    },
  )
}

///|
pub fn adc_quota_http_client(
  inner : &@google_http.HttpClient,
  quota_project_id : String?,
) -> &@google_http.HttpClient {
  match quota_project_id {
    Some(project) if !project.is_empty() =>
      (AdcQuotaHttpClient::{ inner, quota_project_id: project } as &@google_http.HttpClient)
    _ => inner
  }
}

///|
pub fn adc_quota_project_id() -> String? {
  let path = match @env.get_env_var("GOOGLE_APPLICATION_CREDENTIALS") {
    Some(path) if !path.is_empty() => Some(path)
    _ => @googleauth.get_well_known_credentials_path()
  }
  let body = match path {
    Some(path) => Some(@fs.read_file_to_string(path)) catch { _ => None }
    None => None
  }
  let json = match body {
    Some(body) => @json.parse(body) catch { _ => return None }
    None => return None
  }
  let decoded : AdcQuotaProjectFile = @json.from_json(json) catch {
    _ => return None
  }
  match decoded.quota_project_id {
    Some(project) if !project.is_empty() => Some(project)
    _ => None
  }
}
