# macbar — Agent 開發準則

本檔是所有 AI agent 在本 repo 工作的最低約束。細則在 `docs/`，行為規格的唯一事實來源是 `PLAN.md`。

## 鐵律

1. `PLAN.md` 是唯一設計事實來源（SOT）。行為或範圍要變，先改 PLAN.md 再動程式。
2. 開發一律在 `git worktree add ../macbar-wt/<branch> -b <branch>` 進行；main 保持乾淨。完成、驗收通過後才 merge 回 main，隨即移除 worktree。
3. 實際編碼交給獨立的 scoped agents（見 `.github/agents/`）。每個 agent 乾淨上下文、明確輸入、可重跑、可 eval。
4. Commit 訊息用 conventional commits（`feat:` / `fix:` / `docs:` / `build:` / `chore:`）。**一律不可加 Co-Authored-By 或任何 AI 署名。**
5. 不自動 push；push 由人類指令觸發。
6. 回覆使用者一律用台灣繁體中文；log、code、錯誤訊息保留原文。
7. 不引入 TCC 權限（不做麥克風 capture）、不加第三方相依、不開沙盒。

## 準則索引

| 主題 | 文件 |
|---|---|
| 開發準則 | `docs/DEVELOPMENT.md` |
| 維護準則 | `docs/MAINTENANCE.md` |
| AI 開發準則（詳細） | `docs/AI-DEVELOPMENT.md` |
| Review / Eval / Test 準則 | `docs/REVIEW-TEST.md` |
| 交接 PR 準則 | `docs/PR-HANDOFF.md` |