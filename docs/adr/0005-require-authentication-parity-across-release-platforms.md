# Require authentication parity across release platforms

Browser-based Google authorization will become `pumd`'s default only when Apple Silicon macOS, Linux x86-64, and Windows x86-64 all support the same interactive flow and secure operating-system credential storage. Platform adapters may be developed and tested incrementally, with explicit ADC remaining available during the transition, but a macOS-first default would make the documented publishing workflow depend on the downloaded artifact and is therefore rejected.
