///|
test "renders a quoted paragraph through the public seam" {
  match @pumd.render_markdown("> Quoted *text*.") {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@2
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=18 indent-first-line=18 border-left=#B7B7B7 width=1 padding=6
          #|  text "Quoted " font=Arial size=11
          #|  text "text" italic font=Arial size=11
          #|  text "." font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "composes nested quote depth with heading and fenced-code styles" {
  let markdown =
    #|> # Quoted heading
    #|>
    #|> > nested `code`
    #|>
    #|> ```text
    #|> code line
    #|> ```
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@2
          #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8 indent-start=18 indent-first-line=18 border-left=#B7B7B7 width=1 padding=6
          #|  text "Quoted heading" font=Arial size=24
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=36 indent-first-line=36 border-left=#B7B7B7 width=1 padding=6
          #|  text "nested " font=Arial size=11
          #|  text "code" font=Roboto Mono size=10 background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4 indent-start=18 indent-first-line=18 border-left=#B7B7B7 width=1 padding=6
          #|  text "code line" font=Roboto Mono size=10 background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4 indent-start=18 indent-first-line=18 border-left=#B7B7B7 width=1 padding=6
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "keeps quoted list continuations non-bulleted and nested lists native" {
  let markdown =
    #|- item
    #|  > quoted continuation
    #|  >
    #|  > > deeper continuation
    #|  >
    #|  > - nested item
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@2
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
          #|  text "item" font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=54 indent-first-line=54 border-left=#B7B7B7 width=1 padding=6
          #|  text "quoted continuation" font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=72 indent-first-line=72 border-left=#B7B7B7 width=1 padding=6
          #|  text "deeper continuation" font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=90 indent-first-line=72 border-left=#B7B7B7 width=1 padding=6 list=bullet level=1
          #|  text "nested item" font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "keeps the native bullet when a quote is the list item's only content" {
  match @pumd.render_markdown("- > quote") {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@2
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=54 indent-first-line=36 border-left=#B7B7B7 width=1 padding=6 list=bullet level=0
          #|  text "quote" font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "uses deterministic quote offsets for level-zero and nested quoted lists" {
  let markdown =
    #|> - top item
    #|>   - nested item
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@2
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=54 indent-first-line=36 border-left=#B7B7B7 width=1 padding=6 list=bullet level=0
          #|  text "top item" font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 indent-start=90 indent-first-line=72 border-left=#B7B7B7 width=1 padding=6 list=bullet level=1
          #|  text "nested item" font=Arial size=11
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "rejects every table in a blockquote with its actionable diagnostic" {
  let markdown =
    #|> | Header |
    #|> | --- |
    #|> | Cell |
  match @pumd.render_markdown(markdown) {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].kind, @pumd.DiagnosticKind::UnsupportedConstruct)
      assert_eq(diagnostics[0].node_kind, "table-in-blockquote")
      assert_eq(
        diagnostics[0].message,
        "Move the table outside the blockquote or replace it with paragraphs.",
      )
    }
  }
}

///|
test "keeps unsupported descendants actionable without a blockquote diagnostic" {
  match @pumd.render_markdown("> ~~removed~~") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].node_kind, "strikethrough")
      assert_eq(
        diagnostics[0].message,
        "Remove the strikethrough markers or use plain text.",
      )
    }
  }
}
