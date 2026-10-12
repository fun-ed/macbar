# macbar — macOS menubar 音量控制器

> 本檔是本專案的單一事實來源（SOT）。任何行為、範圍、打包方式的變更，先改這裡再改程式。

- 版本：v0.3.0
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
| 產物 | `dist/macbar-0.3.0-arm64.dmg` |
| App icon | 腳本產生：macOS 輪廓圓角方塊漸層底 + 白色喇叭符號，不精雕 |
| 介面語言 | 英文 |
| 開發工作流 | main 保持乾淨；開發一律在 `../macbar-wt/<branch>` worktree 進行，完成後 merge 回 main 並移除 worktree。實際編碼獨立交給 scoped、可控制的 agents（乾淨上下文、可 eval、可測試），merge 前必須通過驗收清單 |
| Git 身分 | fun-ed \<50657368+fun-ed@users.noreply.github.com\>（全域設定） |

## 版本歷史

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