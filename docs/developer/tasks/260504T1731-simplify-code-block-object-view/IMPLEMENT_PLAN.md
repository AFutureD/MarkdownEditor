# Simplify Code Block Object View Implementation Plan

* Task: 260504T1731-simplify-code-block-object-view
* Source: [TASK.md](./TASK.md)

## 设计方向

这次整理的核心不是改变 code block object view 的用户行为，而是收窄状态和职责边界。`CodeBlockObjectView` 应该接收一个简单的展示/编辑状态，更新 UI，并把用户动作转换成回调；Markdown 语义和 source rewrite 留在 view 外部，Runestone 依赖和语言管理收敛在 `CodeBlockObjectView` 内部。

Code block language 在 Markdown 层保持原始文本透传。系统不在绑定对象里传递 normalized language，也不把 Runestone syntax 当作 code block 状态的一部分。语言别名、Tree-sitter grammar 选择和 plain text fallback 是 `CodeBlockObjectView` 私有 Runestone 适配实现。

## 状态边界

编辑/展示绑定对象只描述 UI 需要稳定展示和编辑的数据：block identity、display mode、language text、display language 和 code content。它不包含 syntax、Tree-sitter language、normalized language 或 source range rewrite 细节。

View 内部可以保留少量运行态缓存，用于判断是否需要重建 Runestone state、避免 programmatic update 触发用户编辑回调，并尽量保持 selection/caret 稳定。这些缓存不应成为外部数据契约。

## Runestone 依赖边界

Runestone 相关 import、类型、provider/registry、language switch、Tree-sitter language 实例缓存和 `TextViewState` 创建都集中在 `CodeBlockObjectView.swift` 和 `CodeBlockObjectView` 的实现边界内。外层 editor 不直接引用 Runestone、Tree-sitter language、Runestone syntax enum 或 editor state 类型。

`CodeBlockObjectView` 对外只暴露 UIKit view 能力和 plain Swift 数据回调。它内部可以包含 private nested provider/registry，用于把 Markdown language text 映射为 Runestone state，并把 Runestone 文本变化转换成 semantic intent 发给外层。

## Language 准备策略

Runestone language 准备由 `CodeBlockObjectView` 内部调度。不再在每个 view 初始化时全量预加载所有支持语言；当前 state 需要创建 Runestone editor state 时按需准备并缓存对应 language，未使用的 language 不提前准备。

Language 准备复用 `CodeBlockObjectView` 内部 cached Tree-sitter language 实例。未知语言不参与准备，直接走 plain text fallback，不阻塞 code block 展示和编辑路径。

## 更新流向

数据流保持单向：presentation 生成 code block object state，view 渲染 state；用户修改 code content 或 language 后，view 发出 semantic callback；coordinator 改写 source 并重建 presentation；view 再接收新的 state。

Preview/editing 切换只改变 active scope 和 presentation mode，不产生 source edit。content edit 和 language edit 继续通过现有 coordinator/rewriter 路径完成。

## View 简化方向

`CodeBlockObjectView` 保持 UIKit/Runestone 承载职责：header、language control、copy action、Runestone editor、focus、editable 状态，以及私有 Runestone 语言适配。可删除或下沉的逻辑应从 view 对外接口中移除，包括对外暴露的 language preload、normalized language、source replacement 语义和多余的交互桥接状态。

内部交互可以优先用更直接的 UIKit 命中和 editable/userInteraction 状态表达，减少额外 overlay 或手写 hit-test 逻辑，前提是 preview activation、accessibility 和 Runestone 编辑体验不回退。

## 验证方向

验证重点放在行为不回退和边界变清楚：preview/editing 切换、代码内容编辑、language 编辑、未知 language fallback、Runestone state 重建时的 caret 稳定、多个 code block 下的 language cache，以及 iOS/non-iOS build 边界。
