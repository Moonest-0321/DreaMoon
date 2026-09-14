# 技術基線紀錄

> 核對日期：2026-09-13；本次為唯讀程式／設定稽核，未重新執行完整 Xcode 測試。

## Git

- 分支：`main`
- HEAD：`4ed99bf`（`2026-09-13 V4.4.9`）
- 稽核開始時工作樹乾淨；本工作單只更新文件。

## 專案設定

- Targets：`Sailune`、`SailuneTests`；Scheme：`Sailune`。
- Swift 5 language mode。
- 最低 macOS deployment target：26.5。
- App：`com.MooNest.Sailune`；Tests：`com.MooNest.SailuneTests`。
- Xcode marketing version 1.0、build 1；這與文件中的產品 V4.2.1／開發 V4.4.9 尚未同步。

## 驗證證據

- 目前測試原始碼共有 86 個 `test...` 方法。
- 最近記錄的完整成功結果：2026-09-13，86 項 macOS 測試與無簽章 Release 建置通過。
- 歷史測試報告只代表當時提交，不自動證明目前工作樹。
- 受限環境若出現 SwiftData／Observation macro plugin malformed response，應在允許 Xcode plugin server 的環境重跑，不應因此改寫模型。

## 發布前基線缺口

1. 在目前 HEAD 重跑完整測試、Debug／Release 建置。
2. 完成正式簽章、封裝與實機啟動。
3. 同步 Xcode 產品版本與預定發布版本。
4. 完成右鍵選單、共同 Undo／Redo、匯出與多 store 備份的人工流程驗證。
