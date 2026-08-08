import SwiftUI
import SwiftData
import UniformTypeIdentifiers // 用於處理檔案類型

// MARK: - 作者設定頁 (V1.4)
// 這是一個彈出視窗 (Sheet) 或獨立視窗，用來管理全局作者帳號。
struct AuthorSettingsView: View {
    
    // 取得資料庫操作權限
    @Environment(\.modelContext) private var modelContext
    // 查詢所有的 AuthorProfile (根據 PRD，我們只會有唯一一筆資料)
    @Query private var profiles: [AuthorProfile]
    // 用來關閉當前視窗
    @Environment(\.dismiss) private var dismiss
    
    // 狀態變數：用來暫存預覽的頭像圖片
    @State private var avatarImage: NSImage?
    
    // 取得唯一的作者資料。如果資料庫裡還沒有，我們就建立一個。
    private var profile: AuthorProfile {
        if let existingProfile = profiles.first {
            return existingProfile
        } else {
            // 如果沒有，建立一個預設的並加入資料庫
            let newProfile = AuthorProfile(penName: "我的筆名")
            modelContext.insert(newProfile)
            return newProfile
        }
    }
    
    var body: some View {
        // 使用 @Bindable 讓 profile 的屬性可以直接綁定到 UI 元件上
        // 這樣使用者輸入文字時，SwiftData 會自動在背景儲存，無需手動按「儲存」
        @Bindable var bindableProfile = profile
        
        VStack(spacing: 24) {
            
            // 1. 頭像區域
            avatarSection
            
            // 2. 筆名輸入
            VStack(alignment: .leading, spacing: 8) {
                Text("筆名")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                TextField("請輸入您的筆名", text: $bindableProfile.penName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            
            // 3. 簡介輸入
            VStack(alignment: .leading, spacing: 8) {
                Text("個人簡介")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: Binding(
                    get: { bindableProfile.bio ?? "" },
                    set: { bindableProfile.bio = $0 }
                ))
                    .font(.body)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                // 找到這段程式碼：
                .overlay(alignment: .topLeading) {
                    if bindableProfile.bio?.isEmpty != false {
                        Text("一句話介紹自己... (選填)")
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
            
            Spacer()
            
            // 4. 底部按鈕
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction) // 支援按 Enter 鍵關閉
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 400, height: 500) // 設定一個舒適的彈出視窗大小
        .onAppear {
            // 畫面出現時，如果已有頭像資料，載入顯示
            loadAvatarImage()
        }
    }
    
    // MARK: - 子視圖：頭像區域
    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // 如果有頭像顯示頭像，沒有則顯示筆名首字
                if let image = avatarImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(String(profile.penName.prefix(1)).uppercased())
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.gradient) // 使用系統強調色
                }
                
                // 點擊更換的提示遮罩
                Color.black.opacity(0.01) // 讓整個區域可點擊
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
            .shadow(radius: 5)
            .onTapGesture {
                selectAvatar()
            }
            
            Text("點擊頭像更換圖片")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 功能方法
    
    // 從 Data 載入圖片到 NSImage
    private func loadAvatarImage() {
        if let data = profile.avatarData, let image = NSImage(data: data) {
            avatarImage = image
        } else {
            avatarImage = nil
        }
    }
    
    // 打開 macOS 檔案選擇器
    private func selectAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image] // 只允許圖片
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "選擇您的頭像"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                // 將圖片轉換為 Data 存入 SwiftData
                // 這裡使用 PNG 格式以支援透明背景
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    
                    profile.avatarData = pngData // 存入資料庫
                    avatarImage = image          // 更新 UI 預覽
                }
            }
        }
    }
}

// 預覽 (可選，幫助你在 Xcode 中快速看畫面)
#Preview {
    AuthorSettingsView()
        .modelContainer(for: AuthorProfile.self, inMemory: true)
}
