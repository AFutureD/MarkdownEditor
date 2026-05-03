# Code Block Runestone View

* Task: 260503T1823-code-block-runestone-view
* Author: Huanan
* Status: DONE
* Type: FEAT
* Related:
  * 260503T0008-textkit2-markdown-hybrid-editor

## 目标结果

交付 Code Block object view 支持：Markdown code block 在预览状态和编辑状态都通过自定义 view 呈现，不再使用普通占位文本或 raw fenced source 作为主要交互界面。

自定义 view 使用 Runestone 作为 iOS 代码编辑核心，提供代码文本展示、编辑、语法高亮、滚动和代码编辑器基础能力。Markdown source 仍然是唯一真实数据；Runestone view 只承载 code block 的可见状态和编辑交互，任何修改都必须通过 `MarkdownEditorController` 和 `MarkdownRewriter` 回写到 code block 的 source range。

## 期望能力

- `MarkdownRenderer` 可以把 `codeBlock` 渲染成 TextKit attachment/object presentation，并保持稳定的 source-to-visible 与 visible-to-source mapping。
- `MarkdownHybridEditorView` 可以管理 code block attachment view 的创建、移除、布局和刷新，使其跟随 `UITextView` 的 TextKit 布局和滚动。
- Code block preview mode 使用自定义 Runestone-backed view 展示代码内容，支持语言显示、语法高亮、自动换行、不可内部滚动和复制代码。
- Code block editing mode 使用同一套自定义 Runestone-backed view 进行编辑，支持更新代码内容和语言信息。
- Code block view 的内容修改通过 semantic edit 发给 `MarkdownEditorController.replaceCodeContent(blockID:with:)`，语言修改通过 `MarkdownEditorController.updateCodeLanguage(blockID:language:)`，不直接修改 outer `UITextView.textStorage`。
- Code block view 的高度随内容变化更新，并触发 outer TextKit attachment relayout，不破坏滚动位置和当前 selection/focus。
- Preview 与 editing 切换不会改变 Markdown source；只有用户实际修改代码内容或语言时才产生 source edit。
- iOS 目标集成 Runestone Swift Package；由于 Runestone 当前是 iOS-oriented package，macOS 目标必须通过条件编译、平台隔离或明确 fallback 保持 package build 不被破坏。

## 验收标准

- 包含 fenced code block 的 Markdown 文档在非激活状态下显示为自定义 code block view，而不是 `[Code object: ...]` 文本占位。
- 激活 code block 后仍然显示自定义 code block view，并进入可编辑状态；outer editor 不把该 block 切换成 raw fenced Markdown source。
- 在 code view 中修改代码内容后，`MarkdownDocument.source` 只替换目标 `codeContentRange`，opening fence、closing fence 和其他 block 内容保持不变。
- 修改 code language 后，只更新 opening fence info string，不重写无关 code content。
- Code view 内容增长或减少后，attachment 占位高度与实际 view 高度一致，后续 blocks 不重叠、不跳位。
- Code block view 内部不可滚动；内容通过自动换行和 attachment 高度增长完整呈现，滚动只发生在外层 editor。
- Selection/focus 可以在 outer editor 和 code block view 之间稳定切换；普通 paragraph/list/heading 的编辑行为不回退。
- IME marked text 在 code view 内由 Runestone 承载，不触发 outer presentation 的错误 rebuild。
- 大文档中包含多个 code blocks 时，滚动和刷新只管理当前可见或仍存在的 attachment views，不泄漏已删除 block 的 view。
- 测试覆盖 parser range、code object rendering、attachment mapping、code content rewriting、language rewriting、preview/editing mode、height relayout 和 source preservation。

## 非目标

- 不把 Runestone 作为整个 Markdown editor 的外层 text editor。
- 不让 Runestone view 保存 Markdown 文档真相。
- 不在第一版要求完整支持所有 Tree-sitter language grammar；语言支持可以先覆盖常见 code block language，并对未知语言提供 plain text fallback。
- 不实现 table object view；table 继续由单独任务处理。

## 参考资料

- [Implementation Plan](./IMPLEMENT_PLAN.md)
- [TextKit 2 Markdown Hybrid Editor](../260503T0008-textkit2-markdown-hybrid-editor/TASK.md)
- [Runestone GitHub](https://github.com/simonbs/Runestone)
- [Runestone Documentation](https://docs.runestone.app)
