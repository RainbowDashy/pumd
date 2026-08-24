///|
test "public golden covers every version-four Style Profile role" {
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
      #|profile pumd.default@4
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
      #|  text "inline" font=Roboto Mono size=11 background=#F1F3F4
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
  assert_eq(original.render_metadata.style_profile_version, 4)
  let changed : @pumd.DesiredDocument = {
    ..original,
    render_metadata: {
      style_profile_id: "other.profile",
      style_profile_version: 3,
    },
    provenance: Some({ start: 20, end: 36 }),
  }
  assert_true(original.semantic_eq(changed))
  assert_true(original.to_snapshot() != changed.to_snapshot())
}

///|
test "public Style Profile supplies version-four quote decorations" {
  let profile = builtin_style_profile()
  assert_eq(profile.version, 4)
  assert_eq(profile.quote_indent_per_level_points, 18)
  assert_eq(profile.quote_border.color, "#B7B7B7")
  assert_eq(profile.quote_border.width_points, 1)
  assert_eq(profile.quote_border.padding_points, 6)
}

///|
/// The conversion is deliberately independent from the palette declaration.
fn srgb_channel_luminance(channel : Int) -> Double {
  let normalized = Double::from_int(channel) / 255.0
  if normalized <= 0.04045 {
    normalized / 12.92
  } else {
    @math.pow((normalized + 0.055) / 1.055, 2.4)
  }
}

///|
fn hex_channel(color : String, start : Int) -> Int {
  @string.parse_int(color[start:start + 2].to_owned(), base=16) catch {
    _ => abort("expected a #RRGGBB color")
  }
}

///|
fn relative_luminance(color : String) -> Double {
  let red = srgb_channel_luminance(hex_channel(color, 1))
  let green = srgb_channel_luminance(hex_channel(color, 3))
  let blue = srgb_channel_luminance(hex_channel(color, 5))
  0.2126 * red + 0.7152 * green + 0.0722 * blue
}

///|
fn contrast_ratio(foreground : String, background : String) -> Double {
  let first = relative_luminance(foreground)
  let second = relative_luminance(background)
  if first > second {
    (first + 0.05) / (second + 0.05)
  } else {
    (second + 0.05) / (first + 0.05)
  }
}

///|
test "public Style Profile supplies a contrast-safe syntax foreground palette" {
  let profile = builtin_style_profile()
  let palette = profile.syntax_palette
  assert_eq(palette.comment, "#5F6368")
  assert_eq(palette.keyword, "#6A1B9A")
  assert_eq(palette.string, "#08783F")
  assert_eq(palette.literal, "#9B5200")
  assert_eq(palette.type_tag, "#0057B8")
  assert_eq(palette.function, "#0B57D0")
  assert_eq(palette.property_attribute, "#7A3E00")

  let foregrounds = [
    palette.comment,
    palette.keyword,
    palette.string,
    palette.literal,
    palette.type_tag,
    palette.function,
    palette.property_attribute,
  ]
  for foreground in foregrounds {
    assert_true(contrast_ratio(foreground, "#F1F3F4") >= 4.5)
  }
}
