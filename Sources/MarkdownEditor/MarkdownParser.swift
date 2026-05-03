import Foundation

public struct MarkdownParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> [MarkdownBlock] {
        let lines = MarkdownLine.scan(source)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.isBlank {
                blocks.append(makeBlock(kind: .blank, lines: [line], contentRange: line.range))
                index += 1
                continue
            }

            if let codeBlock = parseCodeBlock(lines: lines, startIndex: index) {
                blocks.append(codeBlock.block)
                index = codeBlock.nextIndex
                continue
            }

            if let tableBlock = parseTable(lines: lines, startIndex: index) {
                blocks.append(tableBlock.block)
                index = tableBlock.nextIndex
                continue
            }

            if isListLine(line.textWithoutNewline) {
                let result = parseList(lines: lines, startIndex: index)
                blocks.append(result.block)
                index = result.nextIndex
                continue
            }

            if let heading = parseHeading(line) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isBlockquoteLine(line.textWithoutNewline) {
                let result = parseBlockquote(lines: lines, startIndex: index)
                blocks.append(result.block)
                index = result.nextIndex
                continue
            }

            let result = parseParagraph(lines: lines, startIndex: index)
            blocks.append(result.block)
            index = result.nextIndex
        }

        return blocks
    }
}

private extension MarkdownParser {
    func makeBlock(
        kind: MarkdownBlockKind,
        lines: [MarkdownLine],
        contentRange: MarkdownSourceRange,
        headingLevel: Int? = nil,
        listGroupID: String? = nil,
        code: MarkdownCodeBlock? = nil,
        table: MarkdownTable? = nil
    ) -> MarkdownBlock {
        let first = lines[0]
        let last = lines[lines.count - 1]
        let sourceRange = MarkdownSourceRange(
            location: first.range.location,
            length: last.range.upperBound - first.range.location
        )
        return MarkdownBlock(
            id: "b\(first.range.location)",
            kind: kind,
            sourceRange: sourceRange,
            contentRange: contentRange,
            headingLevel: headingLevel,
            listGroupID: listGroupID,
            code: code,
            table: table
        )
    }

    func parseHeading(_ line: MarkdownLine) -> MarkdownBlock? {
        let text = line.textWithoutNewline
        let leadingSpaces = text.prefix { $0 == " " }.count
        guard leadingSpaces <= 3 else { return nil }

        let trimmed = text.dropFirst(leadingSpaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }

        let afterHashes = trimmed.dropFirst(hashes)
        guard afterHashes.isEmpty || afterHashes.first == " " else { return nil }

        let markerLength = leadingSpaces + hashes + (afterHashes.first == " " ? 1 : 0)
        let contentLocation = line.range.location + markerLength
        let contentLength = max(0, line.textWithoutNewline.utf16.count - markerLength)
        let contentRange = MarkdownSourceRange(location: contentLocation, length: contentLength)
        return makeBlock(kind: .heading, lines: [line], contentRange: contentRange, headingLevel: hashes)
    }

    func parseCodeBlock(lines: [MarkdownLine], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int)? {
        let line = lines[startIndex]
        let trimmed = line.textWithoutNewline.trimmingCharacters(in: .whitespaces)
        let fence: String
        if trimmed.hasPrefix("```") {
            fence = "```"
        } else if trimmed.hasPrefix("~~~") {
            fence = "~~~"
        } else {
            return nil
        }

        let info = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
        var endIndex = startIndex + 1
        while endIndex < lines.count {
            let candidate = lines[endIndex].textWithoutNewline.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix(fence) {
                break
            }
            endIndex += 1
        }

        let closingIndex = min(endIndex, lines.count - 1)
        let blockLines = Array(lines[startIndex...closingIndex])
        let contentStart = line.range.upperBound
        let contentEnd: Int
        if endIndex < lines.count {
            contentEnd = lines[endIndex].range.location
        } else {
            contentEnd = lines[closingIndex].range.upperBound
        }
        let code = MarkdownCodeBlock(
            language: info,
            fence: fence,
            codeContentRange: MarkdownSourceRange(location: contentStart, length: max(0, contentEnd - contentStart))
        )
        let block = makeBlock(
            kind: .codeBlock,
            lines: blockLines,
            contentRange: code.codeContentRange,
            code: code
        )
        return (block, min(closingIndex + 1, lines.count))
    }

    func parseTable(lines: [MarkdownLine], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }
        let header = lines[startIndex]
        let separator = lines[startIndex + 1]
        guard looksLikeTableRow(header.textWithoutNewline),
              parseAlignmentRow(separator.textWithoutNewline) != nil else {
            return nil
        }

        var endIndex = startIndex + 2
        while endIndex < lines.count && looksLikeTableRow(lines[endIndex].textWithoutNewline) {
            endIndex += 1
        }

        let blockLines = Array(lines[startIndex..<endIndex])
        let columns = splitTableCells(header.textWithoutNewline)
        let alignments = parseAlignmentRow(separator.textWithoutNewline) ?? []
        let rows = blockLines.dropFirst(2).map { splitTableCells($0.textWithoutNewline) }
        let table = MarkdownTable(columns: columns, rows: rows, alignments: alignments)
        let contentRange = MarkdownSourceRange(
            location: header.range.location,
            length: blockLines.last!.range.upperBound - header.range.location
        )
        let block = makeBlock(kind: .table, lines: blockLines, contentRange: contentRange, table: table)
        return (block, endIndex)
    }

    func parseList(lines: [MarkdownLine], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int) {
        var endIndex = startIndex
        while endIndex < lines.count {
            let line = lines[endIndex]
            if line.isBlank {
                break
            }
            if isListLine(line.textWithoutNewline) || isIndentedListContinuation(line.textWithoutNewline) {
                endIndex += 1
                continue
            }
            break
        }

        let blockLines = Array(lines[startIndex..<endIndex])
        let first = blockLines[0]
        let contentRange = MarkdownSourceRange(
            location: first.range.location,
            length: blockLines.last!.range.upperBound - first.range.location
        )
        let listGroupID = "list-\(first.range.location)"
        let block = makeBlock(
            kind: .list,
            lines: blockLines,
            contentRange: contentRange,
            listGroupID: listGroupID
        )
        return (block, endIndex)
    }

    func parseBlockquote(lines: [MarkdownLine], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int) {
        var endIndex = startIndex
        while endIndex < lines.count && isBlockquoteLine(lines[endIndex].textWithoutNewline) {
            endIndex += 1
        }
        let blockLines = Array(lines[startIndex..<endIndex])
        let first = blockLines[0]
        let contentRange = MarkdownSourceRange(
            location: first.range.location,
            length: blockLines.last!.range.upperBound - first.range.location
        )
        return (makeBlock(kind: .blockquote, lines: blockLines, contentRange: contentRange), endIndex)
    }

    func parseParagraph(lines: [MarkdownLine], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int) {
        var endIndex = startIndex
        while endIndex < lines.count {
            let line = lines[endIndex]
            if line.isBlank || parseHeading(line) != nil || isListLine(line.textWithoutNewline) || isBlockquoteLine(line.textWithoutNewline) {
                break
            }
            if parseCodeBlock(lines: lines, startIndex: endIndex) != nil {
                break
            }
            if parseTable(lines: lines, startIndex: endIndex) != nil {
                break
            }
            endIndex += 1
        }

        let blockLines = Array(lines[startIndex..<endIndex])
        let first = blockLines[0]
        let contentRange = MarkdownSourceRange(
            location: first.range.location,
            length: blockLines.last!.range.upperBound - first.range.location
        )
        return (makeBlock(kind: .paragraph, lines: blockLines, contentRange: contentRange), endIndex)
    }

    func isBlockquoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    func isIndentedListContinuation(_ line: String) -> Bool {
        let leadingSpaces = line.prefix { $0 == " " }.count
        return leadingSpaces >= 2
    }

    func isListLine(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }

        var digitCount = 0
        for character in trimmed {
            if character.isNumber {
                digitCount += 1
                continue
            }
            return digitCount > 0 && (character == "." || character == ")") && trimmed.dropFirst(digitCount + 1).first == " "
        }

        return false
    }

    func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    func splitTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    func parseAlignmentRow(_ line: String) -> [MarkdownTableAlignment]? {
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTableAlignment] = []

        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("-") && trimmed.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }

            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            switch (left, right) {
            case (true, true):
                alignments.append(.center)
            case (true, false):
                alignments.append(.left)
            case (false, true):
                alignments.append(.right)
            case (false, false):
                alignments.append(.none)
            }
        }

        return alignments
    }
}

struct MarkdownLine: Equatable {
    var text: String
    var range: MarkdownSourceRange

    var textWithoutNewline: String {
        if text.hasSuffix("\r\n") {
            return String(text.dropLast(2))
        }
        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            return String(text.dropLast())
        }
        return text
    }

    var isBlank: Bool {
        textWithoutNewline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func scan(_ source: String) -> [MarkdownLine] {
        guard !source.isEmpty else {
            return []
        }

        var lines: [MarkdownLine] = []
        var startIndex = source.startIndex
        var offset = 0

        while startIndex < source.endIndex {
            var endIndex = startIndex
            while endIndex < source.endIndex && source[endIndex] != "\n" {
                endIndex = source.index(after: endIndex)
            }
            if endIndex < source.endIndex {
                endIndex = source.index(after: endIndex)
            }

            let text = String(source[startIndex..<endIndex])
            let length = text.utf16.count
            lines.append(MarkdownLine(text: text, range: MarkdownSourceRange(location: offset, length: length)))
            offset += length
            startIndex = endIndex
        }

        return lines
    }
}

