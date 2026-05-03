import Foundation

#if os(iOS)
import SwiftUI
import UIKit

#if canImport(Runestone)
import Runestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterPythonRunestone
import TreeSitterSwiftRunestone
#endif

/// Preview-only hit target for the code body.
///
/// The embedded Runestone/UITextView is not interactive while a code block is
/// rendered as an object preview. Leaving it interactive would let its own text
/// gestures compete with the outer editor and with block activation. This clear
/// control gives preview taps a deterministic activation target.
private final class CodeBlockActivationOverlay: UIControl {
    var onActivate: (() -> Void)?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onActivate?()
        super.touchesEnded(touches, with: event)
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

@MainActor
public final class MarkdownHybridEditorView: UIView, UITextViewDelegate {
    public var coordinator: MarkdownEditorCoordinator {
        didSet {
            applyPresentation()
        }
    }

    public let textView: UITextView
    public var onSourceChange: ((String) -> Void)?

    public override var accessibilityIdentifier: String? {
        get {
            super.accessibilityIdentifier
        }
        set {
            super.accessibilityIdentifier = newValue
            textView.accessibilityIdentifier = newValue
        }
    }

    private var isApplyingPresentation = false
    private var isTransferringFocusToCodeBlock = false
    private var scrollRestoreGeneration = 0
    private var codeBlockViews: [String: CodeBlockObjectView] = [:]

    public init(coordinator: MarkdownEditorCoordinator) {
        self.coordinator = coordinator
        self.textView = UITextView(frame: .zero, textContainer: nil)
        super.init(frame: .zero)
        configure()
        applyPresentation()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func applyPresentation(selectedSourceOffset: Int? = nil, preserveScrollPosition: Bool = true) {
        guard !isApplyingPresentation else { return }
        let currentSourceOffset = selectedSourceOffset ?? coordinator.sourceOffset(forVisibleOffset: textView.selectedRange.location)
        let needsTextUpdate = !textView.attributedText.isEqual(to: coordinator.presentation.attributedString)
        if !needsTextUpdate && selectedSourceOffset == nil {
            syncCodeBlockViews()
            syncOuterTextViewCaretVisibility()
            return
        }

        let shouldPreserveScrollOffset = preserveScrollPosition && isTrackingScrollPosition
        let preservedContentOffset = textView.contentOffset
        scrollRestoreGeneration += 1
        let restoreGeneration = scrollRestoreGeneration

        isApplyingPresentation = true
        UIView.performWithoutAnimation {
            if needsTextUpdate {
                textView.attributedText = coordinator.presentation.attributedString
            }
            let visibleOffset = outerSelectionVisibleOffset(forSourceOffset: currentSourceOffset)
            textView.selectedRange = NSRange(location: min(visibleOffset, textView.attributedText.length), length: 0)
            syncOuterTextViewCaretVisibility()
            syncCodeBlockViews()
            restoreContentOffset(preservedContentOffset, when: shouldPreserveScrollOffset)
        }
        isApplyingPresentation = false

        guard shouldPreserveScrollOffset else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.scrollRestoreGeneration == restoreGeneration else { return }
            self.restoreContentOffset(preservedContentOffset, when: true)
            self.layoutCodeBlockViews()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        syncCodeBlockViews()
    }

    public func activateCodeBlock(blockID: String) {
        guard let block = coordinator.document.block(id: blockID) else { return }
        if coordinator.activeScope == .codeBlock(blockID) {
            syncOuterTextViewCaretVisibility()
            focusCodeBlockEditor(blockID: blockID, scrollIntoView: false)
            return
        }
        _ = coordinator.activate(scope: .codeBlock(blockID), preservingSourceOffset: block.sourceRange.location)
        applyPresentation(selectedSourceOffset: block.sourceRange.location, preserveScrollPosition: false)
        focusCodeBlockEditor(blockID: blockID, scrollIntoView: true)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView === self.textView, !isApplyingPresentation, textView.markedTextRange == nil else { return }
        let selectedRange = textView.selectedRange
        let sourceOffset = coordinator.sourceOffset(forVisibleOffset: selectedRange.location)
        let newVisibleOffset = coordinator.activate(atVisibleOffset: selectedRange.location)
        if newVisibleOffset != selectedRange.location || !textView.attributedText.isEqual(to: coordinator.presentation.attributedString) {
            applyPresentation(selectedSourceOffset: sourceOffset)
        }
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === self.textView else { return }
        guard !isTransferringFocusToCodeBlock else { return }
        coordinator.deactivate()
        applyPresentation()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Scrolling changes which code-block attachments are near the viewport;
        // refresh lazy-mounted object views without rebuilding the presentation.
        guard scrollView === textView, !isApplyingPresentation else { return }
        syncVisibleCodeBlockViews()
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard textView === self.textView else { return true }
        if textView.markedTextRange != nil {
            return true
        }

        guard !visibleRangeIntersectsCodeBlock(range) else {
            _ = coordinator.activate(atVisibleOffset: range.location)
            applyPresentation()
            return false
        }

        let sourceStart = coordinator.sourceOffset(forVisibleOffset: range.location)
        let sourceEnd = coordinator.sourceOffset(forVisibleOffset: range.location + range.length)

        _ = coordinator.activate(atVisibleOffset: range.location)

        let activeStart = coordinator.visibleOffset(forSourceOffset: sourceStart)
        let activeEnd = coordinator.visibleOffset(forSourceOffset: sourceEnd)
        let activeRange = NSRange(location: activeStart, length: max(0, activeEnd - activeStart))

        guard let result = coordinator.replaceVisible(range: activeRange, with: text) else {
            applyPresentation()
            return false
        }

        applyPresentation(selectedSourceOffset: result.selectionSourceOffset)
        onSourceChange?(coordinator.source)
        return false
    }

    private func configure() {
        backgroundColor = .systemBackground
        clipsToBounds = true
        accessibilityIdentifier = "HybridMarkdownEditorContainer"

        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .systemBackground
        textView.clipsToBounds = true
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.isScrollEnabled = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
        textView.accessibilityIdentifier = "HybridMarkdownEditor"
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private var isTrackingScrollPosition: Bool {
        textView.window != nil && textView.bounds.height > 0 && textView.contentSize.height > textView.bounds.height
    }

    private func restoreContentOffset(_ contentOffset: CGPoint, when shouldRestore: Bool) {
        guard shouldRestore else { return }
        textView.layoutIfNeeded()
        textView.setContentOffset(clampedContentOffset(contentOffset), animated: false)
    }

    private func clampedContentOffset(_ contentOffset: CGPoint) -> CGPoint {
        let inset = textView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, textView.contentSize.width - textView.bounds.width + inset.right)
        let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
        return CGPoint(
            x: min(max(contentOffset.x, minX), maxX),
            y: min(max(contentOffset.y, minY), maxY)
        )
    }
}

private extension MarkdownHybridEditorView {
    func syncCodeBlockViews() {
        guard textView.attributedText.length == coordinator.presentation.attributedString.length else {
            return
        }

        let presentations = codeBlockPresentations

        // Attachment heights still drive document layout when their object views
        // are offscreen, so keep sizing separate from expensive view creation.
        var needsLayout = false
        for presentation in presentations {
            needsLayout = updateAttachmentHeight(for: presentation) || needsLayout
        }
        if needsLayout {
            textView.layoutIfNeeded()
        }

        syncVisibleCodeBlockViews(with: presentations)
    }

    // Runestone views are expensive to create and syntax-highlight. Keep them
    // mounted only for visible blocks plus the active editor.
    func syncVisibleCodeBlockViews(with presentations: [MarkdownCodeBlockPresentation]? = nil) {
        guard textView.attributedText.length == coordinator.presentation.attributedString.length else {
            return
        }

        let presentations = presentations ?? codeBlockPresentations
        let liveIDs = Set(presentations.map(\.blockID))
        for staleID in codeBlockViews.keys where !liveIDs.contains(staleID) {
            codeBlockViews.removeValue(forKey: staleID)?.removeFromSuperview()
        }

        let visiblePresentations = visibleCodeBlockPresentations(in: presentations)
        let visibleIDs = Set(visiblePresentations.map(\.blockID))
        for (blockID, view) in codeBlockViews {
            view.isHidden = !visibleIDs.contains(blockID)
        }

        for presentation in visiblePresentations {
            let view = codeBlockViews[presentation.blockID] ?? makeCodeBlockView(for: presentation)
            view.isHidden = false
            view.update(presentation)
        }

        layoutCodeBlockViews(presentations: visiblePresentations)
    }

    func makeCodeBlockView(for presentation: MarkdownCodeBlockPresentation) -> CodeBlockObjectView {
        let view = CodeBlockObjectView()
        view.accessibilityIdentifier = "CodeBlockView-\(presentation.blockID)"
        view.onActivate = { [weak self] blockID in
            self?.activateCodeBlock(blockID: blockID)
        }
        view.onContentChange = { [weak self] blockID, content in
            guard let self else { return }
            coordinator.replaceCodeContent(blockID: blockID, with: content)
            onSourceChange?(coordinator.source)
            applyPresentation(selectedSourceOffset: coordinator.document.block(id: blockID)?.code?.codeContentRange.location)
        }
        view.onLanguageChange = { [weak self] blockID, language in
            guard let self else { return }
            coordinator.updateCodeLanguage(blockID: blockID, language: language)
            onSourceChange?(coordinator.source)
            applyPresentation(selectedSourceOffset: coordinator.document.block(id: blockID)?.sourceRange.location)
        }
        textView.addSubview(view)
        codeBlockViews[presentation.blockID] = view
        return view
    }

    func updateAttachmentHeight(for presentation: MarkdownCodeBlockPresentation) -> Bool {
        guard let attachment = codeBlockAttachment(at: presentation.visibleRange.location) else { return false }
        let targetHeight = CodeBlockObjectView.preferredHeight(for: presentation.codeContent, width: codeBlockContentWidth)
        guard abs((attachment.bounds.height) - targetHeight) > 0.5 else { return false }

        attachment.updateHeight(targetHeight)
        textView.layoutManager.invalidateLayout(forCharacterRange: presentation.visibleRange, actualCharacterRange: nil)
        textView.layoutManager.invalidateDisplay(forCharacterRange: presentation.visibleRange)
        textView.setNeedsLayout()
        return true
    }

    func layoutCodeBlockViews(presentations: [MarkdownCodeBlockPresentation]? = nil) {
        guard textView.attributedText.length == coordinator.presentation.attributedString.length else {
            return
        }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let width = codeBlockContentWidth
        let presentations = presentations ?? visibleCodeBlockPresentations(in: codeBlockPresentations)

        for presentation in presentations {
            guard let view = codeBlockViews[presentation.blockID],
                  presentation.visibleRange.location < textView.attributedText.length else {
                continue
            }
            let glyphRange = textView.layoutManager.glyphRange(
                forCharacterRange: presentation.visibleRange,
                actualCharacterRange: nil
            )
            var rect = textView.layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textView.textContainer
            )
            rect.origin.x = textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            rect.size.width = width
            rect.size.height = max(CodeBlockObjectView.preferredHeight(for: presentation.codeContent, width: width), rect.height)
            view.frame = rect.integral
            textView.bringSubviewToFront(view)
        }
    }

    func scrollCodeBlockToVisible(blockID: String) {
        if let presentation = codeBlockPresentation(blockID: blockID) {
            let view = codeBlockViews[presentation.blockID] ?? makeCodeBlockView(for: presentation)
            view.isHidden = false
            view.update(presentation)
            if updateAttachmentHeight(for: presentation) {
                textView.layoutIfNeeded()
            }
            layoutCodeBlockViews(presentations: [presentation])
        } else {
            layoutCodeBlockViews()
        }
        guard let view = codeBlockViews[blockID] else { return }

        let targetRect = view.frame.insetBy(dx: 0, dy: -12)
        textView.scrollRectToVisible(targetRect, animated: false)
        layoutCodeBlockViews(presentations: visibleCodeBlockPresentations(in: codeBlockPresentations))
    }

    func focusCodeBlockEditor(blockID: String, scrollIntoView: Bool) {
        isTransferringFocusToCodeBlock = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if scrollIntoView {
                self.scrollCodeBlockToVisible(blockID: blockID)
            }
            self.codeBlockViews[blockID]?.focusEditor()
            DispatchQueue.main.async { [weak self] in
                self?.isTransferringFocusToCodeBlock = false
            }
        }
    }

    func visibleRangeIntersectsCodeBlock(_ range: NSRange) -> Bool {
        let target = NSRange(location: range.location, length: max(range.length, 1))
        return coordinator.presentation.blocks.contains { presentation in
            guard presentation.kind == .codeBlock else { return false }
            return NSIntersectionRange(target, presentation.visibleRange).length > 0 || target.location == presentation.visibleRange.location
        }
    }

    func outerSelectionVisibleOffset(forSourceOffset sourceOffset: Int) -> Int {
        if let activeCodeBlockPresentation {
            if sourceOffset >= activeCodeBlockPresentation.sourceRange.upperBound {
                return coordinator.visibleOffset(forSourceOffset: sourceOffset)
            }
            return activeCodeBlockPresentation.visibleRange.location
        }
        return coordinator.visibleOffset(forSourceOffset: sourceOffset)
    }

    func syncOuterTextViewCaretVisibility() {
        if let activeCodeBlockPresentation,
           textView.selectedRange.location < activeCodeBlockPresentation.visibleRange.upperBound {
            textView.tintColor = .clear
        } else {
            textView.tintColor = tintColor
        }
    }

    var activeCodeBlockPresentation: MarkdownCodeBlockPresentation? {
        guard let blockID = activeCodeBlockID else { return nil }
        return codeBlockPresentation(blockID: blockID)
    }

    var activeCodeBlockID: String? {
        guard case .codeBlock(let blockID) = coordinator.activeScope else { return nil }
        return blockID
    }

    var codeBlockPresentations: [MarkdownCodeBlockPresentation] {
        coordinator.presentation.blocks.compactMap(\.codeBlock)
    }

    func codeBlockPresentation(blockID: String) -> MarkdownCodeBlockPresentation? {
        coordinator.presentation.blocks.first { $0.blockID == blockID }?.codeBlock
    }

    func codeBlockAttachment(at location: Int) -> MarkdownCodeBlockAttachment? {
        guard location < textView.attributedText.length else { return nil }
        return textView.attributedText.attribute(.attachment, at: location, effectiveRange: nil) as? MarkdownCodeBlockAttachment
    }

    var codeBlockContentWidth: CGFloat {
        let inset = textView.textContainerInset
        return max(1, textView.bounds.width - inset.left - inset.right)
    }

    func visibleCodeBlockPresentations(in presentations: [MarkdownCodeBlockPresentation]) -> [MarkdownCodeBlockPresentation] {
        guard textView.bounds.height > 0,
              textView.attributedText.length > 0 else {
            return presentations
        }

        let textContainer = textView.textContainer
        textView.layoutManager.ensureLayout(for: textContainer)

        var visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
        visibleRect.origin.x -= textView.textContainerInset.left
        visibleRect.origin.y -= textView.textContainerInset.top
        // Use one extra viewport as a buffer so fast scrolling does not create
        // views exactly when a code block crosses the visible edge.
        visibleRect = visibleRect.insetBy(dx: 0, dy: -textView.bounds.height)

        let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let activeBlockID = activeCodeBlockID

        return presentations.filter { presentation in
            presentation.blockID == activeBlockID
                || NSIntersectionRange(characterRange, presentation.visibleRange).length > 0
                || characterRange.location == presentation.visibleRange.location
        }
    }
}

@MainActor
private final class CodeBlockObjectView: UIControl, UITextFieldDelegate {
    var onActivate: ((String) -> Void)?
    var onContentChange: ((String, String) -> Void)?
    var onLanguageChange: ((String, String) -> Void)?

    private let headerView = UIView()
    private let languageField = UITextField()
    private let copyButton = UIButton(type: .system)
    private let activationOverlay = CodeBlockActivationOverlay()
    #if canImport(Runestone)
    private let codeView = TextView(frame: .zero)
    private let theme = DefaultTheme()
    private var appliedRunestoneLanguage: String?
    #else
    private let codeView = UITextView(frame: .zero)
    #endif
    private var presentation: MarkdownCodeBlockPresentation?
    private var isUpdatingState = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ presentation: MarkdownCodeBlockPresentation) {
        self.presentation = presentation
        isUpdatingState = true

        languageField.text = presentation.language
        languageField.placeholder = presentation.displayLanguage
        languageField.accessibilityIdentifier = "CodeLanguageControl-\(presentation.blockID)"
        copyButton.accessibilityIdentifier = "CodeCopyButton-\(presentation.blockID)"
        codeView.accessibilityIdentifier = "CodeBlockEditor-\(presentation.blockID)"
        activationOverlay.accessibilityIdentifier = "CodeBlockActivationOverlay-\(presentation.blockID)"

        let isEditing = presentation.mode == .objectEditing
        activationOverlay.isHidden = isEditing
        activationOverlay.isUserInteractionEnabled = !isEditing
        activationOverlay.isAccessibilityElement = !isEditing
        #if canImport(Runestone)
        codeView.isEditable = isEditing
        codeView.isSelectable = isEditing
        // Preview mode renders plain code text; language-backed Runestone state
        // is deferred until editing so Tree-sitter setup happens on demand.
        let language = isEditing ? presentation.language : ""
        if codeView.text == presentation.codeContent,
           appliedRunestoneLanguage == language {
            // The user may have just typed this text; avoid resetting state and moving the caret.
        } else if codeView.text != presentation.codeContent || appliedRunestoneLanguage != language {
            codeView.setState(runestoneState(text: presentation.codeContent, language: language))
            appliedRunestoneLanguage = language
        }
        #else
        codeView.isEditable = isEditing
        codeView.isSelectable = isEditing
        if codeView.text != presentation.codeContent {
            codeView.text = presentation.codeContent
        }
        #endif
        codeView.isUserInteractionEnabled = isEditing

        setActiveAppearance(isEditing)
        isUpdatingState = false
        setNeedsLayout()
    }

    static func preferredHeight(for text: String, width: CGFloat) -> CGFloat {
        let visualLineCount = wrappedLineCount(for: text, width: width)
        let contentHeight = CGFloat(visualLineCount) * 20 + 16
        return ceil(max(84, 36 + contentHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight: CGFloat = 36
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)

        let horizontalInset: CGFloat = 10
        let buttonWidth: CGFloat = 64
        copyButton.frame = CGRect(
            x: bounds.width - horizontalInset - buttonWidth,
            y: 5,
            width: buttonWidth,
            height: 26
        )
        languageField.frame = CGRect(
            x: horizontalInset,
            y: 5,
            width: max(44, copyButton.frame.minX - horizontalInset * 2),
            height: 26
        )
        codeView.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )
        activationOverlay.frame = codeView.frame
        if !activationOverlay.isHidden {
            bringSubviewToFront(activationOverlay)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        // In preview mode, route code-body taps to the overlay instead of the
        // disabled code view. In editing mode the overlay is hidden, so Runestone
        // receives text interaction normally.
        if presentation?.mode != .objectEditing, codeView.frame.contains(point) {
            let overlayPoint = convert(point, to: activationOverlay)
            return activationOverlay.hitTest(overlayPoint, with: event) ?? activationOverlay
        }
        return super.hitTest(point, with: event)
    }

    @objc private func activate() {
        guard let presentation else { return }
        guard presentation.mode != .objectEditing else { return }
        onActivate?(presentation.blockID)
    }

    @objc private func copyCode() {
        UIPasteboard.general.string = presentation?.codeContent ?? currentCodeText
    }

    @objc private func languageEditingDidEnd() {
        guard let presentation else { return }
        let language = (languageField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard language != presentation.language else { return }
        onLanguageChange?(presentation.blockID, language)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func focusEditor() {
        #if canImport(Runestone)
        _ = codeView.becomeFirstResponder()
        #else
        _ = codeView.becomeFirstResponder()
        #endif
    }

    private var currentCodeText: String {
        #if canImport(Runestone)
        codeView.text
        #else
        codeView.text ?? ""
        #endif
    }

    private func configure() {
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        layer.cornerRadius = 8
        layer.borderWidth = 1
        setActiveAppearance(false)

        headerView.backgroundColor = .tertiarySystemBackground
        addSubview(headerView)

        languageField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        languageField.textColor = .secondaryLabel
        languageField.borderStyle = .none
        languageField.autocorrectionType = .no
        languageField.autocapitalizationType = .none
        languageField.returnKeyType = .done
        languageField.delegate = self
        languageField.addTarget(self, action: #selector(languageEditingDidEnd), for: .editingDidEnd)
        languageField.addTarget(self, action: #selector(languageEditingDidEnd), for: .primaryActionTriggered)
        headerView.addSubview(languageField)

        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        headerView.addSubview(copyButton)

        #if canImport(Runestone)
        codeView.editorDelegate = self
        codeView.theme = theme
        codeView.backgroundColor = .clear
        codeView.isScrollEnabled = false
        codeView.alwaysBounceVertical = false
        codeView.alwaysBounceHorizontal = false
        codeView.showsVerticalScrollIndicator = false
        codeView.showsHorizontalScrollIndicator = false
        codeView.isLineWrappingEnabled = true
        codeView.showLineNumbers = false
        codeView.lineHeightMultiplier = 1.15
        codeView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 6, right: 10)
        codeView.autocorrectionType = .no
        codeView.autocapitalizationType = .none
        codeView.smartDashesType = .no
        codeView.smartQuotesType = .no
        codeView.spellCheckingType = .no
        #else
        codeView.delegate = self
        codeView.backgroundColor = .clear
        codeView.isScrollEnabled = false
        codeView.alwaysBounceVertical = false
        codeView.showsVerticalScrollIndicator = false
        codeView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        codeView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 6, right: 6)
        codeView.autocorrectionType = .no
        codeView.autocapitalizationType = .none
        codeView.smartDashesType = .no
        codeView.smartQuotesType = .no
        codeView.spellCheckingType = .no
        #endif
        addSubview(codeView)

        activationOverlay.backgroundColor = .clear
        activationOverlay.accessibilityLabel = "Edit code block"
        activationOverlay.accessibilityTraits = .button
        activationOverlay.onActivate = { [weak self] in
            self?.activate()
        }
        addSubview(activationOverlay)
    }

    private func setActiveAppearance(_ isActive: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.borderColor = isActive ? UIColor.systemBlue.cgColor : UIColor.separator.cgColor
        CATransaction.commit()
    }

    private static func wrappedLineCount(for text: String, width: CGFloat) -> Int {
        let insetWidth: CGFloat = 24
        let availableWidth = max(40, width - insetWidth)
        let characterWidth = max(7, "M".size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)]).width)
        let maxColumns = max(1, Int(floor(availableWidth / characterWidth)))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return max(1, lines.reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.utf16.count) / Double(maxColumns))))
        })
    }

    #if canImport(Runestone)
    private func runestoneState(text: String, language: String) -> TextViewState {
        switch language.lowercased() {
        case "swift":
            TextViewState(text: text, theme: theme, language: .swift)
        case "javascript", "js":
            TextViewState(text: text, theme: theme, language: .javaScript)
        case "json":
            TextViewState(text: text, theme: theme, language: .json)
        case "python", "py":
            TextViewState(text: text, theme: theme, language: .python)
        default:
            TextViewState(text: text, theme: theme)
        }
    }
    #endif
}

#if canImport(Runestone)
extension CodeBlockObjectView: @preconcurrency TextViewDelegate {
    func textViewShouldBeginEditing(_ textView: TextView) -> Bool {
        guard let presentation else { return false }
        guard presentation.mode != .objectEditing else { return true }
        activate()
        return false
    }

    func textViewDidChange(_ textView: TextView) {
        guard !isUpdatingState,
              textView.markedTextRange == nil,
              let presentation else {
            return
        }
        onContentChange?(presentation.blockID, presentation.sourceReplacement(forEditedContent: textView.text))
    }
}
#else
extension CodeBlockObjectView: @preconcurrency UITextViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        guard let presentation else { return false }
        guard presentation.mode != .objectEditing else { return true }
        activate()
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isUpdatingState,
              textView.markedTextRange == nil,
              let presentation else {
            return
        }
        onContentChange?(presentation.blockID, presentation.sourceReplacement(forEditedContent: textView.text))
    }
}
#endif

public struct MarkdownHybridEditor: UIViewRepresentable {
    private let coordinator: MarkdownEditorCoordinator

    public init(coordinator: MarkdownEditorCoordinator) {
        self.coordinator = coordinator
    }

    public func makeUIView(context: Context) -> MarkdownHybridEditorView {
        MarkdownHybridEditorView(coordinator: coordinator)
    }

    public func updateUIView(_ uiView: MarkdownHybridEditorView, context: Context) {
        uiView.coordinator = coordinator
        uiView.applyPresentation()
    }
}
#endif
