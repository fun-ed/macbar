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
3. 證據紀錄格式：一般 PR 見下方範本；各版本的機器驗證、人工確認與未驗項另列於下方。準備中的版本不沿用歷史 PASS。

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

## v0.3.1 驗證紀錄（2026-10-23，已發佈）

版本為 0.3.1 / build 9，產物為 `dist/macbar-0.3.1-arm64.dmg`。以下為 parent 於 2026-10-23 提供的最終 500 ms VU 版本驗證結果；本次文件更新未重跑驗證。機器項目 PASS，人工未驗項由使用者明確豁免，不視為人工 PASS。

| 證據 | 目前狀態 |
|---|---|
| 自動化測試 | `swift test`：29/29 PASS，包含 8 項 LevelMeter XCTest 與既有 21 項測試。 |
| Release app | `Scripts/make-app.sh`：release build PASS、arm64 PASS、`CFBundleShortVersionString` 0.3.1、`CFBundleVersion` 9；`codesign --verify --strict` PASS。 |
| CoreAudio smoke | `Scripts/smoke-coreaudio.swift`：7/7 PASS，輸出音量與 mute 原值已還原。 |
| DMG 封裝 | create-dmg 簽章身分不可用，既有 hdiutil 後備成功。唯讀掛載 PASS，Applications symlink 指向 `/Applications` PASS，掛載 App 為 0.3.1 / build 9 且簽章 PASS；完整 App 檔案 SHA manifest 與 build 逐位元組一致。大小與 SHA-256 見下方。 |
| 介面與真實 VU | 本版未新增人工觀察。無呼吸／流光、靜態 mute 區別、滑桿／mute 即時生效、短暫及持續音訊、停止歸零、關閉再開啟無殘留峰值，以及 VU 僅在 popover 開啟時運作，均保留未驗；使用者已豁免本次人工驗收，不標 PASS。 |
| 逐 App 與生命週期 | 本版未新增人工驗證兩個 App 的 gain／mute 隔離、主音量不變、popover 關閉後 route 持續，以及程序退出、切換輸出、退出 macbar 的 cleanup；保留未驗，使用者已豁免本次人工驗收。 |
| CPU 證據邊界 | `PLAN.md` 的 animation-only A/B 是先前無 capture／route、保留 discovery timer 的量測，不是最終 500 ms 版本或 active-route 效能。本版未新增 live VU 或 active-route CPU 量測，不保證特定 CPU 百分比。 |
| 最終背景執行 | 最終 500 ms release App 自啟動起即隱藏，no-capture／no-route，另行執行 60.029 秒，消耗 0.212036 CPU 秒，平均單核心 CPU 0.353%；App 持續存活，低於 1% 目標。此為獨立執行，不是配對 A/B，也不是 live VU 或 active-route CPU 量測。 |
| 權限、平台與硬體 | macOS 13 / 14.3 fallback、完整 TCC 允許／拒絕／撤銷與 Retry、Boom3D 及硬體矩陣未重跑；保留未驗，使用者已明確豁免本次人工驗收，不推定相容或通過。 |
| 獨立複審 | 本版獨立程式碼快照複審 PASS；與人工驗收分開記錄。 |
| 人工放行 | 使用者已得知 29 項測試、7 項 smoke 與 DMG 驗證通過，以及缺少最終 500 ms 人工觀察與完整矩陣，於 2026-10-23 明確選擇「保留未驗項，正式發佈」。此為保留未驗項的發佈豁免，不是人工 PASS。 |
| GitHub 發佈 | [v0.3.1](https://github.com/fun-ed/macbar/releases/tag/v0.3.1) 於 2026-10-23T05:31:08Z 正式發佈，`isDraft=false`、`isPrerelease=false`。tag 固定指向 release merge commit `38cbfb106dce4fa2fb4c8ac451354e53c8377b29`，實作 commit `3f61eff` 可由此到達；發佈時 main／develop 已推送至該 release commit。遠端 Release body 讀回與已審閱的完整 English、台灣繁體中文 notes 一致，順序為英文在前。 |
| GitHub 下載驗證 | 重新下載 `macbar-0.3.1-arm64.dmg`，688,443 bytes，SHA-256 與本機產物一致。唯讀掛載後，App 0.3.1 / build 9、strict 簽章與 Applications symlink 指向 `/Applications` 均 PASS；完整 App 檔案 SHA manifest 與本機 build 逐位元組一致。 |

本機及 GitHub 重新下載並驗證的 asset 均為 `macbar-0.3.1-arm64.dmg`，688,443 bytes，SHA-256 相同：

```text
7e6d2103d95cc7740a8f022a1735db84ccb87cb031c1cfd46c839066af9dd73a  macbar-0.3.1-arm64.dmg
```

v0.3.1 已依上述人工豁免正式發佈，GitHub tag、Release body 與重新下載驗證均完成；人工未驗項仍保留未驗。App 維持 ad-hoc 簽章、未 notarized；未安裝或變更 `/Applications/macbar.app`。若需回退，重新安裝既有 [v0.3.0 release asset](https://github.com/fun-ed/macbar/releases/tag/v0.3.0)，不移動或覆寫舊 tag。

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
| GitHub 發佈 | [v0.3.0](https://github.com/fun-ed/macbar/releases/tag/v0.3.0) 已正式發佈，非 draft／prerelease；tag 指向 `a3801d4a02f127c3f6e57675beeaaa06f22afdaf`。已下載 asset，確認版本、簽章與 App 內容，SHA-256 與本機產物一致。 |

發佈 asset 為 `macbar-0.3.0-arm64.dmg`，667,219 bytes：

```text
5df2b394c29166f58504c2655cb9de8e2e55cd0effc847b8390ecc8caa103ae2  macbar-0.3.0-arm64.dmg
```


## 簽收紀錄

| 日期 | 版本 | Eval | Manual | 簽核 |
|---|---|---|---|---|
| 2026-09-01 | 0.1.0 | 7/7 PASS | 1,8 自動化通過；2-7 待人類 | fun-ed |
| 2026-09-02 | 0.2.0 | 7/7 PASS + 簽章 + DMG | VU 授權流程與 bar 跟動待人工 | fun-ed |
| 2026-10-12 | 0.3.0 | 21/21 unit tests + release arm64 + 簽章 + 7/7 smoke + DMG 掛載驗證通過 | 使用者確認內建喇叭 Firefox 音量／mute；完整人工矩陣與 Boom3D 未驗 | 使用者功能確認；機器驗證完成 |
| 2026-10-23 | 0.3.1 / build 9 | PASS：29/29 tests + release arm64 + strict codesign + 7/7 smoke（輸出音量／mute 已還原）+ 本機與 GitHub 重新下載 DMG 的 checksum／唯讀掛載／版本／簽章／Applications 捷徑／完整 App manifest 一致；獨立程式碼快照複審 PASS。最終 500 ms 背景執行 60.029 秒、0.212036 CPU 秒、平均單核心 CPU 0.353%，持續存活且低於 1% 目標，僅限啟動起即隱藏、no-capture／no-route，非配對 A/B、live VU 或 active-route 量測 | 最終 500 ms 介面／VU／逐 App／生命週期未人工驗證；TCC、舊版 OS、Boom3D 與硬體矩陣未重跑。人工未驗，已明確豁免，不標 PASS | 使用者於 2026-10-23 明確選擇「保留未驗項，正式發佈」；[v0.3.1](https://github.com/fun-ed/macbar/releases/tag/v0.3.1) 於 2026-10-23T05:31:08Z 正式發佈，非 draft／prerelease，tag 固定指向 `38cbfb106dce4fa2fb4c8ac451354e53c8377b29`；GitHub 重新下載驗證 PASS，詳見上方證據 |