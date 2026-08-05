import SwiftUI
import SwiftData
import AppKit

// MARK: - 主畫面：網格書櫃
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.updatedAt, order: .reverse) private var books: [Book]
    @Query private var profiles: [AuthorProfile]
    @State private var showingNewBookSheet = false
    @State private var searchText = ""
    @State private var showingAuthorSettings = false
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?
    @State private var bookToOpen: Book?

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

    let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if filteredBooks.isEmpty && searchText.isEmpty {
                    ContentUnavailableView {
                        Label("書櫃還沒有小說", systemImage: "books.vertical")
                    } description: {
                        Text("建立第一本小說，立即開始寫作。")
                    } actions: {
                        Button("建立第一本小說", systemImage: "plus") { showingNewBookSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    if filteredBooks.isEmpty {
                        ContentUnavailableView("找不到書籍", systemImage: "magnifyingglass")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(filteredBooks) { book in
                                    NavigationLink(value: book) {
                                        BookCardView(book: book)
                                    }
                                    .buttonStyle(.plain)
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
                            .padding(24)
                        }
                    }
                }
            }
            .navigationTitle("DreaMoon")
            .searchable(text: $searchText, prompt: "搜尋書名或作者")
            .toolbar {
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
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(profiles.first?.penName ?? "設定作者帳號")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewBookSheet = true }) {
                        Label("新建書籍", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBookSheet) {
                NewBookSheet { book in
                    bookToOpen = book
                }
            }
            .sheet(isPresented: $showingAuthorSettings) {
                AuthorSettingsView()
            }
            .navigationDestination(for: Book.self) { book in
                BookOverviewView(book: book)
            }
            .navigationDestination(for: Section.self) { section in
                if let book = section.volume?.book {
                    EditorWorkspaceView(book: book, initialSection: section)
                }
            }
            .navigationDestination(item: $bookToOpen) { book in
                if let section = book.volumes
                    .sorted(by: { $0.sortOrder < $1.sortOrder })
                    .flatMap({ $0.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) })
                    .first {
                    EditorWorkspaceView(book: book, initialSection: section)
                } else {
                    BookOverviewView(book: book)
                }
            }
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

// MARK: - 書籍卡片視圖
struct BookCardView: View {
    let book: Book

    var firstCharacter: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                generatePastelColor(from: book.title)
                Text(firstCharacter)
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
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
    @Query private var profiles: [AuthorProfile]
    @State private var title = ""
    @State private var author = ""
    let onCreated: (Book) -> Void

    init(onCreated: @escaping (Book) -> Void = { _ in }) {
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("書名", text: $title)
                TextField("作者", text: $author)
            }
            .navigationTitle("新建書籍")
            .onAppear {
                if author.isEmpty {
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

    @MainActor
    private func saveBook() {
        let newBook = Book(title: title, author: author)
        let defaultVolume = Volume(title: "第一卷", book: newBook)
        let firstSection = Section(title: "第一節", sortOrder: 0, volume: defaultVolume)
        defaultVolume.sections.append(firstSection)
        newBook.volumes.append(defaultVolume)
        modelContext.insert(newBook)

        // V3：建書即預建首年號與主軸（PRD 第 7 節 bootstrap）
        #if DEBUG
        do {
            try TimelineEngine.Bootstrap.ensure(for: newBook, in: modelContext)
            let eraStart = newBook.currentEra?.startOrdinal ?? -1
            let eraName  = newBook.currentEra?.name ?? "nil"
            let primary  = newBook.timelines.filter(\.isPrimary).count
            print("✅ [Bootstrap] 建書完成 → currentEra.startOrdinal=\(eraStart), name='\(eraName)', 主軸數=\(primary)")
        } catch {
            print("❌ [Bootstrap] 失敗：\(error)")
        }
        #else
        try? TimelineEngine.Bootstrap.ensure(for: newBook, in: modelContext)
        #endif

        do { try modelContext.save() } catch { print("❌ 新書儲存失敗：\(error)") }
        onCreated(newBook)
        dismiss()
    }
}
