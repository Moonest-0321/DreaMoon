# 聊天交接文件

- `current.md`：唯一有效的當前操作交接，保存進度、工作樹、測試、阻礙與下一步。
- `template.md`：建立或重置交接時使用的固定格式。
- 需求、UI、驗收條件與 R／U／I 批准狀態保存在 `docs/work-items/current.md`；交接檔不得自行改變或取代它們。
- 新聊天依 `AGENTS.md` 順序同時讀取 work item 與 handoff，而不是只靠一份摘要。
- 已完成工作的長期資訊應分流至正式文件，不把 `current.md` 當歷史資料庫。
- 若確實需要保存某次事故或遷移紀錄，應移至測試報告、troubleshooting 或 ADR，而不是累積聊天摘要。
