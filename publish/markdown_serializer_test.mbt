///|
fn serializer_paragraph(run : SourceSemanticRun) -> SourceSemanticUnit {
  SourceSemanticUnit::Paragraph({
    runs: [run],
    images: [],
    heading: 0,
    list: None,
    nesting_level: 0,
    quote_depth: 0,
    code_block: false,
  })
}

///|
fn serializer_semantic_round_trips(
  unit : SourceSemanticUnit,
  expected_source : String,
) -> Bool {
  let actual = match
    @pumd.render_markdown(serialize_source_semantic_unit(unit)) {
    Ok(document) => document
    Err(_) => abort("canonical Markdown must render")
  }
  let expected = match @pumd.render_markdown(expected_source) {
    Ok(document) => document
    Err(_) => abort("expected Markdown fixture must render")
  }
  actual.semantic_eq(expected)
}

///|
test "canonical inline code delimiter exceeds every content backtick run" {
  let unit = serializer_paragraph({
    text: "alpha `` beta ` gamma",
    bold: false,
    italic: false,
    code: true,
    link: None,
  })
  inspect(
    serialize_source_semantic_unit(unit),
    content="```alpha `` beta ` gamma```",
  )
  assert_true(
    serializer_semantic_round_trips(unit, "```alpha `` beta ` gamma```"),
  )
}

///|
test "canonical inline code separates edge backticks from its delimiter" {
  let unit = serializer_paragraph({
    text: "` edge ``",
    bold: false,
    italic: false,
    code: true,
    link: None,
  })
  inspect(
    serialize_source_semantic_unit(unit),
    content="``` ` edge `` ```",
  )
  assert_true(
    serializer_semantic_round_trips(unit, "``` ` edge `` ```"),
  )
}

///|
test "canonical link destinations preserve parentheses backslashes and spaces" {
  let unit = serializer_paragraph({
    text: "linked",
    bold: false,
    italic: false,
    code: false,
    link: Some("https://example.test/a (b)\\c d"),
  })
  inspect(
    serialize_source_semantic_unit(unit),
    content="[linked](<https://example.test/a (b)\\c d>)",
  )
  assert_true(
    serializer_semantic_round_trips(
      unit, "[linked](<https://example.test/a (b)\\c d>)",
    ),
  )
}
