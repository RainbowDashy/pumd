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
      style_profile_version: 1,
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
