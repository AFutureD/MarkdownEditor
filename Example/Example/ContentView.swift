//
//  ContentView.swift
//  Example
//
//  Created by Huanan on 2026/5/1.
//

import MarkdownEditor
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        HybridEditorDemoRepresentable()
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

struct HybridEditorDemoRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> HybridEditorDemoView {
        HybridEditorDemoView()
    }

    func updateUIView(_ uiView: HybridEditorDemoView, context: Context) {
        uiView.refresh()
    }
}

@MainActor
final class HybridEditorDemoView: UIView {
    private let controller = MarkdownEditorController(source: HybridEditorDemoView.sampleMarkdown)
    private lazy var editorView = MarkdownHybridEditorView(controller: controller)
    private let sourceTextView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func refresh() {
        editorView.applyPresentation()
        sourceTextView.text = controller.source
    }

    private func configure() {
        backgroundColor = .systemBackground
        accessibilityIdentifier = "HybridEditorDemoView"

        let rootStack = UIStackView()
        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        let sourcePanel = makeSourcePanel()

        editorView.accessibilityIdentifier = "HybridMarkdownEditorContainer"
        editorView.onSourceChange = { [weak self] source in
            self?.sourceTextView.text = source
        }

        rootStack.addArrangedSubview(editorView)
        rootStack.addArrangedSubview(sourcePanel)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sourcePanel.heightAnchor.constraint(equalToConstant: 220),
        ])

        refresh()
    }

    private func makeSourcePanel() -> UIView {
        let container = UIView()
        container.backgroundColor = .tertiarySystemBackground

        let label = UILabel()
        label.text = "Markdown Source"
        label.font = .preferredFont(forTextStyle: .caption1).withTraits(.traitBold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        sourceTextView.isEditable = false
        sourceTextView.isSelectable = true
        sourceTextView.backgroundColor = .clear
        sourceTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        sourceTextView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        sourceTextView.accessibilityIdentifier = "SourcePreview"
        sourceTextView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sourceTextView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            sourceTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            sourceTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            sourceTextView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            sourceTextView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
        ])

        return container
    }

    private static let sampleMarkdown = """
    # Hybrid Markdown Editor

    Tap a paragraph or heading to edit raw Markdown source.

    This paragraph has _italic text_, **strong text**, `inline code`, ***bold and italic text*** and [a link](https://example.com).

    > Text that is a quote
    
    Use `git status` to list all new or modified files that haven't yet been committed.
    
    1. ok
      - ok
      2. ok 
    - ok
      - ok 
      3. ok
    4. ok
    
    - Alpha item
    - Beta item
      - Nested beta detail
    - Gamma item

    1. First numbered step
    10. Tenth numbered step
      2. Nested numbered step
    
    

    | Name | Status |
    | --- | --- |
    | Table row | Pending |

    ```swift
    let status = "Preview"
    print(status)
    ```

    ```unknown-language
    this stays editable as plain text fallback
    ```
    """
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

#Preview {
    ContentView()
}
