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
          #|profile pumd.default@3
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

///|
test "renders explicitly tagged JavaScript as colored editable text" {
  let markdown =
    #|```javascript
    #|const greeting = "hello"
    #|```
  match @pumd.render_markdown(markdown) {
    Ok(document) =>
      inspect(
        document.to_snapshot(),
        content=(
          #|profile pumd.default@3
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
          #|  text " greeting = " font=Roboto Mono size=10 background=#F1F3F4
          #|  text "\"hello\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
          #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
          #|
        ),
      )
    Err(_) => assert_true(false)
  }
}

///|
fn fenced_snapshot(info : String, code : String) -> String {
  let markdown = "```" + info + "\n" + code + "\n```\n"
  match @pumd.render_markdown(markdown) {
    Ok(document) => document.to_snapshot()
    Err(_) => "render error"
  }
}

///|
fn markdown_snapshot(markdown : String) -> String {
  match @pumd.render_markdown(markdown) {
    Ok(document) => document.to_snapshot()
    Err(_) => "render error"
  }
}

///|
fn has_noncanonical_code_runs(document : @pumd.DesiredDocument) -> Bool {
  for element in document.content {
    match element {
      @pumd.StructuralElement::Paragraph(paragraph) => {
        let mut previous : @pumd.TextRun? = None
        for run in paragraph.runs {
          if run.content.is_empty() {
            return true
          }
          match previous {
            Some(last) if last.style == run.style && last.link == run.link => return true
            _ => ()
          }
          previous = Some(run)
        }
      }
      _ => ()
    }
  }
  false
}

///|
test "renders a representative golden for every canonical fenced language" {
  let snapshots = StringBuilder::new()
  let fixtures = [
    ("javascript", "const greeting = \"hello\""),
    ("jsx", "const node = <span title=\"hi\">ok</span>"),
    ("typescript", "interface User { name: string }"),
    ("tsx", "const node = <span>{name}</span>"),
    ("shell", "echo \"hello\""),
    ("powershell", "$name = \"hello\""),
    ("json", "{\"name\": true}"),
    ("yaml", "name: value"),
    ("toml", "name = \"value\""),
    ("html", "<div class=\"box\">hello</div>"),
    ("css", ".box { color: red; }"),
    ("xml", "<item id=\"1\">hello</item>"),
    ("sql", "SELECT name FROM users"),
    ("markdown", "# hello"),
    ("http", "GET /health HTTP/1.1"),
    ("protobuf", "message User { string name = 1; }"),
  ]
  for fixture in fixtures {
    let (language, source) = fixture
    snapshots.write_string("--- ")
    snapshots.write_string(language)
    snapshots.write_string(" ---\n")
    snapshots.write_string(fenced_snapshot(language, source))
  }
  inspect(
    snapshots.to_string(),
    content=(
      #|--- javascript ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " greeting = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"hello\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- jsx ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " node = <" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "span" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "title" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text "=" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"hi\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text ">ok</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "span" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- typescript ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "interface" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "User" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text " { " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "name" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text ": " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "string" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text " }" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- tsx ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " node = <" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "span" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">{name}</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "span" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- shell ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "echo" font=Roboto Mono size=10 color=#0B57D0 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"hello\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- powershell ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "$name = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"hello\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- json ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "{" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"name\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text ": " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "true" font=Roboto Mono size=10 color=#9B5200 background=#F1F3F4
      #|  text "}" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- yaml ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "name" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text ": " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "value" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- toml ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "name = \"value\"" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- html ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "<" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "div" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "class" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text "=\"" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "box" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text "\">hello</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "div" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- css ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "." font=Roboto Mono size=10 background=#F1F3F4
      #|  text "box" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text " { " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "color" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text ": red; }" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- xml ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "<" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "item" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "id" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text "=" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"1\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text ">hello</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "item" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- sql ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "SELECT" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "name" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "FROM" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "users" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- markdown ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "# " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "hello" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- http ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "GET" font=Roboto Mono size=10 color=#0B57D0 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "/health" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "HTTP/1.1" font=Roboto Mono size=10 color=#9B5200 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- protobuf ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "message" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " User { string name = 1; }" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|
    ),
  )
}

///|
test "Protobuf receives bundled Syntax Highlighting" {
  let snapshot = fenced_snapshot(
    "protobuf",
    "message User { string name = 1; }",
  )
  assert_true(snapshot.contains(" color=#"))
}

///|
test "Markdown receives bundled Syntax Highlighting" {
  let snapshot = fenced_snapshot("markdown", "# hello")
  assert_true(snapshot.contains(" color=#"))
}

///|
test "JSX and TSX retain JavaScript keywords and tag captures" {
  let jsx = fenced_snapshot("jsx", "const node = <span />")
  let tsx = fenced_snapshot("tsx", "const node = <span />")
  assert_true(jsx.contains("text \"const\" font=Roboto Mono size=10 color=#6A1B9A"))
  assert_true(jsx.contains("text \"span\" font=Roboto Mono size=10 color=#0057B8"))
  assert_true(tsx.contains("text \"const\" font=Roboto Mono size=10 color=#6A1B9A"))
  assert_true(tsx.contains("text \"span\" font=Roboto Mono size=10 color=#0057B8"))
}

///|
test "case-insensitive aliases select the same bundled treatment" {
  let aliases = [
    ("JavaScript", "javascript", "const answer = 1"),
    ("JS", "javascript", "const answer = 1"),
    ("JsX", "jsx", "const node = <span />"),
    ("TypeScript", "typescript", "interface User {}"),
    ("TS", "typescript", "interface User {}"),
    ("TsX", "tsx", "const node = <span />"),
    ("Shell", "shell", "echo \"ok\""),
    ("SH", "shell", "echo \"ok\""),
    ("Bash", "shell", "echo \"ok\""),
    ("ZsH", "shell", "echo \"ok\""),
    ("PoWeRsHeLl", "powershell", "$name = \"ok\""),
    ("PS1", "powershell", "$name = \"ok\""),
    ("JSON", "json", "{\"name\": true}"),
    ("Yaml", "yaml", "name: value"),
    ("YML", "yaml", "name: value"),
    ("TomL", "toml", "name = \"value\""),
    ("HTML", "html", "<div class=\"box\" />"),
    ("CSS", "css", ".box { color: red; }"),
    ("XML", "xml", "<item id=\"1\" />"),
    ("SQL", "sql", "SELECT name FROM users"),
    ("Markdown", "markdown", "````javascript\nconst answer = 1\n````"),
    ("MD", "markdown", "````javascript\nconst answer = 1\n````"),
    ("HTTP", "http", "GET /health HTTP/1.1"),
    ("Protobuf", "protobuf", "syntax = \"proto3\";"),
    ("Proto", "protobuf", "syntax = \"proto3\";"),
  ]
  for entry in aliases {
    let (tag, canonical, source) = entry
    assert_eq(fenced_snapshot(tag, source), fenced_snapshot(canonical, source))
  }
}

///|
test "console colors commands while preserving transcript output as plain text" {
  inspect(
    fenced_snapshot("CoNsOlE", "$ echo \"ok\"\nplain output"),
    content=(
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "$ " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "echo" font=Roboto Mono size=10 color=#0B57D0 background=#F1F3F4
      #|  text " " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"ok\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "plain output" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|
    ),
  )
}

///|
test "HTML and Markdown use only bundled explicit language injections" {
  let snapshots = StringBuilder::new()
  let bundled_markdown =
    #|````markdown
    #|```javascript
    #|const answer = 1
    #|```
    #|````
  let unavailable_markdown =
    #|````markdown
    #|```not-bundled
    #|const answer = 1
    #|```
    #|````
  snapshots.write_string(
    fenced_snapshot(
      "html",
      "<script>const answer = \"ok\"</script>\n<style>.box { color: red; }</style>",
    ),
  )
  snapshots.write_string("--- markdown ---\n")
  snapshots.write_string(markdown_snapshot(bundled_markdown))
  snapshots.write_string("--- unavailable ---\n")
  snapshots.write_string(markdown_snapshot(unavailable_markdown))
  inspect(
    snapshots.to_string(),
    content=(
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "<" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "script" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " answer = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"ok\"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|  text "</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "script" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "<" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "style" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">." font=Roboto Mono size=10 background=#F1F3F4
      #|  text "box" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text " { " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "color" font=Roboto Mono size=10 color=#7A3E00 background=#F1F3F4
      #|  text ": red; }</" font=Roboto Mono size=10 background=#F1F3F4
      #|  text "style" font=Roboto Mono size=10 color=#0057B8 background=#F1F3F4
      #|  text ">" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- markdown ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "```javascript" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " answer = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "1" font=Roboto Mono size=10 color=#9B5200 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "```" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|--- unavailable ---
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "```not-bundled" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const answer = 1" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "```" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|
    ),
  )
}

///|
test "missing, plain, and unknown tags take the negative native adapter fallback" {
  let plain = [
    fenced_snapshot("", "const answer = 1"),
    fenced_snapshot("text", "const answer = 1"),
    fenced_snapshot("plaintext", "const answer = 1"),
    fenced_snapshot("txt", "const answer = 1"),
    fenced_snapshot("unknown:example.js", "const answer = 1"),
    fenced_snapshot("", "#!/usr/bin/env node\nconst answer = 1"),
  ]
  for snapshot in plain {
    assert_false(snapshot.contains(" color=#"))
  }
  assert_true(
    fenced_snapshot("javascript:example.txt", "const answer = 1")
    .contains("color=#6A1B9A"),
  )
}

///|
test "incomplete code preserves valid-prefix captures and exact text" {
  let snapshot = fenced_snapshot("javascript", "const answer = 1;\nconst (")
  inspect(
    snapshot,
    content=(
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " answer = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "1" font=Roboto Mono size=10 color=#9B5200 background=#F1F3F4
      #|  text ";" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " (" font=Roboto Mono size=10 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|
    ),
  )
}

///|
test "highlighted fences preserve CJK combining emoji whitespace blank and trailing lines" {
  inspect(
    fenced_snapshot("javascript", "const label = \"界é🚀\t \"\n\n// note"),
    content=(
      #|profile pumd.default@3
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "const" font=Roboto Mono size=10 color=#6A1B9A background=#F1F3F4
      #|  text " label = " font=Roboto Mono size=10 background=#F1F3F4
      #|  text "\"界é🚀\t \"" font=Roboto Mono size=10 color=#08783F background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|  text "// note" font=Roboto Mono size=10 color=#5F6368 background=#F1F3F4
      #|paragraph normal font=Roboto Mono size=10 line=1.0 before=0 after=0 background=#F1F3F4
      #|
    ),
  )
}

///|
test "highlighted rendering is repeatable and canonically merges same-style neighbors" {
  let source = "const value = \"x\""
  let first = fenced_snapshot("javascript", source)
  let second = fenced_snapshot("JaVaScRiPt", source)
  assert_eq(first, second)
  match @pumd.render_markdown("```javascript\n" + source + "\n```\n") {
    Ok(document) => assert_false(has_noncanonical_code_runs(document))
    Err(_) => assert_true(false)
  }
}
