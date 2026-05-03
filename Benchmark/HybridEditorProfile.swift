import Foundation
import MarkdownEditor

@main
struct HybridEditorProfile {
    @MainActor
    static func main() {
        let source = makeDocument(paragraphs: 1_000, tables: 50, codeBlocks: 100)
        let parser = MarkdownParser()
        let renderer = MarkdownRenderer()
        let rewriter = MarkdownRewriter()

        let blocks = measure("parse.large-document") {
            parser.parse(source)
        }

        let preview = measure("render.preview") {
            renderer.render(source: source, blocks: blocks)
        }

        let listScope = blocks.first(where: { $0.kind == .list })!.activeScope
        _ = measure("render.active-list-group") {
            renderer.render(source: source, blocks: blocks, activeScope: listScope)
        }

        let prefixEditedSource: String
        if let paragraph = blocks.first(where: { $0.kind == .paragraph }) {
            let editResult = measure("rewrite.paragraph-insert") {
                rewriter.replace(
                    source: source,
                    range: MarkdownSourceRange(location: paragraph.contentRange.location, length: 0),
                    with: "typed "
                )
            }
            prefixEditedSource = editResult.source
        } else {
            prefixEditedSource = source
        }

        let prefixEditedBlocks = measure("parse.prefix-edited-large-document") {
            parser.parse(prefixEditedSource)
        }

        if let table = blocks.first(where: { $0.kind == .table }) {
            _ = measure("rewrite.table-cell") {
                rewriter.updateTableCell(source: source, block: table, row: 1, column: 1, text: "99")
            }
        }

        let visibleLookupChecksum = measure("presentation.visible-to-source-lookups") {
            lookupVisibleOffsets(in: preview, repetitions: 20)
        }

        let sourceLookupChecksum = measure("presentation.source-to-visible-lookups") {
            lookupSourceOffsets(in: preview, sourceLength: source.utf16.count, repetitions: 20)
        }

        let controllerSourceLength = measure("controller.prefix-typing-before-code-blocks") {
            typeBeforeCodeBlocks(source: source, insertions: 20)
        }

        let originalCodeBlockIDs = codeBlockIDs(in: blocks)
        let retainedCodeBlockIDCount = retainedCodeBlockIDs(before: blocks, after: prefixEditedBlocks)

        print("visible.characters=\(preview.attributedString.length)")
        print("source.characters=\(source.utf16.count)")
        print("blocks=\(blocks.count)")
        print("code.blocks=\(originalCodeBlockIDs.count)")
        print("code.block.ids.retained.after-prefix-edit=\(retainedCodeBlockIDCount)")
        print("visible.lookup.checksum=\(visibleLookupChecksum)")
        print("source.lookup.checksum=\(sourceLookupChecksum)")
        print("controller.source.characters.after-prefix-typing=\(controllerSourceLength)")
    }

    static func measure<T>(_ name: String, operation: () -> T) -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = operation()
        let elapsed = start.duration(to: clock.now)
        print("\(name)=\(elapsed.components.seconds)s \(elapsed.components.attoseconds / 1_000_000_000_000_000)ms")
        return result
    }

    static func lookupVisibleOffsets(in presentation: MarkdownPresentation, repetitions: Int) -> Int {
        let length = presentation.attributedString.length
        guard length > 0 else { return 0 }

        // Accumulate results so release builds cannot optimize the lookup loop away.
        var checksum = 0
        for _ in 0..<repetitions {
            for offset in 0...length {
                checksum &+= presentation.visibleOffsetToSource(offset)
            }
        }
        return checksum
    }

    static func lookupSourceOffsets(
        in presentation: MarkdownPresentation,
        sourceLength: Int,
        repetitions: Int
    ) -> Int {
        guard sourceLength > 0 else { return 0 }

        // Accumulate results so release builds cannot optimize the lookup loop away.
        var checksum = 0
        for _ in 0..<repetitions {
            for offset in 0...sourceLength {
                checksum &+= presentation.sourceOffsetToVisible(offset)
            }
        }
        return checksum
    }

    @MainActor
    static func typeBeforeCodeBlocks(source: String, insertions: Int) -> Int {
        // Mirror the trace scenario: repeated typing before code blocks should
        // preserve downstream IDs and avoid code block view churn in the app.
        let controller = MarkdownEditorController(source: source)
        guard let paragraph = controller.document.blocks.first(where: { $0.kind == .paragraph }) else {
            return controller.source.utf16.count
        }

        var sourceOffset = paragraph.contentRange.location
        for _ in 0..<insertions {
            let visibleOffset = controller.visibleOffset(forSourceOffset: sourceOffset)
            _ = controller.activate(atVisibleOffset: visibleOffset)
            guard let result = controller.replaceVisible(
                range: NSRange(location: visibleOffset, length: 0),
                with: "x"
            ) else {
                continue
            }
            sourceOffset = result.selectionSourceOffset
        }

        return controller.source.utf16.count
    }

    static func codeBlockIDs(in blocks: [MarkdownBlock]) -> [String] {
        blocks.filter { $0.kind == .codeBlock }.map(\.id)
    }

    static func retainedCodeBlockIDs(before: [MarkdownBlock], after: [MarkdownBlock]) -> Int {
        let beforeIDs = Set(codeBlockIDs(in: before))
        return codeBlockIDs(in: after).filter { beforeIDs.contains($0) }.count
    }

    static func makeDocument(paragraphs: Int, tables: Int, codeBlocks: Int) -> String {
        var output = """
        # Benchmark Document

        - Alpha
        - Beta
          - Nested
        - Gamma

        """

        for index in 0..<paragraphs {
            output += "Paragraph \(index) has **strong text**, `inline code`, and [a link](https://example.com).\n\n"
            if index < tables {
                output += """
                | Name | Score |
                | --- | ---: |
                | Row \(index) | \(index) |

                """
            }
            if index < codeBlocks {
                output += """
                ```swift
                let value\(index) = \(index)
                print(value\(index))
                ```

                """
            }
        }

        return output
    }
}
