# 交接 PR 準則

## 分支與 worktree

- 預設整合分支是 `develop`；功能一律從 develop 開 `feat-v<version>`（或 `fix-<slug>`），對應 worktree `../macbar-wt/<branch>`，PR 回 develop，develop 穩定後再進 main 打 release。
- main 只放已發佈狀態；develop 是整合線。
- PR 建立後若已 merge：`git worktree remove` + 刪分支，main 保持乾淨。

## PR 必備內容

1. **對應 PLAN.md 條目**：本 PR 滿足／變更了哪些決策
2. **Diff 摘要**：改了哪些檔、為什麼
3. **Eval 證據**：`docs/REVIEW-TEST.md` 的機器可驗項目輸出
4. **Test 清單勾選**：人工驗證逐項結果
5. **風險與未驗項**：明列沒驗到的部分

## Commit 規則

- Conventional commits：`feat:` / `fix:` / `docs:` / `build:` / `chore:`
- 一個 commit 一個主題
- **不可有任何 Co-Authored-By 或 AI 產生標記**
- push 需人類明確指示

## Merge 規則

- 帶 Eval 證據 + Test 清單全綠才可 merge
- merge 後移除 worktree、刪已併分支
- merge 後在 main 跑一次 `make-app.sh` 煙囪驗證