# 功能盤點（第一版）

> 盤點日期：2026-09-01
>
> 本文件先記錄目前程式可確認的功能，不等同於完整產品規格。尚未確認產品意圖的項目會保留並標記為待確認。

## 1. 書櫃與書籍管理

- 狀態：已存在
- 可確認行為：建立、瀏覽與刪除書籍；顯示建立／更新日期與字數統計。
- 相關檔案：`ContentView.swift`、`Book.swift`
- 待確認：書籍是否還有未文件化的狀態或分類需求。

## 2. 書籍結構

- 狀態：已存在
- 可確認行為：以「卷／節」組織內容；新增、重新命名、刪除；支援拖放排序。
- 相關檔案：`BookOverviewView.swift`、`EditorWorkspaceView.swift`、`Volume.swift`、`Section.swift`
- 注意：刪除卷會連同其下所有節刪除；目前介面明確提示不可復原。

## 3. 文字編輯器

- 狀態：已存在，屬核心功能
- 可確認行為：編輯節標題與正文；自動儲存；顯示即時字數；上一節／下一節切換。
- 相關檔案：`EditorWorkspaceView.swift`、`RichEditorView.swift`
- 待確認：完整快捷鍵、格式能力與編輯器預期支援的文件格式。

## 4. 文本引用與設定集連結

- 狀態：已存在
- 可確認行為：辨識正文中的角色與物品名稱；顯示正文引用；可由引用跳轉到對應設定。
- 相關檔案：`RichEditorView.swift`、`InspectorViews.swift`
- 注意：已有「未連結的舊名稱」掃描與選擇性套用替換功能。

## 5. 角色設定

- 狀態：已存在
- 可確認行為：建立與編輯角色；管理真名、別名、摘要、來歷、出生資料、外觀與心理資料。
- 相關檔案：`Character.swift`、`CharacterDetails.swift`、`InspectorViews.swift`、`CharacterSectionViews.swift`
- 待確認：各欄位的正式定義與必填規則。

## 6. 角色歷史與時間定位

- 狀態：已存在
- 可確認行為：記錄角色身分、能力、物品、關係等歷史；部分資料可定位到時間軸。
- 相關檔案：`CharacterHistoryViews.swift`、`CharacterDetails.swift`、`Timeline.swift`、`Event.swift`
- 待確認：歷史資料與時間軸事件的完整關聯規則。

## 7. 角色關係

- 狀態：已存在
- 可確認行為：建立一般關係與血緣關係；檢視關係清單／關係網；保留關係歷史。
- 相關檔案：`RelationshipWorkspaceViews.swift`、`KinshipRelation.swift`、`CharacterDetails.swift`、`InspectorViews.swift`
- 待確認：關係類型的完整清單與方向性規則。

## 8. 組織與角色身分

- 狀態：已存在
- 可確認行為：建立組織、將角色加入組織、記錄角色在組織中的身分及其歷史。
- 相關檔案：`CharacterDetails.swift`、`CharacterSectionViews.swift`

## 9. 能力系統

- 狀態：已存在
- 可確認行為：建立能力與能力等級；將能力連接至角色；記錄角色的能力歷史。
- 相關檔案：`AbilityProgress.swift`、`CharacterDetails.swift`、`InspectorViews.swift`、`CharacterSectionViews.swift`
- 注意：介面文字指出能力等級是設定資料，不會自動套用到持有角色。

## 10. 物品與物品副本

- 狀態：已存在
- 可確認行為：建立物品、設定物品等級；建立多個物品副本；記錄副本持有人、目前等級與歷史；從角色連接物品。
- 相關檔案：`Item.swift`、`ItemCopy.swift`、`ItemLevel.swift`、`InspectorViews.swift`
- 注意：刪除物品會一併刪除副本、持有人、等級與歷史，但正文文字會保留。

## 11. 故事標籤

- 狀態：已存在
- 可確認行為：設定集側欄包含標籤頁，可建立／管理故事標籤資料。
- 相關檔案：`StoryTag.swift`、`StoryTagViews.swift`、`InspectorViews.swift`
- 待確認：標籤如何套用至正文、角色或其他設定項目。

## 12. 時間軸

- 狀態：V4.2 頂層時間軸已改用全書大綱；舊時間定位資料作為相容層保留。
- 可確認行為：新時間軸與敘事大綱顯示同一批 `OutlineItem`；舊 `Timeline`、`Node`、`Event` 不刪除、不自動轉換，角色與設定歷史仍可保留既有時間定位。
- 相關檔案：`BookOutline.swift`、`OutlineViews.swift`、`TimelineViews.swift`、`Timeline.swift`、`Event.swift`
- 待確認：新大綱與舊時間定位／設定歷史的正式關聯及相容層退場方式。

## 13. 匯出

- 狀態：已存在
- 可確認行為：將書籍、卷或節匯出為 TXT；將書籍匯出為 EPUB。
- 相關檔案：`ExportManager.swift`、`EpubExporter.swift`、`BookOverviewView.swift`、`EditorWorkspaceView.swift`
- 待確認：匯出格式的正式保證、樣式與錯誤處理規格。

## 14. 查找與替換

- 狀態：已存在
- 可確認行為：在指定範圍查找文字；逐筆瀏覽、替換或全部替換。
- 相關檔案：`SearchReplaceView.swift`

## 15. 資料儲存、遷移與修復

- 狀態：已存在／基礎設施
- 可確認行為：使用 SwiftData 儲存；包含舊版本資料匯入、版本遷移、資料回填與持久化資料修復。
- 相關檔案：`SailuneApp.swift`、`MigrationPlan.swift`、`PersistentStoreRepair.swift`、各資料模型檔案
- 待確認：對使用者可見的備份、復原與資料遺失保護流程。

## 16. 作者設定與書籍封面

- 狀態：已存在
- 可確認行為：編輯作者資料；匯入、顯示與移除書籍封面。
- 相關檔案：`AuthorProfile.swift`、`AuthorSettingsView.swift`、`BookCoverStore.swift`、`BookOverviewView.swift`

## 17. V4.2 全書背景與大綱

- 狀態：第一版已存在，自動驗收完成。
- 可確認行為：大綱底下可編輯故事背景；建立前傳、主線、支線與後記；主線可分階段；大綱項目可手動指定四種狀態與順序；敘事大綱和時間軸共用同一筆資料。
- 相關檔案：`BookOutline.swift`、`StoryTag.swift`、`OutlineViews.swift`、`TimelineViews.swift`
- 待確認：刪除／復原、正文或設定嫁接、搜尋、篩選、統計與匯出；第一版沒有預先決定這些行為。

## 待確認總表

- 故事標籤的實際套用對象與流程
- 新大綱與舊時間定位／事件的正式關聯規則
- 角色欄位的正式定義與必填規則
- 編輯器格式、快捷鍵與文件格式承諾
- 匯出檔案的格式與樣式規格
- 資料備份、復原與修復的使用者流程
