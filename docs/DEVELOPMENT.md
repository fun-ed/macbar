# 開發準則

## 環境

- macOS 13+、Apple Silicon only（arm64）
- Xcode toolchain（Swift 6.x compiler、Swift 語言模式 5）
- 純 SwiftPM，無 .xcodeproj，無第三方相依

## 架構與檔案職責

完整資料流與生命週期見 `docs/ARCHITECTURE.md`。

```text
Sources/macbar/
  main.swift                 NSApplication bootstrap、activation policy .accessory
  AppDelegate.swift          NSStatusItem、NSPopover、系統操作與兩種音訊控制器生命週期
  AudioController.swift      預設裝置、系統 volume/mute、listener、VU metering 狀態
  PopoverView.swift           系統音量列、VU bar、popover 內容
  AppAudioView.swift           Applications 清單、逐 App slider/mute/status/Retry
  LevelMeter.swift             RMS→dB 映射與 attack/release 平滑
  MicLevelMonitor.swift        AVAudioEngine input tap（麥克風 TCC）
  OutputLevelMonitor.swift     CoreAudio process tap + private aggregate（macOS 14.4+）
  AppAudioController.swift     App/process discovery、gain 狀態、route reconciliation 與 health poll
  AppAudioDiscovery.swift      CoreAudio process 查詢、app path/parent metadata 與 listener helper
  AppAudioState.swift           helper grouping、ephemeral gain、health 狀態、LIFO cleanup stack
  AppAudioRoute.swift           per-App process tap、aggregate、IOProc 建立及 route 清理
Sources/AppAudioRT/
  AppAudioRT.c                 C real-time callback、buffer/topology 驗證、atomic gain 與 stereo replay
  include/AppAudioRT.h         Swift 與 C 間的 callback API
Scripts/
  make-icon.swift              產生 AppIcon.iconset
  make-app.sh                  swift build → .app → Info.plist（0.3.0 / build 8）→ ad-hoc codesign
  make-dmg.sh                  create-dmg（失敗 fallback hdiutil UDZO）
  smoke-coreaudio.swift        系統 CoreAudio 活體煙囪測試
```

## CoreAudio 規則

- 系統音量：`kAudioDevicePropertyVolumeScalar`。先試主元素（`kAudioObjectPropertyElementMain`），不存在則對所有有此屬性的聲道（1...32）寫入；讀值取聲道平均。
- 系統 mute：`kAudioDevicePropertyMute`（主元素）。裝置不支援時走軟體路徑：旗標存 UserDefaults（`softwareMuted.<out|in>`），mute 前音量存 `preMuteVolume.<out|in>`，歸 0，解除時還原。
- 系統控制器監聽 `kAudioHardwarePropertyDefaultOutputDevice` / `DefaultInputDevice`，換裝置即重註冊 listener；裝置屬性 listener 用 wildcard scope + wildcard element。
- CoreAudio UI 狀態回呼只透過 `DispatchQueue.main.async` 更新 `@Published`，不直接碰 UI。
- Swift 語言模式固定 5（Package.swift `swift-tools-version:5.9`），不要升到 6 的 strict concurrency。

## 逐 App 音量控制

- `AppAudioController` 在 app 啟動時開始運作，不依賴 popover 是否開啟。它用 process-list、default-output 與程序／輸出 stream listener 追蹤變化，並以 250ms timer 檢查 route；約每秒刷新程序清單。
- `AppAudioDiscovery` 按外層 `.app` 路徑分組同一 App 的 helper processes，排除 macbar 自己。`AppAudioState` 的逐 App gain/mute 只存在記憶體；系統主音量控制是另一條路徑。
- 設定為 100% 且未 mute 時不建立 route。需要處理時先以原始播放不被抑制的 probe 建立 process tap，收到有效 callback 與非靜音 signal 後，才換成 `mutedWhenTapped` 正式 route。
- 正式 route 以 private aggregate 把 process stereo tap 接到當前實體輸出。僅接受單一實體 subdevice、單一 Float32 physical output stream（1–32 聲道）、一個 stereo Float32 tap，且 sample rate 相同。格式、active subdevice、stream 順序、StartingChannel 與 buffer layout 都必須通過驗證。
- Aggregate 中複製的實體 input prefix 必須停用並讀回確認。IOProc 依實際 buffer prefix 定位 tap data，完全忽略實體 input prefix 的指標與內容。Stereo output 使用裝置 PreferredChannelsForStereo；mono 取 L/R 平均，其餘聲道歸零。
- C callback 僅用 lock-free atomics 讀寫 gain/state，檢查有界 buffer 後套用增益。Callback fault、停滯、權限或格式錯誤會停止 route 並顯示未套用狀態與 Retry。
- Popover 關閉只停止 `MicLevelMonitor` 與 `OutputLevelMonitor`。已套用的 app route 持續運作；換輸出、程序停止或 app 結束時清理 IOProc、aggregate 與 tap。每次 HAL resource acquisition 都先登記逆向釋放，無法確認 callback 資源安全釋放時保留 context，避免 use-after-free。

## 權限與限制

- `PLAN.md` 已批准麥克風 TCC 供 VU 量測，以及系統音訊 process tap 供 VU 與 v0.3.0 逐 App 音量處理。新增權限用途前先更新 PLAN；不可加入未批准用途，不加 sandbox entitlements。
- 麥克風 VU 使用 `AVAudioEngine` input tap；輸出 VU 使用 `OutputLevelMonitor`。VU tap 只在 popover 開啟期間運作。
- 逐 App process tap 需要 macOS 14.4+。macOS 13 與 14.3 顯示不支援資訊；這些版本尚未完成人工實機驗證。
- Boom3D 完整相容性未驗證，不保證支援。曾觀察到啟用 Boom 時 Firefox 的 process audio 資訊缺失；切回內建輸出重播後 Firefox 出現，原因未定。
- 不支援的 output topology 拒絕建立 route，保留原始播放；這不表示裝置或驅動必然不相容。
- 不加沙盒 entitlements、不引入 SPM 第三方依賴、不改 main 直接 commit 功能程式碼（走 worktree）。

## 建置與封裝

```bash
swift build -c release        # 純建置
./Scripts/make-app.sh         # 組 .app + icon + ad-hoc 簽章
./Scripts/make-dmg.sh         # 產 dist/macbar-0.3.0-arm64.dmg
```

工作樹的 `build/macbar.app` 是測試用 app，不會取代 `/Applications/macbar.app`。ad-hoc 簽章 app 首次開啟需在 Finder 使用右鍵「打開」。