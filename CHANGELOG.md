# Changelog

## v0.3.1 (2026-10-23)

### English

- Removed popover icon breathing and bar shimmer. Static muted-state distinctions and real VU metering remain; VU runs only while the popover is open. Slider and mute actions remain immediate.
- VU levels publish at most every 500 ms, or 2 Hz. Each eligible publication uses the maximum incoming RMS-mapped level since the previous eligible publication, not a waveform peak. Fast attack and time-based release remain. Consuming a window or resetting clears accumulated levels; repeated zero updates are suppressed without losing the first return to zero.
- Audio sample rate, capture callbacks, RMS stride, mapping and sensitivity, per-app routes, and the 250 ms health/discovery timer are unchanged. No new dependencies or TCC permissions are added.
- Earlier animation-only CPU measurements used the same setup without capture or routes, retaining the original discovery timer. Visible for 20 seconds: 5.101% before, 0.282% after. Hidden for 60 seconds: 4.423% before, 0.277% after. These are not measurements of the final 500 ms meter or active-route CPU, and do not guarantee a particular CPU level during audio use.
- Validated on 2026-10-23: all 29 tests passed, including 8 LevelMeter XCTests and 21 existing tests; release build, arm64, strict codesign, and independent code snapshot review passed. CoreAudio smoke passed 7/7, with output volume and mute restored.
- DMG packaging used the existing hdiutil fallback because the create-dmg signing identity was unavailable. Read-only mounting, the Applications symlink to `/Applications`, mounted app version and signature passed; the full app file SHA manifest was byte-for-byte identical to the build.
- After reviewing those results and the missing final 500 ms manual observations and full matrix, the user explicitly chose "保留未驗項，正式發佈" on 2026-10-23, authorizing formal publication with unverified items retained. This is a human waiver, not a manual PASS. Live VU, per-app route/lifecycle checks, full TCC, macOS 13 / 14.3, Boom3D, and the hardware matrix were not newly exercised; no new live-VU or active-route CPU measurements were taken.
- Ad-hoc signed, not notarized. The installed `/Applications/macbar.app` was left untouched. To roll back, reinstall the existing v0.3.0 release asset; its tag remains unchanged.
- Version: `CFBundleShortVersionString` 0.3.1, `CFBundleVersion` 9; DMG: `macbar-0.3.1-arm64.dmg`. Local asset size and SHA-256 are recorded in `docs/ACCEPTANCE.md`.

### 台灣繁體中文

- 移除 popover 圖示呼吸與 bar 流光。保留靜態 mute 狀態區別與真實 VU，VU 只在 popover 開啟時運作。滑桿與 mute 操作仍即時生效。
- VU level 最多每 500 ms 發布一次，也就是 2 Hz。每次符合發布間隔時，使用前次符合間隔後收到的 RMS 映射 level 最大值，不是波形峰值。保留快速 attack 與時間式 release。消耗視窗或 reset 後清除累積值；抑制重複零值更新，但保留首次歸零。
- 音訊 sample rate、capture callbacks、RMS stride、映射與靈敏度、逐 App routes 及 250 ms health／discovery timer 不變。不新增相依或 TCC 權限。
- 先前 animation-only CPU 量測使用相同環境，無擷取、無 route，保留原有 discovery timer。面板開啟 20 秒，修改前 5.101%、修改後 0.282%；隱藏 60 秒，修改前 4.423%、修改後 0.277%。這不是最終 500 ms meter 或 active-route CPU 的量測，不保證實際音訊使用時的 CPU 數值。
- 2026-10-23 驗證：29 項測試全數通過，包含 8 項 LevelMeter XCTest 與既有 21 項；release build、arm64、strict codesign 與獨立程式碼快照複審通過。CoreAudio smoke 7/7 通過，輸出音量與 mute 原值已還原。
- DMG 因 create-dmg 簽章身分不可用，使用既有 hdiutil 後備封裝。唯讀掛載、Applications 捷徑指向 `/Applications`、掛載 App 的版本與簽章均通過；完整 App 檔案 SHA manifest 與 build 逐位元組一致。
- 使用者在得知上述結果，以及缺少最終 500 ms 人工觀察與完整矩陣後，於 2026-10-23 明確選擇「保留未驗項，正式發佈」，同意保留未驗項並正式發佈。這是人工豁免，不是人工 PASS。本版 live VU、逐 App route／生命週期、完整 TCC、macOS 13 / 14.3、Boom3D 與硬體矩陣未新驗；未新增 live VU 或 active-route CPU 量測。
- 維持 ad-hoc 簽章，未 notarized。已安裝的 `/Applications/macbar.app` 未動。若需回退，重新安裝既有 v0.3.0 release asset，不變更其 tag。
- 版本資訊：`CFBundleShortVersionString` 0.3.1、`CFBundleVersion` 9；DMG 為 `macbar-0.3.1-arm64.dmg`。本機 asset 大小與 SHA-256 記錄於 `docs/ACCEPTANCE.md`。

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
