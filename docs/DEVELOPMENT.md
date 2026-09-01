# 開發準則

## 環境

- macOS 13+（開發機 15.x），Apple Silicon only（arm64）
- Xcode toolchain（Swift 6.x compiler、Swift 語言模式 5）
- 純 SwiftPM，無 .xcodeproj，無第三方相依

## 架構與檔案職責

```
Sources/macbar/
  main.swift              NSApplication bootstrap、activation policy .accessory
  AppDelegate.swift       NSStatusItem、NSPopover、滾輪/鍵盤監聽、右鍵選單、SMAppService、metering 開關
  AudioController.swift   CoreAudio：預設裝置解析、volume/mute 讀寫、監聽器、軟體 mute 後備、metering 狀態
  PopoverView.swift       SwiftUI popover（兩列滑桿 + VolumeLevelBar + 圖示動畫）
  LevelMeter.swift        RMS→dB 映射與 attack/release 平滑（thread-safe）
  MicLevelMonitor.swift   AVAudioEngine input tap（TCC 流程）
  OutputLevelMonitor.swift CoreAudio process tap + 私有 aggregate device（macOS 14.4+）
Scripts/
  make-icon.swift         產生 AppIcon.iconset（Bezier 繪製，不依賴外部素材）
  make-app.sh             swift build → 組 .app → Info.plist → ad-hoc codesign
  make-dmg.sh             create-dmg（失敗 fallback hdiutil UDZO）
  smoke-coreaudio.swift   CoreAudio 活體煙囪測試（eval 用）
```

## CoreAudio 規則

- 音量：`kAudioDevicePropertyVolumeScalar`。先試主元素（`kAudioObjectPropertyElementMain`），不存在則對所有有此屬性的聲道（1...32）寫入；讀值取聲道平均。
- Mute：`kAudioDevicePropertyMute`（主元素）。裝置不支援時走軟體路徑：旗標存 UserDefaults（`softwareMuted.<out|in>`），mute 前音量存 `preMuteVolume.<out|in>`，歸 0，解除時還原。
- 監聽：系統物件的 `kAudioHardwarePropertyDefaultOutputDevice` / `DefaultInputDevice` 換裝置即重註冊 listener；裝置屬性 listener 用 wildcard scope + wildcard element。
- CoreAudio 回呼只做 `DispatchQueue.main.async` 後改 `@Published`，不碰 UI。
- Swift 語言模式固定 5（Package.swift `swift-tools-version:5.9`），不要升到 6 的 strict concurrency。

## 禁止事項

- 新增 TCC / audio capture 類權限前，先在 PLAN.md 拍板（v0.2.0 已引入 mic TCC 與 system audio capture，皆為量測電平、不錄音）
- 不加沙盒 entitlements
- 不引入 SPM 第三方依賴
- 不改 main 直接 commit 功能程式碼（走 worktree）

## 建置

```bash
swift build -c release        # 純建置
./Scripts/make-app.sh         # 組 .app + icon + ad-hoc 簽章
./Scripts/make-dmg.sh         # 產 dist/macbar-0.1.0-arm64.dmg
```