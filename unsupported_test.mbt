test "returns an image diagnostic and no partial desired document" {
  match @pumd.render_markdown("before ![alt](image.png) after") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].kind, @pumd.DiagnosticKind::UnsupportedConstruct)
      assert_eq(diagnostics[0].node_kind, "image")
      assert_true(diagnostics[0].provenance is Some(_))
    }
  }
}

test "collects unsupported diagnostics in stable source order" {
  match @pumd.render_markdown("text\n\n---\n\n> quote") {
    Ok(_) => assert_true(false)
    Err(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_eq(diagnostics[0].node_kind, "thematic-break")
      assert_eq(diagnostics[1].node_kind, "blockquote")
    }
  }
}
