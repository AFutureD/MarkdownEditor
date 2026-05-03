import Foundation

public struct MarkdownEditResult: Equatable, Sendable {
    public var source: String
    public var selectionSourceOffset: Int

    public init(source: String, selectionSourceOffset: Int) {
        self.source = source
        self.selectionSourceOffset = selectionSourceOffset
    }
}

public struct MarkdownRewriter: Sendable {
    public init() {}

    public func replace(source: String, range: MarkdownSourceRange, with replacement: String) -> MarkdownEditResult {
        var updated = source
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let stringRange = Range(nsRange, in: updated) else {
            return MarkdownEditResult(source: source, selectionSourceOffset: range.upperBound)
        }
        updated.replaceSubrange(stringRange, with: replacement)
        return MarkdownEditResult(
            source: updated,
            selectionSourceOffset: range.location + replacement.utf16.count
        )
    }

    public func replaceCodeContent(source: String, block: MarkdownBlock, with replacement: String) -> MarkdownEditResult {
        guard let code = block.code else {
            return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.upperBound)
        }
        return replace(source: source, range: code.codeContentRange, with: replacement)
    }

    public func updateCodeLanguage(source: String, block: MarkdownBlock, language: String) -> MarkdownEditResult {
        guard let code = block.code else {
            return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.location)
        }

        let openingLineRange = MarkdownSourceRange(
            location: block.sourceRange.location,
            length: max(0, code.codeContentRange.location - block.sourceRange.location)
        )
        let openingLine = substring(source, range: openingLineRange)
        let newlineSuffix = openingLine.hasSuffix("\n") ? "\n" : ""
        let replacement = code.fence + (language.isEmpty ? "" : language) + newlineSuffix
        return replace(source: source, range: openingLineRange, with: replacement)
    }

    public func updateTableCell(source: String, block: MarkdownBlock, row: Int, column: Int, text: String) -> MarkdownEditResult {
        guard var table = block.table else {
            return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.upperBound)
        }

        if row == 0 {
            guard table.columns.indices.contains(column) else {
                return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.upperBound)
            }
            table.columns[column] = text
        } else {
            let bodyIndex = row - 1
            guard table.rows.indices.contains(bodyIndex) else {
                return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.upperBound)
            }
            while table.rows[bodyIndex].count < table.columns.count {
                table.rows[bodyIndex].append("")
            }
            guard table.rows[bodyIndex].indices.contains(column) else {
                return MarkdownEditResult(source: source, selectionSourceOffset: block.sourceRange.upperBound)
            }
            table.rows[bodyIndex][column] = text
        }

        let replacement = serialize(table: table)
        return replace(source: source, range: block.sourceRange, with: replacement)
    }

    public func serialize(table: MarkdownTable) -> String {
        let columnCount = max(table.columns.count, table.alignments.count, table.rows.map(\.count).max() ?? 0)
        let columns = paddedRow(table.columns, columnCount: columnCount)
        let rows = table.rows.map { paddedRow($0, columnCount: columnCount) }
        let alignments = paddedAlignments(table.alignments, columnCount: columnCount)
        var widths = Array(repeating: 3, count: columnCount)

        for index in 0..<columnCount {
            widths[index] = max(widths[index], columns[index].count)
            for row in rows {
                widths[index] = max(widths[index], row[index].count)
            }
        }

        var output = ""
        output += renderTableRow(columns, widths: widths)
        output += renderAlignmentRow(alignments, widths: widths)
        for row in rows {
            output += renderTableRow(row, widths: widths)
        }
        return output
    }
}

private extension MarkdownRewriter {
    func paddedRow(_ row: [String], columnCount: Int) -> [String] {
        if row.count >= columnCount {
            return Array(row.prefix(columnCount))
        }
        return row + Array(repeating: "", count: columnCount - row.count)
    }

    func paddedAlignments(_ alignments: [MarkdownTableAlignment], columnCount: Int) -> [MarkdownTableAlignment] {
        if alignments.count >= columnCount {
            return Array(alignments.prefix(columnCount))
        }
        return alignments + Array(repeating: .none, count: columnCount - alignments.count)
    }

    func renderTableRow(_ row: [String], widths: [Int]) -> String {
        let cells = row.enumerated().map { index, cell in
            " " + cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) + " "
        }
        return "|" + cells.joined(separator: "|") + "|\n"
    }

    func renderAlignmentRow(_ alignments: [MarkdownTableAlignment], widths: [Int]) -> String {
        let cells = alignments.enumerated().map { index, alignment -> String in
            let width = max(3, widths[index])
            switch alignment {
            case .none:
                return " " + String(repeating: "-", count: width) + " "
            case .left:
                return " :" + String(repeating: "-", count: width - 1) + " "
            case .right:
                return " " + String(repeating: "-", count: width - 1) + ": "
            case .center:
                return " :" + String(repeating: "-", count: width - 2) + ": "
            }
        }
        return "|" + cells.joined(separator: "|") + "|\n"
    }

    func substring(_ source: String, range: MarkdownSourceRange) -> String {
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let stringRange = Range(nsRange, in: source) else {
            return ""
        }
        return String(source[stringRange])
    }
}
