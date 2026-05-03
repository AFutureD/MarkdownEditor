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

        let titleLabel = UILabel()
        titleLabel.text = "Hybrid Markdown"
        titleLabel.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        let toolbar = makeToolbar()
        let sourcePanel = makeSourcePanel()

        editorView.accessibilityIdentifier = "HybridMarkdownEditorContainer"
        editorView.onSourceChange = { [weak self] source in
            self?.sourceTextView.text = source
        }

        rootStack.addArrangedSubview(titleLabel)
        rootStack.addArrangedSubview(toolbar)
        rootStack.addArrangedSubview(editorView)
        rootStack.addArrangedSubview(sourcePanel)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 54),
            toolbar.heightAnchor.constraint(equalToConstant: 68),
            sourcePanel.heightAnchor.constraint(equalToConstant: 220),
        ])

        refresh()
    }

    private func makeToolbar() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let activateListButton = makeButton(title: "Activate\nList", identifier: "ActivateListButton", action: #selector(activateFirstList))
        let updateTableButton = makeButton(title: "Update\nTable", identifier: "UpdateTableButton", action: #selector(updateTable))
        updateTableButton.configuration = .filled()
        updateTableButton.configuration?.title = "Update\nTable"
        let replaceCodeButton = makeButton(title: "Replace\nCode", identifier: "ReplaceCodeButton", action: #selector(replaceCode))
        let previewButton = makeButton(title: "Preview", identifier: "PreviewButton", action: #selector(preview))

        stack.addArrangedSubview(activateListButton)
        stack.addArrangedSubview(updateTableButton)
        stack.addArrangedSubview(replaceCodeButton)
        stack.addArrangedSubview(previewButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        return container
    }

    private func makeButton(title: String, identifier: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        configuration.titleAlignment = .center
        let button = UIButton(configuration: configuration)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
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

    @objc private func activateFirstList() {
        guard let list = controller.firstBlock(kind: .list),
              let scope = list.activeScope else {
            return
        }
        _ = controller.activate(scope: scope, preservingSourceOffset: list.sourceRange.location)
        editorView.applyPresentation(selectedSourceOffset: list.sourceRange.location)
        refresh()
    }

    @objc private func updateTable() {
        guard let table = controller.firstBlock(kind: .table) else {
            return
        }
        controller.updateTableCell(blockID: table.id, row: 1, column: 1, text: "AXe verified")
        refresh()
    }

    @objc private func replaceCode() {
        guard let code = controller.firstBlock(kind: .codeBlock) else {
            return
        }
        controller.replaceCodeContent(blockID: code.id, with: "let status = \"AXe verified\"\nprint(status)\n")
        refresh()
    }

    @objc private func preview() {
        controller.deactivate()
        refresh()
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

