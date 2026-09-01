# 當前工作交接

> 狀態：active
>
> 更新時間：2026-09-01 21:00（Asia/Taipei）
>
> 工作單元：盤點並完成 V4.2 全書大綱
>
> 對應工作單：`docs/work-items/current.md`
>
> 目前階段：requirements
>
> 批准狀態：R=pending；U=pending；I=pending

## 目標與完成條件

- 目標：依文件與目前程式查證 V4.2 現況，先取得需求與 UI 核准，再實作、測試、驗收及更新發布文件。
- 完成條件：以 `docs/work-items/current.md` 最終批准的範圍為準；目前尚未取得 R。
- 非目標：R 前修改功能程式，或自行把 PRD 後續再談項目寫成 V4.2 必要功能。

## 已完成

- 讀取 V4.2 PRD、專案狀態、backlog、發布清單、資料／遷移／測試文件。
- 查證 `BookOutline.swift`、`StoryTag.swift`、`OutlineViews.swift`、`TimelineViews.swift` 及 V4.2 測試。
- 確認第一版資料模型、store、UI 入口及測試已存在於未提交工作樹。
- 重新執行目前工作樹的完整 macOS 測試，27 項通過、0 項失敗。
- 使用 `/tmp` 隔離 store 啟動 Debug app，從 UI 建立測試書籍、主線、兩個主線階段及大綱項目，並觀察敘事／時間軸；測試程序已停止。
- 將 V4.2 工作單設為 `active`／`requirements`，整理建議範圍、驗收草案與三項待確認問題。

## 已決定事項與理由

- 已確認的第一版核心與 PRD 一致：故事背景、四類故事線、單一分段主線、四種狀態、手填排序、共用 OutlineItem 及 V1 → V2 遷移。
- 「完成 V4.2」範圍尚有歧義，必須由使用者確認；不能因自動測試通過就把後續未定案功能視為完成或非必要。
- 目前不執行產品程式修改；下一步停在 R 關卡。

## 暫時假設

- 建議把 V4.2 定義為「完成並發布 PRD 第一版」，PRD 第 9 節留給後續版本或獨立工作單；尚未獲使用者批准。

## 待使用者確認

- 是否採建議的 V4.2 第一版發布範圍。
- 是否包含正式簽章封裝與 Git tag，以及實際對外發布是否另行授權。
- U 階段需依窄右欄現況比較「改善 inspector」與「較寬／全尺寸工作區」，但此項不阻擋 R。

## 工作樹邊界

- 接手前已存在的修改：V4.2 程式、測試、文件，以及使用者原有 `EditorWorkspaceView.swift`、`InspectorViews.swift`、`RichEditorView.swift` 修改。
- 本工作單元修改：`docs/work-items/current.md`、本交接檔及先前建立的協作流程文件。
- 不可覆蓋或回復：所有接手前未提交修改，尤其編輯器／檢查器既有變更與舊資料相容行為。

## 變更檔案與用途

- `docs/work-items/current.md`：V4.2 現況、需求草案、R／U／I 狀態與待確認範圍。
- `docs/handoffs/current.md`：本次盤點證據、測試結果、工作樹邊界與下一步。

## 測試與驗證

- 已執行（受限沙箱）：`xcodebuild test -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/SailuneV42DiscoveryDerivedData CODE_SIGNING_ALLOWED=NO`
- 結果：失敗；SwiftData／Observation macro plugin server 回傳 malformed response，屬已知沙箱環境限制，不是 V4.2 測試失敗。
- 已執行（允許 Xcode plugin）：`xcodebuild test -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/SailuneV42DiscoveryDerivedDataEscalated CODE_SIGNING_ALLOWED=NO`
- 結果：`TEST SUCCEEDED`；27 項通過、0 項失敗，包含 8 項 V4.2 與 19 項回歸。
- 尚未驗證：Release 本輪重跑、人工 UI 冒煙、正式簽章／封裝、版本設定與 tag。
- UI 現況證據：基本建立流程可操作；窄右欄會壓縮階段 picker、接近裁切儲存控制，時間軸需在 inspector 內水平捲動。這是現況觀察，不是 U 批准或完整 UI 驗收。

## 已知問題或阻礙

- 沒有技術阻礙；目前需要使用者做 R 階段的產品範圍決策。
- `MARKETING_VERSION` 仍為 `1.0`，repository 沒有 Git tag；不能把目前狀態描述成正式 V4.2 發布。

## 不得跨越的關卡

- R=pending。只能繼續需求與範圍討論；不得提出定案 UI、修改功能程式、建立版本 tag 或對外發布。

## 第一個下一步

1. 向使用者回報現況與三項範圍決策；取得 R 批准後，將工作單轉為 `ui` 並提出可評估的介面方案。

## 接手讀取順序

1. `AGENTS.md`
2. `docs/project-status.md`
3. `docs/work-items/current.md`
4. 本文件
5. `docs/prd-v4.2-outline.md`
6. `docs/backlog.md`、`docs/release-checklist.md`
7. `git status`、V4.2 相關 diff、程式與測試
