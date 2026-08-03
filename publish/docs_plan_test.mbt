///|
test "compiles a body paragraph into insert then paragraph formatting" {
  match @pumd.render_markdown("Hello") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "Hello\n"
          #|paragraph-style 1..7 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 1..6 font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "compiles a native list after its paragraph structure" {
  match @pumd.render_markdown("- first\n- second") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "first\n"
          #|paragraph-style 1..7 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 1..6 font=Arial size=11
          #|paragraph-bullets 1..7 bullet level=0
          #|insert-text 7 "second\n"
          #|paragraph-style 7..14 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 7..13 font=Arial size=11
          #|paragraph-bullets 7..14 bullet level=0
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "reapplies quoted-list geometry after native bullet creation" {
  match @pumd.render_markdown("> - quoted") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "quoted\n"
          #|paragraph-style 1..8 normal font=Arial size=11 line=115 before=0 after=6 indent-start=54 indent-first-line=36 border-left=#B7B7B7 width=1 padding=6
          #|text-style 1..7 font=Arial size=11
          #|paragraph-bullets 1..8 bullet level=0
          #|paragraph-decoration 1..8 normal font=Arial size=11 line=115 before=0 after=6 indent-start=54 indent-first-line=36 border-left=#B7B7B7 width=1 padding=6
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "retains ordered-list starts and nested bullet levels" {
  match @pumd.render_markdown("3. third\n\n- outer\n  - nested\n\nafter") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "third\n"
          #|paragraph-style 1..7 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 1..6 font=Arial size=11
          #|paragraph-bullets 1..7 numbered(3.) level=0
          #|insert-text 7 "outer\n"
          #|paragraph-style 7..13 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 7..12 font=Arial size=11
          #|paragraph-bullets 7..13 bullet level=0
          #|insert-text 13 "\tnested\n"
          #|paragraph-style 13..21 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 14..20 font=Arial size=11
          #|paragraph-bullets 13..21 bullet level=1
          #|insert-text 20 "after\n"
          #|paragraph-style 20..26 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 20..25 font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "compiles native tables in row and cell order" {
  let markdown =
    #|| Head |
    #|| ---: |
    #|| [cell](https://example.test) |
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-table 1 rows=2 columns=1
          #|insert-cell-text table=1 row=0 column=0 "Head"
          #|cell-paragraph-style table=1 row=0 column=0 0..5 normal font=Arial size=11 line=115 before=0 after=0
          #|cell-text-style table=1 row=0 column=0 0..4 bold font=Arial size=11
          #|cell-style table=1 row=0 column=0 alignment=right background=#F1F3F4
          #|insert-cell-text table=1 row=1 column=0 "cell"
          #|cell-paragraph-style table=1 row=1 column=0 0..5 normal font=Arial size=11 line=115 before=0 after=0
          #|cell-text-style table=1 row=1 column=0 0..4 underline font=Arial size=11 color=#1155CC link="https://example.test"
          #|cell-style table=1 row=1 column=0 alignment=right
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "places a following paragraph after the complete native table" {
  let markdown =
    #|| Head |
    #|| --- |
    #|| Cell |
    #|
    #|after
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-table 1 rows=2 columns=1
          #|insert-cell-text table=1 row=0 column=0 "Head"
          #|cell-paragraph-style table=1 row=0 column=0 0..5 normal font=Arial size=11 line=115 before=0 after=0
          #|cell-text-style table=1 row=0 column=0 0..4 bold font=Arial size=11
          #|cell-style table=1 row=0 column=0 alignment=unspecified background=#F1F3F4
          #|insert-cell-text table=1 row=1 column=0 "Cell"
          #|cell-paragraph-style table=1 row=1 column=0 0..5 normal font=Arial size=11 line=115 before=0 after=0
          #|cell-text-style table=1 row=1 column=0 0..4 font=Arial size=11
          #|cell-style table=1 row=1 column=0 alignment=unspecified
          #|insert-text 18 "after\n"
          #|paragraph-style 18..24 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 18..23 font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "uses UTF-16 ranges for non-BMP linked text" {
  match
    @pumd.render_markdown("世界 [🚀](https://example.test \"rocket\")") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "世界 🚀\n"
          #|paragraph-style 1..7 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 1..4 font=Arial size=11
          #|text-style 4..6 underline font=Arial size=11 color=#1155CC link="https://example.test" title="rocket"
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "keeps combining marks at one UTF-16 unit each" {
  match @pumd.render_markdown("A é [🚀](https://example.test)") {
    Ok(document) =>
      inspect(
        compile_docs_update_plan(document).to_snapshot(),
        content=(
          #|insert-text 1 "A é 🚀\n"
          #|paragraph-style 1..9 normal font=Arial size=11 line=115 before=0 after=6
          #|text-style 1..6 font=Arial size=11
          #|text-style 6..8 underline font=Arial size=11 color=#1155CC link="https://example.test"
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "UTF-16 matrix covers every published text context" {
  let markdown =
    #|plain A界é🚀
    #|
    #|**formatted A界é🚀** and `inline A界é🚀`
    #|
    #|```text
    #|fenced A界é🚀
    #|```
    #|
    #|- list A界é🚀
    #|
    #|| Value |
    #|| --- |
    #|| cell A界é🚀 |
  let snapshot = match @pumd.render_markdown(markdown) {
    Ok(document) => compile_docs_update_plan(document).to_snapshot()
    Err(_) => abort("UTF-16 matrix fixture must render")
  }
  inspect(
    snapshot,
    content=(
      #|insert-text 1 "plain A界é🚀\n"
      #|paragraph-style 1..14 normal font=Arial size=11 line=115 before=0 after=6
      #|text-style 1..13 font=Arial size=11
      #|insert-text 14 "formatted A界é🚀 and inline A界é🚀\n"
      #|paragraph-style 14..49 normal font=Arial size=11 line=115 before=0 after=6
      #|text-style 14..30 bold font=Arial size=11
      #|text-style 30..35 font=Arial size=11
      #|text-style 35..48 font=Roboto Mono size=10 background=#F1F3F4
      #|insert-text 49 "fenced A界é🚀\n"
      #|paragraph-style 49..63 normal font=Roboto Mono size=10 line=100 before=0 after=0
      #|text-style 49..62 font=Roboto Mono size=10 background=#F1F3F4
      #|insert-text 63 "\n"
      #|paragraph-style 63..64 normal font=Roboto Mono size=10 line=100 before=0 after=0
      #|insert-text 64 "list A界é🚀\n"
      #|paragraph-style 64..76 normal font=Arial size=11 line=115 before=0 after=6
      #|text-style 64..75 font=Arial size=11
      #|paragraph-bullets 64..76 bullet level=0
      #|insert-table 76 rows=2 columns=1
      #|insert-cell-text table=76 row=0 column=0 "Value"
      #|cell-paragraph-style table=76 row=0 column=0 0..6 normal font=Arial size=11 line=115 before=0 after=0
      #|cell-text-style table=76 row=0 column=0 0..5 bold font=Arial size=11
      #|cell-style table=76 row=0 column=0 alignment=unspecified background=#F1F3F4
      #|insert-cell-text table=76 row=1 column=0 "cell A界é🚀"
      #|cell-paragraph-style table=76 row=1 column=0 0..12 normal font=Arial size=11 line=115 before=0 after=0
      #|cell-text-style table=76 row=1 column=0 0..11 font=Arial size=11
      #|cell-style table=76 row=1 column=0 alignment=unspecified
      #|
    ),
  )
}

///|
test "planning reports the index of an empty table after valid tables" {
  let document = match
    @pumd.render_markdown(
      (
        #|| Header |
        #|| --- |
        #|| Value |
      ),
    ) {
    Ok(document) => document
    Err(_) => abort("fixture must render")
  }
  document.content.push(
    @pumd.StructuralElement::Table({ rows: [], provenance: None }),
  )
  match prepare_docs_update_plan(document) {
    Err(EmptyTable(table_index=1)) => ()
    _ => assert_true(false)
  }
}

///|
test "planning rejects a table whose rows have no cells" {
  let document = @pumd.DesiredDocument::{
    metadata: { title: None, locale: None },
    render_metadata: {
      style_profile_id: "pumd.default",
      style_profile_version: 2,
    },
    content: [
      @pumd.StructuralElement::Table({
        rows: [{ cells: [], is_header: false, provenance: None }],
        provenance: None,
      }),
    ],
    provenance: None,
  }
  match prepare_docs_update_plan(document) {
    Err(TableWithoutColumns(table_index=0)) => ()
    _ => assert_true(false)
  }
}

///|
test "planning rejects ordered-list starts Google Docs cannot write" {
  let document = match @pumd.render_markdown("3. third") {
    Ok(document) => document
    Err(_) => abort("ordered-list fixture must render")
  }
  match prepare_docs_update_plan(document) {
    Err(UnsupportedOrderedListStart(start=3)) => ()
    _ => fail("non-default ordered-list start must fail before HTTP")
  }
}
