# macbar 輕量化與低頻 VU 決策

更新日期：2026-10-23。對應 v0.3.1 / build 9；發佈狀態以 `PLAN.md` 與 GitHub Release 為準。

## 已批准的行為

- 輕量常駐優先於裝飾。Popover 圖示保持靜態，移除持續呼吸及音量條流光；保留真實 VU、滑桿、mute、百分比及靜音區別。
- VU 最多每 500 ms 發布一次，即 2 Hz。這只降低顯示值發布頻率，並非更改音訊 sample rate、RMS 取樣步距或小聲訊號門檻。滑桿與 mute 仍即時處理。
- 每個發布視窗累積收到的 RMS-mapped level 最大值，避免短音剛好落在節流期間而消失。這不是音訊波形峰值。發布後及 reset 時清除待發布值。
- Attack 立即跟上較高目標；release 使用 `target + (previous - target) * exp(-dt / releaseTime)`。時間常數保留 0.12 秒。舊公式在低頻更新時會讓高值長時間不下降，不可只把刷新間隔改大而保留反向衰減。
- 持續無聲時不重複發布零值，但由正值轉為零的首次更新必須送出。音量計的 reset 同時清除平滑、節流與待發布視窗狀態。
- 關閉 popover 停止 VU monitor，不停止已套用的逐 App route。250 ms route health timer 與 discovery 保留，不要把它當裝飾刷新率一起降頻。

## 診斷與驗證邊界

- `TimelineView` 在已隱藏的 NSPopover 中仍可能持續驅動 SwiftUI layout。不可只依視窗不可見便假設動畫已停止。
- 原版與僅移除裝飾的同條件測試，包含既有 discovery timer，但未啟動音訊擷取或逐 App route。這些數字不能推論實際音訊擷取或 active-route CPU。
- `LevelMeterTests` 使用明確的 `now` 測試 delivery closure，涵蓋 500 ms 節流、短音保留、視窗消耗、reset、靜音去重及停止有聲後歸零。2026-10-23 的 29 項單元測試已通過。
- 實際 VU 觀感、完整人工 TCC 矩陣、舊版 macOS 與 Boom3D 相容性不可由單元測試或無擷取 CPU 測試推定。

## 維護入口

- `PLAN.md` 是行為及範圍的單一事實來源；版本、changelog、README 與 GitHub Release 要同步。
- README、CHANGELOG 與 Release notes 先提供完整英文，再提供逐項對應的台灣繁體中文。
- 只提交整理後的記憶與本次規格；不提交 Serena cache、個人覆寫設定、憑證或原始對話。測試 app 不會自動取代 `/Applications/macbar.app`。
