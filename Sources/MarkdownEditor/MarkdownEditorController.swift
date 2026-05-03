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
        guard let activeScope = document.activeScope,
              let activePresentation = activePresentation(for: activeScope),
              visibleRange(range, isContainedIn: activePresentation.visibleRange) else {
            return nil
        }

        let sourceStart = presentation.visibleOffsetToSource(range.location)
        let sourceEnd = presentation.visibleOffsetToSource(range.location + range.length)
        let sourceRange = MarkdownSourceRange(location: sourceStart, length: max(0, sourceEnd - sourceStart))
        let result = rewriter.replace(source: document.source, range: sourceRange, with: replacement)
        replaceDocumentSource(
            result.source,
            preferredActiveScope: activeScope,
            fallbackSourceOffset: result.selectionSourceOffset
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

private extension MarkdownEditorController {
    func rebuildPresentation() {
        presentation = renderer.render(document: document)
    }

    func replaceDocumentSource(
        _ source: String,
        preferredActiveScope: MarkdownActiveScope?,
        fallbackSourceOffset: Int? = nil
    ) {
        let activeScope = preferredActiveScope ?? document.activeScope
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

    func visibleRange(_ range: NSRange, isContainedIn container: NSRange) -> Bool {
        range.location >= container.location && range.location + range.length <= container.location + container.length
    }
}
