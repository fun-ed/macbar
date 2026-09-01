---
name: macbar-debug
description: "Debug macbar runtime issues: process checks, log capture, CoreAudio smoke harness, and the troubleshooting table. Use when the user reports macbar crashes, hangs, sliders not working, device switching not following, or asks how to debug macbar."
---

# macbar Debug

Run in order, report each result:

```bash
# 1. Process alive?
pgrep -x macbar

# 2. App logs (launch failures, listener errors)
log show --predicate 'process == "macbar"' --last 5m

# 3. CoreAudio layer against live hardware (7 PASS expected)
swift Scripts/smoke-coreaudio.swift

# 4. Build still clean?
swift build -c release && ./Scripts/make-app.sh && codesign --verify --strict build/macbar.app
```

## Symptom table (full version in docs/MAINTENANCE.md)

| Symptom | Check |
|---|---|
| Launches then quits | `log show` output above |
| Slider does nothing | device lacks VolumeScalar; app falls back to channels 1...32 |
| Device switch not followed | default-device listener re-registration |
| Scroll direction inverted | flip sign in `handleScroll` in AppDelegate.swift |
| VU bar 不動 | 系統設定 → 隱私權 → 麥克風／系統音訊 是否允許 macbar；macOS 14.4 以下 speaker bar 無 tap |
| DMG won't open | ad-hoc signing: right-click → Open to bypass Gatekeeper |

Rules: change nothing without a hypothesis; restore any device state (volume/mute) touched during debugging; rebuild and re-verify after each fix.