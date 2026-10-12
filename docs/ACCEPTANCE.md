# 驗收測試準則

驗收 = 機器可驗（eval）+ 人工煙囪（manual smoke），兩者都要有紀錄。測項清單的唯一事實來源是 `docs/REVIEW-TEST.md`，本文件定義怎麼執行、誰負責、證據長什麼樣。

## 什麼時候跑

- 每個 PR merge 前（對應改動的分級項目）
- 每個 release（版本升級）發佈前：全套
- 任何碰 `AudioController.swift`、listener 生命週期、打包腳本的改動：全套

## 角色

- **dev agent**：執行全部項目，產出證據
- **review agent**：重跑機器可驗項目，核對證據，簽 PASS/FAIL
- 人類：煙囪清單中標記「需人手」的項目由人類勾選

## 執行

1. 機器可驗：跑 `.github/skills/macbar-verify/SKILL.md` 的全部指令，留存輸出
2. 人工煙囪：照 `docs/REVIEW-TEST.md` 逐條操作所有適用測項；由人類執行，agent 只能引導。
3. 證據紀錄格式：一般 PR 見下方範本；v0.3.0 的機器驗證、人工確認與未驗項另列於下方。

## 證據紀錄格式

每次驗收在 PR 描述貼上：

```text
Eval:
  swift build -c release        -> PASS (0 errors)
  file .../macbar               -> PASS (arm64)
  codesign --verify --strict    -> PASS
  smoke-coreaudio.swift         -> 7/7 PASS
  hdiutil mount + verify        -> PASS
Manual smoke:
  1. menubar icon               -> [x] (操作者: <誰>)
  2. popover sliders            -> [x]
  ...（逐列列出 `docs/REVIEW-TEST.md` 所有適用測項）
未驗項: <明列>
```

## 裝置矩陣

至少涵蓋：

| 裝置類型 | 必測 |
|---|---|
| 內建喇叭 + 內建麥克風 | 全套煙囪 |
| 有硬體 mute 的輸入裝置 | mute toggle / restore |
| 無 master 音量元素的裝置 | 聲道 fallback（目前開發機輸出即此類，已驗證） |
| 無硬體 mute 的裝置 | 軟體 mute 路徑（歸 0 + 還原） |

## 失敗處理

- 任何 FAIL：不 merge。先建 issue（`.github/ISSUE_TEMPLATE/bug_report.md`），修復後整套重跑
- 環境受限跑不了的項目（如只有一個輸出裝置）：明列「未驗」+ 原因，由人類決定是否放行

## v0.3.0 驗證紀錄

以下結果於 2026-10-12 在目前開發機取得。機器驗證與使用者確認分開記錄，未完成的人工矩陣不算通過。

| 證據 | 目前狀態 |
|---|---|
| 自動化測試 | `swift test`：21/21 通過；`Scripts/make-app.sh`：release build 通過；`file`：arm64；`codesign --verify --strict` 通過。 |
| 逐 App 即時操作 | Firefox + afplay 在內建 MacBook Air 輸出執行 gain 50%、mute、restore；已觀察有效 tap input 與 replay callbacks，系統主音量未變、tap/aggregate cleanup 通過。開發期間另驗證兩條 controller route 與超過 60 秒的正常靜默；`smoke-coreaudio.swift`：7/7 通過且還原原值。 |
| 發佈封裝 | App 為 0.3.0 / build 8；`dist/macbar-0.3.0-arm64.dmg` 產製成功。因無 Developer ID 身分使用既有 hdiutil 後備；唯讀掛載可見 macbar.app 與 Applications 捷徑，App 簽章有效且內容與 build 相同。 |
| 人工功能 | 使用者確認 Firefox 的獨立滑桿與 mute 實際生效、沒有紅字。其餘完整人工煙囪清單尚未逐項取得本版紀錄；不由這項確認推定全部通過。 |
| 權限與平台 | macOS 13 / 14.3 的實機 fallback，以及系統音訊 TCC 允許、拒絕、撤銷後 Retry 的完整人工矩陣未完成；目前只有本機環境，未驗項保留。 |
| Firefox、原生輸出與 Boom3D | 已驗證內建輸出上的 Firefox；其他 native output 拓樸矩陣與 Boom3D 完整相容性未驗證。不得宣稱 Boom3D 全相容，也不得由目前觀察推論其驅動必然不相容。 |
| GitHub 發佈 | Release 建立、tag 目標與 asset 下載 SHA-256 在發佈操作後另行核對。 |


## 簽收紀錄

| 日期 | 版本 | Eval | Manual | 簽核 |
|---|---|---|---|---|
| 2026-09-01 | 0.1.0 | 7/7 PASS | 1,8 自動化通過；2-7 待人類 | fun-ed |
| 2026-09-02 | 0.2.0 | 7/7 PASS + 簽章 + DMG | VU 授權流程與 bar 跟動待人工 | fun-ed |
| 2026-10-12 | 0.3.0 | 21/21 unit tests + release arm64 + 簽章 + 7/7 smoke + DMG 掛載驗證通過 | 使用者確認內建喇叭 Firefox 音量／mute；完整人工矩陣與 Boom3D 未驗 | 使用者功能確認；機器驗證完成 |