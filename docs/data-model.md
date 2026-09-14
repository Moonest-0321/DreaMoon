# 資料模型與關聯

> 依 2026-09-14 V5 實作與現行 schema、store 操作整理。

## Store 邊界

| Store | Schema／主要模型 | 連結方式 |
|---|---|---|
| `Sailune-v5.store` | `NovelWriterSchemaV5`：Book、Volume、Section、Character、Ability、Item、Timeline、Node、Event 與舊 Organization 相容型別 | SwiftData relationship；V5 不升級此 store schema |
| `Sailune-v5-settings.store` | `V5SettingsSchemaV3`：BookSidebarSetting、PowerLevel、PowerUnit、PowerSubordination、Place、WorldTerm | 只以 `bookID`、層級 UUID 與勢力 UUID 連結，不持有其他主資料 |
| `Sailune-v5-item-copies.store` | ItemCopy、ItemCopyHolding、ItemCopyHistory | `bookID`、`itemID`、`characterID`、`copyID` |
| `Sailune-v5-item-copy-level-selections.store` | ItemCopyLevelSelection | `copyID`、`levelID` |
| `Sailune-v5-ability-progress.store` | AbilityProgressRecord／History | `bookID`、`abilityID`、`characterID`、`nodeID` |
| `Sailune-v5-story-planning.store` | `StoryPlanningSchemaV7`：V6 全部模型加上 PlanningRecordMetadata | `bookID`、`sectionID`、`eventID`、`outlineItemID`、來源種類與來源 UUID 等 |

Book 封面不在 SwiftData，另存於 Application Support 的 `Sailune/Covers` PNG 檔。

## 主關聯

```text
Book
├─ Volume ─ Section（AttributedString 正文）
├─ Character
│  ├─ Alias / Profile / Appearance / Psychology
│  ├─ CharacterAbility / History
│  ├─ CharacterItem / History
│  └─ Relationship / Kinship / History
├─ Item ─ ItemLevel / ItemHistory
└─ Timeline ─ Node ─ Event
                 └─ Character 關聯與可選 Section 來源

PowerLevel（bookID、由高至低 sortOrder）
└─ PowerUnit（bookID、levelID → PowerLevel、簡介、高層管理員、其他名單、勢力關係、政治、宗教）
   └─ PowerSubordination：lowerPowerID → upperPowerID（只保存直接隸屬）

BookSidebarSetting（bookID）→ 顯示項目、可見性、排序
Place / WorldTerm（bookID）→ V5 基礎設定資料
```

## 故事規劃關聯

```text
BookPlanningProfile ─ bookID
StoryTag ─ bookID + sectionID + 文字錨點
ChapterAnnotation ─ bookID + sectionID
OutlineStoryLine ─ OutlineStage ─ OutlineItem
                              ├─ OutlineItemAnchor（正文來源，最多一筆）
                              └─ OutlineItemPlacement（手動安置，最多一筆）
OutlineStage ─ OutlineStageStartAnchor + OutlineStageStartDetail
TimelineEventCardMetadata ─ eventID + 可選 outlineItemID
```

## 重要不變條件

- UUID 是跨 store、遷移與回填的穩定識別；`sortOrder` 只負責同父層顯示順序。
- 同一本書最多一條主線；主線可有多個階段。階段只屬主線。
- 一筆大綱項目最多一個正文來源；手動項目可沒有來源。
- 只有有正文來源的大綱項目可呈現「已完成」；手動項目使用背景、草稿或預定。
- 伏筆／修改標籤和大綱來源都以原文加 UTF-16 offset 解析最近候選，但失效結果不同：標籤刪除；大綱保留、退到原節開頭並轉草稿。
- 手動大綱安置可為待安置、階段首、某項目後或階段末。目標失效時保留內容並回待安置，不猜新位置。
- StoryPlanning V6 的 event metadata 只補充主 store Event；它不擁有事件。刪除 OutlineItem 不刪 Event，缺來源時卡片顯示來源失效。
- StoryPlanning V7 的 `PlanningRecordMetadata` 只保存每筆設定時間序的故事線與可選階段；標題、摘要、世界日期和節次仍以原始來源及 Node 為唯一來源。同一 Node 可供多筆來源共用，不承擔故事線歸屬。
- 物品副本是共用 Item 的獨立實例；副本目前等級不改寫父 Item 定義。
- 產品 V5 只保存目前勢力與直接隸屬，不建立角色／勢力、物品／勢力或正文／勢力關聯；舊 Organization 資料啟動時清除。
- 每本書首次建立設定配置時預設兩個可改名層級「層級 1／層級 2」；勢力先指定層級才可建立隸屬。下級層級的 `sortOrder` 必須大於上級，允許跨級、多上級與多下級。
- 高層管理員、其他名單、勢力關係、政治與宗教在 V5 第一版都是勢力自身的自由文字，不建立角色或其他設定資料的外部連結。
- 勢力改層或層級重新排序若會使既有連線反向或同級，整項操作失敗並保留原層級、原順序與全部連線。
- 設定集隱藏只改變導航，不刪除設定資料；預設顯示角色、勢力、物品、能力、標籤，地點與世界條目可選加入。

## 刪除語意

- `PersistentModelDeletion` 明確解除 Node／Event 與角色歷史、設定歷史或 Section 的引用，再刪除 Book、Character、Item、Event、Node、Timeline、Section 或 Volume。
- `CrossStoreDeletionCoordinator` 對 Book、Event、Node、Timeline 採「先保存主 store，再清理 StoryPlanning」；附屬清理失敗可稍後冪等重試。
- 刪除勢力會刪除以它為端點的直接隸屬；已被勢力使用的層級不可刪除。刪除書籍時會一併刪除該書的層級與 settings 資料。
- 啟動與時間軸載入會按現存 Book／Event UUID 清除孤立規劃資料；缺 OutlineItem 不會使 Event 或 metadata 被刪除。
- 現行 UI 仍有 Volume／Section 與角色事件直接刪除入口，未完整套用上述集中語意；詳見 `consistency-audit.md`。

## 模型風險

- 六個 store 無共同 transaction，任何新增跨域關係都要定義保存順序、失敗狀態、修復與測試。
- 伏筆目前沒有回收狀態或回收來源，不能從既有 StoryTag 推導「未回收」。
- 物品正文引用是名稱掃描；重新命名或同名物品無穩定識別保證。
- 備份必須同時包含六個 store 及封面檔，不能只複製主 store。
