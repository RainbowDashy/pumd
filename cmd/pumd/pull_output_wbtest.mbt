///|
fn pull_output_report() -> @publish.PullReport {
  let prepared = @publish.prepare_publication_markdown("Baseline", "test").unwrap()
  let units : Array[@publish.PullUnitReport] = [
    { category: Incoming, description: "paragraph 1" },
    { category: PreservedLocal, description: "paragraph 2" },
    { category: Converged, description: "table 1" },
    { category: Conflicted, description: "paragraph \"3\"" },
    { category: SkippedSuggestion, description: "paragraph 4" },
    { category: SkippedUnsupported, description: "unsupported structure" },
  ]
  {
    document_id: "doc-1",
    url: "https://docs.test/doc-1",
    title: Some("Reviewer \"title\""),
    plan: {
      source: "Incoming",
      baseline: prepared.document,
      units,
      incoming: 1,
      preserved_local: 1,
      converged: 1,
      conflicted: 1,
      skipped: 2,
    },
  }
}

///|
test "pull JSON output exposes every stable unit category" {
  inspect(
    pull_report_json("conflicted", true, pull_output_report()),
    content="{\"version\":1,\"outcome\":\"conflicted\",\"dry_run\":true,\"document_id\":\"doc-1\",\"url\":\"https://docs.test/doc-1\",\"title\":\"Reviewer \\\"title\\\"\",\"incoming\":1,\"preserved_local\":1,\"converged\":1,\"conflicted\":1,\"skipped\":2,\"units\":[{\"category\":\"incoming\",\"description\":\"paragraph 1\"},{\"category\":\"preserved-local\",\"description\":\"paragraph 2\"},{\"category\":\"converged\",\"description\":\"table 1\"},{\"category\":\"conflicted\",\"description\":\"paragraph \\\"3\\\"\"},{\"category\":\"skipped-suggestion\",\"description\":\"paragraph 4\"},{\"category\":\"skipped-unsupported\",\"description\":\"unsupported structure\"}]}",
  )
}

///|
test "pull presentation preserves dry-run conflict exit classification" {
  let report = pull_output_report()
  let dry = pull_presentation(PullConflicted(report), true)
  assert_eq(dry.name, "conflicted")
  assert_eq(dry.heading, "dry run: pull would encounter Merge Conflicts")
  assert_true(dry.dry_run)
  assert_true(dry.conflict)
  let clean = pull_presentation(Pulled(report), false)
  assert_eq(clean.name, "pulled")
  assert_eq(clean.heading, "pull completed")
  assert_true(!clean.dry_run)
  assert_true(!clean.conflict)
}

///|
test "Pending Merge CLI commands route through main's recovery dispatch" {
  let abort_command = @args.parse_command([
    "pumd", "pull", "--abort", "proposal.md",
  ]).unwrap()
  match pending_command_route(abort_command) {
    AbortRoute(path) => inspect(path, content="proposal.md")
    _ => fail("pull abort must use the local recovery route")
  }
  let resolve_command = @args.parse_command([
    "pumd", "resolve", "--auth=adc", "proposal.md",
  ]).unwrap()
  match pending_command_route(resolve_command) {
    ResolveRoute(path, @args.Authorization::Adc) =>
      inspect(path, content="proposal.md")
    _ => fail("resolve must use the authenticated recovery route")
  }
  assert_eq(
    abort_pull_success_message(),
    "pull aborted; exact pre-pull Markdown restored\n",
  )
}

///|
test "Pending Merge text listing reports merge-conflicted" {
  let baseline = @publish.prepare_publication_markdown("Base", "test").unwrap().document
  let entry : @registry.PublicationEntry = {
    source_path: "proposal.md",
    document_id: Some("doc"),
    url: Some("url"),
    managed_tab_id: Some("tab"),
    lifecycle: Ready,
    last_successful_publish: Some("before"),
    published_baseline: Some(baseline),
    pending_merge: Some({
      pre_pull_source: "Local",
      marked_source: "marked",
      observed_remote_body: "body",
      observed_revision_id: "rev",
    }),
  }
  assert_eq(publication_status_label(entry), "merge-conflicted")
}

///|
async test "Pending Merge command handlers report recovery outcomes and failures" {
  let standard_output : Array[String] = []
  let errors : Array[String] = []
  let exit_codes : Array[Int] = []
  run_abort_handler(
    fn() { Ok(()) },
    fn(message) { standard_output.push(message) },
    fn(message) { errors.push(message); exit_codes.push(1) },
  )
  assert_eq(standard_output, [abort_pull_success_message()])
  assert_eq(errors, [])
  run_abort_handler(
    fn() { Err(@publish.PublishError::Registry("Pending Merge is missing")) },
    fn(message) { standard_output.push(message) },
    fn(message) { errors.push(message); exit_codes.push(1) },
  )
  assert_true(errors[0].contains("Pending Merge is missing"))
  let resolved : Array[@publish.PublishOutcome] = []
  run_resolve_handler(
    Ok(@publish.PublishOutcome::Updated(
      { document_id: "doc", url: "url" },
      "after",
    )),
    fn(outcome) { resolved.push(outcome) },
    fn(message) { errors.push(message); exit_codes.push(1) },
  )
  assert_eq(resolved.length(), 1)
  for error in [
    @publish.PublishError::Concurrency(message="stale remote state"),
    @publish.PublishError::AmbiguousUpdate(document_id="doc", url="url"),
    @publish.PublishError::ReviewBarrier(unresolved=1),
    @publish.PublishError::Registry("Publication has a Pending Merge"),
  ] {
    run_resolve_handler(
      Err(error),
      fn(outcome) { resolved.push(outcome) },
      fn(message) { errors.push(message); exit_codes.push(1) },
    )
  }
  assert_eq(exit_codes, [1, 1, 1, 1, 1])
  assert_true(errors.any(fn(message) { message.contains("stale remote state") }))
  assert_true(errors.any(fn(message) { message.contains("ambiguous") }))
  assert_true(errors.any(fn(message) { message.contains("unresolved") }))
  assert_true(errors.any(fn(message) { message.contains("Pending Merge") }))
}
