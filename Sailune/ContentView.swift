import SwiftUI
import SwiftData
import AppKit

// MARK: - 主畫面：網格書櫃
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.updatedAt, order: .reverse) private var books: [Book]
    @Query private var profiles: [AuthorProfile]
    @State private var navigationPath = NavigationPath()
    @State private var showingNewBookSheet = false
    @State private var searchText = ""
    @State private var showingAuthorSettings = false
    @State private var deletionRequest: BookDeletionRequest?

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

    private var libraryMetrics: (wordCount: Int, sectionCount: Int, byBookID: [UUID: BookStructure.Metrics]) {
        var wordCount = 0
        var sectionCount = 0
        var byBookID: [UUID: BookStructure.Metrics] = [:]
        byBookID.reserveCapacity(books.count)
        for book in books {
            let metrics = BookStructure.metrics(for: book)
            byBookID[book.id] = metrics
            wordCount += metrics.wordCount
            sectionCount += metrics.sectionCount
        }
        return (wordCount, sectionCount, byBookID)
    }

    var body: some View {
        let metrics = libraryMetrics
        NavigationStack(path: $navigationPath) {
            Group {
                if searchText.isEmpty {
                    ScrollView {
                        HStack(alignment: .top, spacing: 24) {
                            AuthorShelfCard(
                                profile: profiles.first,
                                bookCount: books.count,
                                wordCount: metrics.wordCount,
                                sectionCount: metrics.sectionCount,
                                onEdit: { showingAuthorSettings = true }
                            )

                            if books.isEmpty {
                                ContentUnavailableView {
                                    Label("書櫃還沒有小說", systemImage: "books.vertical")
                                } description: {
                                    Text("建立第一本小說，立即開始寫作。")
                                } actions: {
                                    Button("建立第一本小說", systemImage: "plus") { showingNewBookSheet = true }
                                        .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else {
                                LazyVGrid(columns: columns, spacing: 24) {
                                    ForEach(books) { book in
                                        NavigationLink(value: BookRoute(id: book.id, opensEditor: false)) {
                                            BookCardView(book: book, wordCount: metrics.byBookID[book.id]?.wordCount ?? 0)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deletionRequest = BookDeletionRequest(id: book.id, title: book.title)
                                            } label: {
                                                Label("刪除", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    if filteredBooks.isEmpty {
                        ContentUnavailableView("找不到書籍", systemImage: "magnifyingglass")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(filteredBooks) { book in
                                    NavigationLink(value: BookRoute(id: book.id, opensEditor: false)) {
                                        BookCardView(book: book, wordCount: metrics.byBookID[book.id]?.wordCount ?? 0)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deletionRequest = BookDeletionRequest(id: book.id, title: book.title)
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
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewBookSheet = true }) {
                        Label("新建書籍", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBookSheet) {
                NewBookSheet { book in
                    navigationPath.append(BookRoute(id: book.id, opensEditor: true))
                }
            }
            .sheet(isPresented: $showingAuthorSettings) {
                AuthorSettingsView()
            }
            .navigationDestination(for: BookRoute.self) { route in
                BookRouteDestination(route: route)
            }
            .navigationDestination(for: Section.self) { section in
                if let book = section.volume?.book {
                    EditorWorkspaceView(book: book, initialSection: section)
                }
            }
            .alert(
                "確認刪除",
                isPresented: Binding(
                    get: { deletionRequest != nil },
                    set: { if !$0 { deletionRequest = nil } }
                ),
                presenting: deletionRequest
            ) { request in
                Button("取消", role: .cancel) { }
                Button("刪除", role: .destructive) {
                    deleteBook(request)
                }
            } message: { request in
                Text("確定要刪除《\(request.title)》嗎？此操作無法復原。")
            }
        }
    }

    @MainActor
    private func deleteBook(_ request: BookDeletionRequest) {
        defer { deletionRequest = nil }
        guard let book = books.first(where: { $0.id == request.id }) else { return }

        do {
            let bookID = request.id
            try PersistentModelDeletion.deleteBook(book, in: modelContext)
            try? BookCoverStore.removeCover(forID: bookID)
        } catch {
            print("❌ 書籍刪除失敗：\(error.localizedDescription)")
        }
    }
}

private struct BookRoute: Hashable {
    let id: UUID
    let opensEditor: Bool
}

private struct BookDeletionRequest {
    let id: UUID
    let title: String
}

private struct BookRouteDestination: View {
    let route: BookRoute
    @Query private var books: [Book]

    init(route: BookRoute) {
        self.route = route
        let bookID = route.id
        _books = Query(filter: #Predicate<Book> { $0.id == bookID })
    }

    var body: some View {
        Group {
            if let book = books.first {
                destination(for: book)
            } else {
                ContentUnavailableView("找不到這本書", systemImage: "book.closed")
            }
        }
    }

    @ViewBuilder
    private func destination(for book: Book) -> some View {
        if route.opensEditor,
           let section = BookStructure.orderedSections(in: book).first {
            EditorWorkspaceView(book: book, initialSection: section)
        } else {
            BookOverviewView(book: book)
        }
    }
}

// MARK: - 書櫃作者卡片
private struct AuthorShelfCard: View {
    let profile: AuthorProfile?
    let bookCount: Int
    let wordCount: Int
    let sectionCount: Int
    let onEdit: () -> Void

    private var displayName: String {
        let penName = profile?.penName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return penName.isEmpty ? "我的創作空間" : penName
    }

    private var displayBio: String {
        let bio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bio.isEmpty ? "在這裡收集每一個正在成形的故事。" : bio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                avatar
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("編輯作者資料")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 7) {
                Text("AUTHOR")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(displayBio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Divider()

            HStack(spacing: 10) {
                StatisticLabel(value: "\(bookCount)", title: "作品")
                StatisticLabel(value: wordCount.formatted(), title: "字數")
                StatisticLabel(value: "\(sectionCount)", title: "章節")
            }
        }
        .padding(18)
        .frame(width: 216, height: 280, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = profile?.avatarData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(Circle())
        } else {
            Text(String(displayName.prefix(1)).uppercased())
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.gradient, in: Circle())
        }
    }
}

private struct StatisticLabel: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 書籍卡片視圖
struct BookCardView: View {
    let book: Book
    let wordCount: Int

    var body: some View {
        VStack(spacing: 0) {
            BookCoverArtwork(book: book)
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
                    Label("\(wordCount) 字", systemImage: "character.textbox")
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

}

// MARK: - 書籍封面
struct BookCoverArtwork: View {
    let book: Book

    private var firstCharacter: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1))
    }

    var body: some View {
        Group {
            if let image = BookCoverStore.image(for: book) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    defaultColor
                    Text(firstCharacter)
                        .font(.system(size: 64, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                }
            }
        }
        .clipped()
    }

    private var defaultColor: Color {
        var hash = 0
        for character in book.title.unicodeScalars {
            hash = Int(character.value) &+ (hash << 5) &- hash
        }
        let red = Double((hash >> 16) & 0xFF) / 255.0 * 0.3 + 0.7
        let green = Double((hash >> 8) & 0xFF) / 255.0 * 0.3 + 0.7
        let blue = Double(hash & 0xFF) / 255.0 * 0.3 + 0.7
        return Color(red: red, green: green, blue: blue)
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
