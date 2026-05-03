import Foundation

public struct MarkdownSourceRange: Equatable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var upperBound: Int {
        location + length
    }

    public func contains(_ offset: Int) -> Bool {
        offset >= location && offset < upperBound
    }
}

public enum MarkdownBlockKind: String, Equatable, Sendable {
    case paragraph
    case heading
    case list
    case blockquote
    case table
    case codeBlock
    case blank
}

public enum MarkdownDisplayMode: String, Equatable, Sendable {
    case preview
    case sourceEditing
    case objectPreview
    case objectEditing
}

public enum MarkdownActiveScope: Equatable, Sendable {
    case block(String)
    case listGroup(String)
    case table(String)
    case codeBlock(String)
}

public struct MarkdownCodeBlock: Equatable, Sendable {
    public var language: String
    public var fence: String
    public var codeContentRange: MarkdownSourceRange

    public init(language: String, fence: String, codeContentRange: MarkdownSourceRange) {
        self.language = language
        self.fence = fence
        self.codeContentRange = codeContentRange
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public var columns: [String]
    public var rows: [[String]]
    public var alignments: [MarkdownTableAlignment]

    public init(columns: [String], rows: [[String]], alignments: [MarkdownTableAlignment]) {
        self.columns = columns
        self.rows = rows
        self.alignments = alignments
    }
}

public enum MarkdownTableAlignment: String, Equatable, Sendable {
    case none
    case left
    case center
    case right
}

public struct MarkdownBlock: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: MarkdownBlockKind
    public var sourceRange: MarkdownSourceRange
    public var contentRange: MarkdownSourceRange
    public var headingLevel: Int?
    public var listGroupID: String?
    public var code: MarkdownCodeBlock?
    public var table: MarkdownTable?

    public init(
        id: String,
        kind: MarkdownBlockKind,
        sourceRange: MarkdownSourceRange,
        contentRange: MarkdownSourceRange,
        headingLevel: Int? = nil,
        listGroupID: String? = nil,
        code: MarkdownCodeBlock? = nil,
        table: MarkdownTable? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceRange = sourceRange
        self.contentRange = contentRange
        self.headingLevel = headingLevel
        self.listGroupID = listGroupID
        self.code = code
        self.table = table
    }

    public var activeScope: MarkdownActiveScope? {
        switch kind {
        case .list:
            guard let listGroupID else { return nil }
            return .listGroup(listGroupID)
        case .table:
            return .table(id)
        case .codeBlock:
            return .codeBlock(id)
        case .paragraph, .heading, .blockquote, .blank:
            return .block(id)
        }
    }
}

public struct MarkdownDocument: Equatable {
    public private(set) var source: String
    public private(set) var blocks: [MarkdownBlock]
    public var activeScope: MarkdownActiveScope?

    public init(source: String, parser: MarkdownParser = MarkdownParser()) {
        self.source = source
        self.blocks = parser.parse(source)
        self.activeScope = nil
    }

    public func block(id: String) -> MarkdownBlock? {
        blocks.first { $0.id == id }
    }

    public func block(containingSourceOffset offset: Int) -> MarkdownBlock? {
        blocks.first { block in
            block.sourceRange.contains(offset) || block.sourceRange.upperBound == offset
        }
    }
}
