# Render directly from the Markdown CST

`pumd` will render the `mizchi/markdown` CST directly instead of translating it into a separate platform-independent semantic document IR. The CST already provides typed block and inline structure plus source locations, so another generic document model would add conversion code and risk losing supported constructs; the renderer instead produces the Google-Docs-specific desired-state model established in ADR 0002.
