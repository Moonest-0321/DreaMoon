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
fileprivate extension NSAttributedString.Key {
    static let sailuneStoryTagMarker = NSAttributedString.Key("sailune.storyTagMarker")
}

enum CharacterReferenceSource: Equatable {
    case canonical
    case alias(UUID)
    case legacy
}

struct CharacterReference: Equatable {
    let characterID: UUID
    let source: CharacterReferenceSource
}

enum CharacterReferenceLink {
    private static let currentScheme = "sailune"

    static func url(for reference: CharacterReference) -> URL {
        var components = URLComponents()
        components.scheme = currentScheme
        components.host = "character"
        components.path = "/\(reference.characterID.uuidString)"
        switch reference.source {
        case .canonical:
            components.queryItems = [URLQueryItem(name: "source", value: "canonical")]
        case .alias(let aliasID):
            components.queryItems = [URLQueryItem(name: "alias", value: aliasID.uuidString)]
        case .legacy:
            break
        }
        return components.url!
    }

    static func url(for characterID: UUID) -> URL {
        url(for: CharacterReference(characterID: characterID, source: .canonical))
    }

    static func reference(from value: Any) -> CharacterReference? {
        let url: URL?
        if let value = value as? URL {
            url = value
        } else if let value = value as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == currentScheme,
              url.host == "character",
              let characterID = UUID(uuidString: url.lastPathComponent) else { return nil }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let aliasValue = queryItems.first(where: { $0.name == "alias" })?.value,
           let aliasID = UUID(uuidString: aliasValue) {
            return CharacterReference(characterID: characterID, source: .alias(aliasID))
        }
        if queryItems.contains(where: { $0.name == "source" && $0.value == "canonical" }) {
            return CharacterReference(characterID: characterID, source: .canonical)
        }
        return CharacterReference(characterID: characterID, source: .legacy)
    }

    static func characterID(from value: Any) -> UUID? {
        reference(from: value)?.characterID
    }
}

struct CharacterMentionSuggestion {
    let id: UUID
    let characterName: String
    let insertionName: String
    let sortOrder: Int
    let source: CharacterReferenceSource

    var isAlias: Bool { characterName != insertionName }
}

private struct CharacterMentionPayload {
    let reference: CharacterReference
    let insertionName: String
}

private struct CharacterLinkUndoRecord {
    let range: NSRange
    let value: Any
}
func isSceneHeadingFont(_ font: NSFont?) -> Bool {
    guard let font else { return false }
    return font.pointSize == 18 && font.fontDescriptor.symbolicTraits.contains(.bold)
}

// MARK: - 橋接物件
final class EditorBridge {
    weak var coordinator: RichEditorView.Coordinator?
    var isSearchMode = false
    func requestFindNext() {
        NotificationCenter.default.post(name: .sailuneFindNext, object: nil)
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
final class SailuneTextView: CompositionAwareTextView {
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
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // 角色呼叫只要被直接編輯，就先完整解除該呼叫的連結。
        // 文字照常修改，但不留下會在日後改名時重複展開的破碎連結。
        coordinator?.prepareCharacterLinksForEditing(affectedCharRange)
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }
    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: nil)
        if let container = self.textContainer {
            container.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
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
        let attrs: [NSAttributedString.Key: Any] = isSceneHeadingFont(font) ? headingAttrs : bodyAttrs
        let attr = NSAttributedString(string: normalized, attributes: attrs)
        self.insertText(attr, replacementRange: self.selectedRange())
    }

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

        let storyTagsMenu = NSMenu(title: "加入大綱／標籤")
        for kind in StoryTagKind.outlineCreationCases + StoryTagKind.allCases {
            let item = NSMenuItem(
                title: kind.editorActionTitle,
                action: #selector(createStoryTagFromSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = kind.rawValue
            item.isEnabled = selectedRange().length > 0
            storyTagsMenu.addItem(item)
        }
        let storyTagsItem = NSMenuItem(title: "加入大綱／標籤", action: nil, keyEquivalent: "")
        storyTagsItem.submenu = storyTagsMenu
        menu.addItem(storyTagsItem)
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

    @objc func createStoryTagFromSelection(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String,
              let storyKind = StoryTagKind(rawValue: kind) else { return }
        coordinator?.createStoryTag(kind: storyKind)
    }

}

extension Notification.Name {
    static let sailunePreviousSection = Notification.Name("sailune.previousSection")
    static let sailuneNextSection = Notification.Name("sailune.nextSection")
    static let sailuneWillChangeCharacterReferences = Notification.Name("sailune.willChangeCharacterReferences")
    static let sailuneCharacterReferencesChanged = Notification.Name("sailune.characterReferencesChanged")
    static let sailunePlanningMarkersChanged = Notification.Name("sailune.planningMarkersChanged")
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
    var onCreateCharacter: ((String) -> CharacterReference?)? = nil
    var resolveCharacterReference: ((String) -> CharacterReference?)? = nil
    var characterSuggestions: (() -> [CharacterMentionSuggestion])? = nil
    var onCreateStoryTag: ((StoryTagKind, String, NSRange) -> Void)? = nil
    var storyTags: () -> [StoryTag] = { [] }
    var outlineMarkers: () -> [(item: OutlineItem, anchor: OutlineItemAnchor)] = { [] }
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
        context.coordinator.resolveCharacterReference = resolveCharacterReference
        context.coordinator.characterSuggestions = characterSuggestions
        context.coordinator.onCreateStoryTag = onCreateStoryTag
        context.coordinator.storyTags = storyTags
        context.coordinator.outlineMarkers = outlineMarkers
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
        coord.resolveCharacterReference = resolveCharacterReference
        coord.characterSuggestions = characterSuggestions
        coord.onCreateStoryTag = onCreateStoryTag
        coord.storyTags = storyTags
        coord.outlineMarkers = outlineMarkers
        coord.bridge = bridge
        bridge.coordinator = coord
        if let pendingSelection = bridge.pendingSelection,
           bridge.pendingSectionID == nil || bridge.pendingSectionID == coord.lastSectionID {
            bridge.pendingSelection = nil
            bridge.pendingSectionID = nil
            coord.select(range: pendingSelection)
        }
    }
    private func makeScrollViewAndTextView() -> (NSScrollView, SailuneTextView) {
        let textStorage = NSTextStorage()
        let layoutManager = CompositionUnderlineLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = SailuneTextView(
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
        var onCreateCharacter: ((String) -> CharacterReference?)?
        var resolveCharacterReference: ((String) -> CharacterReference?)?
        var characterSuggestions: (() -> [CharacterMentionSuggestion])?
        var onCreateStoryTag: ((StoryTagKind, String, NSRange) -> Void)?
        var storyTags: () -> [StoryTag] = { [] }
        var outlineMarkers: () -> [(item: OutlineItem, anchor: OutlineItemAnchor)] = { [] }
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
            applyStoryTagMarkers(to: textView)
            if resetSelection {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            syncTypingAttributesToCursor()
            reportHeadingState()
            finishReportingContentLoad()
        }
        func createStoryTag(kind: StoryTagKind) {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= (tv.string as NSString).length else { return }
            let text = (tv.string as NSString).substring(with: range)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onCreateStoryTag?(kind, text, range)
        }
        private func applyStoryTagMarkers(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let whole = NSRange(location: 0, length: storage.length)
            guard whole.length > 0 else { return }
            storage.enumerateAttribute(.sailuneStoryTagMarker, in: whole) { value, range, _ in
                guard value != nil else { return }
                storage.removeAttribute(.sailuneStoryTagMarker, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
            }
            for tag in storyTags() where tag.sectionID == section?.id {
                let location = tag.resolvedOffset(in: textView.string)
                guard location < storage.length else { continue }
                let color: NSColor
                let opacity: CGFloat
                switch tag.kind {
                case .main: (color, opacity) = (.systemRed, 0.58)
                case .branch: (color, opacity) = (.systemBlue, 0.58)
                case .foreshadowing: (color, opacity) = (.systemYellow, 0.72)
                case .revision: (color, opacity) = (.systemOrange, 0.16)
                case .plannedAddition: (color, opacity) = (.systemGreen, 0.14)
                }
                let length = tag.markerLength(availableFromOffset: storage.length - location)
                guard length > 0 else { continue }
                let range = NSRange(location: location, length: length)
                storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(opacity), range: range)
                storage.addAttribute(.sailuneStoryTagMarker, value: tag.id.uuidString, range: range)
            }
            for marker in outlineMarkers() where marker.anchor.sectionID == section?.id {
                let location = marker.anchor.resolvedOffset(in: textView.string)
                guard location < storage.length else { continue }
                let color: NSColor = marker.item.status == .draft ? .systemGreen : .systemRed
                let range = NSRange(location: location, length: 1)
                storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.58), range: range)
                storage.addAttribute(.sailuneStoryTagMarker, value: marker.item.id.uuidString, range: range)
            }
        }
        private func storyTagFreeSnapshot(from attributed: NSAttributedString) -> AttributedString {
            let copy = NSMutableAttributedString(attributedString: attributed)
            let whole = NSRange(location: 0, length: copy.length)
            copy.enumerateAttribute(.sailuneStoryTagMarker, in: whole) { value, range, _ in
                guard value != nil else { return }
                copy.removeAttribute(.sailuneStoryTagMarker, range: range)
                copy.removeAttribute(.backgroundColor, range: range)
            }
            return AttributedString(copy)
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
                let snapshot = self.storyTagFreeSnapshot(from: tv.attributedString())
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
            guard let reference = onCreateCharacter?(text) else { return false }
            linkSelectedCharacter(to: reference)
            return true
        }
        func canLinkCharacter(named text: String) -> Bool {
            resolveCharacterReference?(text) != nil
        }
        func linkSelectedCharacter() {
            guard let tv = textView else { return }
            let selectedRange = tv.selectedRange()
            let fullText = tv.string as NSString
            guard selectedRange.length > 0, NSMaxRange(selectedRange) <= fullText.length else { return }
            let selectedText = fullText.substring(with: selectedRange)
            let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let reference = resolveCharacterReference?(trimmedText) else { return }
            linkSelectedCharacter(to: reference)
        }
        private func linkSelectedCharacter(to reference: CharacterReference) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let selectedRange = tv.selectedRange()
            guard selectedRange.length > 0, NSMaxRange(selectedRange) <= storage.length else { return }
            let selectedText = (tv.string as NSString).substring(with: selectedRange)
            let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let relativeRange = (selectedText as NSString).range(of: trimmedText)
            guard !trimmedText.isEmpty, relativeRange.location != NSNotFound else { return }
            let linkRange = NSRange(
                location: selectedRange.location + relativeRange.location,
                length: relativeRange.length
            )
            let linkedText = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: linkRange))
            linkedText.addAttribute(
                .link,
                value: CharacterReferenceLink.url(for: reference),
                range: NSRange(location: 0, length: linkedText.length)
            )
            replaceAttributedText(
                in: linkRange,
                with: linkedText,
                selectedRangeAfterChange: selectedRange,
                actionName: "連結角色"
            )
        }

        private func replaceAttributedText(
            in range: NSRange,
            with replacement: NSAttributedString,
            selectedRangeAfterChange: NSRange,
            actionName: String
        ) {
            guard let tv = textView,
                  let storage = tv.textStorage,
                  range.location >= 0,
                  NSMaxRange(range) <= storage.length else { return }

            let original = storage.attributedSubstring(from: range)
            let selectionBeforeChange = tv.selectedRange()
            let replacementRange = NSRange(location: range.location, length: replacement.length)
            if let undoManager = tv.undoManager {
                undoManager.registerUndo(withTarget: self) { coordinator in
                    coordinator.replaceAttributedText(
                        in: replacementRange,
                        with: original,
                        selectedRangeAfterChange: selectionBeforeChange,
                        actionName: actionName
                    )
                }
                undoManager.setActionName(actionName)
            }

            storage.replaceCharacters(in: range, with: replacement)
            let selectionLocation = min(max(0, selectedRangeAfterChange.location), storage.length)
            let safeSelection = NSRange(
                location: selectionLocation,
                length: min(selectedRangeAfterChange.length, storage.length - selectionLocation)
            )
            tv.setSelectedRange(safeSelection)
            tv.didChangeText()
        }
        func unlinkSelectedCharacter() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let range = tv.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            removeCharacterLinks(
                in: characterLinkRanges(intersecting: range, in: storage),
                from: storage,
                registersUndo: true
            )
            tv.didChangeText()
        }
        func prepareCharacterLinksForEditing(_ range: NSRange) {
            guard let storage = textView?.textStorage else { return }
            removeCharacterLinks(
                in: characterLinkRanges(intersecting: range, in: storage),
                from: storage,
                registersUndo: true
            )
        }
        private func removeCharacterLinks(
            in ranges: [NSRange],
            from storage: NSTextStorage,
            registersUndo: Bool
        ) {
            guard !ranges.isEmpty else { return }
            let records = ranges.compactMap { range -> CharacterLinkUndoRecord? in
                guard range.length > 0,
                      NSMaxRange(range) <= storage.length,
                      let value = storage.attribute(.link, at: range.location, effectiveRange: nil) else { return nil }
                return CharacterLinkUndoRecord(range: range, value: value)
            }
            guard !records.isEmpty else { return }
            if registersUndo, let undoManager = textView?.undoManager {
                undoManager.registerUndo(withTarget: self) { coordinator in
                    coordinator.restoreCharacterLinks(records)
                }
                undoManager.setActionName("編輯角色呼叫")
            }
            for record in records {
                storage.removeAttribute(.link, range: record.range)
            }
        }
        private func restoreCharacterLinks(_ records: [CharacterLinkUndoRecord]) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let validRecords = records.filter {
                $0.range.length > 0 && NSMaxRange($0.range) <= storage.length
            }
            guard !validRecords.isEmpty else { return }
            if let undoManager = tv.undoManager {
                let ranges = validRecords.map(\.range)
                undoManager.registerUndo(withTarget: self) { coordinator in
                    guard let currentStorage = coordinator.textView?.textStorage else { return }
                    coordinator.removeCharacterLinks(in: ranges, from: currentStorage, registersUndo: true)
                    coordinator.textView?.didChangeText()
                }
            }
            for record in validRecords {
                storage.addAttribute(.link, value: record.value, range: record.range)
            }
            tv.didChangeText()
        }
        private func characterLinkRanges(intersecting range: NSRange, in storage: NSTextStorage) -> [NSRange] {
            guard storage.length > 0 else { return [] }

            // 插入點只有位於連結內部時才解除；位於尾端時應讓作者自然接著寫。
            if range.length == 0 {
                guard range.location > 0, range.location < storage.length else { return [] }
                var effectiveRange = NSRange(location: 0, length: 0)
                let value = storage.attribute(
                    .link,
                    at: range.location,
                    longestEffectiveRange: &effectiveRange,
                    in: NSRange(location: 0, length: storage.length)
                )
                guard range.location > effectiveRange.location,
                      range.location < NSMaxRange(effectiveRange),
                      let value,
                      CharacterReferenceLink.characterID(from: value) != nil else { return [] }
                return [effectiveRange]
            }

            let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard safeRange.length > 0 else { return [] }
            var result: [NSRange] = []
            var cursor = safeRange.location
            while cursor < NSMaxRange(safeRange) {
                var effectiveRange = NSRange(location: cursor, length: 1)
                let value = storage.attribute(
                    .link,
                    at: cursor,
                    longestEffectiveRange: &effectiveRange,
                    in: NSRange(location: 0, length: storage.length)
                )
                if let value,
                   CharacterReferenceLink.characterID(from: value) != nil,
                   !result.contains(effectiveRange) {
                    result.append(effectiveRange)
                }
                cursor = max(cursor + 1, NSMaxRange(effectiveRange))
            }
            return result
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
                item.representedObject = CharacterMentionPayload(
                    reference: CharacterReference(characterID: suggestion.id, source: suggestion.source),
                    insertionName: suggestion.insertionName
                )
                menu.addItem(item)
            }

            menu.popUp(positioning: nil, at: mentionMenuPoint(in: tv), in: tv)
        }

        @objc private func insertCharacterMention(_ sender: NSMenuItem) {
            mentionMenuWorkItem?.cancel()
            guard let tv = textView,
                  let payload = sender.representedObject as? CharacterMentionPayload,
                  let storage = tv.textStorage else { return }
            let insertionName = payload.insertionName
            guard let mentionRange = activeMentionRange,
                  NSMaxRange(mentionRange) <= storage.length else { return }

            var attributes = tv.typingAttributes
            attributes[.link] = CharacterReferenceLink.url(for: payload.reference)
            let nextLocation = mentionRange.location + (insertionName as NSString).length
            replaceAttributedText(
                in: mentionRange,
                with: NSAttributedString(string: insertionName, attributes: attributes),
                selectedRangeAfterChange: NSRange(location: nextLocation, length: 0),
                actionName: "插入角色呼叫"
            )
            activeMentionRange = nil
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
            applyStoryTagMarkers(to: tv)
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
                return isSceneHeadingFont(f)
            } else {
                let f = (tv.typingAttributes[.font] as? NSFont) ?? bodyFont
                return isSceneHeadingFont(f)
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
