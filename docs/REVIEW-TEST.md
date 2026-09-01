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
hdiutil attach dist/*.dmg -mountpoint /tmp/macbar-mnt -readonly -nobrowse
ls /tmp/macbar-mnt/                            # macbar.app + Applications
codesign --verify --strict /tmp/macbar-mnt/macbar.app
hdiutil detach /tmp/macbar-mnt -quiet
```

全數通過才算 eval 完成。任何一項失敗 = 不予 merge。

## Test（人工煙囪測試，merge 前逐條勾）

1. `open build/macbar.app` → menubar 出現喇叭圖示
2. 左鍵 popover：兩條滑桿、百分比、mute 按鈕
3. 拖滑桿 → 系統音量即時變化（對照系統設定）
4. mic mute 按鈕 → 系統麥克風輸入靜音、icon 變 `mic.slash`
5. speaker mute → `speaker.slash`；兩者皆 mute → 顯示 `mic.slash`（mic 優先）
6. icon 上滾輪 → 喇叭音量增減
7. 系統偏好切換預設輸出 → 控制對象自動跟隨
8. 右鍵 → Launch at Login 可開關；Quit 可退出
9. 無 mute 屬性的裝置 → mute 走音量 0，解除後音量還原

## Eval 記錄

每次 merge 前在 PR/commit 描述貼上：機器可驗輸出（上述指令輸出摘要）+ 人工清單勾選結果。缺項不得 merge。