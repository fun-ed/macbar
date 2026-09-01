---
name: macbar-verify
description: "Run the macbar machine-verifiable eval suite: build, arm64 check, codesign, DMG mount inspection. Use before any merge or release, when the user asks to verify, test, or evaluate macbar changes, or after fixing a bug to prove the fix."
---

# macbar Verify

Run every step; all must pass:

```bash
swift build -c release
./Scripts/make-app.sh
file build/macbar.app/Contents/MacOS/macbar
codesign --verify --strict build/macbar.app
hdiutil attach dist/*.dmg -mountpoint /tmp/macbar-mnt -readonly -nobrowse
ls /tmp/macbar-mnt/
codesign --verify --strict /tmp/macbar-mnt/macbar.app
hdiutil detach /tmp/macbar-mnt -quiet
```

Then report each result. Any failure blocks merge. See `docs/REVIEW-TEST.md` for the full matrix including manual smoke tests.