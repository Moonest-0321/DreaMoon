# 技術基線紀錄

> 紀錄日期：2026-09-01
>
> 用途：作為後續 V4–V7 修改前後的可比較基準。

## Git 狀態

- 分支：`main`
- HEAD：`ae086e0`
- 與 `origin/main`：同步
- 工作樹：有使用者尚未提交的程式修改與文件新增；本次未覆蓋或回復。

## 專案設定

- Xcode：26.6（Build 17F113）
- Swift：5 language mode；目前工具鏈為 Apple Swift 6.3.3
- 最低 macOS 部署版本：26.5
- Targets：`Sailune`、`SailuneTests`
- Scheme：`Sailune`

## 驗證結果

### 專案識別

- `xcodebuild -list -project Sailune.xcodeproj`：通過。
- Xcode 能識別兩個 target、Debug／Release 組態與 Sailune scheme。

### 測試／建置

- 沙箱內執行仍會因 `sandbox-exec: sandbox_apply: Operation not permitted` 導致 SwiftData／Observation external macro plugin 回傳 malformed response。
- 在允許 Xcode toolchain 正常啟動 plugin 的同一工作環境重跑後，Debug 與 Release macOS 組態建置成功。
- 完整測試命令：`xcodebuild test -project Sailune.xcodeproj -scheme Sailune -destination 'platform=macOS' -derivedDataPath /tmp/SailuneDerivedData CODE_SIGNING_ALLOWED=NO`。
- 結果：27 項測試全數通過；包含 19 項既有回歸與 8 項 V4.2 驗收／遷移測試。
- 另以隔離 store 啟動 Debug 測試版；由於系統同時存在多個相同 bundle identifier 的 Sailune 執行個體，無法可靠辨識隔離視窗，因此沒有執行可能誤寫正式使用者資料的介面操作。

## 基線限制

- 沙箱權限不足時不能把 macro plugin 失敗誤判為程式編譯失敗；應在允許 plugin 執行的環境重跑。
- 自動建置與測試已有綠色基線；發布前仍需完成正式簽章／封裝與人工 UI 流程檢查。
- 任何程式修改仍需執行 `git diff --check`。

## 後續恢復建議

1. 自動化環境需允許 `/Applications/Xcode.app` 的 macro plugin server 執行。
2. 發布前在 Xcode IDE 或正式簽章產物完成大綱底下的故事背景、故事線、敘事大綱與新時間軸人工冒煙測試。
3. 若 macro 再度失敗，先記錄 sandbox 與 plugin server 錯誤，不要修改所有 `@Model` 宣告。
