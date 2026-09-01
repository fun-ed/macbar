# 維護準則

## 版本升級（唯一流程）

1. 改 `Scripts/make-app.sh` 內的 `Info.plist`：`CFBundleShortVersionString`、`CFBundleVersion`。
2. 改 `Scripts/make-dmg.sh` 的輸出檔名 `macbar-<ver>-arm64.dmg`。
3. 更新 `PLAN.md` 版本歷史與驗收清單。
4. 重建並跑完 `docs/REVIEW-TEST.md` 的驗證矩陣。
5. commit：`build: release vX.Y.Z`。不 co-author。
6. GitHub Release：`git tag vX.Y.Z` + `gh release create` 附 changelog 與 DMG asset（見 `.github/skills/macbar-release/SKILL.md`）。

## 日常維護

- 任何行為變更先改 `PLAN.md`（SOT），再改程式。
- `dist/`、`build/`、`.build/` 是 gitignored 產物，可隨時刪除重建。
- CoreAudio API 變動風險低；升 macOS SDK 後重跑 `swift build -c release` 確認。

## 已知邊界與取捨

- 滾輪方向假設：`deltaY > 0` = 音量增加。若實際反向，改 `handleScroll` 的正負號一行。
- `create-dmg` 需要簽章身分；無身分時自動後備 `hdiutil` 純壓縮 DMG（無美化背景，屬預期）。
- SMAppService（Launch at Login）對 ad-hoc 簽章 app 可能註冊失敗；失敗時選單狀態不變，屬已知限制。
- VU 表：output tap 需 macOS 14.4+（13/14.3 的 speaker bar 走設定值模式）；任一授權被拒 → 該 bar 退回設定值模式；metering 只在 popover 開啟期間運作（省電）。
- 麥克風 TCC 與系統音訊 capture 已於 v0.2.0 經拍板引入，僅量測電平、不錄音不存檔。

## Skills 與 Agents 維護

`.github/skills/`（macbar-build、macbar-verify、macbar-release）與 `.github/agents/`（dev、review）是會影響未來行為的設定檔，不是普通文件：

- 修改前先備份：`cp <file> <file>.bak-$(date +%Y%m%d-%H%M%S)`。
- 任何流程變更（SOT、驗證矩陣、merge 規則）落地時，同 commit 內同步對應 skill / agent 的描述，避免漂移。
- 每次版本升級前對照 `PLAN.md` 逐檔檢查 skills / agents 是否仍與現行流程一致。
- Agent 的權限範圍（可讀什麼、可跑什麼、不可破壞什麼）只能縮不能放；放寬需人類明示同意。
- 刪除 skill / agent 屬破壞性操作，需先取得同意並留下備份。

## 疑難排解

| 症狀 | 檢查 |
|---|---|
| app 啟動即退出 | `log show --predicate 'process == "macbar"' --last 5m` |
| 滑桿無反應 | 確認裝置有 VolumeScalar 屬性（`AudioObjectHasProperty`） |
| 換裝置沒跟隨 | 確認 default-device listener 有重註冊 |
| DMG 打不開 | ad-hoc 簽章需右鍵「打開」繞 Gatekeeper |