# macbar

macOS menubar 音量控制器：即時調整系統**喇叭**與**麥克風**的音量與 mute，arm64（Apple Silicon）only。

![](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![](https://img.shields.io/badge/arch-arm64-blue)

## 功能

- 常駐 menubar，點開 popover：喇叭、麥克風各一條滑桿 + mute 按鈕 + 百分比，拖曳即時生效
- **即時 VU 表**：滑桿下的 level bar 由實際聲音驅動 — 有聲音才動、無聲歸零（v0.2.0）
- 圖示上滾輪 = 調喇叭音量；有聲時圖示呼吸動畫、bar 有流光
- 單一 icon 反映「靜音態」：mute **或** 音量 0% 都顯示斜線圖示（mic 狀態優先）
- 換預設裝置自動跟隨（CoreAudio 監聽）
- 不支援硬體 mute 的裝置：改用音量歸 0 + 軟體旗標，解除後還原
- 右鍵選單：Launch at Login、Quit；popover 開啟時 Cmd+Q 可退出
- Popover 開啟期間才跑 metering，關閉即停

## 權限（v0.2.0 起，首次開 popover 會遇到）

| 授權 | 用途 | 拒絕的後果 |
|---|---|---|
| 麥克風（TCC） | 量測即時輸入音量 | mic bar 退回「設定值」模式 |
| 系統音訊 capture（process tap） | 量測即時輸出音量 | speaker bar 退回「設定值」模式 |

- 完整 VU 表需要 **macOS 14.4+**（process tap）；macOS 13 / 14.3 的 speaker bar 走設定值模式
- 滑桿控制音量本身**不需要**任何權限

## 安裝（使用者）

1. 下載 `dist/macbar-0.1.0-arm64.dmg`
2. 掛載後把 **macbar.app** 拖進 **Applications**
3. ad-hoc 簽章：第一次開啟請對 app 按右鍵 →「打開」繞過 Gatekeeper

## Build（本機）

需求：macOS 13+、Apple Silicon、Xcode 工具鏈（Swift 6 compiler）。

```bash
swift build -c release      # 純建置，產物 .build/release/macbar
./Scripts/make-app.sh       # 組 build/macbar.app（icon + Info.plist + ad-hoc 簽章）
./Scripts/make-dmg.sh       # 產 dist/macbar-<ver>-arm64.dmg
open dist/macbar-0.1.0-arm64.dmg
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

| 文件 | 內容 |
|---|---|
| `PLAN.md` | 設計單一事實來源（SOT），決策總表 + 驗收清單 |
| `docs/DEVELOPMENT.md` | 架構、CoreAudio 規則、建置 |
| `docs/MAINTENANCE.md` | 版本升級流程、已知邊界、疑難排解 |
| `docs/AI-DEVELOPMENT.md` | agent 開發約束與 DoD |
| `docs/REVIEW-TEST.md` | Review 分級、Eval/Test 清單 |
| `docs/PR-HANDOFF.md` | 分支、PR 必備內容、merge 規則 |

工作流：`main` 保持乾淨，功能一律開 worktree（`../macbar-wt/<branch>`）→ branch `feat-*`/`fix-*`（從 `develop`）→ PR → merge。細節見 `docs/PR-HANDOFF.md`。

### Commit 與 Push 規則

- Conventional commits：`feat:` / `fix:` / `docs:` / `build:` / `chore:`
- **一律不加 Co-Authored-By 或任何 AI 產生標記**
- `git push` 需人類明確指示，不自動推
- 改行為先改 `PLAN.md`（SOT），程式跟著改

## 作者

fun-ed &lt;50657368+fun-ed@users.noreply.github.com&gt;

## License

[MIT](LICENSE)