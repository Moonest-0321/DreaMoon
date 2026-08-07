import SwiftUI
import AppKit
import SwiftData

// MARK: - 字數計算
fileprivate func countWords(_ string: String) -> Int {
    string.filter { !$0.isWhitespace }.count
}

// MARK: - 兩種固定樣式與行距設定
fileprivate let bodyFont    = NSFont.systemFont(ofSize: 14)
fileprivate let headingFont = NSFont.systemFont(ofSize: 18, weight: .bold)
fileprivate func makeParagraphStyle(lineHeightMultiple: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = lineHeightMultiple
    return style.copy() as! NSParagraphStyle
}
fileprivate let bodyParagraphStyle    = makeParagraphStyle(lineHeightMultiple: 1.35)
fileprivate let headingParagraphStyle = makeParagraphStyle(lineHeightMultiple: 1.62)
fileprivate let bodyAttrs: [NSAttributedString.Key: Any] = [
    .font: bodyFont,
    .foregroundColor: NSColor.textColor,
    .paragraphStyle: bodyParagraphStyle
]
fileprivate let headingAttrs: [NSAttributedString.Key: Any] = [
    .font: headingFont,
    .foregroundColor: NSColor.textColor,
    .paragraphStyle: headingParagraphStyle
]

enum CharacterReferenceLink {
    static func url(for characterID: UUID) -> URL {
        URL(string: "dreamoon://character/\(characterID.uuidString)")!
    }

    static func characterID(from value: Any) -> UUID? {
        let url: URL?
        if let value = value as? URL {
            url = value
        } else if let value = value as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        guard let url, url.scheme == "dreamoon", url.host == "character" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

struct CharacterMentionSuggestion {
    let id: UUID
    let characterName: String
    let insertionName: String
    let sortOrder: Int

    var isAlias: Bool { characterName != insertionName }
}
fileprivate func isHeadingFont(_ font: NSFont?) -> Bool {
    guard let font else { return false }
    return font.pointSize == 18 && font.fontDescriptor.symbolicTraits.contains(.bold)
}

// MARK: - 橋接物件
final class EditorBridge {
    weak var coordinator: RichEditorView.Coordinator?
    var isSearchMode = false
    func requestFindNext() {
        NotificationCenter.default.post(name: .dreaMoonFindNext, object: nil)
    }
    func requestToggleHeading() { coordinator?.toggleSceneHeading() }
    func focusEditor() { coordinator?.focusEditor() }
    func requestSelect(range: NSRange) {
        if let coordinator {
            coordinator.select(range: range)
        } else {
            pendingSelection = range
        }
    }
    func requestSelect(sectionID: UUID, range: NSRange) {
        guard coordinator?.lastSectionID != sectionID else {
            requestSelect(range: range)
            return
        }
        pendingSectionID = sectionID
        pendingSelection = range
    }
    func reloadVisibleContent() { coordinator?.reloadFromModel() }
    func flushPendingSave() { coordinator?.flushPendingSave() }
    fileprivate var pendingSelection: NSRange?
    fileprivate var pendingSectionID: UUID?
}

enum EditorSaveState: Equatable {
    case saved, saving, failed
    var label: String {
        switch self { case .saved: return "已儲存"; case .saving: return "儲存中…"; case .failed: return "儲存失敗" }
    }
}

// MARK: - 中文輸入法組字樣式
final class CompositionUnderlineLayoutManager: NSLayoutManager {
    weak var editorTextView: NSTextView?

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textView = editorTextView else { return }
        let markedRange = textView.markedRange()
        guard markedRange.location != NSNotFound, markedRange.length > 0 else { return }
        let markedGlyphRange = glyphRange(forCharacterRange: markedRange, actualCharacterRange: nil)
        let visibleMarkedGlyphRange = NSIntersectionRange(glyphsToShow, markedGlyphRange)
        guard visibleMarkedGlyphRange.length > 0 else { return }

        enumerateLineFragments(forGlyphRange: visibleMarkedGlyphRange) { _, _, textContainer, lineGlyphRange, _ in
            let fragmentGlyphRange = NSIntersectionRange(visibleMarkedGlyphRange, lineGlyphRange)
            guard fragmentGlyphRange.length > 0 else { return }
            let glyphRect = self.boundingRect(forGlyphRange: fragmentGlyphRange, in: textContainer)
            // NSTextView 為 flipped 座標；maxY 是字形下緣。從這裡畫線可讓線的上緣貼齊字底。
            let y = glyphRect.maxY + origin.y + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: glyphRect.minX + origin.x, y: y))
            path.line(to: NSPoint(x: glyphRect.maxX + origin.x, y: y))
            path.lineWidth = 1
            NSColor.textColor.setStroke()
            path.stroke()
        }
    }
}

class CompositionAwareTextView: NSTextView {
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let marked: NSMutableAttributedString
        if let attributed = string as? NSAttributedString {
            marked = NSMutableAttributedString(attributedString: attributed)
        } else {
            marked = NSMutableAttributedString(string: string as? String ?? "")
        }
        let range = NSRange(location: 0, length: marked.length)
        if range.length > 0 {
            // 關閉輸入法的預設底線，改由 CompositionUnderlineLayoutManager 依字形底部繪製。
            marked.removeAttribute(.underlineStyle, range: range)
            marked.removeAttribute(.underlineColor, range: range)
            marked.removeAttribute(.backgroundColor, range: range)
            marked.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        }
        super.setMarkedText(marked, selectedRange: selectedRange, replacementRange: replacementRange)
    }
}

// MARK: - 自訂 NSTextView 子類
final class DreaMoonTextView: CompositionAwareTextView {
    weak var coordinator: RichEditorView.Coordinator?
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }
    required init?(coder: NSCoder) { fatalError("不支援 storyboard 初始化") }
    override func mouseDown(with event: NSEvent) {
        coordinator?.onEditorFocus?()
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateCharacterLinkCursor(shiftIsPressed: event.modifierFlags.contains(.shift))
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCharacterLinkCursor(shiftIsPressed: false)
        syncFrameToScrollView()
        DispatchQueue.main.async { [weak self] in self?.syncFrameToScrollView() }
    }
    private func updateCharacterLinkCursor(shiftIsPressed: Bool) {
        var attributes = linkTextAttributes ?? [:]
        attributes[.cursor] = shiftIsPressed ? NSCursor.pointingHand : NSCursor.iBeam
        linkTextAttributes = attributes
        if let window {
            window.invalidateCursorRects(for: self)
        }
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.keyCode == 36, coordinator?.openSelectedCharacter() == true {
            return
        }
        super.keyDown(with: event)
    }
    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: nil)
        if let container = self.textContainer {
            container.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        syncFrameToScrollView()
    }
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        syncFrameToScrollView()
    }
    private func syncFrameToScrollView() {
        guard let cv = enclosingScrollView?.contentView else { return }
        let w = cv.bounds.width
        guard w > 0 else { return }
        if self.frame.width != w {
            var f = self.frame
            f.size.width = w
            self.frame = f
        }
        if let tc = self.textContainer, tc.containerSize.width != w {
            tc.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        let inserted: String
        if let string = insertString as? String {
            inserted = string
        } else if let attributed = insertString as? NSAttributedString {
            inserted = attributed.string
        } else {
            inserted = ""
        }
        if !inserted.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator?.showCharacterMentionMenuIfNeeded()
            }
        }
    }
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        DispatchQueue.main.async { [weak self] in
            self?.coordinator?.showCharacterMentionMenuIfNeeded()
        }
    }
    override func deleteForward(_ sender: Any?) {
        super.deleteForward(sender)
        DispatchQueue.main.async { [weak self] in
            self?.coordinator?.showCharacterMentionMenuIfNeeded()
        }
    }
    override func insertNewline(_ sender: Any?) {
        coordinator?.handleEnter()
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string), !raw.isEmpty else { return }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
        let font = coordinator?.currentParagraphFont() ?? bodyFont
        let attrs: [NSAttributedString.Key: Any] = isHeadingFont(font) ? headingAttrs : bodyAttrs
        let attr = NSAttributedString(string: normalized, attributes: attrs)
        self.insertText(attr, replacementRange: self.selectedRange())
    }

    // ⬇️ V3 Phase 3：右鍵捕獲（加入時間軸）⬇️
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let selectedText = selectedPlainText()
        let preview = String(selectedText.prefix(24))
        let createCharacterItem = NSMenuItem(
            title: preview.isEmpty ? "建立角色" : "建立角色「\(preview)」",
            action: #selector(createCharacterFromSelection(_:)),
            keyEquivalent: ""
        )
        createCharacterItem.target = self
        createCharacterItem.isEnabled = coordinator?.canCreateCharacter(named: selectedText) == true
        menu.addItem(createCharacterItem)

        let linkCharacterItem = NSMenuItem(
            title: preview.isEmpty ? "連結到角色" : "連結到角色「\(preview)」",
            action: #selector(linkCharacterFromSelection(_:)),
            keyEquivalent: ""
        )
        linkCharacterItem.target = self
        linkCharacterItem.isEnabled = coordinator?.canLinkCharacter(named: selectedText) == true
        menu.addItem(linkCharacterItem)

        let unlinkCharacterItem = NSMenuItem(
            title: "解除角色連結",
            action: #selector(unlinkCharacterFromSelection(_:)),
            keyEquivalent: ""
        )
        unlinkCharacterItem.target = self
        unlinkCharacterItem.isEnabled = selectedRangeHasCharacterLink()
        menu.addItem(unlinkCharacterItem)
        menu.addItem(NSMenuItem.separator())

        let captureItem = NSMenuItem(
            title: "加入時間軸",
            action: #selector(captureToTimeline(_:)),
            keyEquivalent: ""
        )
        captureItem.target = self
        captureItem.isEnabled = canCaptureSelectedDate()
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "剪下", action: #selector(cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "複製", action: #selector(copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "貼上", action: #selector(paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全選", action: #selector(selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    @objc func createCharacterFromSelection(_ sender: Any?) {
        coordinator?.createCharacter(named: selectedPlainText())
    }

    @objc func linkCharacterFromSelection(_ sender: Any?) {
        coordinator?.linkSelectedCharacter()
    }

    @objc func unlinkCharacterFromSelection(_ sender: Any?) {
        coordinator?.unlinkSelectedCharacter()
    }

    private func selectedPlainText() -> String {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= string.utf16.count else { return "" }
        return (string as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectedRangeHasCharacterLink() -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, NSMaxRange(range) <= storage.length else { return false }
        var found = false
        storage.enumerateAttribute(.link, in: range) { value, _, stop in
            if let value, CharacterReferenceLink.characterID(from: value) != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    @objc func captureToTimeline(_ sender: Any?) {
        guard let coord = coordinator,
              let section = coord.section,
              let book = section.volume?.book,
              let context = section.modelContext,
              let parsed = parseSelectedDate() else { return }
        try? TimelineEngine.Bootstrap.ensure(for: book, in: context)
        guard let era = book.currentEra,
              let primary = TimelineEngine.Query.primaryTimeline(for: book) else { return }
        let node = Node(year: parsed.year, month: parsed.month, day: parsed.day)
        context.insert(node)
        node.era = era
        node.timeline = primary
        node.section = section
        try? context.save()
        print("✅ [Capture] 捕獲節點 year=\(parsed.year) month=\(parsed.month ?? -1) day=\(parsed.day ?? -1) era='\(era.name)' section='\(section.title)'")
    }

    private func canCaptureSelectedDate() -> Bool { parseSelectedDate() != nil }

    private func parseSelectedDate() -> (year: Int, month: Int?, day: Int?)? {
        let sel = self.selectedRange()
        guard sel.length > 0 else { return nil }
        let full = self.string as NSString
        let selected = full.substring(with: sel)
        let pattern = #"(\d+)\s*年(?:\s*(\d+)\s*月)?(?:\s*(\d+)\s*[日号號])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(selected.startIndex..., in: selected)
        guard let match = regex.firstMatch(in: selected, range: range) else { return nil }
        func group(_ i: Int) -> Int? {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let sr = Range(r, in: selected) else { return nil }
            return Int(selected[sr])
        }
        guard let year = group(1) else { return nil }
        return (year, group(2), group(3))
    }
    // ⬆️ V3 Phase 3 結束 ⬆️
}

extension Notification.Name {
    static let dreaMoonPreviousSection = Notification.Name("dreaMoon.previousSection")
    static let dreaMoonNextSection = Notification.Name("dreaMoon.nextSection")
    static let dreaMoonCharacterReferencesChanged = Notification.Name("dreaMoon.characterReferencesChanged")
}

// MARK: - 富文本編輯器
struct RichEditorView: NSViewRepresentable {
    let section: Section
    let bridge: EditorBridge
    var onWordCountChange: ((Int) -> Void)? = nil
    var onHeadingStateChange: ((Bool) -> Void)? = nil
    var onSaveStateChange: ((EditorSaveState) -> Void)? = nil
    var onEditorFocus: (() -> Void)? = nil
    var onLoadingChange: ((Bool) -> Void)? = nil
    var onSelectionTextChange: ((String) -> Void)? = nil
    var onOpenSelectedText: ((String) -> Bool)? = nil
    var onOpenCharacterReference: ((UUID) -> Bool)? = nil
    var canCreateCharacter: ((String) -> Bool)? = nil
    var onCreateCharacter: ((String) -> Bool)? = nil
    var resolveCharacterID: ((String) -> UUID?)? = nil
    var characterSuggestions: (() -> [CharacterMentionSuggestion])? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = makeScrollViewAndTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.section = section
        context.coordinator.bridge = bridge
        context.coordinator.onWordCountChange = onWordCountChange
        context.coordinator.onHeadingStateChange = onHeadingStateChange
        context.coordinator.onSaveStateChange = onSaveStateChange
        context.coordinator.onEditorFocus = onEditorFocus
        context.coordinator.onLoadingChange = onLoadingChange
        context.coordinator.onSelectionTextChange = onSelectionTextChange
        context.coordinator.onOpenSelectedText = onOpenSelectedText
        context.coordinator.onOpenCharacterReference = onOpenCharacterReference
        context.coordinator.canCreateCharacterHandler = canCreateCharacter
        context.coordinator.onCreateCharacter = onCreateCharacter
        context.coordinator.resolveCharacterID = resolveCharacterID
        context.coordinator.characterSuggestions = characterSuggestions
        bridge.coordinator = context.coordinator
        let initial = section.content
        context.coordinator.lastCommitted = initial
        context.coordinator.lastSectionID = section.id
        let sectionID = section.id
        let isLongSection = section.wordCount > 5_000
        // 讓 NavigationSplitView 先完成首個 frame。長篇 AttributedString 的橋接與
        // TextKit 排版都只能在主執行緒完成，若與 push 動畫同一輪執行會明顯掉幀。
        if !initial.characters.isEmpty {
            context.coordinator.scheduleContentLoad(
                after: isLongSection ? 0.016 : 0,
                showsLoadingIndicator: isLongSection
            ) { [weak textView, weak coordinator = context.coordinator] in
                guard let textView,
                      let coordinator,
                      coordinator.lastSectionID == sectionID else { return }
                coordinator.apply(initial, to: textView, resetSelection: false)
            }
        }
        return scrollView
    }
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        guard let textView = coord.textView else { return }
        let sectionChanged = (coord.lastSectionID != section.id)
        if sectionChanged {
            coord.lastSectionID = section.id
            coord.section = section
            coord.lastCommitted = section.content
            let sectionID = section.id
            let content = section.content
            let isLongSection = section.wordCount > 5_000
            coord.scheduleContentLoad(
                after: isLongSection ? 0.016 : 0,
                showsLoadingIndicator: isLongSection
            ) { [weak textView, weak coord] in
                guard let textView, let coord, coord.lastSectionID == sectionID else { return }
                coord.apply(content, to: textView, resetSelection: true)
            }
            // 修 422：view update 途中不可同步改 @State，丟下一 runloop
            let wc = section.wordCount
            let wcCallback = onWordCountChange
            DispatchQueue.main.async { wcCallback?(wc) }
        }
        coord.onWordCountChange = onWordCountChange
        coord.onHeadingStateChange = onHeadingStateChange
        coord.onSaveStateChange = onSaveStateChange
        coord.onEditorFocus = onEditorFocus
        coord.onLoadingChange = onLoadingChange
        coord.onSelectionTextChange = onSelectionTextChange
        coord.onOpenSelectedText = onOpenSelectedText
        coord.onOpenCharacterReference = onOpenCharacterReference
        coord.canCreateCharacterHandler = canCreateCharacter
        coord.onCreateCharacter = onCreateCharacter
        coord.resolveCharacterID = resolveCharacterID
        coord.characterSuggestions = characterSuggestions
        coord.bridge = bridge
        bridge.coordinator = coord
        if let pendingSelection = bridge.pendingSelection,
           bridge.pendingSectionID == nil || bridge.pendingSectionID == coord.lastSectionID {
            bridge.pendingSelection = nil
            bridge.pendingSectionID = nil
            coord.select(range: pendingSelection)
        }
    }
    private func makeScrollViewAndTextView() -> (NSScrollView, DreaMoonTextView) {
        let textStorage = NSTextStorage()
        let layoutManager = CompositionUnderlineLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = DreaMoonTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            textContainer: textContainer
        )
        layoutManager.editorTextView = textView
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = bodyFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.typingAttributes = bodyAttrs
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12),
            .underlineStyle: 0,
            .cursor: NSCursor.iBeam
        ]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainer?.containerSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return (scrollView, textView)
    }
    // MARK: - Coordinator
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView? = nil
        weak var bridge: EditorBridge?
        var section: Section?
        var lastCommitted: AttributedString = AttributedString("")
        var lastSectionID: UUID? = nil
        var onWordCountChange: ((Int) -> Void)?
        var onHeadingStateChange: ((Bool) -> Void)?
        var onSaveStateChange: ((EditorSaveState) -> Void)?
        var onEditorFocus: (() -> Void)?
        var onLoadingChange: ((Bool) -> Void)?
        var onSelectionTextChange: ((String) -> Void)?
        var onOpenSelectedText: ((String) -> Bool)?
        var onOpenCharacterReference: ((UUID) -> Bool)?
        var canCreateCharacterHandler: ((String) -> Bool)?
        var onCreateCharacter: ((String) -> Bool)?
        var resolveCharacterID: ((String) -> UUID?)?
        var characterSuggestions: (() -> [CharacterMentionSuggestion])?
        private var lastReportedHeadingState: Bool?
        private var debounceWork: DispatchWorkItem?
        private var contentLoadWork: DispatchWorkItem?
        private var isReportingContentLoad = false

        func scheduleContentLoad(
            after delay: TimeInterval,
            showsLoadingIndicator: Bool,
            _ load: @escaping () -> Void
        ) {
            cancelScheduledContentLoad()
            // makeNSView/updateNSView 期間不能同步回寫 SwiftUI 狀態。
            isReportingContentLoad = showsLoadingIndicator
            if showsLoadingIndicator {
                let loadingCallback = onLoadingChange
                DispatchQueue.main.async { loadingCallback?(true) }
            }
            let work = DispatchWorkItem { [weak self] in
                load()
                self?.contentLoadWork = nil
            }
            contentLoadWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        func cancelScheduledContentLoad() {
            contentLoadWork?.cancel()
            contentLoadWork = nil
            finishReportingContentLoad()
        }

        func apply(_ content: AttributedString, to textView: NSTextView, resetSelection: Bool) {
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(NSAttributedString(content))
            textView.textStorage?.endEditing()
            if resetSelection {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            syncTypingAttributesToCursor()
            reportHeadingState()
            finishReportingContentLoad()
        }

        private func finishReportingContentLoad() {
            guard isReportingContentLoad else { return }
            isReportingContentLoad = false
            let loadingCallback = onLoadingChange
            DispatchQueue.main.async { loadingCallback?(false) }
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let wc = countWords(tv.string)
            onWordCountChange?(wc)
            onSaveStateChange?(.saving)
            debounceWork?.cancel()
            let targetSection = section
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self = self, let tv, let sec = targetSection else { return }
                let snapshot = AttributedString(tv.attributedString())
                sec.content = snapshot
                sec.wordCount = wc
                sec.updatedAt = Date()
                sec.volume?.book?.updatedAt = Date()
                do {
                    if let context = sec.modelContext { try context.save() }
                    self.lastCommitted = snapshot
                    self.onSaveStateChange?(.saved)
                } catch {
                    self.onSaveStateChange?(.failed)
                }
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        func flushPendingSave() {
            debounceWork?.perform()
            debounceWork = nil
        }
        func focusEditor() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        func openSelectedCharacter() -> Bool {
            guard let tv = textView else { return false }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= tv.string.utf16.count else { return false }
            let text = (tv.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return onOpenSelectedText?(text) ?? false
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // 角色參照是編輯器的內部識別資料，不可交由 macOS 當成外部 URL 開啟。
            guard let characterID = CharacterReferenceLink.characterID(from: link) else {
                return false
            }
            if NSEvent.modifierFlags.contains(.shift) {
                return onOpenCharacterReference?(characterID) ?? true
            }

            // 一般點擊仍是文字編輯操作：放置游標，不觸發角色跳轉。
            let location = min(max(0, charIndex), textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.window?.makeFirstResponder(textView)
            return true
        }
        func canCreateCharacter(named text: String) -> Bool {
            canCreateCharacterHandler?(text) ?? false
        }
        @discardableResult
        func createCharacter(named text: String) -> Bool {
            onCreateCharacter?(text) ?? false
        }
        func canLinkCharacter(named text: String) -> Bool {
            resolveCharacterID?(text) != nil
        }
        func linkSelectedCharacter() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            let text = (tv.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = resolveCharacterID?(text) else { return }
            storage.addAttribute(.link, value: CharacterReferenceLink.url(for: id), range: range)
            tv.didChangeText()
        }
        func unlinkSelectedCharacter() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            storage.removeAttribute(.link, range: range)
            tv.didChangeText()
        }
        private var activeMentionRange: NSRange?
        private var mentionMenuWorkItem: DispatchWorkItem?

        func showCharacterMentionMenuIfNeeded() {
            // 中文、日文等輸入法仍在組字時，候選字面板需要使用游標下方的位置；
            // 不可在此時彈出角色選單或搶走輸入焦點。
            guard let textView, !textView.hasMarkedText() else { return }
            mentionMenuWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.presentCharacterMentionMenuIfNeeded()
            }
            mentionMenuWorkItem = work
            // 不限制單字；使用短暫停頓讓作者可以自然輸入完整查詢。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
        }

        private func presentCharacterMentionMenuIfNeeded() {
            guard let tv = textView, !tv.hasMarkedText() else { return }
            guard let mentionRange = currentMentionRange(in: tv) else { return }
            let fullText = tv.string as NSString
            let queryRange = NSRange(location: mentionRange.location + 1, length: mentionRange.length - 1)
            let query = fullText.substring(with: queryRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }

            let suggestions = characterSuggestions?() ?? []
            let matchingSuggestions = suggestions.filter {
                $0.characterName.localizedCaseInsensitiveContains(query) ||
                $0.insertionName.localizedCaseInsensitiveContains(query)
            }
            guard !matchingSuggestions.isEmpty else { return }

            activeMentionRange = mentionRange
            let menu = NSMenu(title: "選擇角色")
            menu.autoenablesItems = false

            let duplicateInsertions = Dictionary(grouping: matchingSuggestions, by: { $0.insertionName })
                .filter { $0.value.count > 1 }.keys
            for suggestion in matchingSuggestions {
                var title = suggestion.isAlias
                    ? "\(suggestion.insertionName)　— \(suggestion.characterName) 的別名"
                    : suggestion.characterName
                if duplicateInsertions.contains(suggestion.insertionName) {
                    title += " · UID \(String(format: "%06d", suggestion.sortOrder + 1))"
                }
                let item = NSMenuItem(title: title, action: #selector(insertCharacterMention(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "\(suggestion.id.uuidString)|\(suggestion.insertionName)"
                menu.addItem(item)
            }

            menu.popUp(positioning: nil, at: mentionMenuPoint(in: tv), in: tv)
        }

        @objc private func insertCharacterMention(_ sender: NSMenuItem) {
            mentionMenuWorkItem?.cancel()
            guard let tv = textView,
                  let payload = sender.representedObject as? String,
                  let separator = payload.firstIndex(of: "|"),
                  let id = UUID(uuidString: String(payload[..<separator])),
                  let storage = tv.textStorage else { return }
            let insertionName = String(payload[payload.index(after: separator)...])
            guard let mentionRange = activeMentionRange,
                  NSMaxRange(mentionRange) <= storage.length else { return }

            var attributes = tv.typingAttributes
            attributes[.link] = CharacterReferenceLink.url(for: id)
            storage.replaceCharacters(
                in: mentionRange,
                with: NSAttributedString(string: insertionName, attributes: attributes)
            )
            let nextLocation = mentionRange.location + (insertionName as NSString).length
            tv.setSelectedRange(NSRange(location: nextLocation, length: 0))
            activeMentionRange = nil
            tv.didChangeText()
            syncTypingAttributesToCursor()
        }

        private func currentMentionRange(in textView: NSTextView) -> NSRange? {
            let cursor = textView.selectedRange().location
            guard cursor > 1 else { return nil }
            let text = textView.string as NSString
            var location = cursor - 1
            while location >= 0 {
                let character = text.substring(with: NSRange(location: location, length: 1))
                if character == "@" || character == "＠" {
                    return NSRange(location: location, length: cursor - location)
                }
                if character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || ".,，。！？!?；;：:()（）[]【】{}<>《》".contains(character) {
                    return nil
                }
                location -= 1
            }
            return nil
        }

        private func mentionMenuPoint(in textView: NSTextView) -> NSPoint {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  layoutManager.numberOfGlyphs > 0 else {
                return NSPoint(x: textView.textContainerInset.width, y: textView.textContainerInset.height + 20)
            }
            let characterIndex = max(0, min(textView.selectedRange().location - 1, textView.string.utf16.count - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            var point = layoutManager.location(forGlyphAt: glyphIndex)
            point.x += textView.textContainerInset.width
            point.y += textView.textContainerInset.height + layoutManager.defaultLineHeight(for: bodyFont)
            _ = textContainer
            return point
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            syncTypingAttributesToCursor()
            reportHeadingState()
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= tv.string.utf16.count else {
                onSelectionTextChange?("")
                return
            }
            let text = (tv.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onSelectionTextChange?(text)
        }
        func handleEnter() {
            if bridge?.isSearchMode == true {
                bridge?.requestFindNext()
            } else {
                handleSmartNewline()
            }
        }
        func select(range: NSRange) {
            guard let tv = textView else { return }
            let safeLocation = min(max(0, range.location), tv.string.utf16.count)
            let safeLength = min(max(0, range.length), tv.string.utf16.count - safeLocation)
            tv.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            tv.scrollRangeToVisible(NSRange(location: safeLocation, length: safeLength))
            tv.window?.makeFirstResponder(tv)
        }
        func reloadFromModel() {
            guard let tv = textView, let section else { return }
            let selectedRange = tv.selectedRange()
            tv.textStorage?.setAttributedString(NSAttributedString(section.content))
            select(range: selectedRange)
            lastCommitted = AttributedString(tv.attributedString())
            onWordCountChange?(countWords(tv.string))
            reportHeadingState()
        }
        func syncTypingAttributesToCursor() {
            guard let tv = textView else { return }
            guard let storage = tv.textStorage else {
                tv.typingAttributes = bodyAttrs
                return
            }
            let cursor = tv.selectedRange().location
            guard storage.length > 0 else {
                tv.typingAttributes = bodyAttrs
                return
            }
            let safeIndex = min(cursor, max(0, storage.length - 1))
            let font = (storage.attribute(.font, at: safeIndex, effectiveRange: nil) as? NSFont) ?? bodyFont
            let paraStyle = (storage.attribute(.paragraphStyle, at: safeIndex, effectiveRange: nil) as? NSParagraphStyle) ?? bodyParagraphStyle
            tv.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paraStyle
            ]
        }
        private func isHeading(forParagraphRange pr: NSRange, storage: NSTextStorage, tv: NSTextView) -> Bool {
            if pr.length > 0 {
                let f = (storage.attribute(.font, at: pr.location, effectiveRange: nil) as? NSFont) ?? bodyFont
                return isHeadingFont(f)
            } else {
                let f = (tv.typingAttributes[.font] as? NSFont) ?? bodyFont
                return isHeadingFont(f)
            }
        }
        func currentParagraphIsHeading() -> Bool {
            guard let tv = textView, let storage = tv.textStorage else { return false }
            let pr = (tv.string as NSString).paragraphRange(
                for: NSRange(location: tv.selectedRange().location, length: 0))
            return isHeading(forParagraphRange: pr, storage: storage, tv: tv)
        }
        func currentParagraphFont() -> NSFont { currentParagraphIsHeading() ? headingFont : bodyFont }
        func reportHeadingState() {
            let state = currentParagraphIsHeading()
            guard state != lastReportedHeadingState else { return }
            lastReportedHeadingState = state
            onHeadingStateChange?(state)
        }
        func toggleSceneHeading() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let pr = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
            let isCurrentlyHeading = currentParagraphIsHeading()
            let targetFont: NSFont = isCurrentlyHeading ? bodyFont : headingFont
            let targetParaStyle: NSParagraphStyle = isCurrentlyHeading ? bodyParagraphStyle : headingParagraphStyle
            let targetAttrs: [NSAttributedString.Key: Any] = [
                .font: targetFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: targetParaStyle
            ]
            tv.typingAttributes = targetAttrs
            if pr.length > 0 {
                storage.beginEditing()
                storage.addAttributes(targetAttrs, range: pr)
                storage.endEditing()
            }
            commitNow()
            reportHeadingState()
        }
        func handleSmartNewline() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            var sel = tv.selectedRange()
            if sel.length > 0 {
                storage.beginEditing()
                storage.replaceCharacters(in: sel, with: "")
                storage.endEditing()
                tv.didChangeText()
                sel = NSRange(location: sel.location, length: 0)
                tv.setSelectedRange(sel)
            }
            let cursor = sel.location
            let str = tv.string as NSString
            let paraRange = str.paragraphRange(for: NSRange(location: cursor, length: 0))
            let paraStart = paraRange.location
            let paraEnd = NSMaxRange(paraRange)
            let paraIsHeading = isHeading(forParagraphRange: paraRange, storage: storage, tv: tv)
            if !paraIsHeading {
                tv.insertText("\n", replacementRange: sel)
                syncTypingAttributesToCursor()
                reportHeadingState()
                return
            }
            let hasTrailingNewline = paraEnd > paraStart && str.character(at: paraEnd - 1) == 0x000A
            let textEnd = hasTrailingNewline ? (paraEnd - 1) : paraEnd
            storage.beginEditing()
            if cursor == paraStart {
                storage.replaceCharacters(in: NSRange(location: paraStart, length: 0), with: "\n")
                storage.addAttributes(bodyAttrs, range: NSRange(location: paraStart, length: 1))
                storage.endEditing()
                tv.setSelectedRange(NSRange(location: paraStart, length: 0))
                tv.typingAttributes = bodyAttrs
            } else if cursor >= textEnd {
                storage.replaceCharacters(in: NSRange(location: cursor, length: 0), with: "\n")
                storage.addAttributes(bodyAttrs, range: NSRange(location: cursor, length: 1))
                if hasTrailingNewline {
                    storage.addAttributes(bodyAttrs, range: NSRange(location: cursor + 1, length: 1))
                }
                storage.endEditing()
                tv.setSelectedRange(NSRange(location: cursor + 1, length: 0))
                tv.typingAttributes = bodyAttrs
            } else {
                let movedLen = textEnd - cursor
                storage.replaceCharacters(in: NSRange(location: cursor, length: 0), with: "\n")
                storage.addAttributes(bodyAttrs, range: NSRange(location: cursor, length: 1))
                if movedLen > 0 {
                    storage.addAttributes(bodyAttrs, range: NSRange(location: cursor + 1, length: movedLen))
                }
                storage.endEditing()
                tv.setSelectedRange(NSRange(location: cursor + 1, length: 0))
                tv.typingAttributes = bodyAttrs
            }
            tv.didChangeText()
            reportHeadingState()
        }
        private func commitNow() {
            guard let tv = textView, let sec = section else { return }
            let snapshot = AttributedString(tv.attributedString())
            let wc = countWords(tv.string)
            sec.content = snapshot
            sec.wordCount = wc
            sec.updatedAt = Date()
            sec.volume?.book?.updatedAt = Date()
            lastCommitted = snapshot
            debounceWork?.cancel()
            onWordCountChange?(wc)
        }
    }
}
