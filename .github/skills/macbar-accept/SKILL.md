---
name: macbar-accept
description: "Run the macbar acceptance test procedure: machine eval suite plus the 9-item manual smoke checklist, with evidence recording per docs/ACCEPTANCE.md. Use when the user asks to accept, sign off, or tick the review-test checklist for a version or PR."
---

# macbar Accept

1. Run the machine eval suite (`.github/skills/macbar-verify/SKILL.md`): build, arch, codesign, `swift Scripts/smoke-coreaudio.swift` (7 PASS), DMG mount.
2. Walk `docs/REVIEW-TEST.md` manual checklist with the human; agent may only record, never guess UI results.
3. Fill an evidence record per `docs/ACCEPTANCE.md` §Evidence record format.
4. Verdict: PASS only when machine eval is 7/7 and every manual item has a real tick or an explicitly approved exception.

Failure of any item = reject; file a bug issue using the bug template.