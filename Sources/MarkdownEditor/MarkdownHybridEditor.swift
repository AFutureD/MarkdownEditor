import Foundation

#if os(iOS)
import SwiftUI
import UIKit

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
            view.update(CodeBlockObjectState(
                blockID: presentation.blockID,
                mode: presentation.mode,
                language: presentation.language,
                displayLanguage: presentation.displayLanguage,
                codeContent: presentation.codeContent
            ))
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
            guard let presentation = codeBlockPresentation(blockID: blockID) else { return }
            coordinator.replaceCodeContent(
                blockID: blockID,
                with: presentation.sourceReplacement(forEditedContent: content)
            )
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
