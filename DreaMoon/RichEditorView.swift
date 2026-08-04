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
    fileprivate var pendingSelection: NSRange?
    fileprivate var pendingSectionID: UUID?
}

// MARK: - 自訂 NSTextView 子類
final class DreaMoonTextView: NSTextView {
    weak var coordinator: RichEditorView.Coordinator?
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }
    required init?(coder: NSCoder) { fatalError("不支援 storyboard 初始化") }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: nil)
        if let container = self.textContainer {
            container.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncFrameToScrollView()
        DispatchQueue.main.async { [weak self] in self?.syncFrameToScrollView() }
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
    }
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
    }
    override func deleteForward(_ sender: Any?) {
        super.deleteForward(sender)
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

// MARK: - 富文本編輯器
struct RichEditorView: NSViewRepresentable {
    let section: Section
    let bridge: EditorBridge
    var onWordCountChange: ((Int) -> Void)? = nil
    var onHeadingStateChange: ((Bool) -> Void)? = nil
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
        bridge.coordinator = context.coordinator
        let initial = section.content
        context.coordinator.lastCommitted = initial
        context.coordinator.lastSectionID = section.id
        let sectionID = section.id
        DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
            guard let textView,
                  let coordinator,
                  coordinator.lastSectionID == sectionID else { return }
            textView.textStorage?.setAttributedString(NSAttributedString(initial))
            coordinator.syncTypingAttributesToCursor()
            coordinator.reportHeadingState()
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
            textView.textStorage?.setAttributedString(NSAttributedString(section.content))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            coord.lastCommitted = section.content
            coord.syncTypingAttributesToCursor()
            // 修 422：view update 途中不可同步改 @State，丟下一 runloop
            let wc = countWords(textView.string)
            let wcCallback = onWordCountChange
            DispatchQueue.main.async { wcCallback?(wc) }
        }
        coord.onWordCountChange = onWordCountChange
        coord.onHeadingStateChange = onHeadingStateChange
        coord.bridge = bridge
        bridge.coordinator = coord
        if let pendingSelection = bridge.pendingSelection,
           bridge.pendingSectionID == nil || bridge.pendingSectionID == coord.lastSectionID {
            bridge.pendingSelection = nil
            bridge.pendingSectionID = nil
            coord.select(range: pendingSelection)
        }
        // 修 422：reportHeadingState 回調改 @State，不可在 updateNSView 同步執行
        DispatchQueue.main.async { [weak coord] in coord?.reportHeadingState() }
    }
    private func makeScrollViewAndTextView() -> (NSScrollView, DreaMoonTextView) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = DreaMoonTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            textContainer: textContainer
        )
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
        private var lastReportedHeadingState: Bool?
        private var debounceWork: DispatchWorkItem?
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let snapshot = AttributedString(tv.attributedString())
            let wc = countWords(tv.string)
            onWordCountChange?(wc)
            debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let sec = self.section else { return }
                sec.content = snapshot
                sec.wordCount = wc
                sec.updatedAt = Date()
                sec.volume?.book?.updatedAt = Date()
                self.lastCommitted = snapshot
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            syncTypingAttributesToCursor()
            reportHeadingState()
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
