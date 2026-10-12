# Review / Eval / Test 準則

## Review 分級

| 改動類型 | 等級 | 要求 |
|---|---|---|
| Leaf（UI 文案、icon、腳本微調） | 輕 | agent 自檢 + 建置通過即可 |
| Core（AudioController、listener 生命週期、打包腳本） | 重 | 必須第二個獨立 agent 複審 + 全套驗證 |

## Eval（機器可驗）

```bash
swift build -c release                 # 0 錯誤
file build/macbar.app/Contents/MacOS/macbar   # 必須 arm64
codesign --verify --strict build/macbar.app   # 簽章通過
swift Scripts/smoke-coreaudio.swift    # CoreAudio 活體煙囪（set/get/mute/restore，7 項）
hdiutil attach dist/*.dmg -mountpoint /tmp/macbar-mnt -readonly -nobrowse
ls /tmp/macbar-mnt/                            # macbar.app + Applications
codesign --verify --strict /tmp/macbar-mnt/macbar.app
hdiutil detach /tmp/macbar-mnt -quiet
```

全數通過才算 eval 完成。任何一項失敗 = 不予 merge。

## Test（人工煙囪測試，merge 前逐條勾）

1. `open build/macbar.app` → menubar 出現喇叭圖示
2. 左鍵 popover：系統喇叭、麥克風兩條滑桿、百分比、mute 按鈕及 VU bar
3. 拖系統滑桿 → 對照系統設定確認裝置音量變化
4. mic mute 按鈕 → 系統麥克風輸入靜音、icon 變 `mic.slash`
5. speaker mute → `speaker.slash`；兩者皆 mute → 顯示 `mic.slash`（mic 優先）
6. icon 上滾輪 → 喇叭音量增減
7. 系統偏好切換預設輸出 → 系統控制對象自動跟隨
8. 右鍵 → Launch at Login 可開關；Quit 可退出
9. 無 mute 屬性的裝置 → mute 走音量 0，解除後音量還原
10. 播放音樂 → speaker level bar 隨實際聲音起伏，停止後歸零（v0.2.0）
11. 對麥克風說話 → mic level bar 跟動（v0.2.0）
12. 拒絕麥克風／系統音訊授權 → VU bar 退回設定值模式，不 crash（v0.2.0）

## v0.3.0 逐 App 音量驗證清單

### 正常操作

- [ ] 在 macOS 14.4+ 以兩個不同 App（包含 Firefox）同時播放；兩個 App 都出現在清單，macbar 自己不出現。
- [ ] 將 App A 調低音量或 mute，確認 App B 繼續播放、A 只影響自己的聲音，系統主音量與預設輸出不變。
- [ ] 解除 mute 後恢復滑桿設定；拖曳滑桿會解除 mute。
- [ ] 設為 100% 且未 mute 時顯示 Original output；改回低於 100% 後 route 才會套用。重新啟動 macbar 後逐 App 設定回到預設值。
- [ ] 同一 App 的 helper processes 共用一列控制，無關 App 不被合併。

### 權限與錯誤

- [ ] 首次允許系統音訊存取，播放目標音訊後確認 probe 通過並顯示 route 已套用。
- [ ] 拒絕或撤銷系統音訊存取時確認 route 顯示未套用錯誤，不顯示成功狀態；重新允許、播放音訊後按 Retry。
- [ ] 未播放音訊時 route 不會提前顯示已套用；開始播放後按 Retry 可重新驗證。
- [ ] 不支援的輸出 stream、buffer layout、channel map 或 sample rate 顯示未套用錯誤，原始音訊可播放。

### 生命週期

- [ ] 逐 App route 啟用後關閉 popover，確認 route 仍持續；VU meter 停止。
- [ ] 退出目標 App 後確認 route 停止，原始輸出沒有殘留 mute 或重複播放。
- [ ] 切換預設輸出後確認舊 route 清理、新輸出重新套用；系統主音量維持原值。
- [ ] 退出 macbar 後確認 route 與 VU 都停止，目標 App 音訊恢復原始播放。

### 原生輸出、Firefox 與 Boom3D

- [ ] 在內建輸出測試 Firefox 與另一個原生 macOS 音訊來源同時播放，記錄 App list、增益、mute、恢復與主音量。
- [ ] 在原生輸出裝置上記錄實際 stream 數、Float32 格式、聲道數、PreferredChannelsForStereo 與 sample rate；測試拒絕 unsupported topology 的安全路徑。
- [ ] 在 Boom3D 開啟與關閉時各測一次 Firefox process discovery，記錄輸出裝置及結果。Boom3D 完整相容性尚未驗證，不得將單次觀察寫成全面支援或驅動不相容結論。
- [ ] macOS 13 / 14.3 顯示逐 App 不支援說明；這些 OS 版本的人工實機驗證尚待執行。
- [ ] 記錄實際操作者、macOS 版本、輸出裝置與每個未通過／未執行項目原因。

## Eval 記錄

每次 merge 前在 PR/commit 描述貼上：機器可驗輸出（上述指令輸出摘要）+ 人工清單勾選結果。缺項不得 merge。