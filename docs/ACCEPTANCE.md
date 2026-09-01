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
2. 人工煙囪：照 `docs/REVIEW-TEST.md` 的 9 條逐項操作（由人類執行，agent 只能引導）
3. 證據格式：見下方

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
  ...（9 條全列）
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

## 簽收紀錄

| 日期 | 版本 | Eval | Manual | 簽核 |
|---|---|---|---|---|
| 2026-09-01 | 0.1.0 | 7/7 PASS | 1,8 自動化通過；2-7 待人類 | fun-ed |
| 2026-09-02 | 0.2.0 | 7/7 PASS + 簽章 + DMG | VU 授權流程與 bar 跟動待人工 | fun-ed |