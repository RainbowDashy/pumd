///|
test "renders nested bullet and non-default ordered lists as native list paragraphs" {
  let markdown =
    #|- alpha **bold**
    #|  - nested `code`
    #|
    #|3. third
    #|4. fourth
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
          #|  text "alpha " font=Arial size=11
          #|  text "bold" bold font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=1
          #|  text "nested " font=Arial size=11
          #|  text "code" font=Roboto Mono size=11 background=#F1F3F4
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(3.) level=0
          #|  text "third" font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(3.) level=0
          #|  text "fourth" font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "rejects task list state without returning a partial document" {
  match @pumd.render_markdown("before\n\n- [x] done") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].kind, @pumd.DiagnosticKind::UnsupportedConstruct)
      assert_eq(diagnostics[0].node_kind, "task-list-item")
    }
  }
}
