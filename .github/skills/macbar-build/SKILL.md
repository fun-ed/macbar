---
name: macbar-build
description: "Build macbar end to end: swift release build, app bundle with icon, ad-hoc codesign. Use when the user wants to build, rebuild, or check that the macbar app compiles and bundles, or before running any verification."
---

# macbar Build

Run from the repo root (or the active worktree):

```bash
swift build -c release
./Scripts/make-app.sh
file build/macbar.app/Contents/MacOS/macbar   # expect: Mach-O 64-bit executable arm64
codesign --verify --strict build/macbar.app   # expect: valid on disk
```

All four commands must pass. On failure, fix at the source; never hand-patch build artifacts.

Rules:
- No third-party dependencies; pure SwiftPM.
- Swift language mode 5 (Package.swift `swift-tools-version:5.9`).
- Never add TCC usage or sandbox entitlements.