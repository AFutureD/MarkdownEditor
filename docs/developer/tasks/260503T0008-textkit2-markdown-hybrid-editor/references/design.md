下面是一份面向 TextKit 2 + Markdown Live Preview / WYSIWYG Hybrid Editor 的开发计划。重点放在设计思路、数据流、架构、编辑模型和测试策略，不包含具体代码实现。

⸻

Markdown Hybrid Editor 开发计划

1. 产品目标

目标是实现一个基于 TextKit 2 的 Markdown 编辑器，采用 混合编辑模型：

普通 Markdown block：
    非编辑状态 → WYSIWYG preview
    正在编辑 → 显示原始 Markdown source
复杂 block：
    table → 可交互表格对象
    code block → 可交互代码编辑对象
    未来可扩展 math / diagram / embed 等对象

核心目标：

Markdown source 是唯一真实文档数据
TextKit 2 只负责显示、布局和交互承载
用户看到的是 mixed presentation
所有编辑最终都回写 Markdown source

⸻

2. 编辑器整体架构

推荐架构分为五层：

┌──────────────────────────────┐
│ UI / TextKit Layer            │
│ NSTextView / NSTextStorage    │
│ NSTextContentStorage          │
│ NSTextLayoutManager           │
└───────────────┬──────────────┘
                │
┌───────────────▼──────────────┐
│ Presentation Layer            │
│ BlockPresentationEngine       │
│ mixed visible representation  │
└───────────────┬──────────────┘
                │
┌───────────────▼──────────────┐
│ Editor Coordination Layer      │
│ MarkdownEditorController      │
│ selection / focus / undo       │
└───────────────┬──────────────┘
                │
┌───────────────▼──────────────┐
│ Document Model Layer           │
│ MarkdownDocument               │
│ source / blocks / mappings     │
└───────────────┬──────────────┘
                │
┌───────────────▼──────────────┐
│ Markdown Processing Layer      │
│ parser / renderer / rewriter   │
└──────────────────────────────┘

2.1 UI / TextKit Layer

职责：

负责文本显示、布局、selection 表现、viewport 渲染
承载普通文本 block 和复杂 block attachment
不保存真实 Markdown 语义

组成：

NSTextView / UITextView
NSTextStorage
NSTextContentStorage
NSTextLayoutManager
NSTextContainer
NSTextAttachment / attachment view provider

重要原则：

NSTextStorage 保存的是 mixed visible content
不是完整 Markdown source
不是最终文档真相

⸻

2.2 Presentation Layer

职责：

把 Markdown block 转成 TextKit 可显示内容
决定每个 block 当前显示模式
维护 source range 与 visible range 映射
生成 TextStorage patch

每个 block 的显示模式：

preview：
    普通渲染模式，隐藏 Markdown token
sourceEditing：
    显示原始 Markdown source，并做 syntax highlighting
objectPreview / objectEditing：
    用 attachment 或 embedded view 表示复杂 block

典型策略：

Block 类型	非编辑状态	编辑状态
paragraph	preview	raw Markdown source
heading	preview	raw Markdown source
list	preview	raw Markdown source（整个连续关联 list group）
blockquote	preview	raw Markdown source
table	editable table object	editable table object
code block	highlighted code object	code editor object
math / diagram	rendered object	object editor

⸻

2.3 Editor Coordination Layer

核心对象：MarkdownEditorController

职责：

接收用户编辑事件
判断编辑意图
管理 active block / active list group
管理 object focus
协调 source edit
协调 parse / render / patch
维护 selection
维护 undo / redo
处理 IME marked text

它是编辑器的大脑。

不要把 Markdown 编辑逻辑放进：

NSTextStorage
NSTextContentStorage
NSTextLayoutManager

这些 TextKit 对象应该尽量保持“显示层”和“布局层”的职责。

⸻

2.4 Document Model Layer

核心对象：MarkdownDocument

职责：

保存 Markdown source
保存 block model
保存 source range / visible range
保存 range mapping
保存当前 revision
保存 active block / active list group 状态

概念结构：

MarkdownDocument
    source
    blocks
    activeBlockID / activeListGroupID
    presentations
    sourceToVisible map
    visibleToSource map
    revision

每个 block 至少需要：

blockID
block kind
sourceRange
visibleRange
displayMode
inline nodes
block-specific metadata
range mapping

⸻

2.5 Markdown Processing Layer

包含三个关键模块：

MarkdownParser
MarkdownRenderer
MarkdownRewriter

Parser

职责：

Markdown source → block model / AST

支持：

全量 parse
局部 parse
按 block boundary parse
受影响区域扩大 parse

Renderer

职责：

block model → visible attributed content
block model → preview presentation
block model → source editing presentation
block model → object attachment presentation

Rewriter

职责：

把用户编辑意图转换成 Markdown source edit

例如：

toggle bold
insert text
delete range
split block
merge block
update table cell
insert table row
replace code block content
change code language

⸻

3. 核心数据流设计

3.1 初始加载数据流

Markdown source
    ↓
MarkdownParser
    ↓
Markdown blocks / AST
    ↓
BlockPresentationEngine
    ↓
mixed visible attributed string
    ↓
NSTextStorage
    ↓
NSTextContentStorage
    ↓
NSTextLayoutManager
    ↓
NSTextView

初始状态下：

普通 block 默认 preview
table/code 默认 object presentation
activeBlockID / activeListGroupID 为空

⸻

3.2 普通 block 激活流程

用户点击一个普通 paragraph / heading / blockquote block，或点击一个 list item。

1. TextKit 返回点击位置 visible location
2. 根据 visible location 找到 block，并判断 active editing scope
3. 把当前 selection 解析成 semantic position
4. 将该 block 或 list group 切换为 sourceEditing
5. 重新生成该 active scope 的 visible presentation
6. patch NSTextStorage
7. 更新所有 block visibleRange
8. 将 semantic position 映射到新的 visible selection
9. 设置 activeBlockID 或 activeListGroupID

List 的特殊规则：

用户点击任意 list item 时，active scope 不是单个 list item 行，而是上下连续关联的整个 list group。该 group 包含同一列表结构内相邻的 list items 及其嵌套子列表，边界由空行、非 list block、不同父级容器或 Markdown 解析后的 list block boundary 决定。

结果：

点击前：
    - A
    - B
    - C

点击 B 后：
    整个 `- A` / `- B` / `- C` list group 都显示为 raw Markdown source，而不是只把 `- B` 一行切换为 sourceEditing。

结果：

点击前：
    # Title → 显示为 Title
点击后：
    Title → 显示为 # Title

这个切换会改变 visible string 长度，因此必须通过 mapping 恢复 selection，不能简单沿用旧 offset。

⸻

3.3 普通 block 输入流程

当用户在 active source block 或 active list group 中输入文字：

1. 捕获 visible edit
2. 确认 edit 位于 active block / active list group
3. visible range 映射到 source range
4. 生成 source edit
5. 更新 Markdown source
6. 更新 undo item
7. 局部 parse active block / active list group
8. 重新生成 active scope source presentation
9. patch NSTextStorage
10. 更新 block range 和 mapping
11. 恢复 selection

active block / active list group 中 source 与 visible 基本一致，因此 mapping 相对简单：

source offset inside block ≈ visible offset inside block
source offset inside list group ≈ visible offset inside list group

这也是 active-block source editing 模型的核心优势。

⸻

3.4 普通 block 退出流程

用户点击其他 block、方向键离开当前 block、编辑器失焦时：

1. 确认当前 active block / active list group
2. 对 active scope 或附近 block 做 parse
3. 判断 block 类型是否变化
4. 将 active scope 切换为 preview
5. 生成新的 block presentation
6. patch NSTextStorage
7. 更新 mappings
8. 清理 activeBlockID / activeListGroupID 或切换到新 active scope
9. 恢复 selection

例如：

# Title

如果用户删除了 #：

Title

离开 block 后，它应该从 heading preview 变成 paragraph preview。

⸻

3.5 Block 切换流程

当用户从 active scope A 点击到 active scope B：

1. 捕获当前 selection / target position
2. scope A 从 sourceEditing → preview
3. scope B 从 preview → sourceEditing
4. 合并生成一个 presentation transition patch
5. 一次性 patch NSTextStorage
6. 更新所有 downstream visibleRange
7. 恢复 selection 到 scope B 中的正确位置
8. 更新 activeBlockID / activeListGroupID

重要原则：

尽量避免先 patch A、再 patch B。
最好把 block transition 合并成一个 transaction，减少 selection 抖动和 layout 抖动。

⸻

4. Table / Code Object 编辑设计

4.1 复杂 block 的原则

对于 table、code block 等复杂结构，不建议强制显示 raw Markdown。

推荐：

table:
    始终以 table object 显示和编辑
code block:
    始终以 code editor object 显示和编辑
Markdown source:
    仍然是最终真相

它们的数据流是：

Object editor
    ↓ emits semantic block edit
MarkdownEditorController
    ↓
MarkdownRewriter
    ↓
source edit
    ↓
MarkdownDocument.source
    ↓
parse affected block
    ↓
update block model
    ↓
refresh object view / attachment size

⸻

4.2 Table 编辑流

Markdown table source：

| Name | Age |
| --- | --- |
| Ana | 20 |

解析为：

TableBlock
    columns
    rows
    cells
    alignment
    sourceRange

显示为：

editable table grid

用户修改一个 cell：

1. TableEditorView 发出 updateCell edit
2. EditorController 接收 table semantic edit
3. Rewriter 修改 TableBlock model
4. Serializer 重新生成 Markdown table source
5. 替换 document.source 中 table.sourceRange
6. parse 新 table block
7. 更新 block sourceRange
8. 更新 table object view
9. 如尺寸变化，通知 outer TextKit relayout
10. 注册 undo item

第一阶段建议采用：

canonical table serialization

也就是每次修改 table 后重新生成规范 Markdown table，而不是试图完整保留用户原始表格对齐格式。

原因：

实现简单
结果稳定
测试容易
避免复杂 trivia preservation

⸻

4.3 Code Block 编辑流

Markdown source：

```swift
let x = 1
```

解析为：

CodeBlock
    language
    fence style
    code content
    sourceRange
    codeContentRange

用户修改代码内容：

1. CodeEditorView 发出 replaceCodeContent edit
2. EditorController 接收 edit
3. Rewriter 替换 codeContentRange
4. 更新 document.source
5. parse code block
6. 更新 CodeBlock model
7. 刷新 code editor 内容和 syntax highlighting
8. 如高度变化，更新 attachment layout
9. 注册 undo item

如果只是修改代码内容：

只替换 codeContentRange
不要重写整个 fenced block

如果修改语言：

只修改 opening fence info string

⸻

4.4 Object focus 设计

复杂 block 内部需要自己的 selection/focus。

推荐全局 focus 状态：

EditorFocus
    outerText(range)
    activeSourceBlock(blockID, range)
    table(blockID, tableSelection)
    code(blockID, codeSelection)

进入 table/code object 后：

outer NSTextView 不再直接管理内部 selection
object view 自己管理 cell selection 或 code caret

退出 object 时：

Escape / arrow boundary / mouse click outside
    ↓
object focus → outer focus
    ↓
selection 映射到 attachment 前后或目标 block

⸻

5. Range Mapping 设计

5.1 为什么 mapping 是核心

编辑器中同时存在：

Markdown source offset
visible text offset
block-local offset
semantic node position
object-local selection

因此必须有统一的 mapping 机制。

⸻

5.2 Mapping 类型

至少需要支持：

source offset → visible offset
visible offset → source offset
source range → visible range
visible range → source range
semantic position → visible position
visible position → semantic position
object selection → source range
source edit → visible patch

⸻

5.3 不同 block mode 的 mapping

sourceEditing block

source:  This is **bold**
visible: This is **bold**
mapping:
    block 内基本 identity

preview block

source:  This is **bold**
visible: This is bold
mapping:
    Markdown token hidden
    visible text 对应 semantic inline content

object block

source:  Markdown table / fenced code
visible: single attachment character 或 object placeholder
mapping:
    outer visible range 通常是 attachment range
    内部编辑由 object-local mapping 负责

⸻

5.4 Mapping 的推荐实现思路

每个 block presentation 持有自己的 mapping：

BlockPresentation
    blockID
    sourceRange
    visibleRange
    mode
    sourceToVisibleMap
    visibleToSourceMap

文档级 mapping 由 block mapping 拼接而成：

DocumentRangeMap
    blocks ordered by sourceRange / visibleRange
    route mapping request to corresponding block

⸻

6. Selection 设计

6.1 不要只保存 visible offset

因为 block 在 preview/source/object 间切换时 visible 长度会变化，所以不能只保存：

NSRange(location, length)

推荐保存 semantic selection：

SelectionSnapshot
    anchor semantic position
    focus semantic position
    affinity
    focus kind

semantic position 可以是：

blockID + source offset
blockID + visible content offset
inline node position
table cell position
code block content offset
attachment before/after

⸻

6.2 Selection 恢复流程

每次发生 presentation patch 后：

1. patch 前保存 SelectionSnapshot
2. 更新 source / blocks / presentation
3. 更新 mappings
4. 将 SelectionSnapshot 映射回当前 visible selection
5. 设置 TextKit selection 或 object selection

⸻

7. Undo / Redo 设计

7.1 Undo 以 source edit 为核心

不要以 NSTextStorage edit 作为 undo 的真实记录。

原因：

Bold 操作可能 visible text 不变，但 source 变化
Table 操作可能 visible 只是 object 更新，但 source 大范围变化
Code 操作可能只在 object 内变化
Block 切换不应该进入 undo

推荐 undo item：

UndoItem
    edit kind
    old source range
    old source text
    new source range
    new source text
    before selection snapshot
    after selection snapshot
    affected block IDs

⸻

7.2 Undo 分组策略

建议：

连续普通输入：
    合并为一个 typing undo group
toggle bold / italic：
    一个 command 一个 undo item
table cell 连续输入：
    cell edit session 合并
insert/delete table row/column：
    一个结构操作一个 undo item
code block 连续输入：
    按 code editor typing session 合并
block activation / deactivation：
    不进入 undo

⸻

8. IME 输入设计

中文、日文、韩文输入法必须特别处理。

推荐策略：

marked text 期间：
    不做 block mode 切换
    不做大范围 parse/render
    不重建 TextStorage
    不破坏 first responder
commit 后：
    生成正式 source edit
    更新 source
    局部 parse/render
    更新 mapping

对于 active source block / active list group：

marked text 可以临时由 TextKit 承载
commit 后同步到 Markdown source

对于 object code editor：

由 code editor 内部处理 marked text
commit 后向 EditorController 发出 source edit

⸻

9. Patch 与 Layout 设计

9.1 尽量 patch 局部

避免每次编辑都：

全量 parse
全量 render
全量 replace NSTextStorage

这会导致：

selection 抖动
scroll 抖动
性能差
IME 容易中断
object focus 丢失

推荐：

普通 inline edit：
    patch 当前 block
block split / merge：
    patch 相关几个 block
table/code 内容变化：
    优先更新 object view
    只有 presentation 类型变化才 patch outer TextStorage
block mode 切换：
    patch old active scope + new active scope

⸻

9.2 Attachment 尺寸变化

table/code object 内容变化时，可能影响高度。

处理流程：

1. object view 更新内容
2. object view 重新计算 intrinsic size
3. attachment 更新 size
4. 通知 TextKit relayout 对应 fragment
5. 保持 scroll position 和 focus 稳定

原则：

不要因为 table/code 输入一个字符就重建整个 attachment
尽量保持 object view identity
只在必要时 relayout

⸻

10. 开发阶段规划

Phase 1：基础文档模型与渲染

目标：

建立 Markdown source → blocks → presentations → NSTextStorage 的基本链路

范围：

paragraph
heading
emphasis
strong
inline code
link
code block preview
table preview placeholder

交付：

MarkdownDocument
Block model
Parser adapter
Renderer
BlockPresentationEngine
Visible NSTextStorage
初始加载和全量渲染

暂不要求：

复杂局部 patch
table object editing
code object editing
高级 undo

⸻

Phase 2：Active Block Source Editing

目标：

实现普通 block / list group 的 preview/sourceEditing 切换

范围：

点击 block 激活
点击 list item 激活整个连续关联 list group
离开 block preview
普通输入
删除
Enter split block
Backspace merge block
selection restore
局部 parse/render

交付：

activeBlockID
activeListGroupID
block transition patch
sourceEditing presentation
source/visible range mapping
basic undo
IME 初步保护

⸻

Phase 3：Object Block Infrastructure

目标：

支持复杂 block 作为 attachment/object view 存在

范围：

TextKit attachment placeholder
blockID → object view 映射
object focus 管理
object size 更新
outer selection 与 object selection 切换

交付：

BlockAttachment model
ObjectBlockView protocol
FocusCoordinator
Attachment layout update

⸻

Phase 4：Code Block Object Editor

目标：

code block 在 preview object 内可编辑，并回写 Markdown source

范围：

code content edit
language edit
syntax highlighting
code editor focus
code selection
source range rewrite
undo grouping
height update

交付：

CodeBlock model
CodeEditorView integration
CodeBlockRewriter
CodeBlock tests

⸻

Phase 5：Table Object Editor

目标：

table block 在 preview object 内可编辑，并回写 Markdown source

范围：

cell edit
insert/delete row
insert/delete column
alignment edit
canonical serialization
table focus
table selection
undo grouping
height/width update

交付：

TableBlock model
TableEditorView integration
TableSerializer
TableBlockRewriter
Table tests

⸻

Phase 6：性能、稳定性、边界场景

目标：

让编辑器在大文档、复杂编辑、中文输入、频繁切换下稳定

范围：

局部 parse 优化
patch diff 优化
scroll stability
selection stability
IME 稳定性
object view reuse
large document profiling

交付：

benchmark
stress tests
bug fixing
性能指标

⸻

11. 单测计划

单测应重点覆盖：

source/visible mapping
block presentation switching
semantic edit → source edit
source edit → visible patch
selection restore
object block rewrite
undo/redo correctness

⸻

11.1 Parser / Block Model 测试

覆盖：

paragraph block range
heading block range
list block range
blockquote range
fenced code block range
table block range
inline node range

示例测试方向：

输入 Markdown source
验证 blocks 数量
验证 block kind
验证 sourceRange
验证 inline node sourceRange
验证 codeContentRange
验证 table cell model

重点：

sourceRange 必须稳定
block boundary 必须准确
code/table 这种复杂 block 的内部 range 必须准确

⸻

11.2 Preview Rendering 测试

覆盖：

Markdown source → preview visible string
Markdown source → attributes
Markdown source → sourceToVisible mapping
Markdown source → visibleToSource mapping

示例：

This is **bold** text.

期望：

visible string: This is bold text.
bold content 有 strong attribute
** token 不出现在 visible string
visible bold range 可映射回 source bold content range

⸻

11.3 Source Editing Rendering 测试

覆盖 active block / active list group 显示 raw Markdown。

示例：

This is **bold** text.

sourceEditing 模式期望：

visible string: This is **bold** text.
source/visible offset 基本 identity
** token 可见
syntax highlighting attribute 正确

List sourceEditing 模式期望：

点击任意 list item 后，整个连续关联 list group 显示 raw Markdown source。
list group 内 source/visible offset 基本 identity。
相邻非 list block 不进入 active scope。

⸻

11.4 Block Mode Switching 测试

覆盖：

preview → sourceEditing
sourceEditing → preview
block A active → block B active
list item active → whole list group active
visibleRange 更新
selection 映射恢复

测试重点：

切换前后 Markdown source 不变
visible string 正确变化
block visibleRange 正确更新
后续 block visibleRange 正确平移
selection 仍然指向同一 semantic content

⸻

11.5 普通文字输入测试

场景：

active paragraph 中插入字符
active heading 中插入字符
active bold token 中插入字符
active list group 中任意 list item 插入字符

验证：

source 正确更新
visible sourceEditing block / list group 正确更新
parse 后 block model 正确
selection 位于插入内容之后
undo item 正确生成

⸻

11.6 删除测试

覆盖：

删除普通字符
删除 Markdown token
删除 heading marker
删除 list marker
删除 block 开头字符
删除跨 inline node 内容

验证：

source edit 正确
block kind 变化正确
preview 渲染正确
selection 正确
undo 可恢复

⸻

11.7 Enter / Backspace Block 操作测试

Enter：

paragraph split
heading split
list item split
empty list item exit
code block 内换行

Backspace：

普通字符删除
block 开头 merge
list marker 删除
empty block merge
heading marker 删除

验证：

source 结构正确
blocks 数量正确
activeBlockID / activeListGroupID 正确
selection 正确
visible patch 正确

⸻

11.8 Table 编辑测试

覆盖：

parse table
render table object presentation
update cell
insert row
delete row
insert column
delete column
set alignment
serialize table
undo table edit

验证：

TableBlock model 正确
Markdown source 正确回写
canonical serialization 稳定
block sourceRange 更新正确
下游 block sourceRange 更新正确
table object view state 不丢失

重点单测：

修改一个 cell 后，source 中 table block 被正确替换
其他 block source 内容不变
undo 后 source 完全恢复
redo 后 source 再次正确

⸻

11.9 Code Block 编辑测试

覆盖：

parse fenced code block
replace code content
insert newline in code
change language
empty code block
code content 包含 backticks
undo code edit

验证：

codeContentRange 正确
只替换 code content 时 fence 不变
修改语言时 code content 不变
source 正确
selection / code caret 正确恢复

⸻

11.10 Object Focus 测试

覆盖：

outer text → table
table → outer text
outer text → code
code → outer text
table → code
code → table

验证：

EditorFocus 状态正确
outer selection 正确
inner object selection 正确
object first responder 不意外丢失
block activation 不错误触发 undo

⸻

11.11 Undo / Redo 测试

覆盖：

普通输入 undo
block split undo
toggle style undo
table cell edit undo
table row insert undo
code edit undo
block mode switch 不进入 undo

验证：

undo 前后 source 完全匹配
redo 前后 source 完全匹配
selection snapshot 正确恢复
object focus 正确恢复
visible presentation 与 source 一致

⸻

11.12 IME / Marked Text 测试

尽量用抽象事件模拟。

覆盖：

marked text begin
marked text update
marked text commit
marked text cancel
marked text during active source block / active list group
marked text inside code editor

验证：

marked text 期间不触发大范围 parse/render
不切换 active block / active list group
commit 后才产生 source edit
selection 正确
source 不出现中间态污染

⸻

11.13 Mapping Property Tests

建议加入 property-based tests，随机生成小型 Markdown 文档和编辑操作。

验证不变量：

source → parse → render → mapping 不崩溃
visibleToSource(sourceToVisible(x)) 合理
所有 visibleRange 不重叠
所有 sourceRange 不重叠
block 顺序一致
patch 后 source 与 presentation 一致
undo 后 source 恢复到之前状态

尤其要覆盖：

inline token
hidden token
emoji
中文字符
组合字符
多行 block
table
code block

⸻

12. 集成测试计划

除了单测，还需要做端到端编辑测试。

12.1 用户编辑路径测试

场景：

打开文档
点击 heading
修改 heading source
离开 heading
点击 paragraph
插入 bold token
点击 table
修改 cell
点击 code
修改代码
undo 多次
redo 多次
保存 source
重新加载

验证：

最终 source 正确
重新加载后 presentation 一致
selection/focus 没有异常
object block 没有丢状态

⸻

12.2 大文档测试

构造：

1000+ paragraphs
100+ code blocks
50+ tables
大量 inline styles

验证：

初始加载性能
block 激活性能
普通输入延迟
table/code 编辑延迟
scroll 稳定性
TextKit layout 稳定性

⸻

13. 风险与应对

风险 1：Range mapping 复杂度过高

应对：

第一版只支持 block-local mapping；list 使用 list-group-local mapping
普通 block / list group active 时使用 sourceEditing 降低 mapping 难度
preview mode mapping 只用于 selection 定位，不直接编辑

⸻

风险 2：IME 被 TextStorage patch 打断

应对：

marked text 期间暂停 presentation rebuild
commit 后再 source edit
避免在 IME 中途切换 block mode 或 list group scope

⸻

风险 3：Object view 与 outer TextKit 状态不同步

应对：

object edit 只发 semantic edit
EditorController 统一更新 source/model
object view 从 block model 刷新
不要让 object view 私自成为文档真相

⸻

风险 4：Undo 粒度混乱

应对：

所有 undo 以 source edit 为准
block mode switch 不进入 undo
object editor typing session 合并 undo

⸻

风险 5：Table round-trip 丢失格式

应对：

第一版接受 canonical serialization
后续再支持 preserve formatting trivia

⸻

14. 最终建议路线

推荐按这个顺序实现：

1. Markdown source + block model
2. preview renderer
3. sourceEditing renderer
4. active block / active list group switching
5. source-first ordinary editing
6. selection mapping
7. undo based on source edit
8. code block object editor
9. table object editor
10. IME / performance / large document polish

不要一开始就做：

完全自定义 NSTextContentManager
全 WYSIWYG 隐藏 Markdown token 编辑
完整 CommonMark round-trip preservation
复杂 table formatting trivia preservation

更稳的核心路线是：

Markdown source 是真相
普通 block 用 active source editing 降低复杂度
复杂 block 用 object editor 提供更好体验
TextKit 2 作为 mixed presentation 的布局和交互承载层
所有编辑最终统一回写 source

这套架构既保留 Markdown 的可控性，又能给 table/code 等复杂内容提供接近原生对象编辑器的体验。
