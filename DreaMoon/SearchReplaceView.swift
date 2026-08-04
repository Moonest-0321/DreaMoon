import SwiftUI
import AppKit

extension Notification.Name {
    static let dreaMoonFindNext = Notification.Name("DreaMoon.FindNextSearchResult")
}

enum SearchScope: String, CaseIterable, Identifiable {
    case section = "本節次"
    case book = "全書"

    var id: String { rawValue }
}

struct SearchMatch: Identifiable {
    let id = UUID()
    let section: Section
    let range: NSRange
}

private func plainText(of section: Section) -> String {
    NSAttributedString(section.content).string
}

private func matches(in text: String, query: String) -> [NSRange] {
    guard !query.isEmpty else { return [] }
    let source = text as NSString
    var result: [NSRange] = []
    var searchLocation = 0
    while searchLocation < source.length {
        let range = source.range(
            of: query,
            options: [.caseInsensitive],
            range: NSRange(location: searchLocation, length: source.length - searchLocation)
        )
        guard range.location != NSNotFound else { break }
        result.append(range)
        searchLocation = NSMaxRange(range)
    }
    return result
}

private func orderedSections(in book: Book) -> [Section] {
    book.volumes
        .sorted { $0.sortOrder < $1.sortOrder }
        .flatMap { $0.sections.sorted { $0.sortOrder < $1.sortOrder } }
}

private func replace(_ match: SearchMatch, with replacement: String) {
    let attributed = NSMutableAttributedString(attributedString: NSAttributedString(match.section.content))
    guard match.range.location != NSNotFound,
          NSMaxRange(match.range) <= attributed.length else { return }

    let attributes = attributed.attributes(at: match.range.location, effectiveRange: nil)
    attributed.replaceCharacters(in: match.range, with: replacement)
    if !replacement.isEmpty {
        attributed.addAttributes(attributes, range: NSRange(location: match.range.location, length: (replacement as NSString).length))
    }
    match.section.content = AttributedString(attributed)
    match.section.wordCount = attributed.string.filter { !$0.isWhitespace }.count
    match.section.updatedAt = Date()
    match.section.volume?.book?.updatedAt = Date()
}

struct SearchReplaceView: View {
    let book: Book
    @Binding var selectedSection: Section?
    let bridge: EditorBridge

    @State private var query = ""
    @State private var replacement = ""
    @State private var replacementEnabled = false
    @State private var scope: SearchScope = .section
    @State private var results: [SearchMatch] = []
    @State private var currentIndex = 0
    @FocusState private var queryFocused: Bool

    private var currentMatch: SearchMatch? {
        guard results.indices.contains(currentIndex) else { return nil }
        return results[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("查找與替換").font(.headline)
                Spacer()
                Text(resultSummary).font(.caption).foregroundStyle(.secondary)
            }

            TextField("查找文字", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($queryFocused)
                .onSubmit { advanceSearch() }

            Toggle("啟用替換", isOn: $replacementEnabled)

            if replacementEnabled {
                TextField("替換為", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { advanceSearch() }
            }

            Picker("查找範圍", selection: $scope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("上一筆") { reveal(offset: -1) }
                Button("下一筆") { reveal(offset: 1) }
                Spacer()
                if replacementEnabled {
                    Button("替換") { replaceCurrent() }
                        .disabled(currentMatch == nil)
                    Button("全部替換") { replaceAll() }
                        .disabled(results.isEmpty)
                }
            }

            if let currentMatch, scope == .book {
                Text("目前：\(currentMatch.section.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            bridge.isSearchMode = true
            queryFocused = true
            refresh()
        }
        .onDisappear {
            bridge.isSearchMode = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .dreaMoonFindNext)) { _ in
            advanceSearch()
        }
        .onChange(of: query) { _, _ in refresh() }
        .onChange(of: scope) { _, _ in refresh() }
        .onChange(of: selectedSection?.id) { _, _ in
            if scope == .section { refresh() }
        }
    }

    private var resultSummary: String {
        results.isEmpty ? "沒有結果" : "\(currentIndex + 1) / \(results.count)"
    }

    private func refresh() {
        let sections: [Section]
        if scope == .section, let selectedSection {
            sections = [selectedSection]
        } else if scope == .book {
            sections = orderedSections(in: book)
        } else {
            sections = []
        }

        results = sections.flatMap { section in
            matches(in: plainText(of: section), query: query).map { SearchMatch(section: section, range: $0) }
        }
        currentIndex = min(currentIndex, max(0, results.count - 1))
    }

    private func refreshAndRevealFirst() {
        refresh()
        guard !results.isEmpty else { return }
        currentIndex = 0
        revealCurrent()
    }

    private func advanceSearch() {
        if results.isEmpty {
            refreshAndRevealFirst()
        } else {
            reveal(offset: 1)
        }
    }

    private func reveal(offset: Int) {
        guard !results.isEmpty else { return }
        currentIndex = (currentIndex + offset + results.count) % results.count
        revealCurrent()
    }

    private func revealCurrent() {
        guard let match = currentMatch else { return }
        if selectedSection?.id != match.section.id {
            selectedSection = match.section
        }
        bridge.requestSelect(sectionID: match.section.id, range: match.range)
    }

    private func replaceCurrent() {
        guard let match = currentMatch else { return }
        replace(match, with: replacement)
        if selectedSection?.id == match.section.id { bridge.reloadVisibleContent() }
        refresh()
        currentIndex = min(currentIndex, max(0, results.count - 1))
        revealCurrent()
    }

    private func replaceAll() {
        let matchesToReplace = results
        // 同一節次的範圍來自替換前的文字，必須由後往前替換才不會因長度變化而偏移。
        for match in matchesToReplace.reversed() { replace(match, with: replacement) }
        if let selectedSection, matchesToReplace.contains(where: { $0.section.id == selectedSection.id }) {
            bridge.reloadVisibleContent()
        }
        refresh()
    }
}
