///|
test "renders fenced code as editable paragraphs preserving blank lines and Unicode" {
  let markdown =
    #|```moonbit
    #|let x = 1
    #|
    #|打印("🚀")
    #|```
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@1
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|  text "let x = 1" font=Roboto Mono size=10 background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|  text "打印(\"🚀\")" font=Roboto Mono size=10 background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}
