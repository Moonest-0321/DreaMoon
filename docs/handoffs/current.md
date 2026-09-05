# 當前工作交接

> 狀態：active
>
> 更新時間：2026-09-06（Asia/Taipei）
>
> 工作單元：V4.4 大綱系統升級（實作完成，待人工 UI 冒煙）
>
> 對應工作單：`docs/work-items/current.md`
>
> 目前階段：validation（R／U／I 均 approved）

## 已決定

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

- 無產品決策待確認；剩餘工作是人工 UI 驗收。

## 本工作修改邊界

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

- `V42OutlineTests`：26 項通過。
- 完整 macOS 測試：45 項通過、0 失敗。
- Debug 建置：成功。
- 無簽章 Release 建置：成功。
- `git diff --check`：通過。
- 修正版人工 UI：使用 `/tmp/SailuneDerivedDataV44FixedUI5/Build/Products/Debug/Sailune.app` 實際確認書籍總覽順序、文本工具列、進入／返回大綱、敘事／時間軸切換；大綱模式沒有正文 sidebar 或系統 sidebar 按鈕，右側順序為設定集、大綱、快捷鍵。未輸入或儲存正式書籍資料。
- 尚未完成：以隔離資料實際製造失效來源、待安置、背景編輯保存及窄視窗案例；這些仍不得視為人工驗收完成。

## 唯一下一步

1. 在可啟動 GUI 的環境建立隔離資料，驗證工具列順序、寬／窄視窗、背景摘要與完整寬度編輯、敘事／時間軸切換、橫向捲動、待安置區及回正文定位；同時覆蓋 V4.3.1 的階段定位、來源已刪除、手動安置與舊手動完成提示。

## 新對話最小閱讀集合

- `docs/work-items/current.md`
- `docs/handoffs/current.md`
- `Sailune/EditorWorkspaceView.swift`
- `Sailune/OutlineViews.swift`
- `Sailune/StoryTag.swift`
- `SailuneTests/V42OutlineTests.swift`
