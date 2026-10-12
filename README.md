# macbar

macOS menubar 音量控制器：可即時調整預設輸出與輸入，也可獨立控制各 App 的輸出音量與 mute。支援 arm64（Apple Silicon）。

![](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![](https://img.shields.io/badge/arch-arm64-blue)

## 功能

- 常駐 menubar，popover 提供喇叭、麥克風系統音量與 mute、百分比及 VU bar
- Applications 清單依正在輸出音訊的 App 分組，提供各 App 輸出音量與 mute；同一 App 的 helper processes 共用控制，排除 macbar
- 系統音量、mute 與逐 App gain 各自運作；逐 App 控制不改系統主音量或預設輸出
- 逐 App 音量設為 100% 且未 mute 時使用原始輸出，不建立 route；其餘設定只存在本次執行期間
- Popover 關閉只停止 VU metering，不停止已套用的逐 App route。回復 100% 未 mute、程序停止或 macbar 退出時釋放 route；輸出裝置改變時會在新輸出重建 route 並重新驗證。
- 圖示上滾輪調整喇叭系統音量；有聲時圖示呼吸動畫、bar 有流光
- Mute 或音量 0% 顯示斜線 icon（麥克風狀態優先）
- 換預設裝置自動跟隨；右鍵選單提供 Launch at Login、Quit；popover 開啟時 Cmd+Q 可退出

## 權限

| 授權 | 用途 | 拒絕的後果 |
|---|---|---|
| 麥克風（TCC） | VU bar 量測輸入音量，不錄音 | 麥克風 bar 退回設定值模式 |
| 系統音訊存取（process tap） | VU bar 量測輸出；v0.3.0 起也用於即時逐 App 音量處理 | 喇叭 bar 退回設定值模式；逐 App route 顯示未套用錯誤，需允許權限並按 Retry |

- VU speaker tap 與逐 App 音量需要 macOS 14.4+。macOS 13 / 14.3 不支援逐 App 音量，speaker bar 走設定值模式。
- 若逐 App route 顯示系統音訊權限錯誤，先在「系統設定 → 隱私權與安全性」允許 macbar 的系統音訊存取，讓目標 App 播放音訊，再按 Retry。若出現輸出裝置、driver 或格式／拓樸錯誤，先切換到受支援的輸出後按 Retry。所有錯誤狀態都標示未套用；probe 驗證前維持原始播放。
- 逐 App tap 只在記憶體中即時處理，不錄音、不存檔，也不擷取麥克風。Boom3D 完整相容性尚未驗證，不保證支援。

## 安裝

Release asset：[`macbar-0.3.0-arm64.dmg`](https://github.com/fun-ed/macbar/releases/download/v0.3.0/macbar-0.3.0-arm64.dmg)。

1. 下載並掛載 DMG，把 **macbar.app** 拖進 **Applications**。
2. App 使用 ad-hoc 簽章，未經 notarization。若 Gatekeeper 阻擋，先嘗試開啟 app，再到「系統設定 → 隱私權與安全性」選擇 `Open Anyway`。確認下載來源可信後才允許開啟。
3. 首次使用麥克風 VU 或 process tap 時，依系統提示授權。逐 App 功能需要 macOS 14.4+。

從工作樹執行 `open build/macbar.app` 只會啟動該工作樹的測試版，不會取代 `/Applications/macbar.app`。要更新 Applications 中的版本，需把發布版 app 複製或拖入 Applications 並確認替換。

## 已知限制

- 逐 App route 只接受單一實體 subdevice、一條 1–32 聲道 Float32 輸出 stream、一個 stereo Float32 tap，且 sample rate 相同。其他 topology 會拒絕 route，原始輸出應保持可用。
- macOS 13 / 14.3 的逐 App 行為，以及系統音訊授權已允許後再撤銷的完整人工矩陣尚未驗證。Boom3D 完整相容性未驗證，不保證支援；目前觀察不足以判定其原因或相容程度。

## Build（本機）

需求：macOS 13+、Apple Silicon、Xcode 工具鏈（Swift 6 compiler）。

```bash
swift build -c release      # 純建置，產物 .build/release/macbar
./Scripts/make-app.sh       # 組 build/macbar.app（icon + Info.plist + ad-hoc 簽章）
./Scripts/make-dmg.sh       # 產 dist/macbar-0.3.0-arm64.dmg
open dist/macbar-0.3.0-arm64.dmg
```


## Debug

```bash
# app 是否活著
pgrep -x macbar

# app 日誌（啟動即退、listener 錯誤先看這裡）
log show --predicate 'process == "macbar"' --last 5m

# CoreAudio 活體煙囪測試（7 項，set/get/mute/restore）
swift Scripts/smoke-coreaudio.swift
```

VU 表不動？檢查「系統設定 → 隱私權與安全性 → 麥克風 / 系統音訊錄製」是否允許 macbar。
常見症狀對照表見 `docs/MAINTENANCE.md`（§疑難排解）。
滾輪方向若與預期相反：改 `Sources/macbar/AppDelegate.swift` 的 `handleScroll` 正負號。

## 開發

### 開發文件

| 文件 | 內容 |
|---|---|
| `PLAN.md` | 設計單一事實來源（SOT），決策總表 + 版本歷史 + 驗收清單 |
| `docs/ARCHITECTURE.md` | 模組職責、逐 App 音訊資料流、VU 與 mixer 生命週期 |
| `CHANGELOG.md` | 按版本整理的功能與支援邊界 |
| `docs/DEVELOPMENT.md` | 架構、CoreAudio 規則、建置 |
| `docs/MAINTENANCE.md` | 版本升級流程、已知邊界、疑難排解 |
| `docs/AI-DEVELOPMENT.md` | agent 開發約束與 DoD |
| `docs/REVIEW-TEST.md` | Review 分級、Eval/Test 清單 |
| `docs/ACCEPTANCE.md` | 驗收程序與證據格式 |
| `docs/PR-HANDOFF.md` | 分支、PR 必備內容、merge 規則 |

### Commit 與 Push 規則

- Conventional commits：`feat:` / `fix:` / `docs:` / `build:` / `chore:`
- **一律不加 Co-Authored-By 或任何 AI 產生標記**
- `git push` 需人類明確指示，不自動推
- 改行為先改 `PLAN.md`（SOT），程式跟著改

## 作者

fun-ed &lt;50657368+fun-ed@users.noreply.github.com&gt;

## License

[MIT](LICENSE)