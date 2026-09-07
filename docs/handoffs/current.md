# 當前工作交接

> 狀態：active
>
> 更新時間：2026-09-07（Asia/Taipei）
>
> 工作單元：V4.4.3a 大綱工具列回到文本切換
>
> 對應工作單：`docs/work-items/current.md`
>
> 目前階段：completed（V4.4.3a R／U／I 已確認，已完成）

## V4.4.3a 接手起點

- 使用者已確認 UI：同一工具列位置在文本顯示「大綱」，工作區顯示「回到文本編輯」；移除工作區標題列重複入口。
- I 已由使用者明確批准，並已完成。`EditorWorkspaceView` 的工具列在文本顯示「大綱」，在工作區顯示可點擊的「回到文本編輯」；`BookPlanningWorkspaceView` 的重複返回按鈕已移除。保存、節次選取、側欄復原及具正文來源項目的回正文路徑不變。
- 無資料／schema／遷移變更。開始時保留所有既有未提交修改；本輪只修改上述兩個 View 與直接相關文件，沒有覆蓋 V4.4.1 至 V4.4.3 的既有變更。
- 驗證：54 項完整 macOS 測試、Debug、無簽章 Release 及 `git diff --check` 通過。實際 UI 已確認文本→敘事大綱／時間軸→文本均回到原「潮聲未熄」節，按鈕文案正確切換，未改資料。
- V4.4.3a 沒有下一步。若繼續既有工作，唯一下一步仍是以隔離資料驗收 V4.4.3 有事件的寬版／窄版時間軸操作；不要把該未完成驗收歸入 V4.4.3a。

---

## V4.4.3 接手起點

- 使用者以「確認」批准 I；寬版及右欄時間軸均接回 TimelinePanelView。寬度至少 760 點採左日期、右事件，窄版與右欄沿用日期展開。敘事大綱保留。
- 本輪程式修改僅在 OutlineViews.swift（時間軸入口）、TimelineViews.swift（響應式面板、日期投影、選取清理與儲存錯誤呈現）、ItemV3Tests.swift（4 項時間軸回歸）。其他程式及既有大綱修改是接手前工作，不覆蓋。
- TimelineDateProjection 沿用既有排序／粒度／可見性，排除無年份參考點，分開不同紀元的相同日期。新增事件保存失敗會撤除剛插入的事件，保留表單供重試。
- 測試：`xcodebuild test -quiet -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/DreaMoonV443` 成功，54 項通過。新增覆蓋初始化／改元、日期分組／可見性、刪除保留其他軸與正文、檔案 store 重開後日期及事件修改保留。
- Debug 與無簽章 Release 建置、`git diff --check` 通過。Release 命令：`xcodebuild build -quiet -project Sailune.xcodeproj -scheme Sailune -configuration Release -derivedDataPath /tmp/DreaMoonV443Release CODE_SIGNING_ALLOWED=NO`。一般 Release 在簽章階段報 errSecInternalComponent；正式簽章發布未完成。
- UI：已透過實際應用確認敘事大綱原內容及時間軸獨立頁籤、主軸／紀元／新增釘子／改元／年月日入口與空狀態。未手動增刪現有書籍事件；開啟時間軸會按既有 bootstrap 規則補齊缺少的主軸／紀元。受檢書籍無可顯示日期，且截圖視窗位置異常，不能宣稱有資料的左右分欄視覺驗收通過。
- 唯一下一步：用隔離測試資料完成有事件的寬版／窄版 UI 操作驗收（日期選取、切軸／粒度清理、事件表單、刪除後狀態）；不要再次要求 R／U／I 批准。可驗收程式 `/tmp/DreaMoonV443/Build/Products/Debug/Sailune.app`。
- 最小接手文件：工作單、本交接、spec-timeline；必要時 coding-standards 相關章節。無產品決策待確認；沒有 schema／遷移／匯出變更。V4.4.2a 壓力／觸控板驗收為歷史待辦，並非本次範圍。

以下為 V4.4.2a 歷史檢查點。

## V4.4.2a 新工作單元

### 已確認的問題

- 敘事大綱用 `onScrollGeometryChange` 將每次水平捲動位置寫入 `narrativeHorizontalOffset`，再以 View offset 固定左欄；此設計會頻繁重算畫布，是拖動停滯的可確認原因。
- 編輯工具列有「指令」與「快捷鍵」兩個鍵盤操作入口；使用者要求收斂為一個。

### 暫時假設

- 使用者已批准 R／U／I：保留「指令」按鈕，將快捷鍵說明放入指令面板；已實作並通過基本驗證。

### 唯一下一步

- 以修正版 `/tmp/DreaMoonDebugBuild/Build/Products/Debug/Sailune.app` 完成三條以上故事線與觸控板連續拖動的補充驗收；基本捲軸拖曳、列對齊及快捷鍵入口已實測。

### V4.4.2a 實作檢查點

- 使用者明確批准實作與測試。開始時保留既有未提交的 V4.4.1／V4.4.2 修改，本輪僅增修 `OutlineViews.swift`、`EditorWorkspaceView.swift` 與相關文件。
- 敘事畫布使用共用垂直 ScrollView、固定左欄及右側水平 ScrollView；移除水平 offset state 與捲動座標回寫。只量測內容高度以對齊左右列，高度未變不更新狀態。
- 移除獨立快捷鍵按鈕；保留指令按鈕、⌘K、指令面板的快捷鍵說明命令與原 sheet。時間軸繼續使用原雙向捲動。
- 完整 50 項測試通過，Debug 測試建置成功。命令：`xcodebuild test -quiet -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/DreaMoonDebugBuild`。
- UI 連線重置後恢復：已在現有書籍以唯讀操作確認固定左欄、多幕標題水平捲軸拖曳（位置由 0.248 到 0.772）、垂直捲動後列對齊、時間軸切換與卡片詳情開關。工具列只有指令入口；指令面板可成功開啟快捷鍵說明。未修改正文或大綱資料。
- Debug 測試建置、50 項完整測試、無簽章 Release 建置及 `git diff --check` 均通過。剩餘驗證：三條以上故事線壓力資料與觸控板連續拖動手感；目前實測資料為兩條故事線，未取得逐幀效能數據。

---

## V4.4.2 新工作單元

### 已決定

- 使用者指定產品版本為 V4.4.2。
- 書籍結構中的 `Volume` 應稱為「卷次」，不應再誤稱為幕次／幕。
- 有主線時，自動開啟單一故事線的入口預設選主線，不再因既有排序先選前傳。
- 使用者於 2026-09-06 最終確認敘事大綱的預設結構只到「卷次 → 節次 → 幕標題」；段落維持作者自行添加的內容。
- 使用者補充階段定位可在卷次、節次或幕標題任一層停止；階段開始不需要選到段落內容。
- 使用者最終釐清：只在原本卷次／節次結構下新增幕標題並修正卷次名稱；段落是作者可添加的內容，不可自動成為預設結構欄。
- 先前「四層且自動投影正文段落」的理解已被使用者否決，實作已撤除段落欄與段落摘要。

### 暫時假設

- 敘事大綱顯示「卷次 → 節次 → 幕標題」三層結構；幕標題由既有 `AttributedString` 樣式辨識，作者添加的大綱卡片依正文來源位置歸入幕標題。階段定位最多選到幕標題。
- 預設主線只影響自動選取，不改變故事線排序，也不覆蓋使用者仍有效的手動選擇。

### 待確認

- 使用者人工驗收三層表頭、沒有預設段落、階段定位 sheet 與主線預設。

### 唯一下一步

- 開啟 `/tmp/DreaMoonDebugBuild/Build/Products/Debug/Sailune.app` 驗收 V4.4.2 三層表頭及作者自行添加內容的流程；尚未完成的人工 UI 冒煙不能視為通過。

### 本次修正與驗證

- 階段帶補修後 Debug 與無簽章 Release 建置均通過，`git diff --check` 通過；可驗收程式已更新至上方 `/tmp/DreaMoonDebugBuild` 路徑。人工畫面驗收仍未完成。

- 後續核對發現階段帶仍沿用節次範圍；使用者已直接授權補修。`narrativeTimelineLayout` 現直接依階段幕標題起點計算欄位起訖；時間軸仍使用原節次投影。完整測試更新為 50 項通過（大綱 31 項），新增同節多階段定位回歸案例。以下 49 項紀錄為補修前驗證。

- 接手時已有 V4.4.1／V4.4.2 未提交修改；本次僅撤除錯加的段落欄、摘要與未使用的段落解析模型，保留幕標題範圍、原有卡片及時間軸。
- 調整 `BookOutline.swift`、`StoryTag.swift`、`OutlineViews.swift` 及 `V42OutlineTests.swift` 的相關內容；同步工作單、規格及狀態，未回復其他修改。
- `xcodebuild test -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/DreaMoonDerivedData`：49 項通過，包含 30 項大綱測試及「正文段落不自動增加欄位」案例。
- `xcodebuild build -quiet -project Sailune.xcodeproj -scheme Sailune -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/DreaMoonDebugBuild`：通過。
- Release 使用相同建置參數，設定 `-configuration Release -derivedDataPath /tmp/DreaMoonReleaseBuild CODE_SIGNING_ALLOWED=NO`：通過。
- 沙盒內 Swift 巨集載入失敗；經允許在沙盒外重新驗證成功。`git diff --check` 通過。修正版畫面人工驗收仍未完成。

## 已決定

- 使用者於 2026-09-06 批准 V4.4.1 需求：現有結構橫向泳道 UI 成為敘事大綱；既有時間軸必須保留，之後另行改造為世界時間大綱。
- 使用者確認敘事大綱採幕／節次橫軸與故事線泳道、主線階段帶、項目詳情與回正文、待安置固定於底部及窄視窗浮出詳情的方向。
- 先前將「時間軸保留」誤寫為隱藏重複頁籤，使用者於 2026-09-06 明確否決；尚未改動功能程式，文件已修正。
- 使用者於 2026-09-06 重新批准更正版 UI：寬版與右側窄欄的時間軸頁籤及現行行為完整保留；V4.4.1 只把橫向結構 UI 加到敘事大綱，允許兩者暫時相似。
- 使用者於 2026-09-06 釐清兩種大綱的責任：敘事大綱用於理解正文揭露順序與節奏；時間大綱用於理解故事世界的時間先後。
- V4.4.1 先處理敘事大綱：把目前「幕／節次 × 故事線」的橫向泳道 UI 承接為敘事大綱。既有世界曆法與事件的時間大綱整合不是本工作單元的實作範圍。
- 已查核舊時間系統：主 store 的 `Timeline`、`Era`、`Node`、`Event` 支援主／副軸、紀元、可部分留白的年／月／日、時間釘子、事件、角色及節次關聯；資料仍在，未刪除或轉換。

- 同一書籍視窗新增寬版大綱工作區，以中央工作面取代文本，不另開視窗；工作區不顯示左側正文目錄。
- 寬版工作區預設為垂直敘事大綱，另可切換幕／節次橫軸、故事線泳道的橫向時間軸。時間軸只表示書籍結構順序，不表示世界內絕對年代。
- 工具列移除上一節／下一節按鈕；右側順序為「設定集｜大綱｜快捷鍵」。大綱按鈕是唯一新增入口，右欄不另加工作區捷徑。
- 故事背景由右欄移至書籍總覽，順序為基本資訊、封面、簡介、故事背景、統計；摘要卡展開後使用總覽完整寬度編輯。
- 右欄大綱保留敘事大綱與時間軸。文本與寬版大綱使用互斥 surface；大綱不建立正文 sidebar，因此系統按鈕也無法叫回目錄。進入時右欄預設關閉。
- 沿用 V4.3.1 的 StoryPlanning schema V4、階段定位、正文來源、手動安置、狀態、排序與刪除規則；V4.4 不加入 V5 關聯，也不新增資料遷移。
- 無法可靠投影到幕／節次的項目（待安置、失效來源、循環／失效掛點等）固定留在待安置區，不猜測座標。

## 暫時假設

- 時間軸的幕末位置以目前階段至下一個有效階段起點之前的最後節次表示；最後階段使用全書最後節次。
- 非主線故事線沒有階段時，幕首／幕末安置分別投影至全書第一／最後節次。這只影響唯讀時間軸，不回寫資料。

## 待確認

- 無產品決策待確認；本輪不處理時間軸的改造。

## 本工作修改邊界

- `Sailune/BookOutline.swift`：`OutlineTimelineLayout.Lane` 新增純記憶體主線階段帶資料。
- `Sailune/StoryTag.swift`：投影有效階段的開始／結束節次；失效起點不產生階段帶。
- `Sailune/OutlineViews.swift`：敘事大綱改用橫向畫布，新增敘事說明、故事線管理、階段帶、選取詳情及窄視窗 sheet；既有時間軸仍使用原入口與原點擊行為。
- `SailuneTests/V42OutlineTests.swift`：新增主線階段帶正常／失效起點測試，並擴充既有投影案例。
- `docs/spec-story-planning.md`、`docs/spec-timeline.md`、`docs/architecture.md`、`docs/data-model.md`、`docs/project-status.md`、工作單與本交接：同步 V4.4.1 行為、過渡狀態與驗證結果。

本輪開始前工作樹乾淨；下列為既有 V4.4 實作邊界，本輪只在上列 V4.4.1 範圍增修，未回復其他行為：

- `Sailune/BookOutline.swift`：新增 `OutlineTimelineLayout` 唯讀投影型別。
- `Sailune/StoryTag.swift`：新增 `timelineLayout(book:)` 位置解析與待安置分類。
- `Sailune/OutlineViews.swift`：新增寬版工作區、垂直／橫向切換、泳道時間軸及待安置區。
- `Sailune/EditorWorkspaceView.swift`：新增工具列入口、同視窗切換、提交待存內容、欄位復原及回正文定位；移除上一／下一節工具列按鈕。
- 第二輪檢修將文本 `NavigationSplitView` 與寬版大綱拆為互斥 surface，移除重複的自訂目錄按鈕；並修正失效來源提示、時間軸欄寬及單次投影重用。
- `Sailune/BookOverviewView.swift`：調整資訊順序，加入背景摘要卡與完整寬度編輯狀態。
- `Sailune/TimelineViews.swift`：移除右欄故事背景頁籤。
- `SailuneTests/V42OutlineTests.swift`：新增正常投影與失效正文來源不得猜測位置的測試。
- 規格、架構、資料模型、遷移、一致性、專案狀態、工作單與本交接已同步。開始此工作單元時工作樹乾淨，沒有使用者舊修改需要區分。

## 驗證

- `V42OutlineTests`：27 項通過。
- 完整 macOS 測試：46 項通過、0 失敗。
- Debug 建置：成功。
- 無簽章 Release 建置：成功。
- `git diff --check`：通過。
- 修正版人工 UI：使用 `/tmp/SailuneDerivedDataV44FixedUI5/Build/Products/Debug/Sailune.app` 實際確認書籍總覽順序、文本工具列、進入／返回大綱、敘事／時間軸切換；大綱模式沒有正文 sidebar 或系統 sidebar 按鈕，右側順序為設定集、大綱、快捷鍵。未輸入或儲存正式書籍資料。
- 尚未完成：以隔離資料實際製造失效來源、待安置、背景編輯保存及窄視窗案例；這些仍不得視為人工驗收完成。
- V4.4.1 實際 UI：確認敘事大綱顯示橫向結構畫布、卡片開啟詳情、故事線管理可開啟及關閉；切換時間軸後頁籤仍存在，卡片維持原本回正文行為。尚未以多階段隔離資料檢查階段帶及所有寫入／刪除流程。

## V4.4.1 歷史待驗證項目（目前起點以上方 V4.4.2 為準）

1. 請使用者驗收 V4.4.1 畫面；若方向通過，再補完多階段、待安置、失效來源、窄視窗與背景保存的隔離資料 UI 冒煙。

## 新對話最小閱讀集合

- `docs/work-items/current.md`
- `docs/handoffs/current.md`
- `Sailune/EditorWorkspaceView.swift`
- `Sailune/OutlineViews.swift`
- `Sailune/StoryTag.swift`
- `SailuneTests/V42OutlineTests.swift`
