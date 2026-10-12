# Changelog

## v0.3.0 (2026-10-12)

### English

- Added per-app output volume and mute controls. The list groups audio-producing apps; helper processes belonging to the same app share controls. macbar itself is excluded.
- Per-app routes are created only when volume is below 100% or mute is enabled. At 100% and unmuted, audio uses the original output. Per-app settings last only for the current session, are not written to UserDefaults, and do not change system master volume or the default output.
- On macOS 14.4+, a CoreAudio process tap, private aggregate device, and IOProc apply gain in real time before sending audio to the current default output. Audio is processed in memory only: it is not recorded, saved, or captured from the microphone.
- Closing the popover stops only VU metering; the per-app mixer and active routes continue running. Routes stop and resources are released when the default output changes, a process ends, or macbar quits.
- Before creating a route, macbar validates audio access and the buffer signal, then switches to the formal route that suppresses original playback. Format, topology, permission, or startup failures are shown as unapplied, with an error and Retry.
- Supported routing is limited to one physical subdevice, one Float32 output stream with 1–32 channels, one stereo Float32 process tap, and a matching sample rate. Unsupported output topologies do not get a route. Full Boom3D compatibility is unverified and not guaranteed; per-app volume is unavailable on macOS 13 and 14.3.
- Version: `CFBundleShortVersionString` 0.3.0, `CFBundleVersion` 8; DMG: `macbar-0.3.0-arm64.dmg`.

### 台灣繁體中文

- 新增逐 App 輸出音量與 mute。清單依正在輸出音訊的 App 分組，同一 App 的 helper processes 共用一組控制；排除 macbar 自身。
- 只有音量低於 100% 或已 mute 時才建立逐 App route。100% 且未 mute 時使用原始輸出。逐 App 設定只保留在本次執行期間，不寫入 UserDefaults，也不改系統主音量或預設輸出。
- macOS 14.4+ 使用 CoreAudio process tap、private aggregate device 與 IOProc 即時套用增益，再送至目前的預設輸出。音訊只在記憶體中即時處理，不錄音、不存檔，也不擷取麥克風。
- Popover 關閉後只停止 VU metering；逐 App mixer 及已套用的 route 繼續運作。換預設輸出、程序結束或 macbar 退出時會停止 route 並釋放資源。
- Route 建立前先驗證音訊存取與 buffer signal，再切換到抑制原始播放的正式 route。格式、拓樸、權限或啟動失敗時不顯示已套用狀態，並提供錯誤與 Retry。
- 支援範圍限於單一實體 subdevice、一條 1–32 聲道 Float32 輸出 stream、一個 stereo Float32 process tap，以及相同 sample rate。無法驗證的輸出拓樸不建立 route。Boom3D 完整相容性未驗證，不保證支援；macOS 13 與 14.3 無法使用逐 App 音量。
- 版本資訊：`CFBundleShortVersionString` 0.3.0、`CFBundleVersion` 8；DMG 為 `macbar-0.3.0-arm64.dmg`。

## v0.2.0（2026-09-02）

- 將 popover 的喇叭與麥克風 level bar 改為由實際輸出與輸入音訊驅動。
- 麥克風使用 AVAudioEngine input tap，首次使用會要求麥克風 TCC 授權。
- 喇叭使用 CoreAudio process tap；macOS 14.4+ 可讀取即時輸出電平。macOS 13、14.3 或授權遭拒時，level bar 退回設定值模式。
- VU tap 只在 popover 開啟期間運作。

## v0.1.1（2026-09-02）

- Mute 或音量 0% 時，menubar 與 popover 圖示顯示斜線狀態；麥克風狀態優先。
- 新增有聲時的圖示呼吸動畫、滑桿下方音量動畫，以及 mute 切換動畫。
- Popover 開啟時支援 Cmd+Q 退出。

## v0.1.0（2026-09-01）

- 初始版本：Swift 原生 menubar app，提供預設輸出與輸入音量、mute、音量百分比、裝置切換跟隨、icon 滾輪調整、Launch at Login 與 Quit。
- 無硬體 mute 的裝置使用軟體 mute，將音量設為 0 並在解除時還原。
- 使用 ad-hoc 簽章與 arm64 DMG；最低 macOS 13。
