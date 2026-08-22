///|
/// Lifecycle of a locally owned publication.
pub(all) enum PublicationLifecycle {
  Provisional
  Ready
  Blocked
} derive(Eq, @debug.Debug)

///|
/// Recoverable local and observed-remote state for an unresolved Pull.
pub(all) struct PendingMerge {
  pre_pull_source : String
  marked_source : String
  observed_remote_body : String
  observed_revision_id : String
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
/// One publication associated with a canonical Markdown source path.
pub(all) struct PublicationEntry {
  source_path : String
  document_id : String?
  url : String?
  managed_tab_id : String?
  lifecycle : PublicationLifecycle
  last_successful_publish : String?
  published_baseline : @pumd.DesiredDocument?
  pending_merge : PendingMerge?
} derive(@debug.Debug)

///|
/// The in-memory, version-one registry document.
pub(all) struct RegistryDocument {
  entries : Array[PublicationEntry]
} derive(@debug.Debug)

///|
/// Errors returned by registry operations.
pub(all) enum RegistryError {
  Unavailable(String)
  Malformed(String)
  UnsupportedVersion(Int)
  DuplicateSource(String)
  DuplicateDocument(String)
  Invalid(String)
  NotFound(String)
  DestinationOccupied(String)
  BlockedPublication(String)
  PendingMergeRequired(String)
  PendingMergeBlocked(String)
} derive(Eq, @debug.Debug)

///|
/// A user-facing explanation of a registry error.
pub fn RegistryError::user_message(self : RegistryError) -> String {
  match self {
    Unavailable(message) | Malformed(message) | Invalid(message) => message
    UnsupportedVersion(version) =>
      "unsupported publication registry version: \{version}"
    DuplicateSource(path) => "a publication already exists for \{path}"
    DuplicateDocument(id) => "a publication already uses document \{id}"
    NotFound(path) => "no publication exists for \{path}"
    DestinationOccupied(path) => "a publication already exists for \{path}"
    BlockedPublication(path) => "publication is blocked for \{path}"
    PendingMergeRequired(path) => "publication has no Pending Merge for \{path}"
    PendingMergeBlocked(path) => "publication has a Pending Merge for \{path}"
  }
}

///|
/// Resolve the registry directory from environment lookup.
pub fn resolve_registry_directory(
  get_env : (String) -> String?,
) -> Result[String, RegistryError] {
  match get_env("XDG_CONFIG_HOME") {
    Some(path) if !path.is_empty() => Ok(path + "/pumd")
    _ =>
      match get_env("APPDATA") {
        Some(path) if !path.is_empty() => Ok(path + "/pumd")
        _ =>
          match get_env("HOME") {
            Some(path) if !path.is_empty() => Ok(path + "/.config/pumd")
            _ =>
              Err(Unavailable("could not determine a configuration directory"))
          }
      }
  }
}

///|
/// Resolve the registry directory from the process environment.
pub fn default_registry_directory() -> Result[String, RegistryError] {
  resolve_registry_directory(@env.get_env_var)
}

///|
/// Return the registry data-file path.
pub fn registry_file_path(directory : String) -> String {
  directory + "/publications.json"
}

///|
/// Return the advisory-lock path.
pub fn registry_lock_path(directory : String) -> String {
  directory + "/publications.lock"
}

///| Canonicalize a source path: resolve symlinks and relative spellings when

///| the file exists; otherwise keep the path but make it absolute so registry

///|
/// keys never depend on the caller's current directory.
pub async fn canonical_source_path(path : String) -> String {
  @async_fs.realpath(path) catch {
    _ =>
      if is_absolute_path(path) {
        path
      } else {
        match @env.current_dir() {
          Some(cwd) if cwd.has_suffix("/") || cwd.has_suffix("\\") => cwd + path
          Some(cwd) => cwd + "/" + path
          None => path
        }
      }
  }
}

///|
fn is_absolute_path(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\") {
    return true
  }
  // Windows drive-letter absolute paths like `C:\` or `C:/`.
  path.length() >= 3 &&
  path[1] == ':' &&
  ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z'))
}

///|
/// A held cross-process registry lock.
pub(all) struct RegistryLock {
  directory : String
  file : @async_fs.File
}

///|
async fn prepare_registry_directory(
  directory : String,
) -> Result[Unit, RegistryError] {
  if !@async_fs.exists(directory) {
    @async_fs.mkdir(directory, permission=0o700, recursive=true) catch {
      _ =>
        // A concurrent process may have created the directory between the
        // existence check and this mkdir; only fail when it is still absent.
        if !@async_fs.exists(directory) {
          return Err(
            Unavailable("could not create publication registry directory"),
          )
        }
    }
  }
  let windows = match @env.get_env_var("OS") {
    Some("Windows_NT") => true
    _ => false
  }
  if !windows {
    @async_fs.chmod(directory, 0o700) catch {
      _ =>
        return Err(
          Unavailable("could not secure publication registry directory"),
        )
    }
  }
  Ok(())
}

///|
/// Acquire the exclusive registry lock, creating its private directory if needed.
pub async fn acquire_registry_lock(
  directory : String,
) -> Result[RegistryLock, RegistryError] {
  guard prepare_registry_directory(directory) is Ok(_) else {
    return Err(Unavailable("publication registry is unavailable"))
  }
  let file = @async_fs.open(
    registry_lock_path(directory),
    mode=@async_fs.ReadWrite,
    create_mode=@async_fs.OpenOrCreate,
    permission=0o600,
  ) catch {
    _ => return Err(Unavailable("could not open publication registry lock"))
  }
  file.lock(@async_fs.Exclusive) catch {
    _ => {
      file.close()
      return Err(Unavailable("could not lock publication registry"))
    }
  }
  Ok({ directory, file })
}

///|
/// Release a held registry lock.
pub fn RegistryLock::release(self : RegistryLock) -> Unit {
  self.file.unlock()
  self.file.close()
}

///|
fn json_string_option(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn lifecycle_json(value : PublicationLifecycle) -> Json {
  Json::string(
    match value {
      Provisional => "provisional"
      Ready => "ready"
      Blocked => "blocked"
    },
  )
}

///|
fn pending_merge_json(value : PendingMerge) -> Json {
  Json::object({
    "pre_pull_source": Json::string(value.pre_pull_source),
    "marked_source": Json::string(value.marked_source),
    "observed_remote_body": Json::string(value.observed_remote_body),
    "observed_revision_id": Json::string(value.observed_revision_id),
  })
}

///|
fn entry_json(entry : PublicationEntry) -> Json {
  let values : Map[String, Json] = {
    "source_path": Json::string(entry.source_path),
    "document_id": json_string_option(entry.document_id),
    "url": json_string_option(entry.url),
    "managed_tab_id": json_string_option(entry.managed_tab_id),
    "lifecycle": lifecycle_json(entry.lifecycle),
    "last_successful_publish": json_string_option(entry.last_successful_publish),
    "published_baseline": match entry.published_baseline {
      Some(value) => Json::Json(value)
      None => Json::null()
    },
    "pending_merge": match entry.pending_merge {
      Some(value) => pending_merge_json(value)
      None => Json::null()
    },
  }
  Json::object(values)
}

///|
fn registry_json(document : RegistryDocument) -> String {
  let publications = []
  for entry in document.entries {
    publications.push(entry_json(entry))
  }
  Json::object({
    "version": Json::number(1.0),
    "publications": Json::array(publications),
  }).stringify()
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> Result[String, RegistryError] {
  match fields.get(name) {
    Some(String(value)) => Ok(value)
    _ => Err(Malformed("invalid \{name}"))
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> Result[String?, RegistryError] {
  match fields.get(name) {
    Some(String(value)) => Ok(Some(value))
    Some(Null) => Ok(None)
    _ => Err(Malformed("invalid \{name}"))
  }
}

///|
fn parse_pending_merge(json : Json) -> Result[PendingMerge, RegistryError] {
  let fields = match json {
    Object(fields) => fields
    _ => return Err(Malformed("invalid pending_merge"))
  }
  let pre_pull_source = match required_string(fields, "pre_pull_source") {
    Ok(value) => value
    Err(_) => return Err(Malformed("invalid pending_merge"))
  }
  let marked_source = match required_string(fields, "marked_source") {
    Ok(value) => value
    Err(_) => return Err(Malformed("invalid pending_merge"))
  }
  let observed_remote_body = match
    required_string(fields, "observed_remote_body") {
    Ok(value) => value
    Err(_) => return Err(Malformed("invalid pending_merge"))
  }
  let observed_revision_id = match
    required_string(fields, "observed_revision_id") {
    Ok(value) => value
    Err(_) => return Err(Malformed("invalid pending_merge"))
  }
  Ok({
    pre_pull_source,
    marked_source,
    observed_remote_body,
    observed_revision_id,
  })
}

///|
fn add_missing_inline_images(json : Json) -> Unit {
  match json {
    Object(fields) => {
      match fields.get("runs") {
        Some(Array(_)) =>
          if !fields.contains("inline_images") {
            fields.set("inline_images", Json::array([]))
          }
        _ => ()
      }
      for _, value in fields {
        add_missing_inline_images(value)
      }
    }
    Array(values) =>
      for value in values {
        add_missing_inline_images(value)
      }
    _ => ()
  }
}

///|
fn parse_entry(json : Json) -> Result[PublicationEntry, RegistryError] {
  let fields = match json {
    Object(fields) => fields
    _ => return Err(Malformed("publication must be an object"))
  }
  let lifecycle = match required_string(fields, "lifecycle") {
    Ok("provisional") => Provisional
    Ok("ready") => Ready
    Ok("blocked") => Blocked
    _ => return Err(Malformed("invalid lifecycle"))
  }
  let baseline = match fields.get("published_baseline") {
    Some(Null) => None
    Some(value) => {
      add_missing_inline_images(value)
      let decoded : @pumd.DesiredDocument = @json.from_json(value) catch {
        _ => return Err(Malformed("invalid published_baseline"))
      }
      Some(decoded)
    }
    None => return Err(Malformed("invalid published_baseline"))
  }
  let source_path = match required_string(fields, "source_path") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let document_id = match optional_string(fields, "document_id") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let url = match optional_string(fields, "url") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let managed_tab_id = match optional_string(fields, "managed_tab_id") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let last_successful_publish = match
    optional_string(fields, "last_successful_publish") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pending_merge = match fields.get("pending_merge") {
    None | Some(Null) => None
    Some(value) =>
      match parse_pending_merge(value) {
        Ok(value) => Some(value)
        Err(error) => return Err(error)
      }
  }
  Ok({
    source_path,
    document_id,
    url,
    managed_tab_id,
    lifecycle,
    last_successful_publish,
    published_baseline: baseline,
    pending_merge,
  })
}

///|
fn parse_registry(text : String) -> Result[RegistryDocument, RegistryError] {
  let root = @json.parse(text) catch {
    _ => return Err(Malformed("malformed publication registry JSON"))
  }
  let fields = match root {
    Object(fields) => fields
    _ => return Err(Malformed("registry root must be an object"))
  }
  match fields.get("version") {
    Some(Number(number, ..)) if number == 1.0 => ()
    Some(Number(number, ..)) => return Err(UnsupportedVersion(number.to_int()))
    _ => return Err(Malformed("invalid registry version"))
  }
  let raw_entries = match fields.get("publications") {
    Some(Array(entries)) => entries
    _ => return Err(Malformed("invalid publications"))
  }
  let entries = []
  for raw in raw_entries {
    match parse_entry(raw) {
      Ok(entry) => entries.push(entry)
      Err(error) => return Err(error)
    }
  }
  Ok({ entries, })
}

///|
fn invalid_shape(entry : PublicationEntry) -> String? {
  match entry.lifecycle {
    Provisional if entry.document_id is Some(_) &&
      entry.url is Some(_) &&
      entry.managed_tab_id is Some(_) &&
      entry.last_successful_publish is None &&
      entry.published_baseline is None &&
      entry.pending_merge is None => None
    Ready if entry.document_id is Some(_) &&
      entry.url is Some(_) &&
      entry.managed_tab_id is Some(_) &&
      entry.last_successful_publish is Some(_) &&
      entry.published_baseline is Some(_) => None
    Blocked if entry.document_id is None &&
      entry.url is None &&
      entry.managed_tab_id is None &&
      entry.last_successful_publish is None &&
      entry.published_baseline is None &&
      entry.pending_merge is None => None
    _ => Some("publication has an invalid lifecycle shape")
  }
}

///|
/// Validate all registry invariants.
pub fn validate_registry_document(
  document : RegistryDocument,
) -> Result[Unit, RegistryError] {
  let sources : Map[String, Bool] = Map([])
  let documents : Map[String, Bool] = Map([])
  for entry in document.entries {
    if entry.source_path.is_empty() {
      return Err(Invalid("source_path must not be empty"))
    }
    guard invalid_shape(entry) is None else {
      return Err(Invalid("publication has an invalid lifecycle shape"))
    }
    if sources.contains(entry.source_path) {
      return Err(DuplicateSource(entry.source_path))
    }
    sources.set(entry.source_path, true)
    match entry.document_id {
      Some(id) => {
        if documents.contains(id) {
          return Err(DuplicateDocument(id))
        }
        documents.set(id, true)
      }
      None => ()
    }
  }
  Ok(())
}

///|
fn load_validation(
  document : RegistryDocument,
) -> Result[RegistryDocument, RegistryError] {
  match validate_registry_document(document) {
    Ok(_) => Ok(document)
    Err(DuplicateSource(path)) =>
      Err(Malformed("duplicate source_path: \{path}"))
    Err(DuplicateDocument(id)) => Err(Malformed("duplicate document_id: \{id}"))
    Err(_) => Err(Malformed("invalid publication registry"))
  }
}

///|
/// Load and validate the registry, treating a missing file as empty.
pub async fn load_registry_document(
  directory : String,
) -> Result[RegistryDocument, RegistryError] {
  let path = registry_file_path(directory)
  if !@async_fs.exists(path) {
    return Ok({ entries: [] })
  }
  let bytes = @async_fs.read_file(path) catch {
    _ => return Err(Unavailable("could not read publication registry"))
  }
  let text = bytes.text() catch {
    _ => return Err(Malformed("publication registry is not valid UTF-8"))
  }
  let parsed = parse_registry(text)
  match parsed {
    Ok(document) => load_validation(document)
    Err(error) => Err(error)
  }
}

///|
async fn replace_registry_file(
  directory : String,
  text : String,
) -> Result[Unit, RegistryError] {
  guard prepare_registry_directory(directory) is Ok(_) else {
    return Err(Unavailable("publication registry is unavailable"))
  }
  let random = match @env.rand(16) {
    Some(value) => value
    None =>
      return Err(Unavailable("could not generate registry temporary name"))
  }
  let suffix = @base64.encode(random[:], url_safe=true)
  let temporary = registry_file_path(directory) + ".tmp-" + suffix
  let file = @async_fs.open(
    temporary,
    mode=@async_fs.WriteOnly,
    create_mode=@async_fs.CreateNew,
    permission=0o600,
  ) catch {
    _ => return Err(Unavailable("could not write publication registry"))
  }
  let write_outcome : Result[Unit, RegistryError] = try {
    file.write(text)
    file.sync()
    Ok(())
  } catch {
    _ => Err(Unavailable("could not write publication registry"))
  }
  let outcome : Result[Unit, RegistryError] = match write_outcome {
    Ok(_) => {
      file.close()
      try {
        @async_fs.rename(temporary, registry_file_path(directory), replace=true)
        Ok(())
      } catch {
        _ => Err(Unavailable("could not replace publication registry"))
      }
    }
    Err(error) => {
      file.close()
      Err(error)
    }
  }
  match outcome {
    Ok(_) => Ok(())
    Err(error) => {
      @async_fs.remove(temporary) catch {
        _ => ()
      }
      Err(error)
    }
  }
}

///| Atomically save a validated registry. Callers that mutate under the

///| registry lock (see `acquire_registry_lock`) must hold that lock across

///|
/// every load/save pair; standalone mutations use the convenience wrappers.
pub async fn save_registry_document(
  directory : String,
  document : RegistryDocument,
) -> Result[Unit, RegistryError] {
  guard validate_registry_document(document) is Ok(_) else {
    return Err(Invalid("invalid publication registry"))
  }
  replace_registry_file(directory, registry_json(document))
}

///|
/// Read a lock-consistent registry snapshot.
pub async fn registry_snapshot(
  directory : String,
) -> Result[RegistryDocument, RegistryError] {
  let lock = match acquire_registry_lock(directory) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = load_registry_document(directory)
  lock.release()
  result
}

///|
/// Non-destructively verify that the registry location is writable.
pub async fn probe_registry_writable(
  directory : String,
) -> Result[Unit, RegistryError] {
  guard prepare_registry_directory(directory) is Ok(_) else {
    return Err(Unavailable("publication registry is unavailable"))
  }
  let random = match @env.rand(16) {
    Some(value) => value
    None => return Err(Unavailable("could not generate probe name"))
  }
  let suffix = @base64.encode(random[:], url_safe=true)
  let path = directory + "/.registry-probe-" + suffix
  let file = @async_fs.open(
    path,
    mode=@async_fs.WriteOnly,
    create_mode=@async_fs.CreateNew,
    permission=0o600,
  ) catch {
    _ => return Err(Unavailable("could not probe publication registry"))
  }
  let result : Result[Unit, RegistryError] = try {
    file.write("p")
    file.sync()
    file.close()
    let contents = @async_fs.read_file(path)
    if contents.text() != "p" {
      Err(Unavailable("publication registry probe failed"))
    } else {
      Ok(())
    }
  } catch {
    _ => Err(Unavailable("could not probe publication registry"))
  }
  @async_fs.remove(path) catch {
    _ => return Err(Unavailable("could not clean publication registry probe"))
  }
  result
}

///|
/// Find a publication by source path.
pub fn publication_for_source(
  document : RegistryDocument,
  source_path : String,
) -> PublicationEntry? {
  for entry in document.entries {
    if entry.source_path == source_path {
      return Some(entry)
    }
  }
  None
}

///|
/// Find a publication by Google Document ID.
pub fn publication_for_document_id(
  document : RegistryDocument,
  document_id : String,
) -> PublicationEntry? {
  for entry in document.entries {
    if entry.document_id == Some(document_id) {
      return Some(entry)
    }
  }
  None
}

///|
/// Add a valid provisional publication.
pub fn document_with_provisional(
  document : RegistryDocument,
  entry : PublicationEntry,
) -> Result[RegistryDocument, RegistryError] {
  if publication_for_source(document, entry.source_path) is Some(existing) {
    return if existing.lifecycle is Blocked {
      Err(BlockedPublication(entry.source_path))
    } else {
      Err(DuplicateSource(entry.source_path))
    }
  }
  match entry.document_id {
    Some(id) if publication_for_document_id(document, id) is Some(_) =>
      return Err(DuplicateDocument(id))
    _ => ()
  }
  guard invalid_shape(entry) is None else {
    return Err(Invalid("provisional publication has invalid shape"))
  }
  guard entry.lifecycle is Provisional else {
    return Err(Invalid("publication must be provisional"))
  }
  let entries = document.entries.copy()
  entries.push(entry)
  let updated : RegistryDocument = { entries, }
  match validate_registry_document(updated) {
    Ok(_) => Ok(updated)
    Err(error) => Err(error)
  }
}

///|
/// Commit a provisional publication's baseline.
pub fn document_with_ready(
  document : RegistryDocument,
  source_path : String,
  baseline : @pumd.DesiredDocument,
  last_successful_publish : String,
) -> Result[RegistryDocument, RegistryError] {
  let entries = document.entries.copy()
  let mut found = false
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].source_path == source_path {
      found = true
      if entries[index].lifecycle is Blocked {
        return Err(BlockedPublication(source_path))
      }
      guard entries[index].lifecycle is Provisional else {
        return Err(Invalid("publication is not provisional"))
      }
      entries[index] = {
        ..entries[index],
        lifecycle: Ready,
        published_baseline: Some(baseline),
        last_successful_publish: Some(last_successful_publish),
      }
    }
  }
  if !found {
    return Err(NotFound(source_path))
  }
  let updated : RegistryDocument = { entries, }
  match validate_registry_document(updated) {
    Ok(_) => Ok(updated)
    Err(error) => Err(error)
  }
}

///|
/// Update a ready publication's published baseline.
pub fn document_with_updated_baseline(
  document : RegistryDocument,
  source_path : String,
  baseline : @pumd.DesiredDocument,
  last_successful_publish : String,
) -> Result[RegistryDocument, RegistryError] {
  let entries = document.entries.copy()
  let mut found = false
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].source_path == source_path {
      found = true
      guard entries[index].lifecycle is Ready else {
        return Err(Invalid("publication is not ready"))
      }
      entries[index] = {
        ..entries[index],
        published_baseline: Some(baseline),
        last_successful_publish: Some(last_successful_publish),
      }
    }
  }
  if !found {
    return Err(NotFound(source_path))
  }
  let updated : RegistryDocument = { entries, }
  match validate_registry_document(updated) {
    Ok(_) => Ok(updated)
    Err(error) => Err(error)
  }
}

///|
/// Record a source as blocked before it acquires a destination.
pub fn document_with_blocked(
  document : RegistryDocument,
  source_path : String,
) -> Result[RegistryDocument, RegistryError] {
  if publication_for_source(document, source_path) is Some(_) {
    return Err(DuplicateSource(source_path))
  }
  let entries = document.entries.copy()
  entries.push({
    source_path,
    document_id: None,
    url: None,
    managed_tab_id: None,
    lifecycle: Blocked,
    last_successful_publish: None,
    published_baseline: None,
    pending_merge: None,
  })
  Ok(RegistryDocument::{ entries, })
}

///|
/// Remove a publication idempotently.
pub fn document_without_publication(
  document : RegistryDocument,
  source_path : String,
) -> Result[RegistryDocument, RegistryError] {
  let entries = []
  for entry in document.entries {
    if entry.source_path == source_path && entry.pending_merge is Some(_) {
      return Err(PendingMergeBlocked(source_path))
    }
    if entry.source_path != source_path {
      entries.push(entry)
    }
  }
  Ok(RegistryDocument::{ entries, })
}

///|
/// Move an existing publication to a free source path.
pub fn document_with_reassigned_source(
  document : RegistryDocument,
  source_path : String,
  destination : String,
) -> Result[RegistryDocument, RegistryError] {
  match publication_for_source(document, source_path) {
    Some(entry) if entry.pending_merge is Some(_) =>
      return Err(PendingMergeBlocked(source_path))
    _ => ()
  }
  if publication_for_source(document, destination) is Some(_) {
    return Err(DestinationOccupied(destination))
  }
  let entries = document.entries.copy()
  let mut found = false
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].source_path == source_path {
      if entries[index].pending_merge is Some(_) {
        return Err(PendingMergeBlocked(source_path))
      }
      entries[index] = { ..entries[index], source_path: destination }
      found = true
    }
  }
  if !found {
    return Err(NotFound(source_path))
  }
  Ok(RegistryDocument::{ entries, })
}

///|
/// Begin a Pending Merge on a ready Publication.
pub fn document_with_pending_merge(
  document : RegistryDocument,
  source_path : String,
  pending_merge : PendingMerge,
) -> Result[RegistryDocument, RegistryError] {
  let entries = document.entries.copy()
  let mut found = false
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].source_path == source_path {
      found = true
      guard entries[index].lifecycle is Ready else {
        return Err(Invalid("publication is not ready"))
      }
      if entries[index].pending_merge is Some(_) {
        return Err(PendingMergeBlocked(source_path))
      }
      entries[index] = { ..entries[index], pending_merge: Some(pending_merge) }
    }
  }
  if !found {
    return Err(NotFound(source_path))
  }
  let updated : RegistryDocument = { entries, }
  match validate_registry_document(updated) {
    Ok(_) => Ok(updated)
    Err(error) => Err(error)
  }
}

///|
/// Clear an existing Pending Merge from a ready Publication.
pub fn document_without_pending_merge(
  document : RegistryDocument,
  source_path : String,
) -> Result[RegistryDocument, RegistryError] {
  let entries = document.entries.copy()
  let mut found = false
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].source_path == source_path {
      found = true
      guard entries[index].lifecycle is Ready else {
        return Err(Invalid("publication is not ready"))
      }
      if entries[index].pending_merge is None {
        return Err(PendingMergeRequired(source_path))
      }
      entries[index] = { ..entries[index], pending_merge: None }
    }
  }
  if !found {
    return Err(NotFound(source_path))
  }
  let updated : RegistryDocument = { entries, }
  match validate_registry_document(updated) {
    Ok(_) => Ok(updated)
    Err(error) => Err(error)
  }
}

///|
async fn mutate(
  directory : String,
  operation : (RegistryDocument) -> Result[RegistryDocument, RegistryError],
) -> Result[Unit, RegistryError] {
  let lock = match acquire_registry_lock(directory) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = match load_registry_document(directory) {
    Ok(document) =>
      match operation(document) {
        Ok(updated) => save_registry_document(directory, updated)
        Err(error) => Err(error)
      }
    Err(error) => Err(error)
  }
  lock.release()
  result
}

///|
/// Register a provisional publication under the registry lock.
pub async fn register_provisional_publication(
  directory : String,
  entry : PublicationEntry,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) { document_with_provisional(document, entry) })
}

///|
/// Commit a successful publication under the registry lock.
pub async fn commit_ready_publication(
  directory : String,
  source_path : String,
  baseline : @pumd.DesiredDocument,
  last_successful_publish : String,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_with_ready(
      document, source_path, baseline, last_successful_publish,
    )
  })
}

///|
/// Update a ready publication's baseline under the registry lock.
pub async fn update_publication_baseline(
  directory : String,
  source_path : String,
  baseline : @pumd.DesiredDocument,
  last_successful_publish : String,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_with_updated_baseline(
      document, source_path, baseline, last_successful_publish,
    )
  })
}

///|
/// Record a blocked publication under the registry lock.
pub async fn record_blocked_publication(
  directory : String,
  source_path : String,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_with_blocked(document, source_path)
  })
}

///|
/// Begin a Pending Merge under the registry lock.
pub async fn begin_pending_merge(
  directory : String,
  source_path : String,
  pending_merge : PendingMerge,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_with_pending_merge(document, source_path, pending_merge)
  })
}

///|
/// Clear a Pending Merge under the registry lock.
pub async fn clear_pending_merge(
  directory : String,
  source_path : String,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_without_pending_merge(document, source_path)
  })
}

///|
/// Forget a publication under the registry lock.
pub async fn forget_publication(
  directory : String,
  source_path : String,
) -> Result[Bool, RegistryError] {
  let lock = match acquire_registry_lock(directory) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = match load_registry_document(directory) {
    Ok(document) =>
      if publication_for_source(document, source_path) is None {
        // Idempotent forget must not rewrite (or create) the registry file.
        Ok(false)
      } else {
        match document_without_publication(document, source_path) {
          Ok(updated) =>
            match save_registry_document(directory, updated) {
              Ok(_) => Ok(true)
              Err(error) => Err(error)
            }
          Err(error) => Err(error)
        }
      }
    Err(error) => Err(error)
  }
  lock.release()
  result
}

///|
/// Reassociate a publication under the registry lock.
pub async fn reassociate_publication(
  directory : String,
  source_path : String,
  destination : String,
) -> Result[Unit, RegistryError] {
  mutate(directory, fn(document) {
    document_with_reassigned_source(document, source_path, destination)
  })
}
