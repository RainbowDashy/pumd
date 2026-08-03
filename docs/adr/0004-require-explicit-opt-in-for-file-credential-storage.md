# Require explicit opt-in for file credential storage

Interactive Google refresh credentials will use the operating system credential vault by default, and `pumd` will not silently fall back to local token files when that vault is unavailable. Headless and automation environments may explicitly select permission-hardened file storage or provide ephemeral credentials; this makes reduced protection visible and intentional at the cost of extra setup on systems without a usable credential vault.
