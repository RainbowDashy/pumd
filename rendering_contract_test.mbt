///|
fn render_or_fail(source : String) -> @pumd.DesiredDocument raise {
  match @pumd.render_markdown(source) {
    Ok(document) => document
    Err(_) => fail("expected supported Markdown to render")
  }
}

///|
fn mixed_feature_markdown() -> String {
  (
    #|# Contract title
    #|
    #|Body with **bold**, *italic*, [a link](https://example.test/guide "Guide title"), and `inline` code.
    #|
    #|```moonbit
    #|let answer = 42
    #|```
    #|
    #|- outer **bold**
    #|  - nested `code`
    #|
    #|3. third
    #|4. fourth
    #|
    #|| Name | Value |
    #|| :--- | :---: |
    #|| `cell` | [link](https://example.test/table "Table title") |
  )
}

///|
test "mixed supported Markdown has a canonical native golden document" {
  let document = render_or_fail(mixed_feature_markdown())
  inspect(
    document.to_snapshot(),
    content=(
      #|profile pumd.default@2
      #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8
      #|  text "Contract title" font=Arial size=24
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
      #|  text "Body with " font=Arial size=11
      #|  text "bold" bold font=Arial size=11
      #|  text ", " font=Arial size=11
      #|  text "italic" italic font=Arial size=11
      #|  text ", " font=Arial size=11
      #|  text "a link" underline font=Arial size=11 color=#1155CC link="https://example.test/guide" title="Guide title"
      #|  text ", and " font=Arial size=11
      #|  text "inline" font=Roboto Mono size=10 background=#F1F3F4
      #|  text " code." font=Arial size=11
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "let answer = 42" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
      #|  text "outer " font=Arial size=11
      #|  text "bold" bold font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=1
      #|  text "nested " font=Arial size=11
      #|  text "code" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(3.) level=0
      #|  text "third" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(3.) level=0
      #|  text "fourth" font=Arial size=11
      #|table
      #|  header-row
      #|    cell alignment=left background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Name" bold font=Arial size=11
      #|    cell alignment=center background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Value" bold font=Arial size=11
      #|  row
      #|    cell alignment=left
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "cell" font=Roboto Mono size=10 background=#F1F3F4
      #|    cell alignment=center
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "link" underline font=Arial size=11 color=#1155CC link="https://example.test/table" title="Table title"
      #|
    ),
  )
}

///|
test "repeated identical Markdown renders to equal content and identical golden output" {
  let source = mixed_feature_markdown()
  let first = render_or_fail(source)
  let second = render_or_fail(source)
  assert_true(first.semantic_eq(second))
  assert_true(second.semantic_eq(first))
  assert_eq(first.to_snapshot(), second.to_snapshot())
}

///|
test "moving unchanged source changes provenance without changing native content" {
  let original = render_or_fail("# Stable\n\nSame content")
  let moved = render_or_fail("\n\n# Stable\n\nSame content")
  assert_true(original.semantic_eq(moved))
  assert_eq(original.to_snapshot(), moved.to_snapshot())
  match (original.content[0], moved.content[0]) {
    (
      @pumd.StructuralElement::Paragraph(original_heading),
      @pumd.StructuralElement::Paragraph(moved_heading),
    ) => {
      assert_source_range(original_heading.provenance, 0, 9)
      assert_source_range(moved_heading.provenance, 2, 11)
    }
    _ => assert_true(false)
  }
}

///|
test "empty and blank-line whitespace variants have documented deterministic output" {
  let empty = render_or_fail("")
  let blank = render_or_fail("\n\n\n")
  assert_eq(empty.to_snapshot(), "profile pumd.default@2\n")
  assert_eq(blank.to_snapshot(), empty.to_snapshot())
  assert_true(empty.semantic_eq(blank))

  let expected =
    #|profile pumd.default@2
    #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
    #|  text "Text" font=Arial size=11
    #|
  let plain = render_or_fail("Text")
  let final_newline = render_or_fail("Text\n")
  let padded = render_or_fail("\n\nText\n\n\n")
  assert_eq(plain.to_snapshot(), expected)
  assert_eq(final_newline.to_snapshot(), expected)
  assert_eq(padded.to_snapshot(), expected)
  assert_true(plain.semantic_eq(final_newline))
  assert_true(final_newline.semantic_eq(padded))
}

///|
test "CJK combining marks and non-BMP Unicode retain rendered content and code-point provenance" {
  let document = render_or_fail("中文é🚀")
  assert_source_range(document.provenance, 0, 5)
  assert_eq(document.content.length(), 1)
  match document.content[0] {
    @pumd.StructuralElement::Paragraph(paragraph) => {
      assert_source_range(paragraph.provenance, 0, 5)
      assert_eq(paragraph.runs.length(), 1)
      assert_eq(paragraph.runs[0].content, "中文é🚀")
      assert_source_range(paragraph.runs[0].provenance, 0, 5)
    }
    @pumd.StructuralElement::Table(_) => assert_true(false)
  }
}

///|
test "canonical rendering removes empty runs merges adjacent runs and normalizes optional properties" {
  let document = render_or_fail(
    "left\nright  \nafter [plain](https://example.test)\n\n# Heading\n\n| Header |\n| :----- |\n| Value |",
  )
  assert_eq(document.content.length(), 3)
  match document.content[0] {
    @pumd.StructuralElement::Paragraph(paragraph) => {
      assert_true(paragraph.bullet is None)
      assert_eq(paragraph.runs.length(), 2)
      assert_eq(paragraph.runs[0].content, "left right\nafter ")
      assert_true(paragraph.runs[0].link is None)
      assert_true(paragraph.runs[0].style.foreground_color is None)
      assert_true(paragraph.runs[0].style.background_color is None)
      match paragraph.runs[1].link {
        Some(link) => {
          assert_eq(link.url, "https://example.test")
          assert_true(link.title is None)
        }
        None => assert_true(false)
      }
      for run in paragraph.runs {
        assert_true(!run.content.is_empty())
      }
    }
    _ => assert_true(false)
  }
  match document.content[1] {
    @pumd.StructuralElement::Paragraph(paragraph) => {
      assert_eq(paragraph.style.named_style, @pumd.NamedStyle::Heading1)
      assert_true(paragraph.bullet is None)
    }
    _ => assert_true(false)
  }
  match document.content[2] {
    @pumd.StructuralElement::Table(table) => {
      assert_eq(table.rows.length(), 2)
      let header_row = table.rows[0]
      let body_row = table.rows[1]
      let header_cell = header_row.cells[0]
      let body_cell = body_row.cells[0]
      assert_true(header_cell.background_color is Some(_))
      assert_true(body_cell.background_color is None)
      let header_paragraph = header_cell.content[0]
      assert_true(header_paragraph.bullet is None)
    }
    _ => assert_true(false)
  }
}
