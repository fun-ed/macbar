---
name: macbar-release
description: "Produce the macbar arm64 DMG release artifact. Use when the user wants to build, package, or refresh the distributable DMG, or bump the release version."
---

# macbar Release

1. Confirm the version is correct in `Scripts/make-app.sh` (CFBundleShortVersionString) and `Scripts/make-dmg.sh` (output filename).
2. `./Scripts/make-app.sh`
3. `./Scripts/make-dmg.sh` — produce `dist/macbar-0.1.0-arm64.dmg` (falls back to hdiutil if create-dmg cannot sign).
4. Verify: `hdiutil attach` the DMG, check `macbar.app` + `Applications` link, `codesign --verify --strict`, then detach.
5. Update `PLAN.md` version history in the same change.

Output artifact: `dist/macbar-<version>-arm64.dmg` (gitignored, stays local).