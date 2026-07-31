///|
test "Google Docs index advances across ASCII text" {
  assert_eq(advance_google_docs_index(index=1, text="Hello"), 6)
}

///|
test "Google Docs index advances across CJK text" {
  assert_eq(advance_google_docs_index(index=1, text="中文"), 3)
}

///|
test "Google Docs index advances across combining marks" {
  assert_eq(advance_google_docs_index(index=1, text="e\u{0301}"), 3)
}

///|
test "Google Docs index advances across newlines" {
  assert_eq(advance_google_docs_index(index=4, text="first\nsecond"), 16)
}

///|
test "Google Docs index advances across non-BMP emoji" {
  assert_eq(advance_google_docs_index(index=1, text="A🚀B"), 5)
}
