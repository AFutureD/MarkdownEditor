import Foundation

#if os(iOS)
import SwiftUI
import UIKit

import Runestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterPythonRunestone
import TreeSitterSwiftRunestone

/// Preview-only hit target for the code body.
///
/// Runestone stays configured the same way in preview and editing modes; the
/// wrapper uses this clear control to make preview taps activate the block
/// before text editing begins.
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
                configureCodeBlockAttachments(in: coordinator.presentation.attributedString)
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
            self.syncCodeBlockViews()
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
    func configureCodeBlockAttachments(in attributedString: NSAttributedString) {
        guard attributedString.length > 0 else { return }
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? MarkdownCodeBlockAttachment,
                  let presentation = attachment.presentation else {
                return
            }
            attachment.updateHeight(
                MarkdownCodeBlockLayoutMetrics.preferredHeight(
                    for: presentation.codeContent,
                    width: codeBlockContentWidth
                )
            )
        }
    }

    func syncCodeBlockViews() {
        guard textView.attributedText.length == coordinator.presentation.attributedString.length else {
            return
        }

        let presentations = codeBlockPresentations
        let liveIDs = Set(presentations.map(\.blockID))
        for staleID in codeBlockViews.keys where !liveIDs.contains(staleID) {
            codeBlockViews.removeValue(forKey: staleID)?.removeFromSuperview()
        }

        for presentation in presentations {
            guard let attachment = codeBlockAttachment(at: presentation.visibleRange.location) else { continue }
            attachment.updateHeight(
                MarkdownCodeBlockLayoutMetrics.preferredHeight(
                    for: presentation.codeContent,
                    width: codeBlockContentWidth
                )
            )
            let view = codeBlockViews[presentation.blockID] ?? makeCodeBlockView(for: presentation)
            view.isHidden = false
            view.update(presentation)
        }

        layoutCodeBlockViews(presentations: presentations)
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

    func layoutCodeBlockViews(presentations: [MarkdownCodeBlockPresentation]? = nil) {
        guard textView.attributedText.length == coordinator.presentation.attributedString.length else {
            return
        }

        let presentations = presentations ?? codeBlockPresentations
        let width = codeBlockContentWidth
        for presentation in presentations {
            guard let view = codeBlockViews[presentation.blockID],
                  let rect = codeBlockFrame(for: presentation, width: width) else {
                continue
            }
            view.frame = rect.integral
            textView.bringSubviewToFront(view)
        }
    }

    func scrollCodeBlockToVisible(blockID: String) {
        guard let presentation = codeBlockPresentation(blockID: blockID) else { return }
        layoutCodeBlockViews(presentations: [presentation])
        if let view = codeBlockViews[blockID] {
            textView.scrollRectToVisible(view.frame.insetBy(dx: 0, dy: -12), animated: false)
        } else {
            textView.scrollRangeToVisible(presentation.visibleRange)
        }
        textView.layoutIfNeeded()
        syncCodeBlockViews()
    }

    func focusCodeBlockEditor(blockID: String, scrollIntoView: Bool) {
        isTransferringFocusToCodeBlock = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if scrollIntoView {
                self.scrollCodeBlockToVisible(blockID: blockID)
            }
            self.ensureCodeBlockViewLoaded(blockID: blockID)
            self.codeBlockViews[blockID]?.focusEditor()
            DispatchQueue.main.async { [weak self] in
                self?.isTransferringFocusToCodeBlock = false
            }
        }
    }

    func ensureCodeBlockViewLoaded(blockID: String) {
        guard let presentation = codeBlockPresentation(blockID: blockID) else { return }
        syncCodeBlockViews()
        ensureTextLayout(for: presentation.visibleRange)
        textView.layoutIfNeeded()
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

    func ensureTextLayout(for visibleRange: NSRange) {
        guard let textLayoutManager = textView.textLayoutManager,
              let textRange = textRange(forVisibleRange: visibleRange, in: textLayoutManager) else {
            return
        }
        textLayoutManager.ensureLayout(for: textRange)
        textLayoutManager.textViewportLayoutController.layoutViewport()
    }

    func codeBlockFrame(for presentation: MarkdownCodeBlockPresentation, width: CGFloat) -> CGRect? {
        guard presentation.visibleRange.location < textView.attributedText.length,
              let textLayoutManager = textView.textLayoutManager,
              let location = textLocation(forVisibleOffset: presentation.visibleRange.location, in: textLayoutManager) else {
            return nil
        }

        ensureTextLayout(for: presentation.visibleRange)
        guard let layoutFragment = textLayoutManager.textLayoutFragment(for: location) else {
            return nil
        }

        let attachmentFrame = layoutFragment.frameForTextAttachment(at: location)
        let fragmentFrame = layoutFragment.layoutFragmentFrame
        let yOffset = attachmentFrame == .zero ? 0 : attachmentFrame.minY
        let height = max(
            MarkdownCodeBlockLayoutMetrics.preferredHeight(for: presentation.codeContent, width: width),
            attachmentFrame.height,
            fragmentFrame.height
        )
        return CGRect(
            x: textView.textContainerInset.left,
            y: textView.textContainerInset.top + fragmentFrame.minY + yOffset,
            width: width,
            height: height
        )
    }

    func textRange(forVisibleRange visibleRange: NSRange, in textLayoutManager: NSTextLayoutManager) -> NSTextRange? {
        guard let start = textLocation(forVisibleOffset: visibleRange.location, in: textLayoutManager),
              let end = textLayoutManager.location(start, offsetBy: visibleRange.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }

    func textLocation(
        forVisibleOffset visibleOffset: Int,
        in textLayoutManager: NSTextLayoutManager
    ) -> (any NSTextLocation)? {
        textLayoutManager.location(textLayoutManager.documentRange.location, offsetBy: visibleOffset)
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
    private let codeView = TextView(frame: .zero)
    private let theme = DefaultTheme()
    private var appliedRunestoneLanguage: String?
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
        codeView.isEditable = isEditing
        let language = runestoneLanguageIdentifier(for: presentation)
        if codeView.text == presentation.codeContent,
           appliedRunestoneLanguage == language {
            // The user may have just typed this text; avoid resetting state and moving the caret.
        } else if codeView.text != presentation.codeContent || appliedRunestoneLanguage != language {
            codeView.setState(runestoneState(text: presentation.codeContent, language: language))
            appliedRunestoneLanguage = language
        }

        setActiveAppearance(isEditing)
        isUpdatingState = false
        setNeedsLayout()
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
        // In preview mode, route code-body taps to the overlay. In editing mode
        // the overlay is hidden, so Runestone receives text interaction normally.
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
        _ = codeView.becomeFirstResponder()
    }

    private var currentCodeText: String {
        codeView.text
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

        _ = Self.prepareRunestoneLanguages
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
        codeView.isEditable = false
        codeView.isSelectable = true
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

    private func runestoneLanguageIdentifier(
        for presentation: MarkdownCodeBlockPresentation
    ) -> String {
        Self.normalizedRunestoneLanguageIdentifier(presentation.language) ?? ""
    }

    private static func normalizedRunestoneLanguageIdentifier(_ language: String) -> String? {
        switch language.lowercased() {
        case "swift":
            "swift"
        case "javascript", "js":
            "javascript"
        case "json":
            "json"
        case "python", "py":
            "python"
        default:
            nil
        }
    }

    private func runestoneState(text: String, language: String) -> TextViewState {
        switch language.lowercased() {
        case "swift":
            Self.prepareRunestoneLanguage("swift")
            return TextViewState(text: text, theme: theme, language: Self.swiftRunestoneLanguage)
        case "javascript", "js":
            Self.prepareRunestoneLanguage("javascript")
            return TextViewState(text: text, theme: theme, language: Self.javaScriptRunestoneLanguage)
        case "json":
            Self.prepareRunestoneLanguage("json")
            return TextViewState(text: text, theme: theme, language: Self.jsonRunestoneLanguage)
        case "python", "py":
            Self.prepareRunestoneLanguage("python")
            return TextViewState(text: text, theme: theme, language: Self.pythonRunestoneLanguage)
        default:
            return TextViewState(text: text, theme: theme)
        }
    }

    private static let swiftRunestoneLanguage = TreeSitterLanguage.swift
    private static let javaScriptRunestoneLanguage = TreeSitterLanguage.javaScript
    private static let jsonRunestoneLanguage = TreeSitterLanguage.json
    private static let pythonRunestoneLanguage = TreeSitterLanguage.python

    private static let prepareRunestoneLanguages: Void = {
        let languages = ["swift", "javascript", "json", "python"]
        DispatchQueue.global(qos: .utility).async {
            for language in languages {
                prepareRunestoneLanguage(language)
            }
        }
    }()

    private static let runestoneLanguagePreparationLock = NSLock()

    private static func prepareRunestoneLanguage(_ language: String) {
        runestoneLanguagePreparationLock.lock()
        defer {
            runestoneLanguagePreparationLock.unlock()
        }
        switch language {
        case "swift":
            swiftRunestoneLanguage.prepare()
        case "javascript":
            javaScriptRunestoneLanguage.prepare()
        case "json":
            jsonRunestoneLanguage.prepare()
        case "python":
            pythonRunestoneLanguage.prepare()
        default:
            break
        }
    }
}

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
