test "renders a mixed Unicode heading through the public seam" {
  match @pumd.render_markdown("# Hello *世界* 🚀") {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@1
          #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8
          #|  text "Hello " font=Arial size=24
          #|  text "世界" italic font=Arial size=24
          #|  text " 🚀" font=Arial size=24
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

test "composes linked emphasis and inline code in a heading" {
  match
    @pumd.render_markdown("# Build `code` and [*linked*](https://example.test)") {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@1
          #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8
          #|  text "Build " font=Arial size=24
          #|  text "code" font=Roboto Mono size=10 background=#F1F3F4
          #|  text " and " font=Arial size=24
          #|  text "linked" italic underline font=Arial size=24 color=#1155CC link="https://example.test"
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}
