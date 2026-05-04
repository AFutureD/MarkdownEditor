# Responder Driven Code Block Focus

* Task: 260504T2156-responder-driven-code-block-focus
* Author: Huanan
* Status: DONE
* Type: BUG
* Related:
  * 260503T1823-code-block-runestone-view
  * 260504T1731-simplify-code-block-object-view

## 目标结果

用 UIKit first responder 关系驱动 outer Markdown editor 与 code block object editor 之间的焦点切换，替代 `syncOuterTextViewCaretVisibility()` 通过修改 outer `UITextView.tintColor` 隐藏 caret 的方案。

当 code block 内部编辑器主动进入 first responder 时，outer `UITextView` 应自然退出 first responder；系统负责隐藏 outer caret。Markdown editor 不再通过 active code block scope 推导 caret 是否应该透明，也不再把外层 tint color 当作焦点状态同步机制。

## 背景

当前 `MarkdownHybridEditorView` 在 active code block 且 outer selection 位于 code block object 范围内时，会把 outer `UITextView.tintColor` 改为 `.clear`，用于隐藏外层 caret。这让视觉状态和焦点状态分离：即使 outer text view 仍可能保留 responder/selection 状态，caret 也会被颜色逻辑强行隐藏。

更合适的模型是让真正可编辑的子视图成为 first responder。UIKit 在同一 window 中只维护一个 first responder，因此 code block 内部 Runestone editor 成功 `becomeFirstResponder()` 后，outer `UITextView` 会退出 first responder，outer caret 由系统隐藏。

## 期望能力

- 点击或激活 code block 后，code block 内部 Runestone editor 成为 first responder，outer `UITextView` 不再保持 first responder。
- Outer editor 不再依赖 `syncOuterTextViewCaretVisibility()` 或 `tintColor = .clear` 来隐藏 caret。
- Focus 从 outer editor 转移到 code block editor 时，active scope 仍保持 `.codeBlock(blockID)`，不会因为 outer `textViewDidEndEditing` 被错误 `deactivate()`。
- Focus 转回 outer editor 后，普通 paragraph、heading、list、trailing code block insertion 等外层编辑行为保持不变。
- Code block content edit、language edit、copy 和 preview/editing mode 切换行为不回退。
- 如果 code block editor 未能成功成为 first responder，outer editor 不应进入一个 caret 被隐藏但焦点未转移的中间状态。

## 验收标准

- 删除 `syncOuterTextViewCaretVisibility()` 及其调用后，code block 编辑时不会显示 outer text view 的 caret。
- `MarkdownHybridEditorView` 不再通过修改 `UITextView.tintColor` 控制 caret 可见性。
- `CodeBlockObjectView.becomeFirstResponder()` 能把 first responder 请求转发给内部 editor，并表达是否成功。
- `textViewDidEndEditing(_:)` 只在非 code block active scope 下 deactivate；code block active scope 下的 outer resign 视为正常焦点转移。
- 激活 code block 后，coordinator presentation 保持 object editing mode，outer editor 不切换为 raw fenced source。
- 现有 Markdown source rewrite 语义保持不变：code content edit 只更新 code content range，language edit 只更新 opening fence info string。
- iOS build 和现有 unit tests 通过。

## 非目标

- 不改变 Markdown parser、renderer、rewriter 或 source mapping 的语义。
- 不替换 Runestone，也不把 Runestone 用作整个 Markdown editor 的外层编辑器。
- 不引入新的 caret 绘制或自定义 selection 绘制机制。
- 不扩展 code block object view 的语言支持范围。

## 参考资料

- [Implementation Plan](./IMPLEMENT_PLAN.md)
- [Code Block Runestone View](../260503T1823-code-block-runestone-view/TASK.md)
- [Simplify Code Block Object View](../260504T1731-simplify-code-block-object-view/TASK.md)
- [MarkdownHybridEditor.swift](/Sources/MarkdownEditor/MarkdownHybridEditor.swift)
- [CodeBlockObjectView.swift](/Sources/MarkdownEditor/CodeBlockObjectView.swift)
