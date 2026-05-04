#if os(iOS)
import UIKit

import Runestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterPythonRunestone
import TreeSitterSwiftRunestone

struct CodeBlockObjectState: Equatable {
    let blockID: String
    let mode: MarkdownDisplayMode
    let language: String
    let displayLanguage: String
    let codeContent: String
}

@MainActor
final class CodeBlockObjectView: UIControl, UITextFieldDelegate {
    var onActivate: ((String) -> Void)?
    var onContentChange: ((String, String) -> Void)?
    var onLanguageChange: ((String, String) -> Void)?

    private let headerView = UIView()
    private let languageField = UITextField()
    private let copyButton = UIButton(type: .system)
    private let codeView = TextView(frame: .zero)
    private let theme = DefaultTheme()
    private var objectState: CodeBlockObjectState?
    private var appliedEditorValue: EditorValue?
    private var isUpdatingState = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ state: CodeBlockObjectState) {
        objectState = state
        isUpdatingState = true

        languageField.text = state.language
        languageField.placeholder = state.displayLanguage
        languageField.accessibilityIdentifier = "CodeLanguageControl-\(state.blockID)"
        copyButton.accessibilityIdentifier = "CodeCopyButton-\(state.blockID)"
        codeView.accessibilityIdentifier = "CodeBlockEditor-\(state.blockID)"

        let isEditing = state.mode == .objectEditing
        codeView.isEditable = isEditing
        codeView.isUserInteractionEnabled = isEditing
        setActiveAppearance(isEditing)

        let editorValue = EditorValue(text: state.codeContent, language: state.language)
        if codeView.text != state.codeContent || appliedEditorValue != editorValue {
            // Programmatic state application can synchronously trigger delegate plumbing.
            // Keep this guarded so only real user edits flow back to the coordinator.
            codeView.setState(Self.runestoneStateStore.makeState(
                text: state.codeContent,
                language: state.language,
                theme: theme
            ))
            appliedEditorValue = editorValue
        }

        isUpdatingState = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight: CGFloat = 36
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)

        let horizontalInset: CGFloat = 10
        let buttonWidth: CGFloat = 64
        copyButton.frame = CGRect(
            x: bounds.width - horizontalInset - buttonWidth,
            y: 5,
            width: buttonWidth,
            height: 26
        )
        languageField.frame = CGRect(
            x: horizontalInset,
            y: 5,
            width: max(44, copyButton.frame.minX - horizontalInset * 2),
            height: 26
        )
        codeView.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )
    }

    func focusEditor() {
        _ = codeView.becomeFirstResponder()
    }

    @objc private func activate() {
        guard let state = objectState, state.mode != .objectEditing else { return }
        onActivate?(state.blockID)
    }

    @objc private func copyCode() {
        UIPasteboard.general.string = objectState?.codeContent ?? codeView.text
    }

    @objc private func languageEditingDidEnd() {
        guard let state = objectState else { return }
        let language = (languageField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard language != state.language else { return }
        onLanguageChange?(state.blockID, language)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func configure() {
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        layer.cornerRadius = 8
        layer.borderWidth = 1
        setActiveAppearance(false)
        addTarget(self, action: #selector(activate), for: .touchUpInside)

        headerView.backgroundColor = .tertiarySystemBackground
        addSubview(headerView)

        languageField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        languageField.textColor = .secondaryLabel
        languageField.borderStyle = .none
        languageField.autocorrectionType = .no
        languageField.autocapitalizationType = .none
        languageField.returnKeyType = .done
        languageField.delegate = self
        languageField.addTarget(self, action: #selector(languageEditingDidEnd), for: .editingDidEnd)
        languageField.addTarget(self, action: #selector(languageEditingDidEnd), for: .primaryActionTriggered)
        headerView.addSubview(languageField)

        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        headerView.addSubview(copyButton)

        codeView.editorDelegate = self
        codeView.theme = theme
        codeView.backgroundColor = .clear
        codeView.isScrollEnabled = false
        codeView.alwaysBounceVertical = false
        codeView.alwaysBounceHorizontal = false
        codeView.showsVerticalScrollIndicator = false
        codeView.showsHorizontalScrollIndicator = false
        codeView.isLineWrappingEnabled = true
        codeView.showLineNumbers = false
        codeView.lineHeightMultiplier = 1.15
        codeView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 6, right: 10)
        codeView.autocorrectionType = .no
        codeView.autocapitalizationType = .none
        codeView.smartDashesType = .no
        codeView.smartQuotesType = .no
        codeView.spellCheckingType = .no
        codeView.isEditable = false
        codeView.isSelectable = true
        codeView.isUserInteractionEnabled = false
        addSubview(codeView)
    }

    private func setActiveAppearance(_ isActive: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.borderColor = isActive ? UIColor.systemBlue.cgColor : UIColor.separator.cgColor
        CATransaction.commit()
    }

    private struct EditorValue: Equatable {
        let text: String
        let language: String
    }

    private static let runestoneStateStore = RunestoneStateStore()

    private final class RunestoneStateStore {
        private enum Syntax: Hashable, Sendable {
            case swift
            case javaScript
            case json
            case python

            init?(_ language: String) {
                switch language.lowercased() {
                case "swift":
                    self = .swift
                case "javascript", "js":
                    self = .javaScript
                case "json":
                    self = .json
                case "python", "py":
                    self = .python
                default:
                    return nil
                }
            }

            var treeSitterLanguage: TreeSitterLanguage {
                switch self {
                case .swift:
                    TreeSitterLanguage.swift
                case .javaScript:
                    TreeSitterLanguage.javaScript
                case .json:
                    TreeSitterLanguage.json
                case .python:
                    TreeSitterLanguage.python
                }
            }
        }

        private var languages: [Syntax: TreeSitterLanguage] = [:]
        private var preparedSyntaxes = Set<Syntax>()

        func makeState(text: String, language: String, theme: Theme) -> TextViewState {
            guard let syntax = Syntax(language) else {
                return TextViewState(text: text, theme: theme)
            }
            return TextViewState(text: text, theme: theme, language: preparedLanguage(for: syntax))
        }

        private func preparedLanguage(for syntax: Syntax) -> TreeSitterLanguage {
            let language: TreeSitterLanguage
            if let cachedLanguage = languages[syntax] {
                language = cachedLanguage
            } else {
                language = syntax.treeSitterLanguage
                languages[syntax] = language
            }

            if !preparedSyntaxes.contains(syntax) {
                // TreeSitterLanguage helpers are factories. Cache and prepare once
                // so parser/query setup is not repeated for every code block view.
                language.prepare()
                preparedSyntaxes.insert(syntax)
            }
            return language
        }
    }
}

extension CodeBlockObjectView: @preconcurrency TextViewDelegate {
    func textViewShouldBeginEditing(_ textView: TextView) -> Bool {
        guard let state = objectState else { return false }
        guard state.mode != .objectEditing else { return true }
        activate()
        return false
    }

    func textViewDidChange(_ textView: TextView) {
        guard !isUpdatingState,
              textView.markedTextRange == nil,
              let state = objectState else {
            return
        }
        onContentChange?(state.blockID, textView.text)
    }
}
#endif
