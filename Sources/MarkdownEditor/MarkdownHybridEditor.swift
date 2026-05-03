import Foundation

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
public final class MarkdownHybridEditorView: UIView, UITextViewDelegate {
    public var controller: MarkdownEditorController {
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
    private var scrollRestoreGeneration = 0

    public init(controller: MarkdownEditorController) {
        self.controller = controller
        self.textView = UITextView(frame: .zero, textContainer: nil)
        super.init(frame: .zero)
        configure()
        applyPresentation()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func applyPresentation(selectedSourceOffset: Int? = nil) {
        guard !isApplyingPresentation else { return }
        let currentSourceOffset = selectedSourceOffset ?? controller.sourceOffset(forVisibleOffset: textView.selectedRange.location)
        let needsTextUpdate = !textView.attributedText.isEqual(to: controller.presentation.attributedString)
        if !needsTextUpdate && selectedSourceOffset == nil {
            return
        }

        let shouldPreserveScrollOffset = isTrackingScrollPosition
        let preservedContentOffset = textView.contentOffset
        scrollRestoreGeneration += 1
        let restoreGeneration = scrollRestoreGeneration

        isApplyingPresentation = true
        UIView.performWithoutAnimation {
            if needsTextUpdate {
                textView.attributedText = controller.presentation.attributedString
            }
            let visibleOffset = controller.visibleOffset(forSourceOffset: currentSourceOffset)
            textView.selectedRange = NSRange(location: min(visibleOffset, textView.attributedText.length), length: 0)
            restoreContentOffset(preservedContentOffset, when: shouldPreserveScrollOffset)
        }
        isApplyingPresentation = false

        guard shouldPreserveScrollOffset else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.scrollRestoreGeneration == restoreGeneration else { return }
            self.restoreContentOffset(preservedContentOffset, when: true)
        }
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView === self.textView, !isApplyingPresentation, textView.markedTextRange == nil else { return }
        let selectedRange = textView.selectedRange
        let sourceOffset = controller.sourceOffset(forVisibleOffset: selectedRange.location)
        let newVisibleOffset = controller.activate(atVisibleOffset: selectedRange.location)
        if newVisibleOffset != selectedRange.location || !textView.attributedText.isEqual(to: controller.presentation.attributedString) {
            applyPresentation(selectedSourceOffset: sourceOffset)
        }
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === self.textView else { return }
        controller.deactivate()
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

        let sourceStart = controller.sourceOffset(forVisibleOffset: range.location)
        let sourceEnd = controller.sourceOffset(forVisibleOffset: range.location + range.length)

        _ = controller.activate(atVisibleOffset: range.location)

        let activeStart = controller.visibleOffset(forSourceOffset: sourceStart)
        let activeEnd = controller.visibleOffset(forSourceOffset: sourceEnd)
        let activeRange = NSRange(location: activeStart, length: max(0, activeEnd - activeStart))

        guard let result = controller.replaceVisible(range: activeRange, with: text) else {
            applyPresentation()
            return false
        }

        applyPresentation(selectedSourceOffset: result.selectionSourceOffset)
        onSourceChange?(controller.source)
        return false
    }

    private func configure() {
        backgroundColor = .systemBackground
        clipsToBounds = true
        accessibilityIdentifier = "HybridMarkdownEditorContainer"

        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .systemBackground
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

public struct MarkdownHybridEditor: UIViewRepresentable {
    private let controller: MarkdownEditorController

    public init(controller: MarkdownEditorController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> MarkdownHybridEditorView {
        MarkdownHybridEditorView(controller: controller)
    }

    public func updateUIView(_ uiView: MarkdownHybridEditorView, context: Context) {
        uiView.controller = controller
        uiView.applyPresentation()
    }
}
#endif
