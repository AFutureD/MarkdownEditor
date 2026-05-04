import Foundation

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

public struct MarkdownMappingSegment: Equatable {
    public var sourceRange: MarkdownSourceRange
    public var visibleRange: NSRange

    public init(sourceRange: MarkdownSourceRange, visibleRange: NSRange) {
        self.sourceRange = sourceRange
        self.visibleRange = visibleRange
    }
}

public struct MarkdownBlockPresentation: Identifiable, Equatable {
    public var id: String
    public var blockID: String
    public var listGroupID: String?
    public var kind: MarkdownBlockKind
    public var mode: MarkdownDisplayMode
    public var sourceRange: MarkdownSourceRange
    public var visibleRange: NSRange
    public var mappingSegments: [MarkdownMappingSegment]
    public var codeBlock: MarkdownCodeBlockPresentation?

    public init(
        blockID: String,
        listGroupID: String?,
        kind: MarkdownBlockKind,
        mode: MarkdownDisplayMode,
        sourceRange: MarkdownSourceRange,
        visibleRange: NSRange,
        mappingSegments: [MarkdownMappingSegment],
        codeBlock: MarkdownCodeBlockPresentation? = nil
    ) {
        self.id = blockID
        self.blockID = blockID
        self.listGroupID = listGroupID
        self.kind = kind
        self.mode = mode
        self.sourceRange = sourceRange
        self.visibleRange = visibleRange
        self.mappingSegments = mappingSegments
        self.codeBlock = codeBlock
    }
}

public struct MarkdownCodeBlockPresentation: Equatable, Sendable {
    public var blockID: String
    public var mode: MarkdownDisplayMode
    public var sourceRange: MarkdownSourceRange
    public var visibleRange: NSRange
    public var language: String
    public var codeContent: String
    public var codeContentRange: MarkdownSourceRange
    public var estimatedHeight: CGFloat
    public var hasClosingFence: Bool

    public init(
        blockID: String,
        mode: MarkdownDisplayMode,
        sourceRange: MarkdownSourceRange,
        visibleRange: NSRange,
        language: String,
        codeContent: String,
        codeContentRange: MarkdownSourceRange,
        estimatedHeight: CGFloat,
        hasClosingFence: Bool
    ) {
        self.blockID = blockID
        self.mode = mode
        self.sourceRange = sourceRange
        self.visibleRange = visibleRange
        self.language = language
        self.codeContent = codeContent
        self.codeContentRange = codeContentRange
        self.estimatedHeight = estimatedHeight
        self.hasClosingFence = hasClosingFence
    }

    public var displayLanguage: String {
        language.isEmpty ? "plain text" : language
    }

    public func sourceReplacement(forEditedContent editedContent: String) -> String {
        guard hasClosingFence, !editedContent.isEmpty else {
            return editedContent
        }
        return editedContent + "\n"
    }
}

public struct MarkdownPresentation {
    public var attributedString: NSAttributedString
    public var blocks: [MarkdownBlockPresentation]

    public init(attributedString: NSAttributedString, blocks: [MarkdownBlockPresentation]) {
        self.attributedString = attributedString
        self.blocks = blocks
    }

    public func blockPresentation(containingVisibleOffset offset: Int) -> MarkdownBlockPresentation? {
        guard !blocks.isEmpty else { return nil }
        if offset >= attributedString.length {
            return blocks.last
        }

        return binarySearchBlock(containingVisibleOffset: offset)
    }

    public func visibleOffsetToSource(_ offset: Int) -> Int {
        guard let block = blockPresentation(containingVisibleOffset: offset) else {
            return 0
        }
        return mapVisibleOffset(offset, in: block)
    }

    public func sourceOffsetToVisible(_ offset: Int) -> Int {
        guard let block = blockPresentation(containingSourceOffset: offset) else {
            return attributedString.length
        }
        return mapSourceOffset(offset, in: block)
    }

    public func activeScope(containingVisibleOffset offset: Int) -> MarkdownActiveScope? {
        if isTrailingBoundaryOfCodeBlock(offset) {
            return nil
        }

        guard let block = blockPresentation(containingVisibleOffset: offset) else {
            return nil
        }
        switch block.kind {
        case .list:
            guard let listGroupID = block.listGroupID else { return nil }
            return .listGroup(listGroupID)
        case .table:
            return .table(block.blockID)
        case .codeBlock:
            return .codeBlock(block.blockID)
        case .paragraph, .heading, .blockquote, .blank:
            return .block(block.blockID)
        }
    }

    private func blockPresentation(containingSourceOffset offset: Int) -> MarkdownBlockPresentation? {
        let documentUpperBound = blocks.last?.sourceRange.upperBound ?? 0
        if offset >= documentUpperBound {
            return blocks.last
        }

        return binarySearchBlock(containingSourceOffset: offset)
    }

    // Blocks are emitted in source/visible order. These lookups need range
    // containment, so a Dictionary would only help exact block-start offsets.
    private func binarySearchBlock(containingVisibleOffset offset: Int) -> MarkdownBlockPresentation? {
        var lowerBound = 0
        var upperBound = blocks.count

        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            let range = blocks[index].visibleRange

            if offset < range.location {
                upperBound = index
            } else if offset >= range.upperBound {
                lowerBound = index + 1
            } else {
                return blocks[index]
            }
        }

        guard lowerBound < blocks.count,
              blocks[lowerBound].visibleRange.location == offset else {
            return nil
        }
        return blocks[lowerBound]
    }

    private func binarySearchBlock(containingSourceOffset offset: Int) -> MarkdownBlockPresentation? {
        var lowerBound = 0
        var upperBound = blocks.count

        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            let range = blocks[index].sourceRange

            if offset < range.location {
                upperBound = index
            } else if offset >= range.upperBound {
                lowerBound = index + 1
            } else {
                return blocks[index]
            }
        }

        guard lowerBound < blocks.count,
              blocks[lowerBound].sourceRange.location == offset else {
            return nil
        }
        return blocks[lowerBound]
    }

    private func isTrailingBoundaryOfCodeBlock(_ offset: Int) -> Bool {
        guard blocks.contains(where: { $0.kind == .codeBlock && $0.visibleRange.upperBound == offset }) else {
            return false
        }
        return !blocks.contains { presentation in
            presentation.visibleRange.location == offset
        }
    }

    private func mapVisibleOffset(_ offset: Int, in block: MarkdownBlockPresentation) -> Int {
        for segment in block.mappingSegments {
            if offset >= segment.visibleRange.location && offset <= segment.visibleRange.location + segment.visibleRange.length {
                let delta = min(offset - segment.visibleRange.location, segment.sourceRange.length)
                return segment.sourceRange.location + delta
            }
        }

        if offset <= block.visibleRange.location {
            return block.sourceRange.location
        }
        if offset >= block.visibleRange.location + block.visibleRange.length {
            return block.sourceRange.upperBound
        }

        let nearest = block.mappingSegments.min { lhs, rhs in
            abs(lhs.visibleRange.location - offset) < abs(rhs.visibleRange.location - offset)
        }
        return nearest?.sourceRange.location ?? block.sourceRange.location
    }

    private func mapSourceOffset(_ offset: Int, in block: MarkdownBlockPresentation) -> Int {
        if offset >= block.sourceRange.upperBound {
            return block.visibleRange.location + block.visibleRange.length
        }

        for segment in block.mappingSegments {
            if offset >= segment.sourceRange.location && offset <= segment.sourceRange.upperBound {
                let delta = min(offset - segment.sourceRange.location, segment.visibleRange.length)
                return segment.visibleRange.location + delta
            }
        }

        if offset <= block.sourceRange.location {
            return block.visibleRange.location
        }
        let nearest = block.mappingSegments.min { lhs, rhs in
            abs(lhs.sourceRange.location - offset) < abs(rhs.sourceRange.location - offset)
        }
        return nearest?.visibleRange.location ?? block.visibleRange.location
    }
}

public struct MarkdownRenderer: Sendable {
    public init() {}

    public func render(document: MarkdownDocument) -> MarkdownPresentation {
        render(source: document.source, blocks: document.blocks, activeScope: document.activeScope)
    }

    public func render(source: String, blocks: [MarkdownBlock], activeScope: MarkdownActiveScope? = nil) -> MarkdownPresentation {
        let builder = PresentationBuilder()

        for block in blocks {
            let mode = displayMode(for: block, activeScope: activeScope)
            let startVisible = builder.length

            switch mode {
            case .sourceEditing:
                renderSource(block: block, source: source, builder: builder)
            case .objectPreview, .objectEditing:
                renderObject(block: block, mode: mode, source: source, builder: builder)
            case .preview:
                renderPreview(block: block, source: source, builder: builder)
            }

            let visibleRange = NSRange(location: startVisible, length: builder.length - startVisible)
            builder.finishBlock(
                blockID: block.id,
                listGroupID: block.listGroupID,
                kind: block.kind,
                mode: mode,
                sourceRange: block.sourceRange,
                visibleRange: visibleRange
            )
        }

        return MarkdownPresentation(attributedString: builder.attributedString, blocks: builder.blocks)
    }
}

private extension MarkdownRenderer {
    func displayMode(for block: MarkdownBlock, activeScope: MarkdownActiveScope?) -> MarkdownDisplayMode {
        switch block.kind {
        case .table:
            return .objectPreview
        case .codeBlock:
            if case .codeBlock(let id) = activeScope, id == block.id {
                return .objectEditing
            }
            return .objectPreview
        case .list:
            if case .listGroup(let id) = activeScope, id == block.listGroupID {
                return .sourceEditing
            }
            return .preview
        case .paragraph, .heading, .blockquote, .blank:
            if case .block(let id) = activeScope, id == block.id {
                return .sourceEditing
            }
            return .preview
        }
    }

    func renderSource(block: MarkdownBlock, source: String, builder: PresentationBuilder) {
        let text = substring(source, range: block.sourceRange)
        let start = builder.length
        builder.append(text, attributes: sourceAttributes(for: block))
        builder.addMapping(sourceRange: block.sourceRange, visibleRange: NSRange(location: start, length: text.utf16.count))
    }

    func renderPreview(block: MarkdownBlock, source: String, builder: PresentationBuilder) {
        switch block.kind {
        case .heading:
            renderHeading(block: block, source: source, builder: builder)
        case .paragraph:
            renderInlinePreview(block: block, source: source, builder: builder, attributes: bodyAttributes())
        case .blockquote:
            renderBlockquote(block: block, source: source, builder: builder)
        case .list:
            renderList(block: block, source: source, builder: builder)
        case .blank:
            renderSource(block: block, source: source, builder: builder)
        case .table, .codeBlock:
            renderObject(block: block, mode: .objectPreview, source: source, builder: builder)
        }
    }

    func renderHeading(block: MarkdownBlock, source: String, builder: PresentationBuilder) {
        let level = block.headingLevel ?? 1
        let attributes = headingAttributes(level: level)
        renderInlinePreview(block: block, source: source, builder: builder, attributes: attributes)
    }

    func renderBlockquote(block: MarkdownBlock, source: String, builder: PresentationBuilder) {
        let blockText = substring(source, range: block.sourceRange)
        var sourceOffset = block.sourceRange.location
        for line in MarkdownLine.scan(blockText) {
            let lineText = line.textWithoutNewline
            let markerIndex = lineText.firstIndex(of: ">")
            var contentStartInLine = 0
            if let markerIndex {
                contentStartInLine = lineText.distance(from: lineText.startIndex, to: markerIndex) + 1
                if lineText.dropFirst(contentStartInLine).first == " " {
                    contentStartInLine += 1
                }
            }

            let contentSourceOffset = sourceOffset + contentStartInLine
            let content = String(lineText.dropFirst(contentStartInLine))
            let visibleStart = builder.length
            builder.append("| ", attributes: quoteMarkerAttributes())
            builder.append(content, attributes: quoteAttributes())
            builder.addMapping(
                sourceRange: MarkdownSourceRange(location: contentSourceOffset, length: content.utf16.count),
                visibleRange: NSRange(location: visibleStart + 2, length: content.utf16.count)
            )

            if line.text.hasSuffix("\n") {
                builder.append("\n", attributes: quoteAttributes())
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset + line.text.utf16.count - 1, length: 1),
                    visibleRange: NSRange(location: builder.length - 1, length: 1)
                )
            }
            sourceOffset += line.text.utf16.count
        }
    }

    func renderList(block: MarkdownBlock, source: String, builder: PresentationBuilder) {
        let blockText = substring(source, range: block.sourceRange)
        let lines = MarkdownLine.scan(blockText)
        let layout = listLayout(for: lines)
        var sourceOffset = block.sourceRange.location

        for line in lines {
            let lineText = line.textWithoutNewline
            let marker = listMarker(in: lineText)
            let visibleStart = builder.length

            if let marker {
                let markerText = renderedMarker(for: marker, layout: layout)
                let paragraphStyle = listParagraphStyle(marker: marker, layout: layout)
                let markerAttributes = listMarkerAttributes(paragraphStyle: paragraphStyle)
                let contentAttributes = bodyAttributes(paragraphStyle: paragraphStyle)
                builder.append(
                    listMarkerAttributedString(
                        markerText,
                        attributes: markerAttributes,
                        extraTrailingSpaceWidth: markerTrailingSpaceExpansion(
                            marker: marker,
                            markerText: markerText,
                            layout: layout
                        )
                    )
                )
                let content = String(lineText.dropFirst(marker.endOffset))
                let contentVisibleStart = builder.length
                builder.append(content, attributes: contentAttributes)
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset + marker.endOffset, length: content.utf16.count),
                    visibleRange: NSRange(location: contentVisibleStart, length: content.utf16.count)
                )
                if line.text.hasSuffix("\n") {
                    builder.append("\n", attributes: contentAttributes)
                    builder.addMapping(
                        sourceRange: MarkdownSourceRange(location: sourceOffset + line.text.utf16.count - 1, length: 1),
                        visibleRange: NSRange(location: builder.length - 1, length: 1)
                    )
                }
            } else {
                builder.append(lineText, attributes: bodyAttributes())
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset, length: lineText.utf16.count),
                    visibleRange: NSRange(location: visibleStart, length: lineText.utf16.count)
                )
                if line.text.hasSuffix("\n") {
                    builder.append("\n", attributes: bodyAttributes())
                    builder.addMapping(
                        sourceRange: MarkdownSourceRange(location: sourceOffset + line.text.utf16.count - 1, length: 1),
                        visibleRange: NSRange(location: builder.length - 1, length: 1)
                    )
                }
            }
            sourceOffset += line.text.utf16.count
        }
    }

    func renderInlinePreview(
        block: MarkdownBlock,
        source: String,
        builder: PresentationBuilder,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let text = substring(source, range: block.contentRange)
        renderInline(sourceText: text, sourceBaseOffset: block.contentRange.location, builder: builder, baseAttributes: attributes)
    }

    func renderObject(block: MarkdownBlock, mode: MarkdownDisplayMode, source: String, builder: PresentationBuilder) {
        if block.kind == .codeBlock, let code = block.code {
            renderCodeObject(block: block, code: code, mode: mode, source: source, builder: builder)
            return
        }

        let label: String
        let details: String
        switch block.kind {
        case .table:
            let table = block.table
            let rowCount = table?.rows.count ?? 0
            let columnCount = table?.columns.count ?? 0
            label = "Table object"
            details = "\(columnCount) columns, \(rowCount) rows"
        default:
            label = "Object"
            details = block.kind.rawValue
        }

        let start = builder.length
        builder.append("[\(label): \(details)]\n", attributes: objectAttributes())
        builder.addMapping(
            sourceRange: block.sourceRange,
            visibleRange: NSRange(location: start, length: builder.length - start)
        )
    }

    func renderCodeObject(
        block: MarkdownBlock,
        code: MarkdownCodeBlock,
        mode: MarkdownDisplayMode,
        source: String,
        builder: PresentationBuilder
    ) {
        let start = builder.length
        let visibleRange = NSRange(location: start, length: 1)
        let sourceCodeContent = substring(source, range: code.codeContentRange)
        let hasClosingFence = code.codeContentRange.upperBound < block.sourceRange.upperBound
        let codeContent = displayCodeContent(sourceCodeContent, hasClosingFence: hasClosingFence)
        let presentation = MarkdownCodeBlockPresentation(
            blockID: block.id,
            mode: mode,
            sourceRange: block.sourceRange,
            visibleRange: visibleRange,
            language: code.language,
            codeContent: codeContent,
            codeContentRange: code.codeContentRange,
            estimatedHeight: estimatedCodeBlockHeight(for: codeContent),
            hasClosingFence: hasClosingFence
        )

        #if canImport(UIKit) || canImport(AppKit)
        builder.append(NSAttributedString(attachment: MarkdownCodeBlockAttachment(presentation: presentation)))
        builder.append("\n", attributes: bodyAttributes())
        #else
        builder.append("\u{fffc}\n", attributes: objectAttributes())
        #endif

        builder.setCodeBlockPresentation(presentation)
        builder.addMapping(sourceRange: block.sourceRange, visibleRange: visibleRange)
    }

    func displayCodeContent(_ sourceCodeContent: String, hasClosingFence: Bool) -> String {
        guard hasClosingFence else {
            return sourceCodeContent
        }
        if sourceCodeContent.hasSuffix("\r\n") {
            return String(sourceCodeContent.dropLast(2))
        }
        if sourceCodeContent.hasSuffix("\n") {
            return String(sourceCodeContent.dropLast())
        }
        return sourceCodeContent
    }

    func estimatedCodeBlockHeight(for codeContent: String) -> CGFloat {
        let lineCount = max(1, MarkdownLine.scan(codeContent).count)
        let contentHeight = CGFloat(lineCount) * 20 + 16
        return max(84, min(420, 36 + contentHeight))
    }

    func renderInline(
        sourceText: String,
        sourceBaseOffset: Int,
        builder: PresentationBuilder,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        let characters = Array(sourceText)
        var index = 0
        var sourceOffset = sourceBaseOffset

        func renderDelimitedSpan(
            token: String,
            attributes: [NSAttributedString.Key: Any],
            requiresContent: Bool = true
        ) -> Bool {
            let tokenCharacterCount = token.count
            guard match(characters, at: index, token: token),
                  let close = findToken(token, in: characters, from: index + tokenCharacterCount),
                  !requiresContent || close > index + tokenCharacterCount else {
                return false
            }

            let content = String(characters[(index + tokenCharacterCount)..<close])
            let visibleStart = builder.length
            builder.append(content, attributes: attributes)
            builder.addMapping(
                sourceRange: MarkdownSourceRange(location: sourceOffset + token.utf16.count, length: content.utf16.count),
                visibleRange: NSRange(location: visibleStart, length: content.utf16.count)
            )
            let tokenEnd = close + tokenCharacterCount - 1
            let tokenLength = sourceLength(characters[index...tokenEnd])
            sourceOffset += tokenLength
            index = close + tokenCharacterCount
            return true
        }

        while index < characters.count {
            if characters[index] == "*" {
                if renderDelimitedSpan(
                    token: "***",
                    attributes: baseAttributes.merging(strongEmphasisAttributes()) { _, new in new }
                ) {
                    continue
                }

                if renderDelimitedSpan(
                    token: "**",
                    attributes: baseAttributes.merging(strongAttributes()) { _, new in new }
                ) {
                    continue
                }

                if renderDelimitedSpan(
                    token: "*",
                    attributes: baseAttributes.merging(emphasisAttributes()) { _, new in new }
                ) {
                    continue
                }
            }

            if characters[index] == "_" {
                if renderDelimitedSpan(
                    token: "___",
                    attributes: baseAttributes.merging(strongEmphasisAttributes()) { _, new in new }
                ) {
                    continue
                }

                if renderDelimitedSpan(
                    token: "__",
                    attributes: baseAttributes.merging(strongAttributes()) { _, new in new }
                ) {
                    continue
                }

                if renderDelimitedSpan(
                    token: "_",
                    attributes: baseAttributes.merging(emphasisAttributes()) { _, new in new }
                ) {
                    continue
                }
            }

            if characters[index] == "`", let close = findToken("`", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<close])
                let visibleStart = builder.length
                builder.append(content, attributes: baseAttributes.merging(codeSpanAttributes()) { _, new in new })
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset + 1, length: content.utf16.count),
                    visibleRange: NSRange(location: visibleStart, length: content.utf16.count)
                )
                let tokenLength = sourceLength(characters[index...close])
                sourceOffset += tokenLength
                index = close + 1
                continue
            }

            if characters[index] == "[",
               let closeBracket = findCharacter("]", in: characters, from: index + 1),
               closeBracket + 1 < characters.count,
               characters[closeBracket + 1] == "(",
               let closeParen = findCharacter(")", in: characters, from: closeBracket + 2) {
                let content = String(characters[(index + 1)..<closeBracket])
                let visibleStart = builder.length
                builder.append(content, attributes: baseAttributes.merging(linkAttributes()) { _, new in new })
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset + 1, length: content.utf16.count),
                    visibleRange: NSRange(location: visibleStart, length: content.utf16.count)
                )
                let tokenLength = sourceLength(characters[index...closeParen])
                sourceOffset += tokenLength
                index = closeParen + 1
                continue
            }

            if !isInlineTokenStarter(characters[index]) {
                let nextToken = nextInlineTokenStarter(in: characters, from: index + 1)
                let run = String(characters[index..<nextToken])
                let runLength = run.utf16.count
                let visibleStart = builder.length
                builder.append(run, attributes: baseAttributes)
                builder.addMapping(
                    sourceRange: MarkdownSourceRange(location: sourceOffset, length: runLength),
                    visibleRange: NSRange(location: visibleStart, length: runLength)
                )
                sourceOffset += runLength
                index = nextToken
                continue
            }

            let character = String(characters[index])
            let visibleStart = builder.length
            let length = character.utf16.count
            builder.append(character, attributes: baseAttributes)
            builder.addMapping(
                sourceRange: MarkdownSourceRange(location: sourceOffset, length: length),
                visibleRange: NSRange(location: visibleStart, length: length)
            )
            sourceOffset += length
            index += 1
        }
    }

    func substring(_ source: String, range: MarkdownSourceRange) -> String {
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let stringRange = Range(nsRange, in: source) else {
            return ""
        }
        return String(source[stringRange])
    }
}

private final class PresentationBuilder {
    private let storage = NSMutableAttributedString()
    private var currentMappings: [MarkdownMappingSegment] = []
    private var currentCodeBlockPresentation: MarkdownCodeBlockPresentation?
    private(set) var blocks: [MarkdownBlockPresentation] = []

    var length: Int {
        storage.length
    }

    var attributedString: NSAttributedString {
        storage.copy() as! NSAttributedString
    }

    func append(_ text: String, attributes: [NSAttributedString.Key: Any]) {
        storage.append(NSAttributedString(string: text, attributes: attributes))
    }

    func append(_ attributedString: NSAttributedString) {
        storage.append(attributedString)
    }

    func addMapping(sourceRange: MarkdownSourceRange, visibleRange: NSRange) {
        guard sourceRange.length > 0 || visibleRange.length > 0 else { return }
        currentMappings.append(MarkdownMappingSegment(sourceRange: sourceRange, visibleRange: visibleRange))
    }

    func setCodeBlockPresentation(_ presentation: MarkdownCodeBlockPresentation) {
        currentCodeBlockPresentation = presentation
    }

    func finishBlock(
        blockID: String,
        listGroupID: String?,
        kind: MarkdownBlockKind,
        mode: MarkdownDisplayMode,
        sourceRange: MarkdownSourceRange,
        visibleRange: NSRange
    ) {
        blocks.append(
            MarkdownBlockPresentation(
                blockID: blockID,
                listGroupID: listGroupID,
                kind: kind,
                mode: mode,
                sourceRange: sourceRange,
                visibleRange: visibleRange,
                mappingSegments: currentMappings,
                codeBlock: currentCodeBlockPresentation
            )
        )
        currentMappings.removeAll(keepingCapacity: true)
        currentCodeBlockPresentation = nil
    }
}

#if canImport(UIKit) || canImport(AppKit)
enum MarkdownCodeBlockLayoutMetrics {
    static func preferredHeight(for text: String, width: CGFloat) -> CGFloat {
        let visualLineCount = wrappedLineCount(for: text, width: width)
        let contentHeight = CGFloat(visualLineCount) * 20 + 16
        return ceil(max(84, 36 + contentHeight))
    }

    private static func wrappedLineCount(for text: String, width: CGFloat) -> Int {
        let insetWidth: CGFloat = 24
        let availableWidth = max(40, width - insetWidth)
        let characterWidth = max(
            7,
            NSString(string: "M").size(withAttributes: [
                .font: PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            ]).width
        )
        let maxColumns = max(1, Int(floor(availableWidth / characterWidth)))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return max(1, lines.reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.utf16.count) / Double(maxColumns))))
        })
    }
}

public final class MarkdownCodeBlockAttachment: NSTextAttachment {
    public private(set) var presentation: MarkdownCodeBlockPresentation?

    public init(presentation: MarkdownCodeBlockPresentation) {
        self.presentation = presentation
        super.init(data: nil, ofType: nil)
        #if os(iOS)
        allowsTextAttachmentView = false
        #endif
        updateHeight(presentation.estimatedHeight)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func updateHeight(_ height: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: 1, height: ceil(height))
        if var presentation {
            presentation.estimatedHeight = ceil(height)
            self.presentation = presentation
        }
    }

    public override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let height = presentation.map {
            MarkdownCodeBlockLayoutMetrics.preferredHeight(
                for: $0.codeContent,
                width: proposedLineFragment.width
            )
        } ?? bounds.height
        return CGRect(
            x: 0,
            y: 0,
            width: max(1, proposedLineFragment.width),
            height: max(1, height)
        )
    }
}
#endif

private extension MarkdownRenderer {
    struct ListMarker {
        var indent: Int
        var endOffset: Int
        var style: ListMarkerStyle
    }

    enum ListMarkerStyle {
        case unordered
        case ordered(number: String)
    }

    struct ListLayout {
        var orderedWidthsByIndent: [Int: Int]
        var markerColumnWidthsByIndent: [Int: CGFloat]
        var markerStartByIndent: [Int: CGFloat]
        var contentStartByIndent: [Int: CGFloat]
    }

    func listMarker(in line: String) -> ListMarker? {
        let indent = line.prefix { $0 == " " }.count
        let trimmed = String(line.dropFirst(indent))
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return ListMarker(indent: indent, endOffset: indent + 2, style: .unordered)
        }

        var digits = ""
        for character in trimmed {
            if character.isNumber {
                digits.append(character)
                continue
            }
            if !digits.isEmpty && (character == "." || character == ")") {
                let after = trimmed.dropFirst(digits.count + 1)
                if after.first == " " {
                    return ListMarker(
                        indent: indent,
                        endOffset: indent + digits.count + 2,
                        style: .ordered(number: digits)
                    )
                }
            }
            break
        }

        return nil
    }

    func listLayout(for lines: [MarkdownLine]) -> ListLayout {
        let markers = lines.compactMap { listMarker(in: $0.textWithoutNewline) }
        let orderedWidths = orderedMarkerWidthsByIndent(markers: markers)
        let markerColumnWidths = markerColumnWidthsByIndent(markers: markers, orderedWidths: orderedWidths)
        let indents = Set(markers.map(\.indent)).sorted()
        var markerStartByIndent: [Int: CGFloat] = [:]
        var contentStartByIndent: [Int: CGFloat] = [:]

        for indent in indents {
            if let parentIndent = indents.last(where: { $0 < indent }),
               let parentContentStart = contentStartByIndent[parentIndent] {
                markerStartByIndent[indent] = parentContentStart
            } else {
                markerStartByIndent[indent] = listIndentWidth(indent)
            }

            contentStartByIndent[indent] = (markerStartByIndent[indent] ?? 0) + (markerColumnWidths[indent] ?? markerWidth("- "))
        }

        return ListLayout(
            orderedWidthsByIndent: orderedWidths,
            markerColumnWidthsByIndent: markerColumnWidths,
            markerStartByIndent: markerStartByIndent,
            contentStartByIndent: contentStartByIndent
        )
    }

    func orderedMarkerWidthsByIndent(markers: [ListMarker]) -> [Int: Int] {
        var widths: [Int: Int] = [:]
        for marker in markers {
            guard case .ordered(let number) = marker.style else {
                continue
            }
            widths[marker.indent] = max(widths[marker.indent] ?? 0, number.count)
        }
        return widths
    }

    func markerColumnWidthsByIndent(markers: [ListMarker], orderedWidths: [Int: Int]) -> [Int: CGFloat] {
        var widths: [Int: CGFloat] = [:]
        for marker in markers {
            let markerText = renderedMarker(for: marker, orderedWidths: orderedWidths)
            widths[marker.indent] = max(widths[marker.indent] ?? 0, markerWidth(markerText))
        }
        return widths
    }

    func renderedMarker(for marker: ListMarker, layout: ListLayout) -> String {
        renderedMarker(for: marker, orderedWidths: layout.orderedWidthsByIndent)
    }

    func renderedMarker(for marker: ListMarker, orderedWidths: [Int: Int]) -> String {
        switch marker.style {
        case .unordered:
            return "- "
        case .ordered(let number):
            let width = orderedWidths[marker.indent] ?? number.count
            let padding = String(repeating: " ", count: max(0, width - number.count))
            return padding + number + ". "
        }
    }

    func listParagraphStyle(marker: ListMarker, layout: ListLayout) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = layout.markerStartByIndent[marker.indent] ?? listIndentWidth(marker.indent)
        style.headIndent = layout.contentStartByIndent[marker.indent] ?? style.firstLineHeadIndent + markerWidth("- ")
        style.lineBreakMode = .byWordWrapping
        return style.copy() as! NSParagraphStyle
    }

    func markerTrailingSpaceExpansion(marker: ListMarker, markerText: String, layout: ListLayout) -> CGFloat {
        guard markerText.hasSuffix(" ") else {
            return 0
        }
        let columnWidth = layout.markerColumnWidthsByIndent[marker.indent] ?? markerWidth(markerText)
        return max(0, columnWidth - markerWidth(markerText))
    }

    func listMarkerAttributedString(
        _ markerText: String,
        attributes: [NSAttributedString.Key: Any],
        extraTrailingSpaceWidth: CGFloat
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: markerText, attributes: attributes)
        if extraTrailingSpaceWidth > 0 {
            attributed.addAttribute(
                .kern,
                value: extraTrailingSpaceWidth,
                range: NSRange(location: markerText.utf16.count - 1, length: 1)
            )
        }
        return attributed.copy() as! NSAttributedString
    }

    func listIndentWidth(_ sourceIndent: Int) -> CGFloat {
        guard sourceIndent > 0 else {
            return 0
        }
        #if canImport(UIKit) || canImport(AppKit)
        let attributed = NSAttributedString(
            string: String(repeating: " ", count: sourceIndent),
            attributes: [.font: PlatformFont.preferredMonospacedBody]
        )
        return ceil(attributed.size().width)
        #else
        return CGFloat(sourceIndent * 8)
        #endif
    }

    func markerWidth(_ markerText: String) -> CGFloat {
        #if canImport(UIKit) || canImport(AppKit)
        let attributed = NSAttributedString(
            string: markerText,
            attributes: [.font: PlatformFont.preferredMonospacedBody]
        )
        return ceil(attributed.size().width)
        #else
        return CGFloat(markerText.utf16.count * 8)
        #endif
    }

    func match(_ characters: [Character], at index: Int, token: String) -> Bool {
        let tokenCharacters = Array(token)
        guard index + tokenCharacters.count <= characters.count else {
            return false
        }
        return Array(characters[index..<(index + tokenCharacters.count)]) == tokenCharacters
    }

    func findToken(_ token: String, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if match(characters, at: index, token: token) {
                return index
            }
            index += 1
        }
        return nil
    }

    func findCharacter(_ character: Character, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == character {
                return index
            }
            index += 1
        }
        return nil
    }

    func isInlineTokenStarter(_ character: Character) -> Bool {
        character == "*" || character == "_" || character == "`" || character == "["
    }

    func nextInlineTokenStarter(in characters: [Character], from start: Int) -> Int {
        var index = start
        while index < characters.count {
            if isInlineTokenStarter(characters[index]) {
                return index
            }
            index += 1
        }
        return characters.count
    }

    func sourceLength(_ characters: ArraySlice<Character>) -> Int {
        characters.reduce(0) { partialResult, character in
            partialResult + String(character).utf16.count
        }
    }
}

#if canImport(UIKit) || canImport(AppKit)
private func bodyAttributes(paragraphStyle: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.preferredBody,
        .foregroundColor: PlatformColor.markdownPrimaryText,
    ]
    if let paragraphStyle {
        attributes[.paragraphStyle] = paragraphStyle
    }
    return attributes
}

private func quoteAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredBody,
        .foregroundColor: PlatformColor.markdownSecondaryText,
    ]
}

private func quoteMarkerAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredBody,
        .foregroundColor: PlatformColor.accentColor,
    ]
}

private func listMarkerAttributes(paragraphStyle: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.preferredMonospacedBody,
        .foregroundColor: PlatformColor.accentColor,
    ]
    if let paragraphStyle {
        attributes[.paragraphStyle] = paragraphStyle
    }
    return attributes
}

private func strongAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredBoldBody,
    ]
}

private func emphasisAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredItalicBody,
    ]
}

private func strongEmphasisAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredBoldItalicBody,
    ]
}

private func codeSpanAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredMonospacedBody,
        .backgroundColor: PlatformColor.codeBackground,
    ]
}

private func linkAttributes() -> [NSAttributedString.Key: Any] {
    [
        .foregroundColor: PlatformColor.accentColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
}

private func objectAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredMonospacedBody,
        .foregroundColor: PlatformColor.objectText,
        .backgroundColor: PlatformColor.objectBackground,
    ]
}

private func sourceAttributes(for block: MarkdownBlock) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.preferredMonospacedBody,
        .foregroundColor: PlatformColor.sourceText,
    ]
    if block.kind == .list {
        attributes[.backgroundColor] = PlatformColor.listEditingBackground
    }
    return attributes
}

private func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
    [
        .font: PlatformFont.preferredHeading(level: level),
        .foregroundColor: PlatformColor.markdownPrimaryText,
    ]
}

private extension PlatformFont {
    static var preferredBody: PlatformFont {
        #if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body)
        #else
        NSFont.preferredFont(forTextStyle: .body)
        #endif
    }

    static var preferredBoldBody: PlatformFont {
        #if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body).withTraits(.traitBold)
        #else
        NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize)
        #endif
    }

    static var preferredItalicBody: PlatformFont {
        #if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body).withTraits(.traitItalic)
        #else
        NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .body), toHaveTrait: .italicFontMask)
        #endif
    }

    static var preferredBoldItalicBody: PlatformFont {
        #if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body).withTraits([.traitBold, .traitItalic])
        #else
        let bold = NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize)
        return NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        #endif
    }

    static var preferredMonospacedBody: PlatformFont {
        #if canImport(UIKit)
        UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        #else
        NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        #endif
    }

    static func preferredHeading(level: Int) -> PlatformFont {
        let size: CGFloat
        switch level {
        case 1:
            size = 28
        case 2:
            size = 24
        case 3:
            size = 21
        default:
            size = 18
        }
        #if canImport(UIKit)
        return UIFont.systemFont(ofSize: size, weight: .bold)
        #else
        return NSFont.boldSystemFont(ofSize: size)
        #endif
    }
}

#if canImport(UIKit)
private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif

private extension PlatformColor {
    static var markdownPrimaryText: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        NSColor.labelColor
        #endif
    }

    static var markdownSecondaryText: PlatformColor {
        #if canImport(UIKit)
        .secondaryLabel
        #else
        NSColor.secondaryLabelColor
        #endif
    }

    static var accentColor: PlatformColor {
        #if canImport(UIKit)
        .systemTeal
        #else
        .systemTeal
        #endif
    }

    static var codeBackground: PlatformColor {
        #if canImport(UIKit)
        .secondarySystemBackground
        #else
        .textBackgroundColor
        #endif
    }

    static var objectBackground: PlatformColor {
        #if canImport(UIKit)
        .tertiarySystemFill
        #else
        .separatorColor.withAlphaComponent(0.18)
        #endif
    }

    static var objectText: PlatformColor {
        #if canImport(UIKit)
        .systemIndigo
        #else
        .systemIndigo
        #endif
    }

    static var sourceText: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        .labelColor
        #endif
    }

    static var listEditingBackground: PlatformColor {
        #if canImport(UIKit)
        .systemYellow.withAlphaComponent(0.16)
        #else
        .systemYellow.withAlphaComponent(0.16)
        #endif
    }
}
#endif
