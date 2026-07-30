import SwiftUI
import SwiftData
import AppKit // 【V1.4 新增】為了在 Toolbar 處理頭像 NSImage，需要引入 AppKit

// MARK: - 主畫面：網格書櫃
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.updatedAt, order: .reverse) private var books: [Book]
    
    // 【V1.4 新增】查詢作者帳號
    @Query private var profiles: [AuthorProfile]
    
    @State private var showingNewBookSheet = false
    @State private var searchText = ""
    
    // 【V1.4 新增】控制作者設定頁的彈出
    @State private var showingAuthorSettings = false
    
    // 【新增】用於控制刪除確認對話框的狀態
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?

    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return books
        } else {
            return books.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // 調整網格：最小寬度 180，間距 24，讓畫面更有呼吸感
    let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(filteredBooks) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.plain)
                        // 【新增】右鍵選單：刪除
                        .contextMenu {
                            Button(role: .destructive) {
                                bookToDelete = book
                                showingDeleteAlert = true
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24) // 增加整體內邊距
            }
            .navigationTitle("DreaMoon")
            .searchable(text: $searchText, prompt: "搜尋書名或作者")
            .toolbar {
                // 【V1.4 新增】左側：作者頭像/設定入口
                ToolbarItem(placement: .navigation) {
                    Button(action: { showingAuthorSettings = true }) {
                        if let profile = profiles.first {
                            ZStack {
                                if let imageData = profile.avatarData, let nsImage = NSImage(data: imageData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Text(String(profile.penName.prefix(1)).uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.accentColor.gradient)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                        } else {
                            // 如果還沒設定作者，顯示一個提示圖示
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(profiles.first?.penName ?? "設定作者帳號")
                }
                
                // 右側：新建書籍
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewBookSheet = true }) {
                        Label("新建書籍", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBookSheet) {
                NewBookSheet()
            }
            // 【V1.4 新增】彈出作者設定頁
            .sheet(isPresented: $showingAuthorSettings) {
                AuthorSettingsView()
            }
            .navigationDestination(for: Book.self) { book in
                BookOverviewView(book: book)
            }
            // 【新增】刪除確認對話框（符合 PRD：提醒無法復原）
            .alert("確認刪除", isPresented: $showingDeleteAlert, presenting: bookToDelete) { book in
                Button("取消", role: .cancel) { }
                Button("刪除", role: .destructive) {
                    modelContext.delete(book)
                }
            } message: { book in
                Text("確定要刪除《\(book.title)》嗎？此操作無法復原。")
            }
        }
    }
}

// MARK: - 書籍卡片視圖 (調整為豎長方形)
struct BookCardView: View {
    let book: Book
    
    var firstCharacter: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 【上半部：極簡封面】
            ZStack {
                generatePastelColor(from: book.title)
                Text(firstCharacter)
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            
            // 【下半部：書腰區域】
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack {
                    Label("\(calculateTotalWords()) 字", systemImage: "character.textbox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("建立：\(book.createdAt, style: .date)")
                    Text("更新：\(book.updatedAt, style: .date)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 180, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func calculateTotalWords() -> Int {
        var total = 0
        for volume in book.volumes {
            for section in volume.sections {
                total += section.wordCount
            }
        }
        return total
    }

    private func generatePastelColor(from string: String) -> Color {
        var hash = 0
        for char in string.unicodeScalars {
            hash = Int(char.value) &+ (hash << 5) &- hash
        }
        let r = Double((hash >> 16) & 0xFF) / 255.0 * 0.3 + 0.7
        let g = Double((hash >> 8) & 0xFF) / 255.0 * 0.3 + 0.7
        let b = Double(hash & 0xFF) / 255.0 * 0.3 + 0.7
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - 新建書籍視窗
struct NewBookSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 【V1.4 新增】查詢作者帳號，用來自動帶入筆名
    @Query private var profiles: [AuthorProfile]
    
    @State private var title = ""
    // 【V1.4 修改】改為空字串，在 onAppear 中賦值，避免初始化時讀取不到 SwiftData
    @State private var author = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("書名", text: $title)
                TextField("作者", text: $author)
            }
            .navigationTitle("新建書籍")
            // 【V1.4 新增】畫面出現時，自動帶入筆名
            .onAppear {
                if author.isEmpty {
                    // 優先讀取 AuthorProfile 的筆名，若無則 fallback 到 Mac 系統使用者名稱
                    author = profiles.first?.penName ?? NSFullUserName()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        saveBook()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func saveBook() {
        let newBook = Book(title: title, author: author)
        let defaultVolume = Volume(title: "第一卷", book: newBook)
        newBook.volumes.append(defaultVolume)
        modelContext.insert(newBook)
        dismiss()
    }
}
