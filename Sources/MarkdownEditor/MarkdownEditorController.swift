import Combine
import Foundation

@MainActor
public final class MarkdownEditorController: ObservableObject {
    @Published public private(set) var document: MarkdownDocument
    @Published public private(set) var presentation: MarkdownPresentation

    private let parser: MarkdownParser
    private let renderer: MarkdownRenderer
    private let rewriter: MarkdownRewriter

    public init(source: String) {
        self.parser = MarkdownParser()
        self.renderer = MarkdownRenderer()
        self.rewriter = MarkdownRewriter()
        let document = MarkdownDocument(source: source, parser: parser)
        self.document = document
        self.presentation = renderer.render(document: document)
    }

    public var source: String {
        document.source
    }

    public var activeScope: MarkdownActiveScope? {
        document.activeScope
    }

    @discardableResult
    public func activate(atVisibleOffset visibleOffset: Int) -> Int {
        let sourceOffset = presentation.visibleOffsetToSource(visibleOffset)
        let newScope = presentation.activeScope(containingVisibleOffset: visibleOffset)
        guard newScope != document.activeScope else {
            return visibleOffset
        }
        document.activeScope = newScope
        rebuildPresentation()
        return presentation.sourceOffsetToVisible(sourceOffset)
    }

    @discardableResult
    public func activate(scope: MarkdownActiveScope?, preservingSourceOffset sourceOffset: Int? = nil) -> Int {
        document.activeScope = scope
        rebuildPresentation()
        return presentation.sourceOffsetToVisible(sourceOffset ?? 0)
    }

    public func deactivate() {
        document.activeScope = nil
        rebuildPresentation()
    }

    public func replaceVisible(range: NSRange, with replacement: String) -> MarkdownEditResult? {
        let activeScope = document.activeScope
        let targetPresentation: MarkdownBlockPresentation
        let isTrailingCodeBlockInsertion: Bool

        if let activeScope,
           let presentation = activePresentation(for: activeScope) {
            targetPresentation = presentation
            isTrailingCodeBlockInsertion = activeScope.isCodeBlock
                && range.length == 0
                && range.location == targetPresentation.visibleRange.upperBound
        } else if let presentation = trailingCodeBlockPresentation(for: range) {
            targetPresentation = presentation
            isTrailingCodeBlockInsertion = true
        } else {
            return nil
        }

        guard visibleRange(range, isContainedIn: targetPresentation.visibleRange),
              activeScope?.isCodeBlock != true || isTrailingCodeBlockInsertion else {
            return nil
        }

        let sourceStart = presentation.visibleOffsetToSource(range.location)
        let sourceEnd = presentation.visibleOffsetToSource(range.location + range.length)
        let sourceRange = MarkdownSourceRange(location: sourceStart, length: max(0, sourceEnd - sourceStart))
        let adjustedReplacement = replacementForTrailingCodeBlockInsertion(
            replacement,
            sourceRange: sourceRange,
            blockPresentation: targetPresentation,
            isTrailingCodeBlockInsertion: isTrailingCodeBlockInsertion
        )
        let result = rewriter.replace(source: document.source, range: sourceRange, with: adjustedReplacement)
        replaceDocumentSource(
            result.source,
            preferredActiveScope: isTrailingCodeBlockInsertion ? nil : activeScope,
            fallbackSourceOffset: isTrailingCodeBlockInsertion ? nil : result.selectionSourceOffset,
            preserveExistingActiveScope: !isTrailingCodeBlockInsertion
        )
        return result
    }

    public func replaceCodeContent(blockID: String, with replacement: String) {
        guard let block = document.block(id: blockID) else { return }
        let result = rewriter.replaceCodeContent(source: document.source, block: block, with: replacement)
        replaceDocumentSource(result.source, preferredActiveScope: .codeBlock(blockID))
    }

    public func updateCodeLanguage(blockID: String, language: String) {
        guard let block = document.block(id: blockID) else { return }
        let result = rewriter.updateCodeLanguage(source: document.source, block: block, language: language)
        replaceDocumentSource(result.source, preferredActiveScope: .codeBlock(blockID))
    }

    public func updateTableCell(blockID: String, row: Int, column: Int, text: String) {
        guard let block = document.block(id: blockID) else { return }
        let result = rewriter.updateTableCell(source: document.source, block: block, row: row, column: column, text: text)
        replaceDocumentSource(result.source, preferredActiveScope: .table(blockID))
    }

    public func insertTableRow(blockID: String, at row: Int, values: [String]) {
        guard let block = document.block(id: blockID) else { return }
        let result = rewriter.insertTableRow(source: document.source, block: block, at: row, values: values)
        replaceDocumentSource(result.source, preferredActiveScope: .table(blockID))
    }

    public func deleteTableRow(blockID: String, at row: Int) {
        guard let block = document.block(id: blockID) else { return }
        let result = rewriter.deleteTableRow(source: document.source, block: block, at: row)
        replaceDocumentSource(result.source, preferredActiveScope: .table(blockID))
    }

    public func firstBlock(kind: MarkdownBlockKind) -> MarkdownBlock? {
        document.blocks.first { $0.kind == kind }
    }

    public func visibleOffset(forSourceOffset sourceOffset: Int) -> Int {
        presentation.sourceOffsetToVisible(sourceOffset)
    }

    public func sourceOffset(forVisibleOffset visibleOffset: Int) -> Int {
        presentation.visibleOffsetToSource(visibleOffset)
    }
}

private extension MarkdownActiveScope {
    var isCodeBlock: Bool {
        if case .codeBlock = self {
            return true
        }
        return false
    }
}

private extension MarkdownEditorController {
    func rebuildPresentation() {
        presentation = renderer.render(document: document)
    }

    func replaceDocumentSource(
        _ source: String,
        preferredActiveScope: MarkdownActiveScope?,
        fallbackSourceOffset: Int? = nil,
        preserveExistingActiveScope: Bool = true
    ) {
        let activeScope = preferredActiveScope ?? (preserveExistingActiveScope ? document.activeScope : nil)
        document = MarkdownDocument(source: source, parser: parser)
        document.activeScope = restoreActiveScope(activeScope) ?? fallbackActiveScope(containingSourceOffset: fallbackSourceOffset)
        rebuildPresentation()
    }

    func restoreActiveScope(_ scope: MarkdownActiveScope?) -> MarkdownActiveScope? {
        guard let scope else { return nil }
        switch scope {
        case .block(let id):
            return document.block(id: id)?.activeScope
        case .listGroup(let id):
            if document.blocks.contains(where: { $0.listGroupID == id }) {
                return .listGroup(id)
            }
            return nil
        case .table(let id):
            return document.block(id: id)?.kind == .table ? .table(id) : nil
        case .codeBlock(let id):
            return document.block(id: id)?.kind == .codeBlock ? .codeBlock(id) : nil
        }
    }

    func fallbackActiveScope(containingSourceOffset sourceOffset: Int?) -> MarkdownActiveScope? {
        guard let sourceOffset else { return nil }
        return document.block(containingSourceOffset: sourceOffset)?.activeScope
    }

    func activePresentation(for scope: MarkdownActiveScope) -> MarkdownBlockPresentation? {
        switch scope {
        case .block(let id), .table(let id), .codeBlock(let id):
            return presentation.blocks.first { $0.blockID == id }
        case .listGroup(let id):
            return presentation.blocks.first { $0.listGroupID == id }
        }
    }

    func trailingCodeBlockPresentation(for range: NSRange) -> MarkdownBlockPresentation? {
        guard range.length == 0 else { return nil }
        return presentation.blocks.first { presentation in
            presentation.kind == .codeBlock && range.location == presentation.visibleRange.upperBound
        }
    }

    func replacementForTrailingCodeBlockInsertion(
        _ replacement: String,
        sourceRange: MarkdownSourceRange,
        blockPresentation: MarkdownBlockPresentation,
        isTrailingCodeBlockInsertion: Bool
    ) -> String {
        guard isTrailingCodeBlockInsertion,
              !replacement.isEmpty,
              sourceRange.length == 0,
              sourceRange.location == blockPresentation.sourceRange.upperBound,
              !sourceHasLineBreak(beforeUTF16Offset: sourceRange.location),
              !replacementStartsWithLineBreak(replacement) else {
            return replacement
        }
        return "\n" + replacement
    }

    func sourceHasLineBreak(beforeUTF16Offset offset: Int) -> Bool {
        guard offset > 0,
              let index = String.Index(utf16Offset: offset - 1, in: document.source) else {
            return false
        }
        return document.source[index] == "\n" || document.source[index] == "\r"
    }

    func replacementStartsWithLineBreak(_ replacement: String) -> Bool {
        guard let first = replacement.first else { return false }
        return first == "\n" || first == "\r"
    }

    func visibleRange(_ range: NSRange, isContainedIn container: NSRange) -> Bool {
        range.location >= container.location && range.location + range.length <= container.location + container.length
    }
}

private extension String.Index {
    init?(utf16Offset: Int, in string: String) {
        guard let utf16Index = string.utf16.index(
            string.utf16.startIndex,
            offsetBy: utf16Offset,
            limitedBy: string.utf16.endIndex
        ),
        let index = utf16Index.samePosition(in: string) else {
            return nil
        }
        self = index
    }
}
