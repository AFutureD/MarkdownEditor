# TextKit 2 Markdown Hybrid Editor

* Task: 260503T0008-textkit2-markdown-hybrid-editor
* Author: Huanan
* Status: DRAFT
* Type: FEAT

## 目标结果

交付一个基于 TextKit 2 的 Markdown 混合编辑器：普通 Markdown block 在非编辑状态下显示为 WYSIWYG preview，在激活编辑时显示原始 Markdown source；table、code block 等复杂 block 则以可交互对象视图呈现和编辑。

Markdown source 必须是文档的唯一真实数据。TextKit 2 负责 visible presentation、layout、selection 表现和交互承载，但不保存最终 Markdown 语义。所有用户编辑，包括 table/code 等对象编辑，最终都必须转换为 source edit，并同步回可见 presentation。

## 期望能力

- 编辑器可以把 Markdown source 解析成稳定的 block model，包含 source range、visible range、block ID、display mode 以及 inline/object metadata。
- 编辑器可以把 block model 渲染成 TextKit 2 mixed visible content，包括 preview 文本、active raw Markdown source、attachment/object block。
- paragraph、heading、list、blockquote 等普通 block 默认显示 preview，激活后显示 raw Markdown source 并支持 syntax highlighting；其中 list 的 active scope 是上下连续关联的整个 list group，而不是单个 list item 行。
- preview/sourceEditing 切换时，即使 visible string 长度变化，也能恢复到同一语义位置的 selection。
- 普通文本输入、删除、block split、block merge 都先更新 Markdown source，再刷新受影响的 presentation。
- Table block 通过 table object view 编辑，并以稳定的 canonical table serialization 回写 Markdown source。
- Code block 通过 code object view 编辑，可以更新代码内容、语言信息、syntax highlighting、selection 和高度，且不重写无关 source。
- Undo/redo 以 source edit 和 semantic selection snapshot 为核心，而不是以 `NSTextStorage` mutation 为真实记录。
- IME marked text 期间不会中断输入法组合，不会切换 block mode，也不会在 commit 前触发大范围 presentation rebuild。
- 编辑器在大文档、频繁 block/list group 切换、outer text focus、active source block/list group、table focus 和 code focus 之间保持稳定。

## 验收标准

- 打开 Markdown 文档后，可以生成与 source 一致的 mixed TextKit presentation，并且可确定性地重建。
- Preview rendering 能按需隐藏 Markdown token，同时保留语义内容的 source-to-visible 与 visible-to-source mapping。
- Source editing mode 能显示 active block 的原始 Markdown，并提供接近 identity 的 block-local mapping；list editing mode 能显示整个 active list group 的原始 Markdown，并提供 list-group-local mapping。
- Block/list group activation、deactivation、scope-to-scope switching 不修改 Markdown source，也不生成 undo item。
- 普通 block、table block、code block 的编辑只更新目标 source range，不改变无关 block 内容。
- Presentation patch、attachment size 变化、undo、redo 后，selection 和 focus 可以正确恢复。
- Table/code object editor 不持有私有文档真相；semantic edit 应用后，它们从 document model 刷新状态。
- 测试覆盖 parser ranges、preview rendering、source editing rendering、block mode switching、text edits、deletion、block operations、table rewriting、code rewriting、object focus、undo/redo、IME behavior 和 mapping invariants。

## 非目标

- 第一版不做全 WYSIWYG 隐藏 Markdown token 的直接编辑模型。
- 第一版不承诺完整 CommonMark formatting trivia preservation。
- 除非后续性能或架构验证确实需要，否则不引入完全自定义 `NSTextContentManager`。
- 第一版 table editing 接受 canonical serialization，不保留任意用户表格对齐和空格格式。

## 参考资料

- [设计计划](./references/design.md)
