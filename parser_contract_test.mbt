///|
test "parser syntax variants render as a stable canonical contract" {
  let markdown =
    #|# ATX heading
    #|
    #|Setext heading
    #|--------------
    #|
    #|- dash bullet
    #|* star bullet
    #|+ plus bullet
    #|
    #|7. dot ordered
    #|
    #|8) paren ordered
    #|
    #|```text
    #|backtick fence
    #|```
    #|
    #|~~~text
    #|tilde fence
    #|~~~
    #|
    #|[direct](https://direct.example "Direct title")
    #|
    #|[reference][ref]
    #|
    #|<https://autolink.example>
    #|
    #|[ref]: https://reference.example "Reference title"
    #|
    #|| Left | Center | Right | Escaped |
    #|| :--- | :---: | ---: | --- |
    #|| left | center | right | A\|B |
  let document = render_or_fail(markdown)
  inspect(
    document.to_snapshot(),
    content=(
      #|profile pumd.default@4
      #|paragraph heading-1 font=Arial size=24 line=1.15 before=20 after=8
      #|  text "ATX heading" font=Arial size=24
      #|paragraph heading-2 font=Arial size=18 line=1.15 before=18 after=6
      #|  text "Setext heading" font=Arial size=18
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
      #|  text "dash bullet" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
      #|  text "star bullet" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=bullet level=0
      #|  text "plus bullet" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(7.) level=0
      #|  text "dot ordered" font=Arial size=11
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6 list=numbered(8)) level=0
      #|  text "paren ordered" font=Arial size=11
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "backtick fence" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "tilde fence" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
      #|  text "direct" underline font=Arial size=11 color=#1155CC link="https://direct.example" title="Direct title"
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
      #|  text "reference" underline font=Arial size=11 color=#1155CC link="https://reference.example" title="Reference title"
      #|paragraph normal font=Arial size=11 line=1.15 before=0 after=6
      #|  text "https://autolink.example" underline font=Arial size=11 color=#1155CC link="https://autolink.example"
      #|table
      #|  header-row
      #|    cell alignment=left background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Left" bold font=Arial size=11
      #|    cell alignment=center background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Center" bold font=Arial size=11
      #|    cell alignment=right background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Right" bold font=Arial size=11
      #|    cell alignment=unspecified background=#F1F3F4
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "Escaped" bold font=Arial size=11
      #|  row
      #|    cell alignment=left
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "left" font=Arial size=11
      #|    cell alignment=center
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "center" font=Arial size=11
      #|    cell alignment=right
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "right" font=Arial size=11
      #|    cell alignment=unspecified
      #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
      #|        text "A|B" font=Arial size=11
      #|

    ),
  )
}
