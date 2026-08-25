///|
test "renders body paragraphs with emphasis, strong text, and inline code" {
  let markdown = "Intro paragraph.\n\nStyled **strong** and *emphasis* with `code`."
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "Intro paragraph." font=Arial size=11
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "Styled " font=Arial size=11
          #|  text "strong" bold font=Arial size=11
          #|  text " and " font=Arial size=11
          #|  text "emphasis" italic font=Arial size=11
          #|  text " with " font=Arial size=11
          #|  text "code" font=Roboto Mono size=11 background=#F1F3F4
          #|  text "." font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "renders soft and hard breaks inside a paragraph" {
  match @pumd.render_markdown("soft\nbreak  \nhard") {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "soft break\nhard" font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "renders a direct link with its title and link styling" {
  match
    @pumd.render_markdown(
      "Read [the guide](https://example.com/guide \"Guide title\").",
    ) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "Read " font=Arial size=11
          #|  text "the guide" underline font=Arial size=11 color=#1155CC link="https://example.com/guide" title="Guide title"
          #|  text "." font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "resolves a reference link before rendering the paragraph" {
  let markdown =
    #|See [the guide][docs].
    #|
    #|[docs]: https://example.com/docs "Docs title"
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "See " font=Arial size=11
          #|  text "the guide" underline font=Arial size=11 color=#1155CC link="https://example.com/docs" title="Docs title"
          #|  text "." font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "renders web and email autolinks as link runs" {
  match
    @pumd.render_markdown(
      "Visit <https://example.com> or email <team@example.com>.",
    ) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@5
          #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
          #|  text "Visit " font=Arial size=11
          #|  text "https://example.com" underline font=Arial size=11 color=#1155CC link="https://example.com"
          #|  text " or email " font=Arial size=11
          #|  text "team@example.com" underline font=Arial size=11 color=#1155CC link="mailto:team@example.com"
          #|  text "." font=Arial size=11
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "returns a missing-definition diagnostic without a partial document" {
  match @pumd.render_markdown("[missing][unknown]") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].kind, @pumd.DiagnosticKind::MissingDefinition)
      assert_eq(diagnostics[0].node_kind, "reference-link")
      assert_eq(
        diagnostics[0].message,
        "Add a link definition for label: unknown.",
      )
    }
  }
}
