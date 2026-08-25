///|
fn decoded_remote_document(body : String) -> RemoteDocument {
  match decode_remote_document(body, "expected-document") {
    Ok(document) => document
    Err(error) => abort(error.user_message())
  }
}

///|
async test "remote decoder normalizes text runs and paragraph styles" {
  let document = decoded_remote_document(
    (
    #|{
    #|  "documentId":"doc-1", "title":"Read model", "revisionId":"rev-1",
    #|  "body":{"content":[{
    #|    "startIndex":1,"endIndex":6,
    #|    "paragraph":{"paragraphStyle":{
    #|      "namedStyleType":"HEADING_3","lineSpacing":125,
    #|      "spaceAbove":{"magnitude":4},"spaceBelow":{"magnitude":6},
    #|      "indentStart":{"magnitude":12},"indentFirstLine":{"magnitude":3},
    #|      "shading":{"backgroundColor":{"color":{"rgbColor":{"red":1,"green":0.5,"blue":0}}}},
    #|      "borderLeft":{"color":{"color":{"rgbColor":{"red":0,"green":0,"blue":1}}},"width":{"magnitude":2},"padding":{"magnitude":5}}
    #|    },"elements":[{
    #|      "startIndex":1,"endIndex":6,"textRun":{"content":"hello","textStyle":{
    #|        "bold":true,"italic":true,"underline":true,
    #|        "weightedFontFamily":{"fontFamily":"Inter"},"fontSize":{"magnitude":11},
    #|        "foregroundColor":{"color":{"rgbColor":{"red":0,"green":0.5,"blue":1}}},
    #|        "backgroundColor":{"color":{"rgbColor":{"red":1,"green":1,"blue":0}}},
    #|        "link":{"url":"https://example.test"}
    #|      }}}]
    #|    }
    #|  }]}
    #|}
    )
  )
  inspect(document.document_id, content="doc-1")
  assert_eq(document.title, Some("Read model"))
  inspect(remote_revision_id(document), content="rev-1")
  match document.tabs[0].content.units[0] {
    Paragraph(paragraph) => {
      assert_eq(paragraph.start_index, 1)
      assert_eq(paragraph.end_index, 6)
      assert_eq(paragraph.runs.length(), 1)
      let run = paragraph.runs[0]
      inspect(run.text, content="hello")
      assert_eq(run.start_index, 1)
      assert_eq(run.end_index, 6)
      assert_eq(run.style.bold, true)
      assert_eq(run.style.italic, true)
      assert_eq(run.style.underline, true)
      inspect(run.style.font_family, content="Inter")
      assert_eq(run.style.font_size_points, 11)
      assert_eq(run.style.foreground_color, Some("#0080ff"))
      assert_eq(run.style.background_color, Some("#ffff00"))
      assert_eq(run.link, Some("https://example.test"))
      assert_eq(paragraph.style.named_style, @pumd.NamedStyle::Heading3)
      assert_eq(paragraph.style.font_family, "Inter")
      assert_eq(paragraph.style.font_size_points, 11)
      assert_eq(paragraph.style.line_spacing_percent, 125)
      assert_eq(paragraph.style.space_above_points, 4)
      assert_eq(paragraph.style.space_below_points, 6)
      assert_eq(paragraph.style.indent_start_points, Some(12))
      assert_eq(paragraph.style.indent_first_line_points, Some(3))
      assert_eq(paragraph.style.background_color, Some("#ff8000"))
      assert_eq(paragraph.style.border_left, Some({ color: "#0000ff", width_points: 2, padding_points: 5 }))
      assert_eq(paragraph.normalization_warning, false)
    }
    _ => fail("expected paragraph")
  }
}

///|
async test "remote decoder preserves colored run boundaries and canonical hex" {
  let document = decoded_remote_document(
    (
    #|{
    #| "documentId":"doc","revisionId":"rev","body":{"content":[{
    #| "startIndex":1,"endIndex":8,"paragraph":{"elements":[
    #| {"startIndex":1,"endIndex":3,"textRun":{"content":"A界","textStyle":{"foregroundColor":{"color":{"rgbColor":{"red":1,"green":0,"blue":0}}}}}},
    #| {"startIndex":3,"endIndex":5,"textRun":{"content":"é","textStyle":{"foregroundColor":{"color":{"rgbColor":{"red":0,"green":1,"blue":0}}}}}},
    #| {"startIndex":5,"endIndex":7,"textRun":{"content":"🚀","textStyle":{"foregroundColor":{"color":{"rgbColor":{"red":0,"green":0,"blue":1}}}}}}
    #| ]}}
    #| ]}}
    )
  )
  match document.tabs[0].content.units[0] {
    Paragraph(paragraph) => {
      assert_eq(paragraph.runs.length(), 3)
      inspect(paragraph.runs[0].text, content="A界")
      assert_eq(paragraph.runs[0].start_index, 1)
      assert_eq(paragraph.runs[0].end_index, 3)
      assert_eq(paragraph.runs[0].style.foreground_color, Some("#ff0000"))
      inspect(paragraph.runs[1].text, content="é")
      assert_eq(paragraph.runs[1].start_index, 3)
      assert_eq(paragraph.runs[1].end_index, 5)
      assert_eq(paragraph.runs[1].style.foreground_color, Some("#00ff00"))
      inspect(paragraph.runs[2].text, content="🚀")
      assert_eq(paragraph.runs[2].start_index, 5)
      assert_eq(paragraph.runs[2].end_index, 7)
      assert_eq(paragraph.runs[2].style.foreground_color, Some("#0000ff"))
    }
    _ => fail("expected paragraph")
  }
}

///|
async test "remote decoder maps Title and all heading styles and bullets" {
  let document = decoded_remote_document(
    (
    #|{
    #| "documentId":"doc","revisionId":"rev","body":{"content":[
    #| {"startIndex":1,"endIndex":2,"paragraph":{"paragraphStyle":{"namedStyleType":"TITLE"},"elements":[]}},
    #| {"startIndex":2,"endIndex":3,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_1"},"bullet":{"nestingLevel":2,"glyphs":[{"glyph":"1."}]},"elements":[]}},
    #| {"startIndex":3,"endIndex":4,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_2"},"bullet":{"nestingLevel":1,"glyphs":[{"glyph":"•"}]},"elements":[]}},
    #| {"startIndex":4,"endIndex":5,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_3"},"elements":[]}},
    #| {"startIndex":5,"endIndex":6,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_4"},"elements":[]}},
    #| {"startIndex":6,"endIndex":7,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_5"},"elements":[]}},
    #| {"startIndex":7,"endIndex":8,"paragraph":{"paragraphStyle":{"namedStyleType":"HEADING_6"},"elements":[]}}
    #| ]}
    #|}
    )
  )
  let headings = [
    @pumd.NamedStyle::Title,
    @pumd.NamedStyle::Heading1, @pumd.NamedStyle::Heading2,
    @pumd.NamedStyle::Heading3, @pumd.NamedStyle::Heading4,
    @pumd.NamedStyle::Heading5, @pumd.NamedStyle::Heading6,
  ]
  for index in 0..<headings.length() {
    match document.tabs[0].content.units[index] {
      Paragraph(paragraph) => assert_eq(paragraph.style.named_style, headings[index])
      _ => fail("expected heading paragraph")
    }
  }
  match document.tabs[0].content.units[1] {
    Paragraph({ bullet: Some(bullet), .. }) => {
      assert_eq(bullet.nesting_level, 2)
      assert_eq(bullet.numeric, true)
      inspect(bullet.glyph, content="1.")
    }
    _ => fail("expected numeric bullet")
  }
  match document.tabs[0].content.units[2] {
    Paragraph({ bullet: Some(bullet), .. }) => assert_eq(bullet.numeric, false)
    _ => fail("expected disc bullet")
  }
}

///|
async test "remote decoder retains tables cells and their indexes" {
  let document = decoded_remote_document(
    (
    #|{
    #| "documentId":"doc","revisionId":"rev","body":{"content":[{
    #| "startIndex":1,"endIndex":21,"table":{"tableRows":[
    #| {"tableCells":[
    #| {"startIndex":2,"endIndex":6,"tableCellStyle":{"alignment":"CENTER","backgroundColor":{"color":{"rgbColor":{"red":1,"green":0,"blue":0}}}},"content":[{"startIndex":2,"endIndex":5,"paragraph":{"elements":[{"startIndex":2,"endIndex":5,"textRun":{"content":"a","textStyle":{"bold":true}}}]}}]},
    #| {"startIndex":6,"endIndex":10,"content":[{"startIndex":6,"endIndex":9,"paragraph":{"elements":[{"startIndex":6,"endIndex":9,"textRun":{"content":"b","textStyle":{"italic":true}}}]}}]}
    #| ]},
    #| {"tableCells":[
    #| {"startIndex":10,"endIndex":14,"content":[{"startIndex":10,"endIndex":13,"paragraph":{"elements":[{"startIndex":10,"endIndex":13,"textRun":{"content":"c","textStyle":{}}}]}}]},
    #| {"startIndex":14,"endIndex":18,"content":[{"startIndex":14,"endIndex":17,"paragraph":{"elements":[{"startIndex":14,"endIndex":17,"textRun":{"content":"d","textStyle":{}}}]}},{"startIndex":17,"endIndex":18,"table":{"tableRows":[]}}]}
    #| ]}
    #| ]}}
    #| ]}
    #|}
    )
  )
  match document.tabs[0].content.units[0] {
    Table(table) => {
      assert_eq(table.start_index, 1)
      assert_eq(table.end_index, 21)
      assert_eq(table.rows.length(), 2)
      assert_eq(table.rows[0].cells.length(), 2)
      assert_eq(table.rows[1].cells.length(), 2)
      assert_eq(table.rows[0].cells[0].start_index, 2)
      assert_eq(table.rows[1].cells[1].end_index, 18)
      inspect(table.rows[0].cells[0].paragraphs[0].runs[0].text, content="a")
      assert_eq(table.rows[0].cells[0].paragraphs[0].runs[0].style.bold, true)
      assert_eq(table.rows[0].cells[0].alignment, @pumd.TableAlignment::Center)
      assert_eq(table.rows[0].cells[0].background_color, Some("#ff0000"))
      assert_eq(table.rows[0].cells[1].alignment, @pumd.TableAlignment::Unspecified)
      assert_eq(table.rows[0].cells[1].background_color, None)
      assert_eq(table.rows[0].cells[1].paragraphs[0].runs[0].style.italic, true)
      assert_eq(table.rows[1].cells[1].opaque_units.length(), 1)
      inspect(table.rows[1].cells[1].opaque_units[0].kind, content="table")
      assert_eq(table.normalization_warning, true)
    }
    _ => fail("expected table")
  }
}

///|
async test "remote decoder keeps inline suggestions and UTF-16 indexes" {
  let document = decoded_remote_document(
    (
    #|{
    #| "documentId":"doc","revisionId":"rev","body":{"content":[{
    #| "startIndex":1,"endIndex":10,"paragraph":{"elements":[
    #| {"startIndex":1,"endIndex":3,"textRun":{"content":"😀","textStyle":{},"suggestedInsertionIds":["insert-a","insert-b"]}},
    #| {"startIndex":3,"endIndex":7,"textRun":{"content":"kept","textStyle":{},"suggestedDeletionIds":["delete-a"]}},
    #| {"startIndex":7,"endIndex":9,"textRun":{"content":"ok","textStyle":{},"suggestedTextRunStyles":[{"suggestionId":"style-a","textStyle":{}}],"suggestedTextStyleChanges":{"style-b":{"textStyle":{"bold":true},"textStyleSuggestionState":{}}}}}
    #| ]}}
    #| ]}
    #|}
    )
  )
  match document.tabs[0].content.units[0] {
    Paragraph(paragraph) => {
      assert_eq(paragraph.runs.length(), 2)
      assert_eq(paragraph.runs[0].start_index, 3)
      assert_eq(paragraph.runs[0].end_index, 7)
      assert_eq(paragraph.suggestions.length(), 5)
      match paragraph.suggestions[0] {
        InsertedText(start_index~, end_index~, text~, suggestion_id~) => {
          assert_eq(start_index, 1)
          assert_eq(end_index, 3)
          inspect(text, content="😀")
          inspect(suggestion_id, content="insert-a")
        }
        _ => fail("expected insertion")
      }
      match paragraph.suggestions[2] {
        DeletedText(suggestion_id~, ..) => inspect(suggestion_id, content="delete-a")
        _ => fail("expected deletion")
      }
      match paragraph.suggestions[3] {
        StyleChange(start_index~, end_index~, suggestion_id~) => {
          assert_eq(start_index, 7)
          assert_eq(end_index, 9)
          inspect(suggestion_id, content="style-a")
        }
        _ => fail("expected style suggestion")
      }
      match paragraph.suggestions[4] {
        StyleChange(start_index~, end_index~, suggestion_id~) => {
          assert_eq(start_index, 7)
          assert_eq(end_index, 9)
          inspect(suggestion_id, content="style-b")
        }
        _ => fail("expected map style suggestion")
      }
    }
    _ => fail("expected paragraph")
  }
}

///|
async test "remote decoder preserves opaque content tabs warnings and legacy bodies" {
  let document = decoded_remote_document(
    (
    #|{
    #| "documentId":"doc","revisionId":"rev","tabs":[
    #| {"tabProperties":{"tabId":"one"},"documentTab":{"body":{"content":[
    #| {"startIndex":0,"endIndex":1,"sectionBreak":{}},
    #| {"startIndex":1,"endIndex":2,"pageBreak":{}},
    #| {"startIndex":2,"endIndex":3,"horizontalRule":{}},
    #| {"startIndex":3,"endIndex":4,"sectionBreak":{}},
    #| {"startIndex":4,"endIndex":5,"inlineObjectElement":{"inlineObjectProperties":{"embeddedObject":{"title":"chart","description":"ignored"}}}},
    #| {"startIndex":5,"endIndex":6,"paragraph":{"paragraphStyle":{"namedStyleType":"UNSUPPORTED"},"bullet":{"glyphs":[]},"elements":[{"startIndex":5,"endIndex":6,"inlineObjectElement":{"inlineObjectProperties":{"embeddedObject":{"title":"diagram","description":"ignored"}}}}]}}
    #| ]}}},
    #| {"tabProperties":{"tabId":"two"},"documentTab":{"body":{"content":[]}}}
    #| ]
    #|}
    )
  )
  assert_eq(document.tabs.length(), 2)
  assert_true(remote_tab_content(document, "one") is Some(_))
  assert_eq(remote_tab_content(document, "missing"), None)
  match document.tabs[0].content.units[0] {
    Opaque(item) => inspect(item.kind, content="pageBreak")
    _ => fail("expected opaque page break")
  }
  match document.tabs[0].content.units[1] {
    Opaque(item) => inspect(item.kind, content="horizontalRule")
    _ => fail("expected opaque horizontal rule")
  }
  match document.tabs[0].content.units[2] {
    Opaque(unit) => inspect(unit.kind, content="sectionBreak")
    _ => fail("expected non-leading section break to stay opaque")
  }
  match document.tabs[0].content.units[3] {
    Opaque(item) => {
      inspect(item.kind, content="inlineObjectElement")
      assert_eq(item.description, Some("chart"))
    }
    _ => fail("expected opaque inline object")
  }
  match document.tabs[0].content.units[4] {
    Paragraph(paragraph) => {
      assert_eq(paragraph.normalization_warning, true)
      assert_eq(paragraph.bullet, Some({ nesting_level: 0, numeric: false, glyph: "" }))
    }
    _ => fail("expected warned paragraph")
  }
  let legacy = decoded_remote_document(
    (
    #|{"documentId":"legacy","revisionId":"r","body":{"content":[]}}
    )
  )
  assert_eq(legacy.tabs.length(), 1)
  inspect(legacy.tabs[0].tab_id, content="")
}

async test "remote decoder restores native inline images inside paragraphs" {
  let document = decoded_remote_document((#|{
#| "documentId":"doc","revisionId":"rev","tabs":[{
#|  "tabProperties":{"tabId":"tab"},"documentTab":{
#|   "inlineObjects":{"image-1":{"inlineObjectProperties":{"embeddedObject":{"imageProperties":{"sourceUri":"https://example.test/diagram.png"}}}}},
#|   "body":{"content":[{"startIndex":1,"endIndex":10,"paragraph":{
#|    "paragraphStyle":{"namedStyleType":"NORMAL_TEXT"},"elements":[
#|     {"startIndex":1,"endIndex":8,"textRun":{"content":"Before ","textStyle":{}}},
#|     {"startIndex":8,"endIndex":9,"inlineObjectElement":{"inlineObjectId":"image-1"}},
#|     {"startIndex":9,"endIndex":10,"textRun":{"content":"\n","textStyle":{}}}
#|    ]}}]}
#|  }
#| }]}
))
  match document.tabs[0].content.units[0] { Paragraph(paragraph) => { assert_eq(paragraph.inline_images.length(), 1); assert_eq(paragraph.inline_images[0].source_url, "https://example.test/diagram.png"); assert_eq(paragraph.inline_images[0].text_offset, 7); assert_eq(paragraph.normalization_warning, false) }; _ => fail("expected paragraph") }
}

///|
async test "remote decoder makes structural root failures explicit" {
  match decode_remote_document("not-json", "expected") {
    Err(MalformedJson(_)) => ()
    _ => fail("invalid JSON must fail")
  }
  match decode_remote_document("{\"revisionId\":\"r\"}", "expected") {
    Err(InvalidDocument(_)) => ()
    _ => fail("document ID is required")
  }
  match decode_remote_document("{\"documentId\":\"doc\"}", "expected") {
    Err(MissingRevision(_)) => ()
    _ => fail("revision ID is required")
  }
  match decode_remote_document("{\"documentId\":\"doc\",\"revisionId\":\"r\",\"tabs\":[{\"tabProperties\":{},\"documentTab\":{\"body\":{\"content\":[]}}}]}", "expected") {
    Err(InvalidDocument(_)) => ()
    _ => fail("tab ID is required")
  }
}
