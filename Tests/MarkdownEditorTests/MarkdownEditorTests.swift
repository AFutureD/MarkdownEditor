import Foundation
import Testing
@testable import MarkdownEditor

#if canImport(AppKit)
import AppKit
private typealias TestFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias TestFont = UIFont
#endif

@Test func headingPreviewHidesMarkerAndMapsContent() {
    let source = "# Title\n\nBody"
    let document = MarkdownDocument(source: source)
    let presentation = MarkdownRenderer().render(document: document)

    #expect(presentation.attributedString.string.hasPrefix("Title"))
    #expect(!presentation.attributedString.string.hasPrefix("#"))
    #expect(presentation.visibleOffsetToSource(0) == 2)
}

@Test func italicPreviewHidesMarkersAndAppliesItalicFont() {
    let source = "This has *italic* and _emphasis_."
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let italicOffset = utf16Offset(in: string, of: "italic")
    let emphasisOffset = utf16Offset(in: string, of: "emphasis")

    #expect(string == "This has italic and emphasis.")
    #expect(presentation.visibleOffsetToSource(italicOffset + 1) == utf16Offset(in: source, of: "italic") + 1)
    #expect(fontHasItalicTrait(font(in: presentation.attributedString, at: italicOffset)))
    #expect(fontHasItalicTrait(font(in: presentation.attributedString, at: emphasisOffset)))
}

@Test func strongItalicPreviewUsesCombinedFontTraits() {
    let source = "This has ***bold italic*** and ___also bold italic___."
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let firstOffset = utf16Offset(in: string, of: "bold italic")
    let secondOffset = utf16Offset(in: string, of: "also bold italic")
    let firstFont = font(in: presentation.attributedString, at: firstOffset)
    let secondFont = font(in: presentation.attributedString, at: secondOffset)

    #expect(string == "This has bold italic and also bold italic.")
    #expect(fontHasBoldTrait(firstFont))
    #expect(fontHasItalicTrait(firstFont))
    #expect(fontHasBoldTrait(secondFont))
    #expect(fontHasItalicTrait(secondFont))
}

@Test func activatingListItemActivatesWholeListGroup() {
    let source = """
    Intro

    - Alpha
    - Beta
      - Nested
    - Gamma

    Tail
    """
    var document = MarkdownDocument(source: source)
    let renderer = MarkdownRenderer()
    let preview = renderer.render(document: document)
    let utf16Offset = utf16Offset(in: preview.attributedString.string, of: "Beta")
    let scope = preview.activeScope(containingVisibleOffset: utf16Offset)

    document.activeScope = scope
    let active = renderer.render(document: document)
    let activeString = active.attributedString.string

    #expect(scope == .listGroup("list-0"))
    #expect(activeString.contains("- Alpha"))
    #expect(activeString.contains("- Beta"))
    #expect(activeString.contains("  - Nested"))
    #expect(activeString.contains("- Gamma"))
}

@Test func unorderedListPreviewUsesHyphenAndSourceIndent() {
    let source = """
    - Alpha
      - Nested
    - Gamma
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))

    #expect(presentation.attributedString.string == "- Alpha\n- Nested\n- Gamma")
    #expect(!presentation.attributedString.string.contains("•"))
}

@Test func unorderedListPreviewCarriesIndentParagraphStyle() {
    let source = """
    - Alpha
      - Nested
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let rootStyle = paragraphStyle(in: presentation.attributedString, at: 0)
    let nestedStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: presentation.attributedString.string, of: "- Nested"))

    #expect(rootStyle.headIndent > 0)
    #expect(nestedStyle.headIndent > rootStyle.headIndent)
    #expect(nestedStyle.firstLineHeadIndent > rootStyle.firstLineHeadIndent)
}

@Test func orderedListPreviewAlignsPeriodsByIndentLevel() {
    let source = """
    1. One
    10. Ten
      2. Nested two
      11. Nested eleven
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))

    #expect(presentation.attributedString.string == " 1. One\n10. Ten\n 2. Nested two\n11. Nested eleven")
}

@Test func orderedListPreviewUsesSharedMarkerColumnPerIndent() {
    let source = """
    1. One
    10. Ten
      2. Nested two
      11. Nested eleven
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let firstStyle = paragraphStyle(in: presentation.attributedString, at: 0)
    let secondStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "10. Ten"))
    let nestedSingleDigitStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: " 2. Nested two"))
    let nestedDoubleDigitStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "11. Nested eleven"))

    #expect(firstStyle.headIndent == secondStyle.headIndent)
    #expect(nestedSingleDigitStyle.headIndent == nestedDoubleDigitStyle.headIndent)
    #expect(nestedSingleDigitStyle.headIndent > firstStyle.headIndent)
    #expect(nestedSingleDigitStyle.firstLineHeadIndent == firstStyle.headIndent)
}

@Test func mixedSubListMarkersUseLayoutIndentInsteadOfLeadingSpaces() {
    let source = """
    - Parent
      1. Child one
      12. Child twelve
        - Grandchild
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let parentStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "- Parent"))
    let childOneStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: " 1. Child one"))
    let childTwelveStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "12. Child twelve"))
    let grandchildStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "- Grandchild"))

    #expect(string == "- Parent\n 1. Child one\n12. Child twelve\n- Grandchild")
    #expect(childOneStyle.firstLineHeadIndent == childTwelveStyle.firstLineHeadIndent)
    #expect(childOneStyle.headIndent == childTwelveStyle.headIndent)
    #expect(childOneStyle.firstLineHeadIndent == parentStyle.headIndent)
    #expect(grandchildStyle.firstLineHeadIndent == childOneStyle.headIndent)
}

@Test func mixedRootListMarkersShareContentColumn() {
    let source = """
    - Bullet
    10. Ordered
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let bulletStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "- Bullet"))
    let orderedStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "10. Ordered"))
    let bulletSeparatorOffset = utf16Offset(in: string, of: "- Bullet") + 1

    #expect(string == "- Bullet\n10. Ordered")
    #expect(bulletStyle.headIndent == orderedStyle.headIndent)
    #expect(kernValue(in: presentation.attributedString, at: bulletSeparatorOffset) > 0)
}

@Test func mixedSubListMarkersStartAtParentContentAndShareChildContentColumn() {
    let source = """
    1. Parent
      - Child bullet
      2. Child ordered
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let string = presentation.attributedString.string
    let parentStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "1. Parent"))
    let bulletStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "- Child bullet"))
    let orderedStyle = paragraphStyle(in: presentation.attributedString, at: utf16Offset(in: string, of: "2. Child ordered"))
    let bulletSeparatorOffset = utf16Offset(in: string, of: "- Child bullet") + 1

    #expect(string == "1. Parent\n- Child bullet\n2. Child ordered")
    #expect(bulletStyle.firstLineHeadIndent == parentStyle.headIndent)
    #expect(bulletStyle.headIndent == orderedStyle.headIndent)
    #expect(kernValue(in: presentation.attributedString, at: bulletSeparatorOffset) > 0)
}

@Test @MainActor func visibleOffsetZeroActivatesFirstBlock() {
    let coordinator = MarkdownEditorCoordinator(source: "# Title\n\nBody")

    _ = coordinator.activate(atVisibleOffset: 0)

    #expect(coordinator.activeScope == .block("b0"))
    #expect(coordinator.presentation.attributedString.string.hasPrefix("# Title"))
}

@Test @MainActor func activeHeadingEditUpdatesSource() {
    let coordinator = MarkdownEditorCoordinator(source: "# Title\n")
    _ = coordinator.activate(atVisibleOffset: 0)
    let insertionOffset = utf16Offset(in: coordinator.presentation.attributedString.string, of: "Title") + "Title".utf16.count
    let range = NSRange(location: insertionOffset, length: 0)

    let result = coordinator.replaceVisible(range: range, with: "!")

    #expect(result != nil)
    #expect(coordinator.source == "# Title!\n")
}

@Test @MainActor func typingFromPreviewRemapsThroughSourceOffset() {
    let coordinator = MarkdownEditorCoordinator(source: "This has **bold** text")
    let previewInsertion = utf16Offset(in: coordinator.presentation.attributedString.string, of: "bold") + "bold".utf16.count
    let sourceStart = coordinator.sourceOffset(forVisibleOffset: previewInsertion)

    _ = coordinator.activate(atVisibleOffset: previewInsertion)
    let activeStart = coordinator.visibleOffset(forSourceOffset: sourceStart)
    let result = coordinator.replaceVisible(range: NSRange(location: activeStart, length: 0), with: "!")

    #expect(result != nil)
    #expect(coordinator.source == "This has **bold!** text")
}

@Test @MainActor func typingOnBlankLineBetweenParagraphsInsertsContent() {
    let coordinator = MarkdownEditorCoordinator(source: "First paragraph\n\nSecond paragraph")
    let blankLineOffset = utf16Offset(in: coordinator.presentation.attributedString.string, of: "\n\n") + 1

    _ = coordinator.activate(atVisibleOffset: blankLineOffset)
    #expect(coordinator.activeScope == .block("b1"))

    let result = coordinator.replaceVisible(range: NSRange(location: blankLineOffset, length: 0), with: "Inserted paragraph")
    let continuationOffset = coordinator.visibleOffset(forSourceOffset: result?.selectionSourceOffset ?? 0)
    let continuationResult = coordinator.replaceVisible(range: NSRange(location: continuationOffset, length: 0), with: "!")

    #expect(result != nil)
    #expect(continuationResult != nil)
    #expect(coordinator.activeScope == .block("b0"))
    #expect(coordinator.source == "First paragraph\nInserted paragraph!\nSecond paragraph")
}

@Test @MainActor func tableCellEditUsesCanonicalSerialization() {
    let source = """
    | Name | Age |
    | --- | --- |
    | Ana | 20 |
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let table = coordinator.document.blocks.first { $0.kind == .table }!

    coordinator.updateTableCell(blockID: table.id, row: 1, column: 0, text: "Mira")

    #expect(coordinator.source.contains("| Mira | 20  |"))
    #expect(coordinator.source.contains("| Name | Age |"))
}

@Test @MainActor func codeContentEditPreservesFence() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let code = coordinator.document.blocks.first { $0.kind == .codeBlock }!

    coordinator.replaceCodeContent(blockID: code.id, with: "let y = 2\n")

    #expect(coordinator.source == "```swift\nlet y = 2\n```")
}

@Test func codeBlockPreviewRendersAttachmentInsteadOfTextPlaceholder() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    let presentation = MarkdownRenderer().render(document: MarkdownDocument(source: source))
    let block = presentation.blocks.first { $0.kind == .codeBlock }!
    let codeObject = block.codeBlock!

    #expect(block.mode == .objectPreview)
    #expect(!presentation.attributedString.string.contains("[Code object"))
    #expect(presentation.attributedString.string.hasPrefix("\u{fffc}"))
    #expect(codeObject.language == "swift")
    #expect(codeObject.codeContent == "let x = 1")
    #expect(codeObject.sourceReplacement(forEditedContent: "let y = 2") == "let y = 2\n")
    #expect(presentation.visibleOffsetToSource(codeObject.visibleRange.location) == 0)
    #expect(presentation.sourceOffsetToVisible(utf16Offset(in: source, of: "let x")) == codeObject.visibleRange.location + 1)
    #expect(presentation.sourceOffsetToVisible(source.utf16.count) == block.visibleRange.upperBound)
    #expect(presentation.activeScope(containingVisibleOffset: block.visibleRange.upperBound) == nil)

    #if canImport(UIKit) || canImport(AppKit)
    let attachment = presentation.attributedString.attribute(
        .attachment,
        at: codeObject.visibleRange.location,
        effectiveRange: nil
    ) as? MarkdownCodeBlockAttachment
    #expect(attachment?.presentation == codeObject)
    #endif
}

@Test func activeCodeBlockStaysObjectEditingInsteadOfRawFenceSource() {
    var document = MarkdownDocument(source: "Intro\n\n```swift\nlet x = 1\n```\n")
    let code = document.blocks.first { $0.kind == .codeBlock }!

    document.activeScope = .codeBlock(code.id)
    let presentation = MarkdownRenderer().render(document: document)
    let block = presentation.blocks.first { $0.kind == .codeBlock }!

    #expect(block.mode == .objectEditing)
    #expect(block.codeBlock?.mode == .objectEditing)
    #expect(!presentation.attributedString.string.contains("```swift"))
    #expect(presentation.attributedString.string.contains("\u{fffc}"))
}

@Test @MainActor func codeObjectEditKeepsClosingFenceSeparateFromFollowingBlocks() {
    let source = """
    ```swift
    let x = 1
    ```

    Tail paragraph
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let code = coordinator.document.blocks.first { $0.kind == .codeBlock }!
    let codeObject = coordinator.presentation.blocks.first { $0.kind == .codeBlock }!.codeBlock!

    coordinator.replaceCodeContent(blockID: code.id, with: codeObject.sourceReplacement(forEditedContent: "let y = 2"))

    #expect(coordinator.source.contains("let y = 2\n```"))
    #expect(coordinator.source.contains("Tail paragraph"))
    #expect(coordinator.document.blocks.contains { $0.kind == .paragraph })
}

@Test @MainActor func outerVisibleEditCannotModifyCodeBlockFence() {
    let source = """
    ```swift
    let x = 1
    ```

    Tail paragraph
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let code = coordinator.document.blocks.first { $0.kind == .codeBlock }!
    _ = coordinator.activate(scope: .codeBlock(code.id), preservingSourceOffset: code.sourceRange.location)
    let codeBlockPresentation = coordinator.presentation.blocks.first { $0.kind == .codeBlock }!
    let newlineAfterObject = NSRange(location: codeBlockPresentation.visibleRange.upperBound - 1, length: 0)

    let result = coordinator.replaceVisible(range: newlineAfterObject, with: "`")

    #expect(result == nil)
    #expect(coordinator.source == source)
}

@Test @MainActor func outerVisibleEditCanAppendAfterTrailingCodeBlock() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let code = coordinator.document.blocks.first { $0.kind == .codeBlock }!
    _ = coordinator.activate(scope: .codeBlock(code.id), preservingSourceOffset: code.sourceRange.location)
    let codeBlockPresentation = coordinator.presentation.blocks.first { $0.kind == .codeBlock }!
    let trailingInsertion = NSRange(location: codeBlockPresentation.visibleRange.upperBound, length: 0)

    let result = coordinator.replaceVisible(range: trailingInsertion, with: "\n")

    #expect(result != nil)
    #expect(coordinator.source == "```swift\nlet x = 1\n```\n")
    #expect(coordinator.activeScope == nil)

    let continuationOffset = coordinator.visibleOffset(forSourceOffset: result?.selectionSourceOffset ?? 0)
    _ = coordinator.activate(atVisibleOffset: continuationOffset)
    #expect(coordinator.activeScope == nil)
    let continuationResult = coordinator.replaceVisible(
        range: NSRange(location: continuationOffset, length: 0),
        with: "Tail paragraph"
    )

    #expect(continuationResult != nil)
    #expect(coordinator.source == "```swift\nlet x = 1\n```\nTail paragraph")
    #expect(coordinator.document.blocks.contains { $0.kind == .paragraph })
}

@Test @MainActor func outerVisibleTextAppendAfterTrailingCodeBlockStartsNewLine() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let codeBlockPresentation = coordinator.presentation.blocks.first { $0.kind == .codeBlock }!
    let trailingInsertion = NSRange(location: codeBlockPresentation.visibleRange.upperBound, length: 0)

    let result = coordinator.replaceVisible(range: trailingInsertion, with: "Tail paragraph")

    #expect(result != nil)
    #expect(coordinator.source == "```swift\nlet x = 1\n```\nTail paragraph")
    #expect(coordinator.activeScope == nil)
    #expect(coordinator.document.blocks.contains { $0.kind == .paragraph })
}

@Test @MainActor func codeLanguageEditPreservesContentAndClosingFence() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    let coordinator = MarkdownEditorCoordinator(source: source)
    let code = coordinator.document.blocks.first { $0.kind == .codeBlock }!

    coordinator.updateCodeLanguage(blockID: code.id, language: "python")

    #expect(coordinator.source == "```python\nlet x = 1\n```")
}

@Test func codeBlockIDsSurvivePrecedingInlineEdits() {
    let original = """
    Intro paragraph

    ```swift
    let x = 1
    ```
    """
    let edited = """
    Intro paragraph!

    ```swift
    let x = 1
    ```
    """

    let originalCodeID = MarkdownDocument(source: original).blocks.first { $0.kind == .codeBlock }?.id
    let editedCodeID = MarkdownDocument(source: edited).blocks.first { $0.kind == .codeBlock }?.id

    #expect(originalCodeID == editedCodeID)
}

private func utf16Offset(in string: String, of needle: String) -> Int {
    let range = string.range(of: needle)!
    return string.utf16.distance(from: string.utf16.startIndex, to: range.lowerBound.samePosition(in: string.utf16)!)
}

private func paragraphStyle(in attributedString: NSAttributedString, at offset: Int) -> NSParagraphStyle {
    attributedString.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as! NSParagraphStyle
}

private func font(in attributedString: NSAttributedString, at offset: Int) -> TestFont {
    attributedString.attribute(.font, at: offset, effectiveRange: nil) as! TestFont
}

private func fontHasBoldTrait(_ font: TestFont) -> Bool {
    #if canImport(AppKit)
    NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    #else
    font.fontDescriptor.symbolicTraits.contains(.traitBold)
    #endif
}

private func fontHasItalicTrait(_ font: TestFont) -> Bool {
    #if canImport(AppKit)
    NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    #else
    font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    #endif
}

private func kernValue(in attributedString: NSAttributedString, at offset: Int) -> CGFloat {
    let value = attributedString.attribute(.kern, at: offset, effectiveRange: nil)
    if let value = value as? CGFloat {
        return value
    }
    if let number = value as? NSNumber {
        return CGFloat(truncating: number)
    }
    return 0
}
