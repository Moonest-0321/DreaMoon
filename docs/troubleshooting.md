# 問題排查與處理

> 本文件記錄目前可確認的問題與安全處理方式。若問題涉及資料刪除或遷移，不要直接刪除資料庫檔案。

## 1. 專案無法編譯：SwiftData／Observation macro plugin

### 現象

編譯時出現：

```text
External macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found
... swift-plugin-server ... produced malformed response
```

### 目前判定

這表示 SwiftData／Observation external macro plugin 在工具鏈中沒有正常回應。它發生在測試案例執行前，因此不能直接判定為產品程式或測試邏輯錯誤。

### 建議排查順序

1. 在 Xcode IDE 直接執行 Build，確認是否只有 command-line build 受影響。
2. 清理 Xcode Derived Data 後重建。
3. 確認 Xcode、macOS SDK 與專案 deployment target 的組合相容。
4. 記錄第一個 macro 錯誤、Xcode build version 與完整環境資訊。
5. 不要因為此錯誤直接移除 `@Model`、`@Observable` 或改寫資料模型。

目前基線詳見 [technical-baseline.md](technical-baseline.md)。

## 2. 啟動時顯示「資料庫無法開啟」

### 可能原因

- 主資料庫 schema 無法開啟。
- V2／V3 舊資料匯入失敗。
- 回填或懸空資料修復失敗。
- 物品副本、能力進度或故事規劃的獨立 store 無法開啟。

### 安全處理

1. 保留錯誤畫面中的完整診斷資訊。
2. 先備份主 store 與所有獨立 store。
3. 確認錯誤發生的啟動階段。
4. 使用對應 schema 版本的備份進行隔離測試。
5. 不要直接刪除或覆寫原始資料庫。

啟動失敗畫面目前設計為不刪除原始資料；資料檔與啟動順序詳見 [backup-and-migration.md](backup-and-migration.md)。

## 3. 舊資料匯入後內容缺漏

### 可能原因

- 舊 store 與目前 schema 不相容。
- 匯入程序中斷。
- 跨 store 的 UUID 關聯沒有對應。

### 排查方式

- 比對匯入前後 Book、Volume、Section、Character、Timeline、Node、Event 的 UUID 集合。
- 確認匯入驗證器是否回報缺少資料。
- 確認第二次啟動不會重複匯入。
- 檢查獨立 store 是否與主資料中的 `itemID`、`characterID`、`sectionID` 對得上。

## 4. 角色引用跳轉失效或名稱沒有同步

### 可能原因

- 正文文字只有相同字串，尚未建立角色連結。
- 真名或別名存在歧義。
- 文字修改後，舊連結位置或候選文字需要重新掃描。

### 安全處理

- 先確認角色真名與別名是否唯一。
- 使用「未連結的舊名稱」清單逐筆確認，不要直接全部替換。
- 角色刪除後，正文文字預期保留，但連結會解除。
- 若是跨節跳轉，先確認目標節仍屬於同一本書。

## 5. 故事標籤位置偏移

### 可能原因

標籤使用原始選取文字與 UTF-16 offset；當相同文字重複出現、內容大幅改寫或文字被刪除時，最近位置推定可能不符合作者意圖。

### 處理方式

- 重新查看標籤的原始選取文字。
- 若正文有多個相同片段，人工確認標籤是否落在正確位置。
- 不要直接把 Swift String index 與 AppKit `NSRange` 混用。
- 將可重現的漂移案例加入測試資料。

## 6. 匯出失敗或找不到檔案

### 目前限制

TXT 匯出目前寫入使用者 Downloads；這是現行實作，不是跨環境保證。

### 排查方式

- 確認 Downloads 目錄可寫入。
- 確認檔名不含平台禁止字元。
- 檢查書籍／卷／節標題是否為空或包含特殊字元。
- EPUB 問題需同時檢查輸出檔案是否建立，以及 EPUB 內的 `mimetype`、`container.xml`、`content.opf` 與 nav。

## 7. 物品副本或能力資料沒有顯示

### 可能原因

- 對應的獨立 store 沒有成功開啟。
- UUID 對應的主資料已被刪除。
- 回填尚未完成或資料被判定為孤立資料。

### 安全處理

- 先重新載入 store，不要手動新增重複資料。
- 比對副本／能力資料的 UUID 與主資料。
- 執行修復前先建立完整備份。
- 將孤立資料案例記錄到測試與資料修復文件。

## 8. 回報問題時應提供

- 產品版本與 Git commit。
- Xcode／macOS 版本。
- 是否有未提交的程式修改。
- 問題發生在哪個功能與操作步驟。
- 完整錯誤訊息或畫面文字。
- 是否能在備份資料或全新資料庫重現。
- 是否涉及多 store、遷移、刪除或匯出。

