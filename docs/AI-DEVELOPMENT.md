# AI 開發準則

## 開工前（每個 agent、每個任務）

1. 讀 `AGENTS.md` 與 `PLAN.md`，採用其中詞彙，不自創平行術語。
2. `git fetch` 後再開工；一律在 `../macbar-wt/<branch>` worktree 工作。
3. 先 grep 既有 pattern 再寫新碼；repo 已有的做法不重造。
4. 修改前先確認完整的型別與函式簽名，不猜介面。

## 任務執行

- 一個 agent = 一個明確範圍（一個 branch、一個交付物），上下文自包含，不留隱含假設。
- 不確定的決策停下來問，不猜測生產、簽章、刪除類行為。
- 破壞性操作（刪 worktree、強推、改遠端）一律先取得明示同意。
- 不寫註解流水帳；只註解非顯而易見的 why。

## 完成定義（DoD）

1. `swift build -c release` 零錯誤零警告
2. `./Scripts/make-app.sh` 產出可簽章通過的 .app
3. `docs/REVIEW-TEST.md` 對應項目全數通過
4. `PLAN.md` 若受影響，同 commit 內更新
5. conventional commit、無 co-author、無 AI 標記
6. 回報：改了什麼、怎麼驗證、什麼沒驗

## 禁區

- 不引入 TCC 權限、沙盒、第三方依賴
- 不擴大檔案權限、不碰 secrets
- 不在 main 直接開發功能；main 只收 merge 與 docs