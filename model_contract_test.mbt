///|
fn assert_source_range(
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
test "public seam applies all six heading roles and profile sizes" {
  let markdown =
    #|# One
    #|
    #|## Two
    #|
    #|### Three
    #|
    #|#### Four
    #|
    #|##### Five
    #|
    #|###### Six
  let expected_named_styles = [
    @pumd.NamedStyle::Heading1,
    @pumd.NamedStyle::Heading2,
    @pumd.NamedStyle::Heading3,
    @pumd.NamedStyle::Heading4,
    @pumd.NamedStyle::Heading5,
    @pumd.NamedStyle::Heading6,
  ]
  let expected_sizes = [24, 18, 14, 12, 11, 10]
  match @pumd.render_markdown(markdown) {
    Ok(document) => {
      assert_eq(document.render_metadata.style_profile_id, "pumd.default")
      assert_eq(document.render_metadata.style_profile_version, 2)
      assert_eq(document.content.length(), 6)
      for i = 0; i < 6; i = i + 1 {
        match document.content[i] {
          @pumd.StructuralElement::Paragraph(paragraph) => {
            assert_eq(paragraph.style.named_style, expected_named_styles[i])
            assert_eq(paragraph.style.font_size_points, expected_sizes[i])
            assert_eq(paragraph.runs.length(), 1)
            assert_eq(
              paragraph.runs[0].style.font_size_points,
              expected_sizes[i],
            )
          }
          @pumd.StructuralElement::Table(_) => assert_true(false)
        }
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "public seam renders empty Markdown as an empty desired document" {
  match @pumd.render_markdown("") {
    Ok(document) => {
      assert_eq(document.content.length(), 0)
      assert_source_range(document.provenance, 0, 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "blank-line parser nodes are ignored without losing document provenance" {
  match @pumd.render_markdown("\n\n\n") {
    Ok(document) => {
      assert_eq(document.content.length(), 0)
      assert_source_range(document.provenance, 0, 3)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "repeated public rendering is deterministic" {
  let markdown = "# Stable\n\nText with **style** and [link](https://example.test)."
  match (@pumd.render_markdown(markdown), @pumd.render_markdown(markdown)) {
    (Ok(first), Ok(second)) => {
      assert_eq(first.to_snapshot(), second.to_snapshot())
      assert_true(first.semantic_eq(second))
    }
    _ => assert_true(false)
  }
}

///|
test "canonical rendering removes empty runs and merges adjacent native runs" {
  match @pumd.render_markdown("left\nright  \nafter") {
    Ok(document) => {
      assert_eq(document.content.length(), 1)
      match document.content[0] {
        @pumd.StructuralElement::Paragraph(paragraph) => {
          assert_eq(paragraph.runs.length(), 1)
          assert_eq(paragraph.runs[0].content, "left right\nafter")
          for run in paragraph.runs {
            assert_true(!run.content.is_empty())
          }
        }
        @pumd.StructuralElement::Table(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "document block and run provenance retain Unicode code-point ranges" {
  match @pumd.render_markdown("A🚀B") {
    Ok(document) => {
      assert_source_range(document.provenance, 0, 3)
      assert_eq(document.content.length(), 1)
      match document.content[0] {
        @pumd.StructuralElement::Paragraph(paragraph) => {
          assert_source_range(paragraph.provenance, 0, 3)
          assert_eq(paragraph.runs.length(), 1)
          assert_eq(paragraph.runs[0].content, "A🚀B")
          assert_source_range(paragraph.runs[0].provenance, 0, 3)
        }
        @pumd.StructuralElement::Table(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "semantic equality excludes profile metadata and all provenance" {
  match @pumd.render_markdown("same native content") {
    Ok(original) =>
      match original.content[0] {
        @pumd.StructuralElement::Paragraph(paragraph) => {
          let changed_runs = paragraph.runs.map(fn(run) {
            { ..run, provenance: Some({ start: 70, end: 99 }) }
          })
          let changed : @pumd.DesiredDocument = {
            ..original,
            render_metadata: {
              style_profile_id: "different.profile",
              style_profile_version: 999,
            },
            content: [
              @pumd.StructuralElement::Paragraph({
                ..paragraph,
                runs: changed_runs,
                provenance: Some({ start: 50, end: 100 }),
              }),
            ],
            provenance: Some({ start: 40, end: 101 }),
          }
          assert_true(original.semantic_eq(changed))
          assert_true(changed.semantic_eq(original))
        }
        @pumd.StructuralElement::Table(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
