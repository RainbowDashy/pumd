# Maintain a source-level Markdown parser fork

`pumd` owns the parser source under `vendor/markdown` as a maintained fork based on `mizchi/markdown`, rather than treating it as pristine, replaceable vendor code. Parser behavior required for native publishing—including blockquote boundaries and source provenance—cannot be supplied upstream, so dependency updates are manual merges that must preserve or deliberately reconcile local behavior, attribution, and tests.
