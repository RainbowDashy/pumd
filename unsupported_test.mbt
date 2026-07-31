///|
fn assert_diagnostic_source_range(
  actual : @pumd.SourceRange?,
  expected_start : Int,
  expected_end : Int,
) -> Unit raise {
  match actual {
    Some(range) => {
      assert_eq(range.start, expected_start)
      assert_eq(range.end, expected_end)
    }
    None => assert_true(false)
  }
}

///|
fn assert_render_failure(
  source : String,
  expected_kind : @pumd.DiagnosticKind,
  expected_node_kind : String,
  expected_start : Int,
  expected_end : Int,
  expected_message : String,
) -> Unit raise {
  match @pumd.render_markdown(source) {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_diagnostic(
        diagnostics[0],
        expected_kind,
        expected_node_kind,
        expected_start,
        expected_end,
        expected_message,
      )
    }
  }
}

///|
fn assert_diagnostic(
  diagnostic : @pumd.RenderingDiagnostic,
  expected_kind : @pumd.DiagnosticKind,
  expected_node_kind : String,
  expected_start : Int,
  expected_end : Int,
  expected_message : String,
) -> Unit raise {
  assert_eq(diagnostic.kind, expected_kind)
  assert_eq(diagnostic.node_kind, expected_node_kind)
  assert_diagnostic_source_range(
    diagnostic.provenance,
    expected_start,
    expected_end,
  )
  assert_eq(diagnostic.message, expected_message)
}

///|
test "golden frontmatter diagnostic is actionable and has parser provenance" {
  assert_render_failure(
    "---\ntitle: T\n---",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "frontmatter",
    0,
    16,
    "Remove the YAML frontmatter; document metadata is not supported.",
  )
}

///|
test "golden diagnostics cover every directly exposed unsupported construct" {
  assert_render_failure(
    "---",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "thematic-break",
    0,
    3,
    "Replace the thematic break with a paragraph or remove it.",
  )
  assert_render_failure(
    "    code",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "indented-code",
    0,
    8,
    "Replace the indented code block with a fenced code block.",
  )
  assert_render_failure(
    "> quote",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "blockquote",
    0,
    7,
    "Remove the blockquote marker and use regular paragraphs instead.",
  )
  assert_render_failure(
    "<div>html</div>",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "html-block",
    0,
    15,
    "Remove the HTML block and use supported Markdown instead.",
  )
  assert_render_failure(
    "[^note]: note",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "footnote-definition",
    0,
    13,
    "Remove the footnote definition and include its content inline.",
  )
  assert_render_failure(
    "- [ ] todo",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "task-list-item",
    0,
    10,
    "Replace the task list item with a regular list item.",
  )
  assert_render_failure(
    "- [x] done",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "task-list-item",
    0,
    10,
    "Replace the task list item with a regular list item.",
  )
  assert_render_failure(
    "![alt](image.png)",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "image",
    0,
    17,
    "Replace the image with a text link.",
  )
  assert_render_failure(
    "![alt][image]",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "reference-image",
    0,
    13,
    "Replace the reference image with a text link.",
  )
  assert_render_failure(
    "~~deleted~~",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "strikethrough",
    0,
    11,
    "Remove the strikethrough markers or use plain text.",
  )
  assert_render_failure(
    "x <!-- inline -->",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "html-inline",
    2,
    17,
    "Remove the inline HTML and use supported Markdown instead.",
  )
  assert_render_failure(
    "[[Page]]",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "wiki-link",
    0,
    8,
    "Replace the wiki link with a standard Markdown link.",
  )
  assert_render_failure(
    "[^note]",
    @pumd.DiagnosticKind::UnsupportedConstruct,
    "footnote-reference",
    0,
    7,
    "Replace the footnote reference with inline text or a standard link.",
  )
  assert_render_failure(
    "[text][missing]",
    @pumd.DiagnosticKind::MissingDefinition,
    "reference-link",
    0,
    15,
    "Add a link definition for label: missing.",
  )
}

///|
test "rejected containers collect nested diagnostics in preorder" {
  match @pumd.render_markdown("> ![alt](image.png)") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_diagnostic(
        diagnostics[0],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "blockquote",
        0,
        19,
        "Remove the blockquote marker and use regular paragraphs instead.",
      )
      assert_diagnostic(
        diagnostics[1],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "image",
        0,
        17,
        "Replace the image with a text link.",
      )
    }
  }
  match @pumd.render_markdown("[^note]: ![alt](image.png)") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_diagnostic(
        diagnostics[0],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "footnote-definition",
        0,
        26,
        "Remove the footnote definition and include its content inline.",
      )
      assert_diagnostic(
        diagnostics[1],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "image",
        0,
        17,
        "Replace the image with a text link.",
      )
    }
  }
  match @pumd.render_markdown("- [x] ![alt](image.png)") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_diagnostic(
        diagnostics[0],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "task-list-item",
        0,
        23,
        "Replace the task list item with a regular list item.",
      )
      assert_diagnostic(
        diagnostics[1],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "image",
        0,
        17,
        "Replace the image with a text link.",
      )
    }
  }
}

///|
test "multiple unsupported constructs have a stable diagnostic order" {
  match @pumd.render_markdown("![a](x) ~~b~~ [^n]") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 3)
      assert_diagnostic(
        diagnostics[0],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "image",
        0,
        7,
        "Replace the image with a text link.",
      )
      assert_diagnostic(
        diagnostics[1],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "strikethrough",
        8,
        13,
        "Remove the strikethrough markers or use plain text.",
      )
      assert_diagnostic(
        diagnostics[2],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "footnote-reference",
        14,
        18,
        "Replace the footnote reference with inline text or a standard link.",
      )
    }
  }
}

///|
test "missing reference definitions still collect unsupported link-text children" {
  match @pumd.render_markdown("[~~x~~][missing]") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_diagnostic(
        diagnostics[0],
        @pumd.DiagnosticKind::MissingDefinition,
        "reference-link",
        0,
        16,
        "Add a link definition for label: missing.",
      )
      assert_diagnostic(
        diagnostics[1],
        @pumd.DiagnosticKind::UnsupportedConstruct,
        "strikethrough",
        0,
        5,
        "Remove the strikethrough markers or use plain text.",
      )
    }
  }
}

///|
test "collects unsupported diagnostics in stable source order" {
  match @pumd.render_markdown("text\n\n---\n\n> quote") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_eq(diagnostics[0].node_kind, "thematic-break")
      assert_eq(diagnostics[1].node_kind, "blockquote")
    }
  }
}
