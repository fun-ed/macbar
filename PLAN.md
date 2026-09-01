# macbar — macOS menubar 音量控制器

> 本檔是本專案的單一事實來源（SOT）。任何行為、範圍、打包方式的變更，先改這裡再改程式。

- 版本：v0.1.0
- 定案日期：2026-09-01
- 決策過程：grilling 訪談 14 題（Q1–Q14），全數由使用者拍板

## 決策總表

| 決策點 | 結論 |
|---|---|
| 技術棧 | Swift 原生，SwiftPM 管理，UI 用 SwiftUI（狀態列容器用 NSStatusItem + NSPopover，因為需要 icon 滾輪與右鍵選單的完整控制權） |
| 平台 | arm64-only，最低 macOS 13（Ventura） |
| App 形態 | LSUIElement（無 Dock 圖示），常駐 menubar |
| 權限 | v0.1 無 TCC；v0.2.0 起拍板引入：麥克風 TCC（AVAudioEngine 量測）+ 系統音訊 capture（process tap），任一被拒即退回設定值模式 |
| 控制範圍 | 只跟隨系統預設輸出（喇叭）與預設輸入（麥克風），換裝置自動跟隨 |
| Popover | 喇叭、麥克風各一條滑桿 + mute 按鈕 + 百分比，拖曳即時生效 |
| Icon 滾輪 | 在 menubar 圖示上滾動 = 調整喇叭音量 |
| Icon 狀態 | 平時 `speaker.wave.2.fill`；喇叭 mute → `speaker.slash.fill`；麥克風 mute → `mic.slash.fill`（mic 狀態優先顯示） |
| 右鍵選單 | Launch at Login（SMAppService）、Quit |
| Mute 後備行為 | 裝置不支援硬體 mute 屬性時，改用「音量歸 0 + 軟體旗標」，解除 mute 時還原 mute 前音量（前值存 UserDefaults） |
| 持久化 | UserDefaults：軟體 mute 旗標、mute 前音量 |
| 簽章 | ad-hoc（無開發者帳號；首次開啟需右鍵「打開」） |
| DMG | create-dmg 產製（背景圖 + Applications 捷徑），失敗時後備 hdiutil 純壓縮 |
| 產物 | `dist/macbar-0.1.0-arm64.dmg` |
| App icon | 腳本產生：macOS 輪廓圓角方塊漸層底 + 白色喇叭符號，不精雕 |
| 介面語言 | 英文 |
| 開發工作流 | main 保持乾淨；開發一律在 `../macbar-wt/<branch>` worktree 進行，完成後 merge 回 main 並移除 worktree。實際編碼獨立交給 scoped、可控制的 agents（乾淨上下文、可 eval、可測試），merge 前必須通過驗收清單 |
| Git 身分 | fun-ed \<50657368+fun-ed@users.noreply.github.com\>（全域設定） |

## 版本歷史

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
- 錄音／聲音預覽播放（v0.2.0 已引入僅量測電平的 VU 表，不錄音不播放）
- Developer ID 簽章與 notarization
- 自動更新、多國語系

## 實作備註

- 純 SwiftPM，無 .xcodeproj；`swift build -c release` 產出執行檔後由腳本組 `.app`。
- CoreAudio：`kAudioDevicePropertyVolumeScalar`（主元素優先，否則寫入所有有此屬性的聲道）、`kAudioDevicePropertyMute`；監聽 `kAudioHardwarePropertyDefaultOutputDevice` / `kAudioHardwarePropertyDefaultInputDevice` 換裝置即時跟隨。
- Swift 語言模式固定 5，避開 CoreAudio 回呼與 Swift 6 strict concurrency 的摩擦。

## 驗收清單

- [ ] `swift build -c release` 通過
- [ ] macbar.app 結構完整（Info.plist、AppIcon.icns、arm64 執行檔）
- [ ] ad-hoc 簽章通過 `codesign --verify`
- [ ] DMG 掛載後可見 macbar.app 與 Applications 捷徑
- [ ] App 可啟動、出現在 menubar、可 Quit
- [ ] 滑桿拖曳即時改變系統音量；mute 按鈕切換系統 mute
- [ ] 換預設裝置後控制對象自動跟隨