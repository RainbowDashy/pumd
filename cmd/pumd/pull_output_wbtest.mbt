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
