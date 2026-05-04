# Simplify Code Block Object View

* Task: 260504T1731-simplify-code-block-object-view
* Author: Huanan
* Status: DONE
* Type: FEAT
* Related:
  * 260503T1823-code-block-runestone-view

## 目标结果

整理 `CodeBlockObjectView` 的职责边界，使它成为更薄的 code block object view：只负责展示当前 code block 状态、承载 Runestone 编辑器交互，并向外发出用户意图。

Markdown source 仍然是唯一真实数据。Code block 的内容、语言和编辑模式由外层 presentation/coordinator 驱动；view 不保存 Markdown 语义状态，也不承担 source rewrite。Runestone 相关依赖和实现细节收敛在 `CodeBlockObjectView` 内部，不向外层 editor、presentation、coordinator 或绑定对象扩散。

## 期望能力

- `CodeBlockObjectView` 的绑定输入只表达 code block 的展示和编辑数据，不暴露 Runestone-specific syntax 概念或 Runestone 类型。
- Code block language 在绑定层保持 Markdown 原始语言文本；别名解析、Tree-sitter language 选择和 plain text fallback 属于 `CodeBlockObjectView` 的私有实现。
- Runestone language 准备和缓存策略收敛在 `CodeBlockObjectView` 文件和类型内部，不由外层 editor/view model 管理 Runestone 依赖。
- Runestone language 实例可以在 `CodeBlockObjectView` 内部复用，避免 computed language factory 和 `prepare()` 被重复使用成隐性开销。
- 预览和编辑模式切换不修改 Markdown source；只有用户修改 code content 或 language 时才发出 semantic edit。
- View 内部状态只用于避免重复 `setState`、保留 selection/caret 和区分 programmatic update 与用户输入。
- 未知或不支持的 language 继续稳定显示为 plain text，不影响复制、编辑和 source 回写。

## 验收标准

- `CodeBlockObjectView` 对外不暴露 language normalization、Runestone syntax 或 Runestone language preparation 全局策略。
- 编辑/展示绑定对象不包含 Runestone syntax、Tree-sitter language 或 normalized language 字段。
- Runestone 适配逻辑集中在 `CodeBlockObjectView` 的私有边界内，支持缓存和按需创建。
- 当前 code block preview、activation、editing、copy、language edit 和 content edit 行为不回退。
- 现有 source rewrite 语义保持不变：content edit 只替换 code content range，language edit 只更新 opening fence info string。
- iOS build 保持 Runestone 集成可用；非 iOS build 不引入新的 Runestone 依赖边界问题。

## 非目标

- 不扩展新的 Tree-sitter language 支持范围。
- 不改变 Markdown parser、rewriter 或 source mapping 的语义。
- 不迁移到 TextKit attachment view provider。
- 不把 Runestone 用作整个 Markdown editor 的外层编辑器。

## 参考资料

- [Implementation Plan](./IMPLEMENT_PLAN.md)
- [Code Block Runestone View](../260503T1823-code-block-runestone-view/TASK.md)
- [Runestone GitHub](https://github.com/simonbs/Runestone)
