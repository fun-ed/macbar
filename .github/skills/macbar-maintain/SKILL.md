---
name: macbar-maintain
description: "Run the macbar maintenance loop: version bump, PLAN.md and doc consistency sweep, skills/agents drift check, rebuild and re-verify. Use when the user asks to maintain, upgrade the version, sync docs, or audit that skills and agents still match the current process."
---

# macbar Maintain

## Version bump (single flow)

1. `Scripts/make-app.sh`: update `CFBundleShortVersionString` + `CFBundleVersion`.
2. `Scripts/make-dmg.sh`: update output filename `macbar-<ver>-arm64.dmg`.
3. `PLAN.md`: add version-history entry, update acceptance checklist.
4. `./Scripts/make-app.sh && ./Scripts/make-dmg.sh`, then `swift Scripts/smoke-coreaudio.swift`.
5. Commit: `build: release vX.Y.Z`.

## Doc / skills / agents consistency sweep

- Compare each `.github/skills/*/SKILL.md` and `.github/agents/*.agent.md` against `AGENTS.md`, `PLAN.md`, and `docs/REVIEW-TEST.md`.
- Fix drift in the same commit as the change that caused it.
- Before editing any skill/agent file: `cp <file> <file>.bak-$(date +%Y%m%d-%H%M%S)`.
- Permissions in agent files may only shrink; widening requires explicit human approval.

## Verification

All machine checks from `docs/REVIEW-TEST.md` must pass after maintenance changes. Report what changed, what stays the same, what was re-run.