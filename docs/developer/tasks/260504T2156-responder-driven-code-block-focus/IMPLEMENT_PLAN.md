# Responder Driven Code Block Focus Implementation Plan

* Task: 260504T2156-responder-driven-code-block-focus
* Source: [TASK.md](./TASK.md)

## 设计方向

这次调整的核心是把 caret 可见性重新交给 UIKit responder system，而不是由 Markdown presentation state 间接控制。`activeScope` 继续表达 Markdown block 当前处于 preview 还是 editing presentation；first responder 只表达当前真正接收输入、显示 caret 和承载 selection interaction 的 view。

Code block 激活后，outer editor 负责切换 `.codeBlock(blockID)` presentation，并把焦点交给 code block 内部 Runestone editor。Runestone editor 成功成为 first responder 后，outer `UITextView` 由系统退出 first responder，outer caret 自然消失。

## 焦点边界

`MarkdownHybridEditorView` 仍是 outer editor 与 code block object view 之间的焦点协调者。它决定何时激活 code block、何时加载 object view、何时请求 code block object view 获取 first responder，以及如何在 outer `textViewDidEndEditing(_:)` 中用当前 active scope 区分普通失焦和 code block 焦点转移。

`CodeBlockObjectView` 通过 `becomeFirstResponder()` 把 responder 请求转发给内部 Runestone editor，不把 Runestone responder 细节泄漏给 coordinator 或 renderer。这个 API 需要能表达请求是否成功，避免外层进入“presentation 已切到 code block editing，但实际 first responder 没有转移”的不明确状态。

## State 与 Responder 分离

Presentation state 和 responder state 应保持分离：

- `activeScope == .codeBlock(blockID)` 表示 code block 使用 object editing presentation。
- Runestone editor 是 first responder 表示输入、caret 和 selection interaction 发生在 code block 内部。
- Outer `UITextView.selectedRange` 可以继续作为 source/visible mapping 的锚点，但不再用于决定 caret 是否隐藏。

这个设计允许 outer selection 保持在 object placeholder 附近，用于 presentation rebuild 和 source offset preservation；视觉 caret 则完全由当前 first responder 所属 view 决定。

## 去除颜色同步

`syncOuterTextViewCaretVisibility()` 和对 `UITextView.tintColor` 的 caret 控制应被移除。`applyPresentation`、selection change 和 code block activation 不再同步 outer tint color。

Outer `UITextView` 的 tint color 回到普通 UIKit 行为：当它是 first responder 时显示自己的 caret；当 code block 内部 editor 是 first responder 时，由系统隐藏 outer caret。

## 交互流向

激活 code block 的主路径保持单向：用户点击 code block object view，outer editor 切换 active scope 并重建 presentation，object view 进入 editing 状态，然后内部 editor 请求 first responder。Preview/editing 切换本身不修改 Markdown source。

Code content 和 language 修改继续通过现有 semantic callback 进入 coordinator，再由 rewriter 更新 source。焦点切换不参与 source rewrite，也不直接修改 outer text storage。

## 回退与恢复

如果内部 editor 获取 first responder 失败，outer editor 应保留清晰状态，不通过隐藏 tint color 掩盖失败。后续点击普通 Markdown 文本时，outer `UITextView` 按 UIKit 默认行为重新成为 first responder，并通过现有 selection activation 进入对应 block editing presentation。

普通失焦仍可以触发 coordinator deactivate；但当当前 active scope 已经是 code block 时，outer `textViewDidEndEditing(_:)` 不再 deactivate，因为这代表焦点正在交给 object editor 内部 responder，而不是离开当前编辑对象。

## 验证方向

验证重点放在 responder 行为和现有编辑语义不回退：code block 激活后只有内部 editor 显示 caret，outer editor 不再改 tint color；普通文本编辑、code content edit、language edit、trailing code block insertion 和 presentation rebuild 后的 focus/selection preservation 保持稳定。
