///|
test "renders aligned native tables with rich header and cell content" {
  let markdown =
    #|| Name | Value | Empty |
    #|| :--- | :---: | ---: |
    #|| **A\|B** | [link](https://example.test) and `x` | |
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@4
          #|table
          #|  header-row
          #|    cell alignment=left background=#F1F3F4
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|        text "Name" bold font=Arial size=11
          #|    cell alignment=center background=#F1F3F4
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|        text "Value" bold font=Arial size=11
          #|    cell alignment=right background=#F1F3F4
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|        text "Empty" bold font=Arial size=11
          #|  row
          #|    cell alignment=left
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|        text "A|B" bold font=Arial size=11
          #|    cell alignment=center
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|        text "link" underline font=Arial size=11 color=#1155CC link="https://example.test"
          #|        text " and " font=Arial size=11
          #|        text "x" font=Roboto Mono size=11 background=#F1F3F4
          #|    cell alignment=right
          #|      paragraph normal font=Arial size=11 line=1.15 before=0 after=0
          #|

        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
test "retains table and cell ranges without inventing row provenance" {
  let markdown =
    #|| A | B |
    #|| - | - |
    #|| C | D |
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      match document.content[0] {
        @pumd.StructuralElement::Table(table) => {
          assert_true(table.provenance is Some(_))
          assert_eq(table.rows.length(), 2)
          for row in table.rows {
            assert_true(row.provenance is None)
            for cell in row.cells {
              assert_true(cell.provenance is Some(_))
              assert_true(cell.content[0].provenance is Some(_))
            }
          }
        }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
