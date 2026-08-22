///|
/// Result of a registry-aware publish operation.
pub(all) enum PublishOutcome {
  Completed(PublishSuccess)
  AlreadyPublished(PublishSuccess, String)
  Updated(PublishSuccess, String)
  NoOp(PublishSuccess, String)
  DryRunCreation(title~ : String)
  DryRunUpdate(report~ : DryRunUpdateReport)
  DryRunProvisional(PublishSuccess)
  DryRunBlocked(source_path~ : String)
} derive(@debug.Debug)

///|
/// The reconciliation state reported by a dry-run of an existing Publication.
pub(all) struct DryRunUpdateReport {
  document_id : String
  url : String
  title : String?
  planned_units : Int
  planned : Array[String]
  conflicts : Int
  conflicted : Array[String]
  review_barriers : Int
  concurrency_sensitive : Bool
} derive(@debug.Debug)

///|
pub(all) struct PullReport {
  document_id : String
  url : String
  title : String?
  plan : PullPlan
} derive(@debug.Debug)

///|
pub(all) enum PullOutcome {
  Pulled(PullReport)
  PullNoOp(PullReport)
  PullDryRun(PullReport)
  PullConflicted(PullReport)
} derive(@debug.Debug)

///|
/// The state of a registered document observed through Drive and Docs.
pub(all) enum RemotePublicationStatus {
  Ready
  Trashed
  ReadOnly
  RemoteMissing
  Inaccessible
  Unavailable
} derive(Eq, @debug.Debug)

///|
/// A remote inspection suitable for `pumd list --refresh`.
pub(all) struct RemotePublicationInspection {
  document_id : String
  url : String
  title : String?
  trashed : Bool
  editable : Bool?
  managed_tab_present : Bool
  status : RemotePublicationStatus
} derive(@debug.Debug)

///|
async fn selected_token(
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
) -> Result[String, AuthenticationProblem] {
  match authorization_mode {
    Project | Ephemeral => get_project_token()
    Adc => get_adc_token()
  }
}

///|
fn authentication_error(
  authorization_mode : AuthorizationMode,
  problem : AuthenticationProblem,
) -> PublishError {
  Authentication(authorization_mode~, problem~, created_document=None)
}

///|
fn success_from_entry(entry : @registry.PublicationEntry) -> PublishSuccess {
  let document_id = match entry.document_id {
    Some(value) => value
    None => abort("registry entry has no document ID")
  }
  let url = match entry.url {
    Some(value) => value
    None => abort("registry entry has no URL")
  }
  { document_id, url }
}

///|
fn population_error(
  authorization_mode : AuthorizationMode,
  success : PublishSuccess,
  error : DocsAdapterError,
) -> PublishError {
  match error {
    AdapterTransport(_) => AmbiguousPopulation(success)
    AdapterHttpStatus(status~, kind~) =>
      match
        classified_google_error(
          authorization_mode,
          DocumentPopulation,
          kind,
          Some(success),
        ) {
        Some(error) => error
        None =>
          Population(
            created_document=success,
            message=AdapterHttpStatus(status~, kind~).message(),
          )
      }
    AdapterDecode(message) =>
      ResponseDecode(
        stage=DocumentPopulation,
        message~,
        created_document=Some(success),
      )
  }
}

///|
fn read_error(
  authorization_mode : AuthorizationMode,
  document_id : String,
  url : String,
  error : DocsAdapterError,
) -> PublishError {
  match error {
    AdapterHttpStatus(status=404, ..) => RemoteMissing(document_id~, url~)
    AdapterHttpStatus(kind=Some(PermissionDenied), ..) =>
      Permission(authorization_mode~, stage=DocumentRead, created_document=None)
    AdapterHttpStatus(kind=Some(Throttled), ..) =>
      Throttled(stage=DocumentRead, created_document=None)
    AdapterHttpStatus(kind=Some(Unauthenticated), ..) =>
      Authentication(
        authorization_mode~,
        problem=CredentialsRejected,
        created_document=None,
      )
    _ => Read(document_id~, url~, message=error.message())
  }
}

///|
fn registry_error(error : @registry.RegistryError) -> PublishError {
  Registry(error.user_message())
}

///|
/// Commit a confirmed successful update to the Published Baseline under the
/// already-held registry lock.
async fn commit_updated_baseline(
  document : @registry.RegistryDocument,
  registry_directory : String,
  canonical : String,
  baseline : @pumd.DesiredDocument,
  timestamp : String,
  success : PublishSuccess,
) -> Result[PublishOutcome, PublishError] {
  let updated = match
    @registry.document_with_updated_baseline(
      document, canonical, baseline, timestamp,
    ) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  match @registry.save_registry_document(registry_directory, updated) {
    Ok(_) => Ok(Updated(success, timestamp))
    Err(error) => Err(registry_error(error))
  }
}

///|
fn decoded_read_error(
  success : PublishSuccess,
  error : RemoteDecodeError,
) -> PublishError {
  match error {
    MissingManagedTab(_) =>
      RemoteMissing(document_id=success.document_id, url=success.url)
    _ =>
      Read(
        document_id=success.document_id,
        url=success.url,
        message=error.user_message(),
      )
  }
}

///|
fn reconciliation_error(error : ReconcileError) -> PublishError {
  match error {
    PlanningFailed(message) => Planning(message)
    InvalidRemoteStructure(message) | AmbiguousAlignment(message) =>
      MergeConflict(
        message="the Google Docs content cannot be aligned safely: " + message,
      )
  }
}

///|
fn conflict_error(report : ReconciliationReport) -> PublishError {
  let descriptions = StringBuilder::new()
  for unit in report.units {
    if unit.conflict {
      if !descriptions.is_empty() {
        descriptions.write_string(", ")
      }
      descriptions.write_string(unit.description)
    }
  }
  MergeConflict(
    message="local and remote changes conflict in " + descriptions.to_string(),
  )
}

///|
fn comment_error(
  authorization_mode : AuthorizationMode,
  success : PublishSuccess,
  error : CommentsError,
) -> PublishError {
  match error {
    HttpStatus(status=404) =>
      RemoteMissing(document_id=success.document_id, url=success.url)
    HttpStatus(status=403) =>
      Permission(authorization_mode~, stage=DocumentRead, created_document=None)
    HttpStatus(status=429) =>
      Throttled(stage=DocumentRead, created_document=None)
    HttpStatus(status=401) =>
      Authentication(
        authorization_mode~,
        problem=CredentialsRejected,
        created_document=None,
      )
    _ =>
      Read(
        document_id=success.document_id,
        url=success.url,
        message="comment inspection failed: " + error.user_message(),
      )
  }
}

///|
fn update_error(
  authorization_mode : AuthorizationMode,
  success : PublishSuccess,
  error : DocsAdapterError,
) -> PublishError {
  match error {
    AdapterHttpStatus(status=404, ..) =>
      RemoteMissing(document_id=success.document_id, url=success.url)
    AdapterHttpStatus(kind=Some(PermissionDenied), ..) =>
      Permission(
        authorization_mode~,
        stage=DocumentUpdate,
        created_document=Some(success),
      )
    AdapterHttpStatus(kind=Some(Throttled), ..) =>
      Throttled(stage=DocumentUpdate, created_document=Some(success))
    AdapterHttpStatus(kind=Some(Unauthenticated), ..) =>
      Authentication(
        authorization_mode~,
        problem=CredentialsRejected,
        created_document=Some(success),
      )
    AdapterHttpStatus(status~, kind~) =>
      UpdateFailed(
        document_id=success.document_id,
        url=success.url,
        message=AdapterHttpStatus(status~, kind~).message(),
      )
    AdapterDecode(message) =>
      UpdateFailed(document_id=success.document_id, url=success.url, message~)
    AdapterTransport(message) =>
      UpdateFailed(
        document_id=success.document_id,
        url=success.url,
        message="transport error: " + message,
      )
  }
}

///|
/// Publish a Markdown source through the local Publication Registry.
pub async fn publish_path_with_registry(
  path : String,
  read_source : async (String) -> Result[String, String],
  registry_directory : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
  dry_run : Bool,
) -> Result[PublishOutcome, PublishError] {
  let prepared = match prepare_publication_path(path, read_source) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  publish_prepared_with_registry(
    prepared, path, registry_directory, authorization_mode, get_project_token, get_adc_token,
    http, dry_run,
  )
}

///|
/// Publish an already prepared document through the local Publication Registry.
pub async fn publish_prepared_with_registry(
  prepared : PreparedPublication,
  source_path : String,
  registry_directory : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
  dry_run : Bool,
) -> Result[PublishOutcome, PublishError] {
  let canonical = @registry.canonical_source_path(source_path)
  if dry_run {
    // Read-only inspection: loading without the lock keeps dry-run free of
    // every registry mutation, including lock-file and directory creation.
    let document = match @registry.load_registry_document(registry_directory) {
      Ok(document) => document
      Err(error) => return Err(registry_error(error))
    }
    match @registry.publication_for_source(document, canonical) {
      None => Ok(DryRunCreation(title=prepared.title))
      Some(entry) => {
        if entry.pending_merge is Some(_) {
          return Err(registry_error(@registry.PendingMergeBlocked(canonical)))
        }
        match entry.lifecycle {
          Blocked => Ok(DryRunBlocked(source_path=canonical))
          Provisional => Ok(DryRunProvisional(success_from_entry(entry)))
          Ready => {
            let success = success_from_entry(entry)
            let managed_tab_id = match entry.managed_tab_id {
              Some(value) => value
              None => abort("invalid ready registry entry")
            }
            let baseline = match entry.published_baseline {
              Some(value) => value
              None => abort("invalid ready registry entry")
            }
            let token = match
              selected_token(
                authorization_mode, get_project_token, get_adc_token,
              ) {
              Ok(token) => token
              Err(problem) =>
                return Err(authentication_error(authorization_mode, problem))
            }
            let client = @google_core.GoogleClient::new(
              fn() { token },
              http=Some(http),
            )
            let retrieved = match
              get_remote_document_body(client, success.document_id) {
              Ok(value) => value
              Err(error) =>
                return Err(
                  read_error(
                    authorization_mode,
                    success.document_id,
                    success.url,
                    error,
                  ),
                )
            }
            let decoded = match
              decode_remote_document(retrieved.body, retrieved.document_id) {
              Ok(value) => value
              Err(error) => return Err(decoded_read_error(success, error))
            }
            let managed_content = match
              remote_tab_content(decoded, managed_tab_id) {
              Some(value) => value
              None =>
                return Err(
                  RemoteMissing(
                    document_id=success.document_id,
                    url=success.url,
                  ),
                )
            }
            let outcome = match
              reconcile_document(baseline, prepared.document, managed_content) {
              Ok(value) => value
              Err(error) => return Err(reconciliation_error(error))
            }
            let report = match outcome {
              NoLocalChanges(report) => report
              Planned(report, _) => report
              Conflict(report) => report
            }
            let planned = []
            let conflicted = []
            for unit in report.units {
              if unit.local_change && !unit.conflict {
                planned.push(unit.description)
              }
              if unit.conflict {
                conflicted.push(unit.description)
              }
            }
            let comments = match inspect_comments(client, success.document_id) {
              Ok(value) => value
              Err(error) =>
                return Err(comment_error(authorization_mode, success, error))
            }
            Ok(
              DryRunUpdate(report={
                document_id: success.document_id,
                url: success.url,
                title: decoded.title,
                planned_units: report.local_changes,
                planned,
                conflicts: report.conflicts,
                conflicted,
                review_barriers: comments.unresolved,
                concurrency_sensitive: report.local_changes > 0 &&
                report.conflicts == 0 &&
                comments.unresolved == 0,
              }),
            )
          }
        }
      }
    }
  } else {
    let lock = match @registry.acquire_registry_lock(registry_directory) {
      Ok(lock) => lock
      Err(error) => return Err(registry_error(error))
    }
    defer lock.release()
    let document = match @registry.load_registry_document(registry_directory) {
      Ok(document) => document
      Err(error) => return Err(registry_error(error))
    }
    match @registry.publication_for_source(document, canonical) {
      Some(entry) => {
        if entry.pending_merge is Some(_) {
          return Err(registry_error(@registry.PendingMergeBlocked(canonical)))
        }
        match entry.lifecycle {
          Ready => {
            let previous_timestamp = match entry.last_successful_publish {
              Some(value) => value
              None => abort("invalid ready registry entry")
            }
            let success = success_from_entry(entry)
            let managed_tab_id = match entry.managed_tab_id {
              Some(value) => value
              None => abort("invalid ready registry entry")
            }
            let baseline = match entry.published_baseline {
              Some(value) => value
              None => abort("invalid ready registry entry")
            }
            let token = match
              selected_token(
                authorization_mode, get_project_token, get_adc_token,
              ) {
              Ok(token) => token
              Err(problem) =>
                return Err(authentication_error(authorization_mode, problem))
            }
            let client = @google_core.GoogleClient::new(
              fn() { token },
              http=Some(http),
            )
            let retrieved = match
              get_remote_document_body(client, success.document_id) {
              Ok(value) => value
              Err(error) =>
                return Err(
                  read_error(
                    authorization_mode,
                    success.document_id,
                    success.url,
                    error,
                  ),
                )
            }
            let decoded = match
              decode_remote_document(retrieved.body, retrieved.document_id) {
              Ok(value) => value
              Err(error) => return Err(decoded_read_error(success, error))
            }
            let managed_content = match
              remote_tab_content(decoded, managed_tab_id) {
              Some(value) => value
              None =>
                return Err(
                  RemoteMissing(
                    document_id=success.document_id,
                    url=success.url,
                  ),
                )
            }
            let reconciliation = match
              reconcile_document(baseline, prepared.document, managed_content) {
              Ok(value) => value
              Err(error) => return Err(reconciliation_error(error))
            }
            let (plan, reconcile_report) = match reconciliation {
              NoLocalChanges(_) => return Ok(NoOp(success, previous_timestamp))
              Conflict(report) => return Err(conflict_error(report))
              Planned(report, plan) => (plan, report)
            }
            let comments = match inspect_comments(client, success.document_id) {
              Ok(value) => value
              Err(error) =>
                return Err(comment_error(authorization_mode, success, error))
            }
            if comments.unresolved > 0 {
              return Err(ReviewBarrier(unresolved=comments.unresolved))
            }
            match
              batch_update_document_with_revision(
                client,
                success.document_id,
                managed_tab_id,
                plan,
                remote_revision_id(decoded),
              ) {
              Ok(_) => {
                let timestamp = format_unix_timestamp(current_unix_seconds())
                commit_updated_baseline(
                  document,
                  registry_directory,
                  canonical,
                  prepared.document,
                  timestamp,
                  success,
                )
              }
              Err(RevisionConflict) =>
                Err(
                  Concurrency(
                    message="the Google Docs revision changed after the document was read; nothing was applied. Re-read and publish again.",
                  ),
                )
              Err(Adapter(AdapterTransport(_))) => {
                let reread = match
                  get_remote_document_body(client, success.document_id) {
                  Ok(value) => value
                  Err(_) =>
                    return Err(
                      AmbiguousUpdate(
                        document_id=success.document_id,
                        url=success.url,
                      ),
                    )
                }
                let remote = match
                  decode_remote_document(reread.body, reread.document_id) {
                  Ok(value) => value
                  Err(_) =>
                    return Err(
                      AmbiguousUpdate(
                        document_id=success.document_id,
                        url=success.url,
                      ),
                    )
                }
                let content = match remote_tab_content(remote, managed_tab_id) {
                  Some(value) => value
                  None =>
                    return Err(
                      AmbiguousUpdate(
                        document_id=success.document_id,
                        url=success.url,
                      ),
                    )
                }
                // Confirm the intended remote state actually landed by checking
                // the planned units specifically, not by re-reconciling
                // (which is always a no-op against the desired document).
                if update_intended_state_landed(
                    baseline,
                    prepared.document,
                    content,
                    reconcile_report,
                  ) {
                  let timestamp = format_unix_timestamp(current_unix_seconds())
                  commit_updated_baseline(
                    document,
                    registry_directory,
                    canonical,
                    prepared.document,
                    timestamp,
                    success,
                  )
                } else {
                  Err(
                    AmbiguousUpdate(
                      document_id=success.document_id,
                      url=success.url,
                    ),
                  )
                }
              }
              Err(Adapter(error)) =>
                Err(update_error(authorization_mode, success, error))
            }
          }
          Blocked => Err(BlockedPublication(source_path=canonical))
          Provisional => {
            let success = success_from_entry(entry)
            let managed_tab_id = match entry.managed_tab_id {
              Some(tab_id) => tab_id
              None =>
                return Err(
                  Registry(
                    "provisional Publication is missing its Managed Tab for " +
                    canonical,
                  ),
                )
            }
            let token = match
              selected_token(
                authorization_mode, get_project_token, get_adc_token,
              ) {
              Ok(token) => token
              Err(problem) =>
                return Err(authentication_error(authorization_mode, problem))
            }
            let client = @google_core.GoogleClient::new(
              fn() { token },
              http=Some(http),
            )
            match
              batch_update_document_in_tab(
                client,
                success.document_id,
                managed_tab_id,
                prepared.plan,
              ) {
              Ok(_) => {
                let updated = match
                  @registry.document_with_ready(
                    document,
                    canonical,
                    prepared.document,
                    format_unix_timestamp(current_unix_seconds()),
                  ) {
                  Ok(updated) => updated
                  Err(error) => return Err(registry_error(error))
                }
                match
                  @registry.save_registry_document(registry_directory, updated) {
                  Ok(_) => Ok(Completed(success))
                  Err(error) => Err(registry_error(error))
                }
              }
              Err(error) =>
                Err(population_error(authorization_mode, success, error))
            }
          }
        }
      }
      None => {
        match @registry.probe_registry_writable(registry_directory) {
          Ok(_) => ()
          Err(error) => return Err(registry_error(error))
        }
        let token = match
          selected_token(authorization_mode, get_project_token, get_adc_token) {
          Ok(token) => token
          Err(problem) =>
            return Err(authentication_error(authorization_mode, problem))
        }
        let client = @google_core.GoogleClient::new(
          fn() { token },
          http=Some(http),
        )
        match create_document_with_managed_tab(client, prepared.title) {
          Ok(created) => {
            let success : PublishSuccess = {
              document_id: created.document_id,
              url: canonical_document_url(created.document_id),
            }
            let provisional : @registry.PublicationEntry = {
              source_path: canonical,
              document_id: Some(created.document_id),
              url: Some(success.url),
              managed_tab_id: Some(created.managed_tab_id),
              lifecycle: Provisional,
              last_successful_publish: None,
              published_baseline: None,
              pending_merge: None,
            }
            let provisional_document = match
              @registry.document_with_provisional(document, provisional) {
              Ok(value) => value
              Err(error) => return Err(registry_error(error))
            }
            match
              @registry.save_registry_document(
                registry_directory, provisional_document,
              ) {
              Ok(_) => ()
              Err(error) =>
                return Err(
                  Registry(
                    "could not record the created document " +
                    success.document_id +
                    "; " +
                    error.user_message(),
                  ),
                )
            }
            match
              batch_update_document_in_tab(
                client,
                success.document_id,
                created.managed_tab_id,
                prepared.plan,
              ) {
              Ok(_) => {
                let updated = match
                  @registry.document_with_ready(
                    provisional_document,
                    canonical,
                    prepared.document,
                    format_unix_timestamp(current_unix_seconds()),
                  ) {
                  Ok(updated) => updated
                  Err(error) => return Err(registry_error(error))
                }
                match
                  @registry.save_registry_document(registry_directory, updated) {
                  Ok(_) => Ok(Completed(success))
                  Err(error) => Err(registry_error(error))
                }
              }
              Err(error) =>
                Err(population_error(authorization_mode, success, error))
            }
          }
          Err(AdapterTransport(_)) => {
            match @registry.document_with_blocked(document, canonical) {
              Ok(blocked) =>
                match
                  @registry.save_registry_document(registry_directory, blocked) {
                  Ok(_) => ()
                  Err(error) =>
                    return Err(
                      Registry(
                        "could not record blocked state for `" +
                        canonical +
                        "`; " +
                        error.user_message() +
                        " A duplicate document may exist; inspect Google Drive before retrying.",
                      ),
                    )
                }
              Err(error) => return Err(registry_error(error))
            }
            Err(AmbiguousCreation)
          }
          Err(AdapterHttpStatus(status~, kind~)) =>
            match
              classified_google_error(
                authorization_mode,
                DocumentCreation,
                kind,
                None,
              ) {
              Some(error) => Err(error)
              None => Err(Creation(AdapterHttpStatus(status~, kind~).message()))
            }
          Err(AdapterDecode(message)) => {
            match @registry.document_with_blocked(document, canonical) {
              Ok(blocked) =>
                match
                  @registry.save_registry_document(registry_directory, blocked) {
                  Ok(_) => ()
                  Err(error) =>
                    return Err(
                      Registry(
                        "could not record blocked state for `" +
                        canonical +
                        "`; " +
                        error.user_message() +
                        " A duplicate document may exist; inspect Google Drive before retrying.",
                      ),
                    )
                }
              Err(error) => return Err(registry_error(error))
            }
            Err(
              ResponseDecode(
                stage=DocumentCreation,
                message~,
                created_document=None,
              ),
            )
          }
        }
      }
    }
  }
}

///|
fn two_digits(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
/// Format a UTC timestamp for a successful registry commit.
pub fn format_unix_timestamp(seconds : Int64) -> String {
  let time = @time.ZonedDateTime::from_unix_second(seconds) catch {
    _ => return seconds.to_string()
  }
  time.year().to_string() +
  "-" +
  two_digits(time.month()) +
  "-" +
  two_digits(time.day()) +
  "T" +
  two_digits(time.hour()) +
  ":" +
  two_digits(time.minute()) +
  ":" +
  two_digits(time.second()) +
  "Z"
}

///|
fn inspection_for_unavailable_entry(
  entry : @registry.PublicationEntry,
) -> RemotePublicationInspection {
  {
    document_id: "",
    url: entry.url.unwrap_or(""),
    title: None,
    trashed: false,
    editable: None,
    managed_tab_present: false,
    status: Unavailable,
  }
}

///|
fn remote_error_status(error : DocsAdapterError) -> RemotePublicationStatus {
  match error {
    AdapterHttpStatus(status=404, ..) => RemoteMissing
    AdapterHttpStatus(status=403, ..)
    | AdapterHttpStatus(kind=Some(Unauthenticated), ..) => Inaccessible
    _ => Unavailable
  }
}

///|
/// Inspect a registered publication without mutating the registry or the registered document.
pub async fn inspect_registered_publication(
  token : String,
  http : &@google_http.HttpClient,
  entry : @registry.PublicationEntry,
) -> RemotePublicationInspection {
  let document_id = match entry.document_id {
    Some(value) => value
    None => return inspection_for_unavailable_entry(entry)
  }
  let url = entry.url.unwrap_or(canonical_document_url(document_id))
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let drive = match get_drive_file(client, document_id) {
    Ok(view) => view
    Err(error) =>
      return {
        document_id,
        url,
        title: None,
        trashed: false,
        editable: None,
        managed_tab_present: false,
        status: remote_error_status(error),
      }
  }
  if drive.trashed {
    return {
      document_id,
      url,
      title: drive.name,
      trashed: true,
      editable: drive.can_edit,
      managed_tab_present: false,
      status: Trashed,
    }
  }
  let docs = match get_document_view(client, document_id) {
    Ok(view) => view
    Err(error) =>
      return {
        document_id,
        url,
        title: drive.name,
        trashed: false,
        editable: drive.can_edit,
        managed_tab_present: false,
        status: remote_error_status(error),
      }
  }
  let managed_tab_present = match entry.managed_tab_id {
    Some(tab_id) => docs.tab_ids.contains(tab_id)
    None => false
  }
  let title = match docs.title {
    Some(value) => Some(value)
    None => drive.name
  }
  let status = if !managed_tab_present {
    RemotePublicationStatus::RemoteMissing
  } else {
    match drive.can_edit {
      Some(false) => ReadOnly
      _ => Ready
    }
  }
  {
    document_id,
    url,
    title,
    trashed: false,
    editable: drive.can_edit,
    managed_tab_present,
    status,
  }
}

///|
fn write_optional_string(value : String?, output : StringBuilder) -> Unit {
  match value {
    Some(value) => write_json_string(value, output)
    None => output.write_string("null")
  }
}

///|
fn write_optional_bool(value : Bool?, output : StringBuilder) -> Unit {
  match value {
    Some(value) => output.write_string(value.to_string())
    None => output.write_string("null")
  }
}

///|
fn lifecycle_name(entry : @registry.PublicationEntry) -> String {
  if entry.pending_merge is Some(_) {
    return "merge-conflicted"
  }
  match entry.lifecycle {
    Ready => "ready"
    Provisional => "provisional"
    Blocked => "blocked"
  }
}

///|
fn remote_status_name(status : RemotePublicationStatus) -> String {
  match status {
    Ready => "ready"
    Trashed => "trashed"
    ReadOnly => "read-only"
    RemoteMissing => "remote-missing"
    Inaccessible => "inaccessible"
    Unavailable => "unavailable"
  }
}

///|
fn write_publication(
  entry : @registry.PublicationEntry,
  missing_source : (String) -> Bool,
  inspection : RemotePublicationInspection?,
  output : StringBuilder,
) -> Unit {
  output.write_string("{\"source_path\":")
  write_json_string(entry.source_path, output)
  output.write_string(",\"document_id\":")
  write_optional_string(entry.document_id, output)
  output.write_string(",\"url\":")
  write_optional_string(entry.url, output)
  output.write_string(",\"managed_tab_id\":")
  write_optional_string(entry.managed_tab_id, output)
  output.write_string(",\"lifecycle\":")
  write_json_string(lifecycle_name(entry), output)
  output.write_string(",\"last_successful_publish\":")
  write_optional_string(entry.last_successful_publish, output)
  output.write_string(",\"source_missing\":")
  output.write_string(missing_source(entry.source_path).to_string())
  match inspection {
    Some(inspection) => {
      output.write_string(",\"title\":")
      write_optional_string(inspection.title, output)
      output.write_string(",\"editable\":")
      write_optional_bool(inspection.editable, output)
      output.write_string(",\"remote_status\":")
      write_json_string(remote_status_name(inspection.status), output)
    }
    None => ()
  }
  output.write_char('}')
}

///|
fn sorted_entries(
  document : @registry.RegistryDocument,
) -> Array[@registry.PublicationEntry] {
  let entries = document.entries.copy()
  entries.sort_by(fn(a, b) {
    if a.source_path < b.source_path {
      -1
    } else if a.source_path > b.source_path {
      1
    } else {
      0
    }
  })
  entries
}

///|
/// Render the stable machine JSON contract for local registry listing.
pub fn publication_list_json(
  document : @registry.RegistryDocument,
  missing_source : (String) -> Bool,
) -> String {
  let output = StringBuilder::new()
  output.write_string("{\"version\":1,\"publications\":[")
  let mut first = true
  for entry in sorted_entries(document) {
    if !first {
      output.write_char(',')
    }
    first = false
    write_publication(entry, missing_source, None, output)
  }
  output.write_string("]}")
  output.to_string()
}

///|
/// Render the stable machine JSON contract enriched with remote inspections.
pub fn publication_refresh_json(
  document : @registry.RegistryDocument,
  missing_source : (String) -> Bool,
  inspections : Array[RemotePublicationInspection],
) -> String {
  let output = StringBuilder::new()
  output.write_string("{\"version\":1,\"publications\":[")
  let mut first = true
  for entry in sorted_entries(document) {
    if !first {
      output.write_char(',')
    }
    first = false
    let inspection = match entry.document_id {
      Some(document_id) => {
        let mut found = None
        for candidate in inspections {
          if candidate.document_id == document_id {
            found = Some(candidate)
          }
        }
        found
      }
      None => None
    }
    write_publication(entry, missing_source, inspection, output)
  }
  output.write_string("]}")
  output.to_string()
}

///|
fn pull_reconciliation_error(error : PullReconcileError) -> PublishError {
  match error {
    AmbiguousAlignment(message) => MergeConflict(message~)
    InvalidLocalSource(message) | CanonicalSerialization(message) =>
      Planning(message)
  }
}

///|
async fn pull_loaded_publication(
  source : String,
  prepared : PreparedPublication,
  canonical : String,
  document : @registry.RegistryDocument,
  registry_directory : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
  replace_source : async (String, String) -> Result[Unit, String],
  dry_run : Bool,
) -> Result[PullOutcome, PublishError] {
  let entry = match @registry.publication_for_source(document, canonical) {
    Some(entry) => entry
    None =>
      return Err(
        Registry("no Publication is registered for `" + canonical + "`"),
      )
  }
  match entry.lifecycle {
    Blocked => return Err(BlockedPublication(source_path=canonical))
    Provisional => return Err(Registry("Publication is not ready for pull"))
    Ready => ()
  }
  if entry.pending_merge is Some(_) {
    return Err(
      Registry(
        "Publication has a Pending Merge; run `pumd resolve " +
        canonical +
        "` or `pumd pull --abort " +
        canonical +
        "`",
      ),
    )
  }
  let success = success_from_entry(entry)
  let managed_tab_id = match entry.managed_tab_id {
    Some(value) => value
    None => abort("invalid ready registry entry")
  }
  let baseline = match entry.published_baseline {
    Some(value) => value
    None => abort("invalid ready registry entry")
  }
  let previous_timestamp = match entry.last_successful_publish {
    Some(value) => value
    None => abort("invalid ready registry entry")
  }
  let token = match
    selected_token(authorization_mode, get_project_token, get_adc_token) {
    Ok(token) => token
    Err(problem) =>
      return Err(authentication_error(authorization_mode, problem))
  }
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let retrieved = match get_remote_document_body(client, success.document_id) {
    Ok(value) => value
    Err(error) =>
      return Err(
        read_error(authorization_mode, success.document_id, success.url, error),
      )
  }
  let decoded = match
    decode_remote_document(retrieved.body, retrieved.document_id) {
    Ok(value) => value
    Err(error) => return Err(decoded_read_error(success, error))
  }
  let managed_content = match remote_tab_content(decoded, managed_tab_id) {
    Some(value) => value
    None =>
      return Err(
        RemoteMissing(document_id=success.document_id, url=success.url),
      )
  }
  let plan = match
    plan_pull(source, baseline, prepared.document, managed_content) {
    Ok(value) => value
    Err(error) => return Err(pull_reconciliation_error(error))
  }
  let report = {
    document_id: success.document_id,
    url: success.url,
    title: decoded.title,
    plan,
  }
  if plan.conflicted > 0 {
    if dry_run {
      return Ok(PullConflicted(report))
    }
    let pending : @registry.PendingMerge = {
      pre_pull_source: source,
      marked_source: plan.source,
      observed_remote_body: retrieved.body,
      observed_revision_id: remote_revision_id(decoded),
    }
    let updated = match
      @registry.document_with_pending_merge(document, canonical, pending) {
      Ok(value) => value
      Err(error) => return Err(registry_error(error))
    }
    match @registry.save_registry_document(registry_directory, updated) {
      Ok(_) => ()
      Err(error) => return Err(registry_error(error))
    }
    match replace_source(canonical, plan.source) {
      Ok(_) => return Ok(PullConflicted(report))
      Err(message) => return Err(SourceWrite(path=canonical, message~))
    }
  }
  if dry_run {
    return Ok(PullDryRun(report))
  }
  let source_changed = plan.source != source
  let baseline_changed = plan.incoming > 0 || plan.converged > 0
  if source_changed {
    match replace_source(canonical, plan.source) {
      Ok(_) => ()
      Err(message) => return Err(SourceWrite(path=canonical, message~))
    }
  }
  if baseline_changed {
    let updated = match
      @registry.document_with_updated_baseline(
        document,
        canonical,
        plan.baseline,
        previous_timestamp,
      ) {
      Ok(value) => value
      Err(error) => return Err(registry_error(error))
    }
    match @registry.save_registry_document(registry_directory, updated) {
      Ok(_) => ()
      Err(error) => return Err(registry_error(error))
    }
  }
  if source_changed || baseline_changed {
    Ok(Pulled(report))
  } else {
    Ok(PullNoOp(report))
  }
}

///|
/// Pull committed Source Semantics from a ready Publication. The injected
/// replacement seam lets workflow tests observe source-first persistence.
pub async fn pull_path_with_registry(
  path : String,
  read_source : async (String) -> Result[String, String],
  replace_source : async (String, String) -> Result[Unit, String],
  registry_directory : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
  dry_run : Bool,
) -> Result[PullOutcome, PublishError] {
  let source = match read_source(path) {
    Ok(value) => value
    Err(_) => return Err(SourceAccess(path~))
  }
  let prepared = match
    prepare_publication_markdown(source, publication_title_from_path(path)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let canonical = @registry.canonical_source_path(path)
  if dry_run {
    let document = match @registry.load_registry_document(registry_directory) {
      Ok(value) => value
      Err(error) => return Err(registry_error(error))
    }
    return pull_loaded_publication(
      source, prepared, canonical, document, registry_directory, authorization_mode,
      get_project_token, get_adc_token, http, replace_source, true,
    )
  }
  let lock = match @registry.acquire_registry_lock(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  defer lock.release()
  let document = match @registry.load_registry_document(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  pull_loaded_publication(
    source, prepared, canonical, document, registry_directory, authorization_mode,
    get_project_token, get_adc_token, http, replace_source, false,
  )
}

///|
/// Restore the exact pre-pull Markdown bytes and then clear Pending Merge.
/// This path performs no authorization or remote access; source-first ordering
/// makes a retry safe if registry persistence is interrupted.
pub async fn abort_pull_with_registry(
  path : String,
  replace_source : async (String, String) -> Result[Unit, String],
  registry_directory : String,
) -> Result[Unit, PublishError] {
  let canonical = @registry.canonical_source_path(path)
  let lock = match @registry.acquire_registry_lock(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  defer lock.release()
  let document = match @registry.load_registry_document(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  let entry = match @registry.publication_for_source(document, canonical) {
    Some(value) => value
    None =>
      return Err(
        Registry("no Publication is registered for `" + canonical + "`"),
      )
  }
  let pending = match entry.pending_merge {
    Some(value) => value
    None =>
      return Err(registry_error(@registry.PendingMergeRequired(canonical)))
  }
  match replace_source(canonical, pending.pre_pull_source) {
    Ok(_) => ()
    Err(message) => return Err(SourceWrite(path=canonical, message~))
  }
  let updated = match
    @registry.document_without_pending_merge(document, canonical) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  match @registry.save_registry_document(registry_directory, updated) {
    Ok(_) => Ok(())
    Err(error) => Err(registry_error(error))
  }
}

///|
fn source_has_merge_markers(source : String) -> Bool {
  for line in source.split("\n") {
    if line.has_prefix("<<<<<<< ") ||
      line.has_prefix("||||||| ") ||
      (line.has_prefix("=======") &&
      (line.length() == 7 ||
      (line.length() == 8 && line.has_suffix("\r")))) ||
      line.has_prefix(">>>>>>> ") {
      return true
    }
  }
  false
}

///|
fn resolved_state_landed(
  source : String,
  observed_baseline : @pumd.DesiredDocument,
  desired : @pumd.DesiredDocument,
  current : RemoteContent,
  report : ReconciliationReport,
) -> Bool {
  if report.local_changes > 0 {
    return update_intended_state_landed(
      observed_baseline,
      desired,
      current,
      report,
    )
  }
  match plan_pull(source, desired, desired, current) {
    Ok(plan) => plan.incoming == 0 && plan.conflicted == 0
    Err(_) => false
  }
}

///|
async fn commit_resolved_merge(
  document : @registry.RegistryDocument,
  registry_directory : String,
  canonical : String,
  baseline : @pumd.DesiredDocument,
  success : PublishSuccess,
) -> Result[PublishOutcome, PublishError] {
  let cleared = match
    @registry.document_without_pending_merge(document, canonical) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  let timestamp = format_unix_timestamp(current_unix_seconds())
  let updated = match
    @registry.document_with_updated_baseline(
      cleared, canonical, baseline, timestamp,
    ) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  match @registry.save_registry_document(registry_directory, updated) {
    Ok(_) => Ok(Updated(success, timestamp))
    Err(error) => Err(registry_error(error))
  }
}

///|
/// Resolve an edited Pending Merge through the same authenticated, revision-
/// checked remote update path used by publish.
pub async fn resolve_path_with_registry(
  path : String,
  read_source : async (String) -> Result[String, String],
  registry_directory : String,
  authorization_mode : AuthorizationMode,
  get_project_token : async () -> Result[String, AuthenticationProblem],
  get_adc_token : async () -> Result[String, AuthenticationProblem],
  http : &@google_http.HttpClient,
) -> Result[PublishOutcome, PublishError] {
  let canonical = @registry.canonical_source_path(path)
  let lock = match @registry.acquire_registry_lock(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  defer lock.release()
  let document = match @registry.load_registry_document(registry_directory) {
    Ok(value) => value
    Err(error) => return Err(registry_error(error))
  }
  let entry = match @registry.publication_for_source(document, canonical) {
    Some(value) => value
    None =>
      return Err(
        Registry("no Publication is registered for `" + canonical + "`"),
      )
  }
  let pending = match entry.pending_merge {
    Some(value) => value
    None =>
      return Err(registry_error(@registry.PendingMergeRequired(canonical)))
  }
  let source = match read_source(path) {
    Ok(value) => value
    Err(_) => return Err(SourceAccess(path~))
  }
  if source_has_merge_markers(source) {
    return Err(
      Planning("edited Markdown still contains diff3 conflict markers"),
    )
  }
  let prepared = match
    prepare_publication_markdown(source, publication_title_from_path(path)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  guard entry.lifecycle is Ready else {
    return Err(Registry("Publication is not ready for resolve"))
  }
  let success = success_from_entry(entry)
  let managed_tab_id = match entry.managed_tab_id {
    Some(value) => value
    None => abort("invalid ready registry entry")
  }
  let published_baseline = match entry.published_baseline {
    Some(value) => value
    None => abort("invalid ready registry entry")
  }
  let observed = match
    decode_remote_document(pending.observed_remote_body, success.document_id) {
    Ok(value) => value
    Err(_) =>
      return Err(
        Registry("Pending Merge contains invalid observed remote state"),
      )
  }
  if remote_revision_id(observed) != pending.observed_revision_id {
    return Err(Registry("Pending Merge observed revision is inconsistent"))
  }
  let observed_content = match remote_tab_content(observed, managed_tab_id) {
    Some(value) => value
    None => return Err(Registry("Pending Merge Managed Tab is missing"))
  }
  let newline = if source.contains("\r\n") { "\r\n" } else { "\n" }
  let observed_baseline = match
    desired_document_from_remote(observed_content, published_baseline, newline~) {
    Ok(value) => value
    Err(error) => return Err(pull_reconciliation_error(error))
  }
  let reconciliation = match
    reconcile_pending_merge_resolution(
      observed_baseline,
      prepared.document,
      observed_content,
    ) {
    Ok(value) => value
    Err(error) => return Err(reconciliation_error(error))
  }
  let (report, plan) = match reconciliation {
    Conflict(report) => return Err(conflict_error(report))
    NoLocalChanges(report) => (report, None)
    Planned(report, plan) => (report, Some(plan))
  }
  let token = match
    selected_token(authorization_mode, get_project_token, get_adc_token) {
    Ok(value) => value
    Err(problem) =>
      return Err(authentication_error(authorization_mode, problem))
  }
  let client = @google_core.GoogleClient::new(fn() { token }, http=Some(http))
  let retrieved = match get_remote_document_body(client, success.document_id) {
    Ok(value) => value
    Err(error) =>
      return Err(
        read_error(authorization_mode, success.document_id, success.url, error),
      )
  }
  let current = match
    decode_remote_document(retrieved.body, retrieved.document_id) {
    Ok(value) => value
    Err(error) => return Err(decoded_read_error(success, error))
  }
  let current_content = match remote_tab_content(current, managed_tab_id) {
    Some(value) => value
    None =>
      return Err(
        RemoteMissing(document_id=success.document_id, url=success.url),
      )
  }
  let current_revision = remote_revision_id(current)
  if current_revision != pending.observed_revision_id &&
    !resolved_state_landed(
      source,
      observed_baseline,
      prepared.document,
      current_content,
      report,
    ) {
    return Err(
      Concurrency(
        message="the Google Docs revision changed since pull; the Pending Merge was retained",
      ),
    )
  }
  let comments = match inspect_comments(client, success.document_id) {
    Ok(value) => value
    Err(error) => return Err(comment_error(authorization_mode, success, error))
  }
  if comments.unresolved > 0 {
    return Err(ReviewBarrier(unresolved=comments.unresolved))
  }
  if current_revision != pending.observed_revision_id || plan is None {
    return commit_resolved_merge(
      document,
      registry_directory,
      canonical,
      prepared.document,
      success,
    )
  }
  guard plan is Some(update_plan) else { abort("checked resolve plan") }
  match
    batch_update_document_with_revision(
      client,
      success.document_id,
      managed_tab_id,
      update_plan,
      current_revision,
    ) {
    Ok(_) =>
      commit_resolved_merge(
        document,
        registry_directory,
        canonical,
        prepared.document,
        success,
      )
    Err(RevisionConflict) =>
      Err(
        Concurrency(
          message="the Google Docs revision changed during resolve; nothing was applied and the Pending Merge was retained",
        ),
      )
    Err(Adapter(AdapterTransport(_))) => {
      let reread = match get_remote_document_body(client, success.document_id) {
        Ok(value) => value
        Err(_) =>
          return Err(
            AmbiguousUpdate(document_id=success.document_id, url=success.url),
          )
      }
      let reread_document = match
        decode_remote_document(reread.body, reread.document_id) {
        Ok(value) => value
        Err(_) =>
          return Err(
            AmbiguousUpdate(document_id=success.document_id, url=success.url),
          )
      }
      let reread_content = match
        remote_tab_content(reread_document, managed_tab_id) {
        Some(value) => value
        None =>
          return Err(
            AmbiguousUpdate(document_id=success.document_id, url=success.url),
          )
      }
      if resolved_state_landed(
        source,
        observed_baseline,
          prepared.document,
          reread_content,
          report,
        ) {
        commit_resolved_merge(
          document,
          registry_directory,
          canonical,
          prepared.document,
          success,
        )
      } else {
        Err(AmbiguousUpdate(document_id=success.document_id, url=success.url))
      }
    }
    Err(Adapter(error)) => Err(update_error(authorization_mode, success, error))
  }
}
