# Code Block Runestone View Implementation Plan

* Task: 260503T1823-code-block-runestone-view
* Source: [TASK.md](./TASK.md)

## 设计方向

Code block 继续遵守 Markdown source 是唯一真实数据的原则。Runestone 只作为 iOS 上的 code block object view，负责展示、输入、selection、IME 和语法高亮；任何内容或语言修改都必须转换成 `MarkdownEditorController` 的 semantic edit，再由 `MarkdownRewriter` 改写目标 source range。

外层 Markdown editor 不再把 code block 展开成 raw fenced source，也不再用 `[Code object: ...]` 作为主要界面。`MarkdownRenderer` 需要把 code block 渲染为稳定的 attachment/object presentation：outer visible range 是 object placeholder，内部 code selection 和 code content offset 由 Runestone view 自己维护。

## 架构边界

Runestone 集成应隔离在 iOS-only 层。核心 model、parser、renderer、controller、rewriter 保持跨平台可编译；macOS 或其他非 iOS target 使用 fallback，不直接依赖 Runestone package。

建议的职责划分：

- `MarkdownRenderer`：决定 code block 的 object preview / object editing mode，并输出 object presentation metadata。
- `MarkdownHybridEditorView`：管理 object view 生命周期、layout、focus 切换和 scroll 同步。
- `RunestoneCodeBlockView`：承载代码展示与编辑，发出 content / language semantic callbacks。
- `MarkdownEditorController` / `MarkdownRewriter`：继续作为 source edit 的唯一入口。

## Presentation 设计

Code block presentation 需要包含足够的 object metadata：`blockID`、`sourceRange`、`visibleRange`、`language`、`codeContentRange`、display mode 和当前 layout size。outer mapping 只处理 source block 与 placeholder 的映射，不尝试表达 Runestone 内部字符级 selection。

Preview 与 editing 是同一种 object view 的两种状态。切换状态不能修改 Markdown source，也不能把 fenced source 写回 outer text storage。只有用户实际修改 code content 或 language 时才产生 source edit。

## NSTextAttachment 核心逻辑

Code block 在 outer `UITextView` 中应表现为一个 `NSTextAttachment` 占位，而不是普通文本。Attachment 是 TextKit layout token：它提供 placeholder visible range、block identity、当前高度和必要的 object metadata；它不保存 code content 的真实状态，也不直接参与 Markdown source rewrite。

推荐把 attachment 与 view 分离：`NSTextAttachment` 负责让 outer text layout 预留准确矩形；`MarkdownHybridEditorView` 根据 attachment metadata 管理覆盖在对应 rect 上的 `RunestoneCodeBlockView`。这样第一版可以避开 attachment view provider 的平台差异，同时保留未来迁移到 TextKit 2 attachment view provider 的空间。

Attachment bounds 由 code view 的 measured height 驱动。宽度跟随 outer text container 可用宽度，高度来自 code view 内容、header 和 inset。Renderer 生成初始 attachment，后续高度变化通过 attachment update 和 layout invalidation 反映到 outer text layout。

## View 与 Layout 设计

`MarkdownHybridEditorView` 负责按 block ID 复用 code object view，并在 presentation 变化、scroll、layout 和高度变化后同步 frame。object view 删除或 block 消失时必须移除回调和 view 引用，避免大文档多个 code block 时泄漏。

Code view 内部不独立滚动。Runestone 的内容高度应反馈给 outer attachment layout，由外层 editor 承载滚动。高度变化时需要保持 outer scroll position、outer selection 或 Runestone first responder 状态稳定。

## 更新逻辑

Presentation rebuild 后，editor view 对比当前 presentation 中的 code block attachment metadata 与已存在 view registry。已有 block ID 复用 view 并更新 state；新增 block 创建 view；消失的 block 移除 view、断开 callback、释放引用。

内容编辑的更新路径是单向的：Runestone view 发出 semantic edit，controller 改写 Markdown source 并重建 presentation，editor view 再把新的 block state 同步回对应 view。同步过程中需要 reentrancy guard，避免 programmatic state update 被当成用户输入。

高度更新不应该触发 source edit。Runestone view 内容尺寸变化后通知 editor view，editor view 更新对应 attachment bounds，invalidate outer text layout，然后重新定位所有可见 object views。此过程需要保留 scroll offset、outer selection 和 Runestone first responder。

Focus 更新也应与 source edit 解耦。点击 attachment 或 code view 只切换 active scope 到 `.codeBlock(blockID)`，进入 object editing mode；离开 code view 或点击普通 block 只切换 focus / presentation mode。Preview 与 editing 切换本身不修改 Markdown source。

## Source Edit 设计

Code content 修改只替换 `MarkdownCodeBlock.codeContentRange`。Language 修改只更新 opening fence info string。Opening fence、closing fence 和其他 blocks 不应因为 object edit 被重写。

IME marked text 由 Runestone view 承载。composition 未提交期间不触发 outer presentation rebuild；commit 后再发出 semantic edit。

## Example 与验证方向

Example app 用来验证端到端体验：启动后 code block 是 custom object view，激活后仍然是 object view，编辑代码和语言后 source preview 只显示目标 range 变化。

验证重点放在四类风险：

- parser / rewriter range 是否稳定。
- renderer 是否不再输出 `[Code object: ...]` 文本占位。
- object view lifecycle、height relayout、focus 是否稳定。
- iOS simulator 中 Runestone 输入、IME、复制和外层滚动是否符合预期。
