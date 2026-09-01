---
name: 功能需求
about: 新功能或行為變更，給 scoped agent 派工用
labels: feature
---

## 目標

<!-- 一句話說完要做什麼 -->

## 動機

<!-- 為什麼現在需要；對照 PLAN.md 的哪個決策，是否要改 SOT -->

## 範圍

- 包含：
- 不做：

## 驗收

- [ ] `swift build -c release` 零錯誤零警告
- [ ] `./Scripts/make-app.sh` + `codesign --verify --strict` 通過
- [ ] `docs/REVIEW-TEST.md` 相關人工清單重跑通過
- [ ] `PLAN.md` 已更新（若有行為變更）

## 禁區提醒

不加 TCC、不加沙盒、不加第三方依賴、不動 main 直接開發。