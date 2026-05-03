import Foundation
import MarkdownEditor

@main
struct HybridEditorProfile {
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

        if let paragraph = blocks.first(where: { $0.kind == .paragraph }) {
            _ = measure("rewrite.paragraph-insert") {
                rewriter.replace(
                    source: source,
                    range: MarkdownSourceRange(location: paragraph.contentRange.location, length: 0),
                    with: "typed "
                )
            }
        }

        if let table = blocks.first(where: { $0.kind == .table }) {
            _ = measure("rewrite.table-cell") {
                rewriter.updateTableCell(source: source, block: table, row: 1, column: 1, text: "99")
            }
        }

        print("visible.characters=\(preview.attributedString.length)")
        print("source.characters=\(source.utf16.count)")
        print("blocks=\(blocks.count)")
    }

    static func measure<T>(_ name: String, operation: () -> T) -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = operation()
        let elapsed = start.duration(to: clock.now)
        print("\(name)=\(elapsed.components.seconds)s \(elapsed.components.attoseconds / 1_000_000_000_000_000)ms")
        return result
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

