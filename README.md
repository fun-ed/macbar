# macbar

![](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![](https://img.shields.io/badge/arch-arm64-blue)

**Languages:** [English](#english) · [台灣繁體中文](#台灣繁體中文)

## English

macOS menu-bar volume controller: adjust the default output and input in real time, and independently control each app's output volume and mute. Supports arm64 (Apple Silicon).

### Features

- Lives in the menu bar. The popover provides speaker and microphone system volume and mute controls, percentages, and VU bars.
- The Applications list groups apps currently playing audio and provides per-app output volume and mute controls. Helper processes belonging to the same app share controls; macbar is excluded.
- System volume and mute are independent of per-app gain. Per-app controls do not change system master volume or the default output.
- At 100% and unmuted, an app uses the original output without creating a route. Other per-app settings last only for the current run.
- Closing the popover stops only VU metering, not an active per-app route. A route is released when volume returns to 100% unmuted, the process stops, or macbar quits. When the default output changes, macbar rebuilds and revalidates the route on the new output.
- Scroll over the menu-bar icon to adjust speaker system volume. Popover icons are static, with no breathing or bar shimmer; real VU bars remain.
- While the popover is open, VU levels publish at most every 500 ms, or 2 Hz. Each eligible publication uses the maximum incoming RMS-mapped level since the previous eligible publication, not a waveform peak. Fast attack and time-based release remain; reset clears accumulated levels, and repeated zero updates are suppressed.
- Slider and mute actions remain immediate. Audio sample rate, capture callbacks, RMS stride, mapping and sensitivity, per-app routes, and the 250 ms health/discovery timer are unchanged. No new dependencies or TCC permissions are added.
- Mute or 0% volume shows a slashed icon (microphone state takes precedence).
- Follows changes to the default device. The right-click menu provides Launch at Login and Quit; press Cmd+Q to quit while the popover is open.

### Permissions

| Permission | Purpose | If denied |
|---|---|---|
| Microphone (TCC) | Measures input volume for the VU bar; does not record audio | The microphone bar falls back to setting-based mode |
| System audio access (process tap) | Measures output for the VU bar; since v0.3.0, also enables real-time per-app volume processing | The speaker bar falls back to setting-based mode; a per-app route is marked unapplied with an error until access is allowed and Retry is pressed |

- The speaker VU tap and per-app volume require macOS 14.4+. Per-app volume is unavailable on macOS 13 and 14.3; the speaker bar uses setting-based mode there.
- If a per-app route reports a system audio permission error, allow macbar under **System Settings → Privacy & Security**, have the target app play audio, then press Retry. For output-device, driver, format, or topology errors, switch to a supported output and press Retry. Error states are always marked unapplied; original playback continues until the probe is validated.
- Per-app taps process audio in real time in memory only. They do not record or save audio and do not capture the microphone. Full Boom3D compatibility has not been verified and is not guaranteed.

### Installation

v0.3.1 / build 9; release asset: [`macbar-0.3.1-arm64.dmg`](https://github.com/fun-ed/macbar/releases/download/v0.3.1/macbar-0.3.1-arm64.dmg). See `PLAN.md` for current publication status.

Asset size: 688,443 bytes. SHA-256 of the locally verified DMG:

```text
7e6d2103d95cc7740a8f022a1735db84ccb87cb031c1cfd46c839066af9dd73a  macbar-0.3.1-arm64.dmg
```

1. Download and mount the DMG, then drag **macbar.app** into **Applications**.
2. The app is ad-hoc signed and not notarized. If Gatekeeper blocks it, first try opening the app, then choose `Open Anyway` under **System Settings → Privacy & Security**. Allow it only after confirming that you trust the download source.
3. Grant access when prompted the first time you use microphone VU metering or a process tap. Per-app volume requires macOS 14.4+.

Running `open build/macbar.app` from a worktree starts only that worktree's test build; it does not replace `/Applications/macbar.app`. To update the installed app, copy or drag the release app into Applications and confirm replacement.

To roll back, reinstall the asset from [v0.3.0](https://github.com/fun-ed/macbar/releases/tag/v0.3.0). The existing v0.3.0 tag remains unchanged.

### Known limitations

- A per-app route supports only one physical subdevice, one Float32 output stream with 1–32 channels, one stereo Float32 tap, and a matching sample rate. Other topologies are rejected, and the original output should remain available.
- Per-app behavior on macOS 13 / 14.3 and the complete manual matrix for revoking system audio access after it has been granted have not been verified. Full Boom3D compatibility is unverified and not guaranteed; current observations are insufficient to determine its cause or compatibility level.
- The macOS 13 / 14.3 fallback, full TCC, Boom3D, and hardware matrix have not been rerun for v0.3.1.

### Build (local)

Requirements: macOS 13+, Apple Silicon, and the Xcode toolchain (Swift 6 compiler). DMG packaging invokes `npx` through `mise exec --` and requires mise with Node.js/npm available.

```bash
swift build -c release      # pure build; output: .build/release/macbar
./Scripts/make-app.sh       # assemble build/macbar.app (icon + Info.plist + ad-hoc signature)
./Scripts/make-dmg.sh       # create dist/macbar-0.3.1-arm64.dmg
open dist/macbar-0.3.1-arm64.dmg
```

### Debug

```bash
# check whether the app is running
pgrep -x macbar

# app logs (check here first for immediate exit or listener errors)
log show --predicate 'process == "macbar"' --last 5m

# CoreAudio live smoke test (7 checks: set/get/mute/restore)
swift Scripts/smoke-coreaudio.swift
```

VU bars not moving? Check **System Settings → Privacy & Security → Microphone / System Audio Recording** and confirm macbar is allowed.
See `docs/MAINTENANCE.md` (§ troubleshooting) for common symptoms.
If the scroll direction is reversed, change the sign in `handleScroll` in `Sources/macbar/AppDelegate.swift`.

### Development

#### Development documents

| File | Contents |
|---|---|
| `PLAN.md` | Single source of truth (SOT): decision table, version history, and acceptance checklist |
| `docs/ARCHITECTURE.md` | Module responsibilities, per-app audio data flow, and VU/mixer lifecycle |
| `CHANGELOG.md` | Features and support boundaries by version |
| `docs/DEVELOPMENT.md` | Architecture, CoreAudio rules, and build instructions |
| `docs/MAINTENANCE.md` | Version upgrade process, known boundaries, and troubleshooting |
| `docs/AI-DEVELOPMENT.md` | Agent development constraints and definition of done |
| `docs/REVIEW-TEST.md` | Review levels and Eval/Test checklist |
| `docs/ACCEPTANCE.md` | Acceptance procedure and evidence format |
| `docs/PR-HANDOFF.md` | Branches, required PR contents, and merge rules |

#### Commit and push rules

- Conventional commits: `feat:` / `fix:` / `docs:` / `build:` / `chore:`
- Never add `Co-Authored-By` or any AI-generated marker.
- `git push` requires explicit human direction; never push automatically.
- Change behavior in `PLAN.md` (the SOT) first, then update the code.

### Author

fun-ed &lt;50657368+fun-ed@users.noreply.github.com&gt;

### License

[MIT](LICENSE)

## 台灣繁體中文

macOS 選單列音量控制器：可即時調整預設輸出與輸入，也可獨立控制各 App 的輸出音量與 mute。支援 arm64（Apple Silicon）。

### 功能

- 常駐選單列；popover 提供喇叭與麥克風系統音量、mute、百分比及 VU bar。
- Applications 清單依正在播放音訊的 App 分組，提供各 App 輸出音量與 mute；同一 App 的 helper processes 共用控制，排除 macbar。
- 系統音量與 mute 和逐 App gain 各自獨立；逐 App 控制不改系統主音量或預設輸出。
- 音量為 100% 且未 mute 時使用原始輸出，不建立 route；其他逐 App 設定只保留在本次執行期間。
- 關閉 popover 只會停止 VU metering，不會停止已套用的逐 App route。音量回到 100% 且未 mute、程序停止或 macbar 退出時會釋放 route。預設輸出改變時，會在新輸出重建 route 並重新驗證。
- 在選單列圖示上滾動可調整喇叭系統音量；popover 圖示使用靜態顯示，不再呼吸或顯示 bar 流光，保留真實 VU bar。
- Popover 開啟時，VU level 最多每 500 ms 發布一次，也就是 2 Hz。每次符合發布間隔時，使用前次符合間隔後收到的 RMS 映射 level 最大值，不是波形峰值。保留快速 attack 與時間式 release；reset 清除累積值，並抑制重複零值更新。
- 滑桿與 mute 操作仍即時生效。音訊 sample rate、capture callbacks、RMS stride、映射與靈敏度、逐 App routes 及 250 ms health／discovery timer 不變。不新增相依或 TCC 權限。
- Mute 或音量 0% 時顯示斜線圖示（麥克風狀態優先）。
- 自動跟隨預設裝置；右鍵選單提供 Launch at Login 與 Quit；popover 開啟時可按 Cmd+Q 退出。

### 權限

| 權限 | 用途 | 拒絕時的影響 |
|---|---|---|
| 麥克風（TCC） | 量測 VU bar 的輸入音量，不錄音 | 麥克風 bar 退回設定值模式 |
| 系統音訊存取（process tap） | 量測 VU bar 的輸出；自 v0.3.0 起也用於即時逐 App 音量處理 | 喇叭 bar 退回設定值模式；逐 App route 標示未套用並顯示錯誤，需允許權限後按 Retry |

- 喇叭 VU tap 與逐 App 音量需要 macOS 14.4+。macOS 13 與 14.3 無法使用逐 App 音量；喇叭 bar 在這些版本使用設定值模式。
- 若逐 App route 顯示系統音訊權限錯誤，請在「系統設定 → 隱私權與安全性」允許 macbar，讓目標 App 播放音訊，再按 Retry。若是輸出裝置、driver、格式或拓樸錯誤，請切換到支援的輸出後按 Retry。錯誤狀態一律標示為未套用；probe 驗證前會維持原始播放。
- 逐 App tap 只在記憶體中即時處理音訊，不錄音、不存檔，也不擷取麥克風。Boom3D 完整相容性尚未驗證，不保證支援。

### 安裝

v0.3.1 / build 9；release asset：[`macbar-0.3.1-arm64.dmg`](https://github.com/fun-ed/macbar/releases/download/v0.3.1/macbar-0.3.1-arm64.dmg)。目前發佈狀態見 `PLAN.md`。

Asset 大小：688,443 bytes。本機已驗證 DMG 的 SHA-256：

```text
7e6d2103d95cc7740a8f022a1735db84ccb87cb031c1cfd46c839066af9dd73a  macbar-0.3.1-arm64.dmg
```

1. 下載並掛載 DMG，將 **macbar.app** 拖入 **Applications**。
2. App 使用 ad-hoc 簽章，未經 notarization。若 Gatekeeper 阻擋，先嘗試開啟 app，再到「系統設定 → 隱私權與安全性」選擇 `Open Anyway`。確認信任下載來源後才允許開啟。
3. 首次使用麥克風 VU metering 或 process tap 時，依提示授權。逐 App 音量需要 macOS 14.4+。

從 worktree 執行 `open build/macbar.app` 只會啟動該 worktree 的測試版，不會取代 `/Applications/macbar.app`。要更新已安裝的 App，需把 release app 複製或拖入 Applications 並確認替換。

若需回退，請重新安裝 [v0.3.0](https://github.com/fun-ed/macbar/releases/tag/v0.3.0) 的 asset。既有 v0.3.0 tag 保持不變。

### 已知限制

- 逐 App route 僅支援單一實體 subdevice、一條 1–32 聲道 Float32 輸出 stream、一個 stereo Float32 tap，且 sample rate 相同。其他拓樸會拒絕 route，原始輸出應保持可用。
- macOS 13 / 14.3 的逐 App 行為，以及系統音訊存取已允許後再撤銷的完整人工測試矩陣尚未驗證。Boom3D 完整相容性未驗證且不保證支援；目前觀察不足以判定原因或相容程度。
- v0.3.1 尚未重跑 macOS 13 / 14.3 fallback、完整 TCC、Boom3D 與硬體矩陣。

### 本機建置

需求：macOS 13+、Apple Silicon、Xcode 工具鏈（Swift 6 compiler）。DMG 封裝透過 `mise exec --` 執行 `npx`，需要 mise 與可用的 Node.js/npm。

```bash
swift build -c release      # 純建置；產物：.build/release/macbar
./Scripts/make-app.sh       # 組成 build/macbar.app（icon + Info.plist + ad-hoc 簽章）
./Scripts/make-dmg.sh       # 產生 dist/macbar-0.3.1-arm64.dmg
open dist/macbar-0.3.1-arm64.dmg
```

### 除錯

```bash
# 確認 app 是否正在執行
pgrep -x macbar

# app 日誌（立即退出或 listener 錯誤時先查看）
log show --predicate 'process == "macbar"' --last 5m

# CoreAudio 即時 smoke test（7 項：set/get/mute/restore）
swift Scripts/smoke-coreaudio.swift
```

VU bar 沒有動？請檢查「系統設定 → 隱私權與安全性 → 麥克風 / 系統音訊錄製」是否允許 macbar。
常見症狀請參閱 `docs/MAINTENANCE.md`（§疑難排解）。
若滾輪方向相反，請修改 `Sources/macbar/AppDelegate.swift` 中 `handleScroll` 的正負號。

### 開發

#### 開發文件

| 文件 | 內容 |
|---|---|
| `PLAN.md` | 單一事實來源（SOT）：決策總表、版本歷史與驗收清單 |
| `docs/ARCHITECTURE.md` | 模組職責、逐 App 音訊資料流、VU 與 mixer 生命週期 |
| `CHANGELOG.md` | 按版本整理的功能與支援邊界 |
| `docs/DEVELOPMENT.md` | 架構、CoreAudio 規則與建置說明 |
| `docs/MAINTENANCE.md` | 版本升級流程、已知邊界與疑難排解 |
| `docs/AI-DEVELOPMENT.md` | agent 開發約束與完成定義 |
| `docs/REVIEW-TEST.md` | Review 分級與 Eval/Test 清單 |
| `docs/ACCEPTANCE.md` | 驗收程序與證據格式 |
| `docs/PR-HANDOFF.md` | 分支、PR 必備內容與 merge 規則 |

#### Commit 與 Push 規則

- Conventional commits：`feat:` / `fix:` / `docs:` / `build:` / `chore:`
- 一律不加 `Co-Authored-By` 或任何 AI 產生標記。
- `git push` 需人類明確指示，不自動推送。
- 改變行為前先修改 `PLAN.md`（SOT），再更新程式。

### 作者

fun-ed &lt;50657368+fun-ed@users.noreply.github.com&gt;

### 授權條款

[MIT](LICENSE)
