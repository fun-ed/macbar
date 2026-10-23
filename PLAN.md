# macbar — macOS menubar 音量控制器

> 本檔是本專案的單一事實來源（SOT）。任何行為、範圍、打包方式的變更，先改這裡再改程式。

- 版本：v0.3.1，build 9
- 發佈狀態：PUBLISHED（2026-10-23T05:31:08Z），[v0.3.1](https://github.com/fun-ed/macbar/releases/tag/v0.3.1) 已正式發佈，非 draft／prerelease；本版測試、release build、簽章、smoke、獨立複審、本機 DMG 與 GitHub asset 重新下載驗證通過。使用者明確選擇「保留未驗項，正式發佈」，豁免未完成人工驗收，不代表人工 PASS。前版為 [v0.3.0](https://github.com/fun-ed/macbar/releases/tag/v0.3.0)。
- 定案日期：2026-09-01
- 決策過程：grilling 訪談 14 題（Q1–Q14），全數由使用者拍板

## 決策總表

| 決策點 | 結論 |
|---|---|
| 技術棧 | Swift 原生，SwiftPM 管理，UI 用 SwiftUI（狀態列容器用 NSStatusItem + NSPopover，因為需要 icon 滾輪與右鍵選單的完整控制權） |
| 平台 | arm64-only，最低 macOS 13（Ventura） |
| App 形態 | LSUIElement（無 Dock 圖示），常駐 menubar |
| 權限 | v0.1 無 TCC；v0.2.0 起已批准麥克風 TCC（VU）與系統音訊 process tap（VU）；v0.3.0 沿用系統音訊存取逐 App 即時處理，不增加權限。授權遭拒時，VU 退回設定值模式，逐 App route 不套用並顯示錯誤 |
| 控制範圍 | 系統控制器只跟隨預設輸出與輸入；逐 App 控制器只處理指定 App 的輸出，不改變系統主音量或預設輸出 |
| Popover | 喇叭、麥克風系統音量各一條滑桿 + mute 按鈕 + 百分比；Applications 列出輸出中的 App，提供逐 App 音量、mute 與 route 狀態 |
| 逐 App route | macOS 14.4+ process tap；單一實體 subdevice、一條 1–32 聲道 Float32 輸出 stream、一個 stereo Float32 tap，sample rate 必須一致。100% 未 mute 不建立 route；不支援的拓樸顯示錯誤並保留原始播放 |
| Icon 滾輪 | 在 menubar 圖示上滾動 = 調整喇叭系統音量 |
| Icon 狀態 | 平時 `speaker.wave.2.fill`；喇叭 mute → `speaker.slash.fill`；麥克風 mute → `mic.slash.fill`（mic 狀態優先顯示） |
| 右鍵選單 | Launch at Login（SMAppService）、Quit |
| Mute 後備行為 | 裝置不支援硬體 mute 屬性時，改用「音量歸 0 + 軟體旗標」，解除 mute 時還原 mute 前音量（前值存 UserDefaults） |
| 持久化 | UserDefaults：系統軟體 mute 旗標、mute 前音量；逐 App 音量與 mute 只保留在當次執行記憶體 |
| 簽章 | ad-hoc（無開發者帳號；首次開啟需右鍵「打開」） |
| DMG | create-dmg 產製（背景圖 + Applications 捷徑），失敗時後備 hdiutil 純壓縮 |
| 產物 | `dist/macbar-0.3.1-arm64.dmg`（本機封裝與 GitHub 重新下載的 checksum、唯讀掛載及 App 內容驗證通過；688,443 bytes，SHA-256 見 `docs/ACCEPTANCE.md`） |
| App icon | 腳本產生：macOS 輪廓圓角方塊漸層底 + 白色喇叭符號，不精雕 |
| 介面語言 | 英文 |
| README / Release notes | English 先列，接著提供完整且逐項對應的台灣繁體中文；README 與 GitHub Release notes 一律維持此順序 |
| 開發工作流 | main 保持乾淨；開發一律在 `../macbar-wt/<branch>` worktree 進行，完成後 merge 回 main 並移除 worktree。實際編碼獨立交給 scoped、可控制的 agents（乾淨上下文、可 eval、可測試），merge 前必須通過驗收清單 |
| Git 身分 | fun-ed \<50657368+fun-ed@users.noreply.github.com\>（全域設定） |

## 輕量化介面（分階段）

- Stage 1：Popover 圖示使用靜態明暗，不再持續呼吸；移除 VU bar 的裝飾流光，保留真實 VU、漸層、既有版面、控制項與輔助使用設定。Mute 與音量 0% 的斜線圖示、mute 按鈕的紅色區別，以及使用者操作觸發的短暫 bounce 與設定值 spring 回饋維持不變。
- VU 只在 popover 開啟時量測，關閉即停止；逐 App mixer 與已套用 route 不受影響。
- Stage 2：VU level 發布頻率上限降至 2 Hz（每 500 ms）。每次符合發布間隔時，使用前次符合間隔後收到的 RMS 映射 level 最大值作為目標，避免短暫有聲被節流丟棄；這不是波形峰值，RMS 映射不變。視窗消耗後與 reset 時清除累積值。
- Attack 立即跟上較高目標；release 保留 0.12 秒時間常數，以 `target + (previous - target) * exp(-dt / releaseTime)` 向較低目標衰減。僅在視窗目標為零且衰減值低於 0.015 時歸零。抑制初始與持續靜音的重複零值發布，保留首次歸零、重複正值、靜音後恢復有聲、節流時間記帳與 reset 後更新。
- 音訊格式、sample rate、RMS 取樣與映射、VU 靈敏度、音訊 callback、音訊引擎、route、250 ms route health timer、App discovery 與 UI 音量／mute 輸入行為不變。
- 歷史驗證紀錄（15 Hz 階段，parent 實測；不是 500 ms 版本的驗證）：`swift test` 全部 25 項通過（新增 4 項 LevelMeter + 既有 21 項）；`Scripts/make-app.sh` release app 建置、arm64、strict codesign 與 diff check 通過。同一 no-capture/no-route harness 的 animation-only A/B CPU 為 visible-no-capture 20 秒舊版 5.101%、新版 0.282%，hidden-no-route 60 秒舊版 4.423%、新版 0.277%；包含未變動的 AppAudioController timer/discovery，未擷取音訊、未調整音量，也未量測 active routes，不得推論實際 active-route CPU。該階段未重新驗證 live VU、active route、人工 TCC、舊版 OS 與 release DMG；最終 500 ms 版本的證據另列於下方，不由此歷史紀錄推定。

## 版本歷史
### v0.3.1 輕量化介面（2026-10-23，已發佈）

- 移除 popover 圖示呼吸與 bar 流光，保留靜態 mute 區別、真實 VU 與原有控制。VU 只在 popover 開啟時運作；滑桿與 mute 操作仍即時生效。
- VU 最多每 500 ms 發布一次（2 Hz），取前次符合發布間隔後收到的 RMS 映射 level 最大值，不是波形峰值。保留快速 attack 與時間式 release；消耗視窗或 reset 後清除累積值，抑制重複零值並保留有聲轉無聲的首次歸零。
- 音訊 sample rate、capture callbacks、RMS stride／映射／靈敏度、逐 App routes 與 250 ms health／discovery timer 不變。不新增相依或 TCC 用途。
- 上方 animation-only、無擷取與無 route 的同條件 A/B 為歷史 15 Hz 階段量測，不是最終 500 ms VU 版本的 A/B。最終 500 ms release App 另以啟動起即隱藏、no-capture／no-route 狀態執行 60.029 秒，消耗 0.212036 CPU 秒，平均單核心 CPU 為 0.353%，App 持續存活且低於 1% 目標。此為獨立背景執行，不是配對 A/B，也不是 live VU 或 active-route CPU 量測，不保證實際音訊使用時的 CPU。
- 版本資訊為 `CFBundleShortVersionString` 0.3.1、`CFBundleVersion` 9。2026-10-23 `swift test` 全部 29 項通過（8 項 LevelMeter XCTest + 既有 21 項）；release build、arm64、strict codesign 與獨立程式碼快照複審 PASS。
- `Scripts/smoke-coreaudio.swift` 7/7 PASS，輸出音量與 mute 原值已還原。`dist/macbar-0.3.1-arm64.dmg` 因 create-dmg 簽章身分不可用，經既有 hdiutil 後備成功產製；唯讀掛載、Applications 捷徑指向 `/Applications`、掛載 App 的 0.3.1 / build 9 與簽章均 PASS，完整 App 檔案 SHA manifest 與 build 逐位元組一致。大小與 SHA-256 見 `docs/ACCEPTANCE.md`。
- 使用者在得知 29 項測試、7 項 smoke 與 DMG 驗證通過，以及缺少最終 500 ms 人工觀察與完整矩陣後，於 2026-10-23 明確選擇「保留未驗項，正式發佈」。本版 live VU、逐 App／生命週期人工操作、完整 TCC、macOS 13 / 14.3、Boom3D 與硬體矩陣仍未驗，人工驗收予以豁免，不標成 PASS。
- [GitHub Release](https://github.com/fun-ed/macbar/releases/tag/v0.3.1) 於 2026-10-23T05:31:08Z 正式發佈，非 draft／prerelease；v0.3.1 tag 固定指向 release merge commit `38cbfb106dce4fa2fb4c8ac451354e53c8377b29`，實作 commit `3f61eff` 可由此到達。遠端 notes 讀回與已審閱的完整 English、台灣繁體中文內容一致。重新下載 asset 的 SHA-256 與本機產物一致，唯讀掛載後版本、strict 簽章、Applications 捷徑與完整 App 檔案 SHA manifest 均 PASS。
- 維持 ad-hoc、未 notarized；未新增 live VU 或 active-route CPU 量測。已安裝的 `/Applications/macbar.app` 未動。回退時重新安裝 v0.3.0 的既有 release asset，不移動或覆寫舊 tag。


### v0.3.0 逐 App 音量控制（2026-10-12）

- 在既有喇叭與麥克風控制下新增 Applications 清單，每個輸出音訊的 App 有名稱、音量滑桿、百分比與 mute 按鈕。同一外層 App 的 helper processes 共用控制，排除 macbar 自己。
- macOS 14.4+ 使用原生 CoreAudio process tap 擷取指定 App 音訊，套用 0–100% 增益後送到目前的預設輸出。不裝第三方驅動、不加相依、不錄音、不存檔、不擷取麥克風；沿用 v0.2.0 已批准的系統音訊存取，不新增權限。
- 逐 App 路由獨立於 VU 量測。Popover 關閉後 VU monitor 停止，mixer 與已套用 route 繼續運作。逐 App 音量及 mute 只保留在本次執行期間，不寫 UserDefaults。
- 100% 且未靜音時使用原始輸出，不建立 route。Mute 保留滑桿設定，解除後恢復；調整滑桿解除 mute。
- Route 啟動先使用不抑制原始播放的 probe，確認 tap callback 有效且收到非靜音 signal 後，才換成 `mutedWhenTapped` 的正式 route。失敗時釋放資源、恢復原始播放並顯示錯誤，不顯示成功控制的假狀態。
- 不變更系統預設輸出、不影響未選取的 App、不擷取麥克風。換預設輸出、process 結束或 App 退出時釋放 IOProc、aggregate device 與 tap；換裝置後在支援的輸出上重新套用設定。
- 逐 App 路由支援單一實體 subdevice、單一 Float32 輸出 stream（1–32 聲道）與一個附加的 stereo Float32 tap。依 SDK 的 full subdevice UID 順序、active subdevice、stream 起始聲道、格式及 buffer configuration 驗證 aggregate：實體輸入 stream 必須複製為連續 prefix，附加 tap 的邏輯起始聲道不得與 prefix 重疊，但允許 HAL 在兩者間保留 logical channel gap；callback 的實際 BufferList offset 只依已驗證的實體 buffer prefix 計算，不由 tap 的 logical StartingChannel 推導。不要求複製後的 stream ID 相同；實體輸入必須停用並讀回確認，callback 一律忽略實體輸入 prefix，不檢查或讀取其資料指標與內容，因為 HAL 可能保留已停用輸入的配置緩衝區。
- Stereo tap 依實體輸出的 PreferredChannelsForStereo 寫入 L/R，缺少此屬性時使用前兩聲道；mono 平均 L/R，其餘輸出聲道每次 callback 歸零。輸出與 tap 必須是相同 sample rate；無法確認 topology 或聲道對應無效時安全拒絕，不改變預設輸出或系統音量。
- macOS 13–14.3 顯示需要 macOS 14.4 的說明；沒有輸出 App 時顯示空狀態。權限拒絕、格式不支援或路由失敗時顯示錯誤並釋放 tap，恢復原始播放，不顯示成功控制的假狀態。macOS 13 / 14.3 與完整 TCC 拒絕／撤銷矩陣尚未完成人工實機驗證。
- 曾觀察到 Boom3D 啟用時 Firefox 的 process audio 資訊缺失，停用 Boom、改用內建輸出並重新播放後 Firefox 出現。原因未定，Boom3D 完整相容性未驗證且不保證支援。
- 發佈範圍保留既有系統音量、mute、VU、登入啟動與 icon 行為；修改限於逐 App 控制器、路由、UI、打包版本資訊與文件。
- 驗證：21 項 unit tests、release build、arm64、ad-hoc 簽章、7/7 CoreAudio smoke 與正式 DMG 掛載驗證通過。Firefox + afplay 在內建輸出的逐 App route、gain/mute/restore、主音量不變與清理通過；使用者確認 Firefox 的音量與 mute 正常。完整人工矩陣與未驗項見 `docs/ACCEPTANCE.md`，不將未驗項標成通過。


### v0.2.0（2026-09-02 已發佈）

- 真實聲音 VU 表：popover 的 level bar 改由實際 loudness 驅動（有聲音才動，無聲歸零），取代純設定值模式
  - Mic 端：AVAudioEngine input tap → RMS；首次啟動觸發 TCC 麥克風權限（Info.plist 加 `NSMicrophoneUsageDescription`）— **使用者已拍板接受打破「無 TCC」禁區**
  - 喇叭端：CoreAudio process tap（`AudioHardwareCreateProcessTap`，macOS 14.4+），系統首次會跳同意對話框；macOS 13/14.3 無此 API
  - 權限被拒或系統不支援 → level bar 退回「設定值」模式（v0.1.1 行為），不 crash
  - tap 只在 popover 開啟期間運作，關閉即停（省電）

### v0.1.1（2026-09-02）

- Menubar icon 與 popover 圖示改為「靜音態」語意：mute **或** 音量 0% 都顯示斜線圖示（`speaker.slash` / `mic.slash`），不再讓人誤判為有聲（mic 狀態仍優先）
- Popover 圖示動畫：有聲時 icon 以呼吸明暗循環（TimelineView 驅動，不依賴 SF Symbol variable layers，speaker 與 mic 都會動）；mute 切換時 bounce（macOS 14+，舊版自動停用）
- 滑桿下方新增實際音量 animation bar：填充寬度即時對應目前音量，有聲時跑流光（shimmer）動畫；0%/mute 時停止並熄滅
- Popover 開啟（focus 在 app）時按 **Cmd+Q** 可直接退出

### v0.1.0（2026-09-01）

範圍：上表全部。

## 不做（範圍外）

- 裝置選擇器／多裝置管理
- 全域快捷鍵
- 錄音／聲音預覽播放。逐 App 音量控制允許即時音訊擷取、增益處理與重新播放，不寫入錄音檔。
- Developer ID 簽章與 notarization
- 自動更新、多國語系

## 實作備註

- 純 SwiftPM，無 .xcodeproj；`swift build -c release` 產出執行檔後由腳本組 `.app`。
- CoreAudio：`kAudioDevicePropertyVolumeScalar`（主元素優先，否則寫入所有有此屬性的聲道）、`kAudioDevicePropertyMute`；監聽 `kAudioHardwarePropertyDefaultOutputDevice` / `kAudioHardwarePropertyDefaultInputDevice` 換裝置即時跟隨。
- Swift 語言模式固定 5，避開 CoreAudio 回呼與 Swift 6 strict concurrency 的摩擦。

## 驗收清單

### v0.3.1 目前驗收（2026-10-23，機器 PASS；人工未驗，使用者明確豁免）

- [x] 最終 500 ms 版本 `swift test`：29/29 PASS（8 項 LevelMeter XCTest + 既有 21 項）
- [x] `Scripts/make-app.sh` release build、arm64 與 `codesign --verify --strict` PASS
- [x] App 版本 0.3.1 / build 9；`dist/macbar-0.3.1-arm64.dmg` 唯讀掛載、Applications 捷徑、完整 App 檔案 SHA manifest 與 build 一致及簽章 PASS
- [x] CoreAudio smoke 7/7 PASS，輸出音量／mute 原值已還原
- [x] 獨立程式碼快照複審 PASS
- [x] 最終 500 ms release App 背景執行 60.029 秒，啟動起即隱藏、no-capture／no-route；0.212036 CPU 秒，平均單核心 CPU 0.353%，持續存活且低於 1% 目標（獨立執行，非配對 A/B、live VU 或 active-route 量測）
- [ ] 靜態 mute 區別、滑桿／mute 即時生效、開啟時真實 VU、短暫訊號與停止歸零、關閉再開啟無殘留峰值（未驗，使用者於 2026-10-23 明確豁免）
- [ ] 逐 App gain／mute、popover 關閉後 route 持續、程序／裝置切換與退出 cleanup（本版人工未驗，同日豁免）
- [ ] 人工 TCC、macOS 13 / 14.3 fallback、Boom3D 與硬體矩陣（未重跑，同日豁免；不標 PASS）
- [x] GitHub Release 已正式發佈，v0.3.1 tag 固定指向 `38cbfb106dce4fa2fb4c8ac451354e53c8377b29`；重新下載 asset 的 SHA-256 與本機產物一致，唯讀掛載、版本／strict 簽章、Applications 捷徑與完整 App 檔案 SHA manifest 均 PASS

### 歷史驗收清單（v0.3.0，不代表 v0.3.1 已通過）

- [x] `swift build -c release` 通過
- [x] macbar.app 結構完整（Info.plist、AppIcon.icns、arm64 執行檔）
- [x] ad-hoc 簽章通過 `codesign --verify`
- [x] DMG 掛載後可見 macbar.app 與 Applications 捷徑
- [ ] App 可啟動、出現在 menubar、可 Quit
- [ ] 滑桿拖曳即時改變系統音量；mute 按鈕切換系統 mute
- [ ] 換預設裝置後控制對象自動跟隨
- [x] v0.3.0 `CFBundleShortVersionString` 0.3.0、`CFBundleVersion` 8，DMG 路徑為 `dist/macbar-0.3.0-arm64.dmg`
- [ ] 逐 App 兩個不同 App 同播、gain/mute、主音量不變、popover 關閉後 route 及程序／裝置退出 cleanup
- [ ] 系統音訊權限拒絕／撤銷、未播放與 Retry、不支援 output topology 的安全降級
- [ ] macOS 13 / 14.3 fallback、native output 拓樸與 Boom3D 觀察結果逐項記錄；目前未驗項不得標成通過