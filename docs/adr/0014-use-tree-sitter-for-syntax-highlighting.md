# Use Tree-sitter for Syntax Highlighting

`pumd` will bundle Tree-sitter, pinned generated parsers, and vetted highlight queries for its fixed supported language set, exposing them through the existing native C integration boundary. This accepts a larger binary, longer builds, and more vendored-source maintenance in exchange for parser-grade highlighting of incomplete code; project-owned approximate lexers across the full language set would be smaller but substantially harder to keep correct and consistent.
