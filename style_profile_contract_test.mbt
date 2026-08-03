///|
test "public golden covers every version-two Style Profile role" {
  let markdown =
    #|# Heading one
    #|## Heading two
    #|### Heading three
    #|#### Heading four
    #|##### Heading five
    #|###### Heading six
    #|
    #|Body [link](https://example.test) and `inline`.
    #|
    #|- bullet
    #|
    #|3. ordered
    #|
    #|```text
    #|block code
    #|```
    #|
    #|| Header |
    #|| --- |
    #|| Cell |
  let document = render_or_fail(markdown)
  inspect(
    document.to_snapshot(),
    content=(
      #|profile pumd.default@2
      #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8
      #|  text "Heading one" font=Arial size=24
      #|paragraph heading-2 font=Arial size=18 line=1.15 before=18 after=6
      #|  text "Heading two" font=Arial size=18
      #|paragraph heading-3 font=Arial size=14 line=1.15 before=16 after=4
      #|  text "Heading three" font=Arial size=14
      #|paragraph heading-4 font=Arial size=12 line=1.15 before=14 after=4
      #|  text "Heading four" font=Arial size=12
      #|paragraph heading-5 font=Arial size=11 line=1.15 before=12 after=3
      #|  text "Heading five" font=Arial size=11
      #|paragraph heading-6 font=Arial size=10 line=1.15 before=10 after=3
      #|  text "Heading six" font=Arial size=10
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
      #|  text "Body " font=Arial size=11
      #|  text "link" underline font=Arial size=11 color=#1155CC link="https://example.test"
      #|  text " and " font=Arial size=11
      #|  text "inline" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "." font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
      #|  text "bullet" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(3.) level=0
      #|  text "ordered" font=Arial size=11
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "block code" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|table
      #|  header-row
      #|    cell alignment=unspecified background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Header" bold font=Arial size=11
      #|  row
      #|    cell alignment=unspecified
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Cell" font=Arial size=11
      #|
    ),
  )
}

///|
test "render metadata retains the built-in profile outside native semantic equality" {
  let original = render_or_fail("profile contract")
  assert_eq(original.render_metadata.style_profile_id, "pumd.default")
  assert_eq(original.render_metadata.style_profile_version, 2)
  let changed : @pumd.DesiredDocument = {
    ..original,
    render_metadata: {
      style_profile_id: "other.profile",
      style_profile_version: 2,
    },
    provenance: Some({ start: 20, end: 36 }),
  }
  assert_true(original.semantic_eq(changed))
  assert_true(original.to_snapshot() != changed.to_snapshot())
}

///|
test "public Style Profile supplies version-two quote decorations" {
  let profile = builtin_style_profile()
  assert_eq(profile.version, 2)
  assert_eq(profile.quote_indent_per_level_points, 18)
  assert_eq(profile.quote_border.color, "#B7B7B7")
  assert_eq(profile.quote_border.width_points, 1)
  assert_eq(profile.quote_border.padding_points, 6)
}
