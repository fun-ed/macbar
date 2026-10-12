# 維護準則

## 版本升級（唯一流程）

1. 先更新 `PLAN.md`，記錄版本、已批准權限、控制範圍及未完成 release gate。
2. 更新 `Scripts/make-app.sh` 的 `CFBundleShortVersionString` 與遞增的 `CFBundleVersion`；更新 `Scripts/make-dmg.sh` 的 final DMG 名稱及 create-dmg 輸出名稱。
3. 同步 `CHANGELOG.md`、`README.md` 安裝連結、`PLAN.md` 版本狀態與 `docs/ACCEPTANCE.md` release evidence。準備階段勿稱已發佈。
4. 依 `docs/REVIEW-TEST.md` 執行與版本相關的機器及人工驗證，將未驗項與原因寫入 `docs/ACCEPTANCE.md`。
5. 完成 build、簽章、DMG 驗證及人工 gate 後才建立 GitHub Release；Release 建立完成後才將文件標記已發佈。

## 日常維護

- 任何行為變更先改 `PLAN.md`（SOT），再改程式。
- `docs/ARCHITECTURE.md` 說明實際模組、路由資料流與資源生命週期。新增模組或改變 VU/mixer 啟停條件時，同步維護此文件與 `docs/DEVELOPMENT.md`。
- `dist/`、`build/`、`.build/` 是 gitignored 產物，可隨時刪除重建。
- CoreAudio API 變動風險低；升 macOS SDK 後重跑 `swift build -c release` 確認。

## 已知邊界與取捨

- 滾輪方向假設：`deltaY > 0` = 音量增加。若實際反向，改 `handleScroll` 的正負號一行。
- `create-dmg` 需要簽章身分；無身分時自動後備 `hdiutil` 純壓縮 DMG（無美化背景，屬預期）。
- SMAppService（Launch at Login）對 ad-hoc 簽章 app 可能註冊失敗；失敗時選單狀態不變，屬已知限制。
- VU 表：output tap 需 macOS 14.4+（13/14.3 的 speaker bar 走設定值模式）；任一授權被拒時該 bar 退回設定值模式。VU metering 只在 popover 開啟期間運作。
- 逐 App mixer 也需 macOS 14.4+，但生命週期獨立於 VU：popover 關閉後 route 繼續運作，直到設定回到 100% 未 mute、程序停止、輸出改變或 app 退出。
- 逐 App route 僅支援單一實體 subdevice、單一 1–32 聲道 Float32 output stream、一個 stereo Float32 tap，且 sample rate 相同。拓樸或 buffer layout 不符時不套用 route，保留原始播放。
- 麥克風 TCC 用於輸入 VU；系統音訊 process tap 用於輸出 VU 與已批准的逐 App 即時處理。音訊不錄音、不存檔。不可新增未經 `PLAN.md` 批准的 TCC 用途。
- macOS 13 / 14.3 尚未完成逐 App 人工實機驗證。Boom3D 完整相容性未驗證，也不保證支援。曾觀察到啟用 Boom 時 Firefox process audio 資訊缺失，切回內建輸出重播後才出現；原因未定。

## Skills 與 Agents 維護

`.github/skills/`（macbar-build、macbar-verify、macbar-release）與 `.github/agents/`（dev、review）是會影響未來行為的設定檔，不是普通文件：

- 修改前先備份：`cp <file> <file>.bak-$(date +%Y%m%d-%H%M%S)`。
- 任何流程變更（SOT、驗證矩陣、merge 規則）落地時，同 commit 內同步對應 skill / agent 的描述，避免漂移。
- 每次版本升級前對照 `PLAN.md` 逐檔檢查 skills / agents 是否仍與現行流程一致。
- Agent 的權限範圍（可讀什麼、可跑什麼、不可破壞什麼）只能縮不能放；放寬需人類明示同意。已批准用途以 `PLAN.md` 為準，不得擴展到未批准用途。
- 刪除 skill / agent 屬破壞性操作，需先取得同意並留下備份。

## 疑難排解

| 症狀 | 檢查 |
|---|---|
| app 啟動即退出 | `log show --predicate 'process == "macbar"' --last 5m` |
| 滑桿無反應 | 確認裝置有 VolumeScalar 屬性（`AudioObjectHasProperty`） |
| 換裝置沒跟隨 | 確認 default-device listener 有重註冊 |
| DMG 打不開 | ad-hoc 簽章需右鍵「打開」繞 Gatekeeper |
| App row 顯示未套用或 Retry | macOS 14.4+、目標 App 正在播放、系統音訊存取已允許；確認 route 顯示錯誤後再按 Retry |
| App row 長時間停在 Checking | 目標 App 播放音訊，再檢查系統音訊存取授權、CoreAudio route 錯誤與 app log |
| 逐 App route 不支援裝置 | 記錄預設輸出型號、stream 格式、聲道與 sample rate；不要將 topology 拒絕推論為驅動不相容 |
| Firefox process audio 不見 | 記錄輸出裝置及 Boom3D 開關狀態，改用內建輸出重播比較；Boom3D 支援狀態未確認 |