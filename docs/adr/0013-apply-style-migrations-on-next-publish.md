# Apply Style Migrations on the next publish

New versions of the built-in Style Profile apply to existing Publications through the normal safe update flow on their next publish, even when the Markdown source is unchanged. This keeps one canonical rendering contract and makes migrations inspectable through `--dry-run`; preserving legacy formatting or adding migration flags would create multiple long-lived rendering modes, while existing conflict and review safeguards already prevent unsafe updates.
