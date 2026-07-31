///|
test "public golden covers every version-one Style Profile role" {
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
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@1
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
    Err(_) => assert_true(false)
  }
}

///|
test "render metadata retains the built-in profile outside native semantic equality" {
  match @pumd.render_markdown("profile contract") {
    Ok(original) => {
      assert_eq(original.render_metadata.style_profile_id, "pumd.default")
      assert_eq(original.render_metadata.style_profile_version, 1)
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
    Err(_) => assert_true(false)
  }
}
