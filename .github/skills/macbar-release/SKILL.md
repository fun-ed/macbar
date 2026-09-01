---
name: macbar-release
description: "Full macbar release pipeline: bump version in Info.plist and DMG filename, update PLAN.md, build and verify, merge and push, git tag, create the GitHub Release with changelog notes and the DMG asset via gh release. Use when the user asks to release, publish a version, or ship a new DMG."
---

# macbar Release

完整發佈流程（升版 → 驗證 → GitHub Release）。

## 1. Version bump

1. `Scripts/make-app.sh`：`CFBundleShortVersionString` 升版、`CFBundleVersion` +1
2. `Scripts/make-dmg.sh`：輸出檔名改 `macbar-<ver>-arm64.dmg`
3. `PLAN.md`：版本歷史新增段落 + 驗收清單更新

## 2. Build + verify

```bash
./Scripts/make-app.sh && codesign --verify --strict build/macbar.app
swift Scripts/smoke-coreaudio.swift        # 7/7 PASS
./Scripts/make-dmg.sh
```

## 3. Merge + push

- worktree 分支 merge 回 main（--no-ff），`git push . main:develop` 同步
- push 需人類指示（release 除外：`gh release` 本身就是要出去）

## 4. Tag + GitHub Release（含 changelog + DMG）

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z dist/macbar-X.Y.Z-arm64.dmg \
  --title "macbar vX.Y.Z" \
  --notes-file <(生成自 PLAN.md 版本歷史對應段落)
```

Changelog 直接取 `PLAN.md` 該版本段落（SOT），轉成 markdown bullet。首次 release 需涵蓋先前版本。

## 5. 事後

- 更新 `docs/ACCEPTANCE.md` 簽核表
- 確認 GitHub Release 頁面的 asset 可下載、checksum 一致

Output artifact: `dist/macbar-<version>-arm64.dmg`（gitignored，發佈時上傳到 release asset）。