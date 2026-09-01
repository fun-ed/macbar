---
name: Bug 回報
about: 回報 macbar 的錯誤行為
labels: bug
---

## 現象

<!-- 實際行為，一行講完 -->

## 重現步驟

1.
2.

## 期望行為

<!-- 對照 PLAN.md 的哪一條決策 -->

## 環境

- macOS 版本：
- 裝置（輸出/輸入）：

## 診斷資料

```text
log show --predicate 'process == "macbar"' --last 5m
```

## 驗收（修好怎麼驗）

- [ ] `swift build -c release` 通過
- [ ] `docs/REVIEW-TEST.md` 相關煙囪項目重跑通過