# 文件與實作一致性檢查

> 稽核日期：2026-09-14。範圍包含 Swift 原始碼、三個 XCTest 檔、Xcode 設定與 `docs/`；本文件記錄程式事實和產品文件的差異，不代表已修正程式。

## 已確認一致

- 主資料使用 `NovelWriterSchemaV5`；故事規劃使用 `StoryPlanningSchemaV7`，產品版本與 schema 版本分離。
- 應用建立一個既有主 store 與五個獨立功能 store；V5 settings store 只以 UUID 連結，不遷移主資料。
- V5 settings schema V3 以每書層級限制隸屬方向，預設兩個可改名層級，並保存完整勢力自由文字項目；V1→V2 只清除無法驗證的舊勢力連線，V2→V3 保留既有層級與勢力資料。
- 角色正文引用使用穩定 URL；已連結名稱可同步，未連結文字只列候選。
- 正文大綱來源和伏筆／修改標籤均可重新定位；來源消失時分別採大綱降級與標籤刪除。
- 世界時間軸使用主 store Timeline／Era／Node／Event；既有敘事大綱可建立 Event 並以 metadata 關聯。
- 原始碼中共有 104 個 XCTest 方法；V5 專項 14 項及完整測試均已通過。

## P0：公開測試前應處理

### 匯出目的地寫死為開發者帳號

`ExportManager` 與 `EpubExporter` 都寫入 `/Users/hsuchengyu/Downloads`。其他使用者通常無法使用該路徑；文件曾寫成泛稱「使用者 Downloads」，與程式不符。應改用存檔面板或系統 Downloads URL，並呈現成功／失敗結果。

## P1：資料一致性

### 部分刪除入口繞過既有集中服務

- `BookOverviewView` 與 `EditorWorkspaceView` 直接刪除 Volume／Section，沒有呼叫 `PersistentModelDeletion.deleteVolume/deleteSection`。這可能讓 Node／Event 的 Section 引用依賴 SwiftData 行為或後續修復，而不是立即明確解除。
- `CharacterEventSectionView` 直接刪除 Event，沒有呼叫 `CrossStoreDeletionCoordinator.deleteEvent`，可能留下 `TimelineEventCardMetadata`，直到下一次冪等修復才清除。
- 文件不得宣稱「所有 Event／Node／Timeline／Book／卷節刪除都已統一」。目前協調服務本身存在且有測試，但不是所有 UI 入口都使用。

### 多 store 備份仍不完整

目前沒有把六個 store、SQLite sidecar 與封面目錄一起封裝的備份／還原流程。公開測試前至少需提供可驗證的備份方式。

## P1：產品宣稱邊界

### 伏筆不是「未回收伏筆管理」

`StoryTagKind.allCases` 目前只有伏筆與修改；設定集可列出、跳回正文及刪除伏筆。但 `StoryTag` 沒有回收狀態、回收錨點、完成時間或篩選欄位。因此：

- 可以宣稱：標記伏筆、集中查看伏筆標記、跳回原文。
- 不可宣稱：自動列出尚未回收伏筆、追蹤伏筆回收、判斷整體連動是否完成。

### 敘事大綱與世界時間軸不是同一筆資料

舊文件將 V4.2 過渡時間軸描述為和大綱共用 OutlineItem，這只適用歷史版本。現況世界時間軸由 Event 擁有內容，可選擇關聯 OutlineItem；兩者可連動但不會雙向等值同步。

## P2：可靠性與 UX

- 刪除後復原規則不一致：卷節有短期 UI Undo，部分設定刪除立即生效；跨 store 刪除沒有垃圾桶或跨啟動復原。
- 角色同步只自動更新已連結引用；同名、別名與未連結文字必須維持「候選替換」描述。
- 物品正文引用依名稱掃描，不具角色引用同等的 UUID 穩定性。
- 固定最低 macOS 26.5、簽章、封裝與 V4.4.9 實機右鍵狀態仍需發布前驗證。

## 結論

帆夢已具備可展示的「正文—設定—敘事大綱—世界時間」連動骨架，也有相當完整的模型與遷移測試。現階段最值得發展的產品方向是伏筆生命週期，但在 schema 與 UI 完成前只能作為預告方向。公開測試的技術前置則是匯出路徑、刪除入口一致性、多 store 備份與人工冒煙。
