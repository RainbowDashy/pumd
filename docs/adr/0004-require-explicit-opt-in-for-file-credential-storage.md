# Require explicit opt-in for file credential storage

Interactive Google refresh credentials will use the operating system credential vault by default, and `pumd` will not silently fall back to local token files when that vault is unavailable. Headless and automation environments may explicitly select permission-hardened file storage or provide ephemeral credentials; this makes reduced protection visible and intentional at the cost of extra setup on systems without a usable credential vault.

An explicit credential-store choice made during setup may be persisted as non-secret configuration and reused by later status, publish, and logout commands. With no persisted choice, the operating-system vault remains the default. Detecting that a vault is unsupported, denied, locked, mispackaged, or otherwise unusable may disable that setup option with an actionable reason, but must never select file storage automatically; file storage still requires an informed affirmative choice.
