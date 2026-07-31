///|
test "publication title uses the file name without its final extension" {
  inspect(
    publication_title_from_path("notes/design.v2.md"),
    content="design.v2",
  )
  inspect(
    publication_title_from_path("C:\\drafts\\proposal.md"),
    content="proposal",
  )
}

///|
test "publication title keeps a leading-dot file name" {
  inspect(publication_title_from_path(".proposal"), content=".proposal")
  inspect(publication_title_from_path(".proposal.md"), content=".proposal")
}
