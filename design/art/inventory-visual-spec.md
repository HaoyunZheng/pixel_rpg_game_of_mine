# Visual Spec: 背包界面（Inventory）

> **Status**: Draft
> **Author**: art-director
> **Last Updated**: 2026-06-11
> **Source UX Spec**: `design/ux/inventory.md`（13 章节，已通过复审）
> **Implementation target**: ui-programmer（GDScript / `.tscn`）
> **Scope**: 本次不新增美术资产；新增视觉元素一律走 `StyleBoxFlat` / `StyleBoxTexture`（复用现有 9-patch）+ 调色板程序化方案，参照 `BattleWidgets.make_cmd_cell_style()` 的"切片优先、缺失回退纯色"模式。

---

## 0. 调色板与基线复用速查

直接复用，不新增颜色（除非本文档明确定义新增语义色，见 §5.7 / §6）：

| 常量 | 值 | 用途 |
|---|---|---|
| `COL_BONE` | `Color(0.847, 0.812, 0.753)` | 默认文字、行囊格描边 |
| `COL_GOLD` | `Color(0.902, 0.753, 0.290)` | 选中/高亮反馈（焦点加粗描边、ActionMenu 选中项、CategoryTab 拉出态） |
| `COL_DIM` | `Color(0.45, 0.43, 0.40)` | 置灰（未选中 Tab、禁用 ActionMenu 项、EmptySlotGhost） |
| `COL_ALLY` | `Color(0.22, 0.52, 0.82)` | 不在本屏使用 |
| `COL_ENEMY` | `Color(0.82, 0.22, 0.22)` | 不在本屏使用 |
| `COL_HP` | `Color(0.70, 0.27, 0.27)` | 不在本屏使用（StatBlock 不用条形，用文本） |
| `COL_MP` | `Color(0.31, 0.52, 0.66)` | 不在本屏使用 |

字体基线（`battle_theme.tres`）：`default_font_size=18`，字色 `Color(0.847,0.812,0.753,1)`，描边色 `Color(0.086,0.078,0.102,0.9)`，`outline_size=2`。Inventory 界面**全局沿用此 Theme**（场景根节点 `theme = battle_theme.tres`），仅在羊皮纸侧页区域局部覆盖字色（见 §5）。

资产路径前缀：`res://assets/ui/battle/`（9-patch/chip）、`res://assets/ui/items/`（物品图标）。

---

## 1. 整体面板

**尺寸与定位**
- 面板整体尺寸：`1600 × 880`，在 1920×1080 画布中居中（`offset` 四边各 `160 / 100`）。选取理由：与战斗 UI 中央框比例呼应，同时为左右两栏（约 65/35 分割）留出足够格宽——5~6 列 96px 格 + 间距，刚好落在整数像素网格上。
- 半透明背景遮罩：场景根 `CanvasLayer`（`layer = 10`，确保盖在游戏世界之上，参照 [[godot Node2D 下 Control 锚点坑]] 的全屏挂载方式）下挂一个 `ColorRect`，铺满全屏（`PRESET_FULL_RECT`），颜色 `Color(0.05, 0.045, 0.06, 0.55)`——55% 不透明度的冷紫黑色，呼应"世界冻结/翻开手记"的暗调氛围，同时让背景场景仍可辨认轮廓。

**外框 9-patch 复用方案**
- 复用 `panel_central_9p.png`（已是"8px 黑框 + 内部细描边"的中央框切片）。作为 `NinePatchRect`，铺满整个 `1600×880` 面板区域，`patch_margin_*` 沿用该资产烘焙时的外框宽度（与 `cmd_cell_9p` 同源风格，外黑框 8px + 骨白细线 2px + 暗缝 2px = 12px）：`patch_margin_left/top/right/bottom = 12`。
- 面板内容（书签栏、网格、侧页）全部铺设在该 9-patch 的 `content` 区域内（即整体再内缩 12px）。
- 理由：`panel_central_9p` 已经是"深色面板 + 8-bit 粗黑边"的现成资产，背包外框与战斗中央框使用同一视觉语言，符合"整个面板外部用战斗 UI 同款 8-bit 粗黑边 9-patch 包裹"的 UX 要求，零新增资产。

**内部分区网格（基于 1600×880，内缩 12px 后约 1576×856 可用区）**
- 顶部书签栏：高度 `64px`，横跨整个可用宽度。
- 主体区域（书签栏下方）：高度 `856 - 64 - 8(间隔) = 784px`，左右切分：
  - 左侧主背包区域：宽度 `1576 × 0.66 ≈ 1040px`
  - 右侧详情侧页：宽度 `1576 - 1040 - 8(间隔) = 528px`

> 注：以上数值为推荐网格基准，ui-programmer 可用 `HBoxContainer`/`VBoxContainer` + `size_flags_stretch_ratio`（左 0.66 / 右 0.34）实现，无需写死像素值，但**格子尺寸（§3）必须保持整数像素**以避免 Nearest 缩放下的非整数拉伸。

---

## 2. CategoryTab（书签标签）

**布局**：5 个 Tab 水平排列于顶部书签栏，`HBoxContainer`，`separation = 4`。每个 Tab 是一个 `PanelContainer` + 内部 `Label`（分类名 + 角标）。

**尺寸**：每个 Tab 宽度自适应内容（最长标签"重要物品(9)"约可容纳 6 字符），`custom_minimum_size = Vector2(0, 56)`（未选中态高度），文字水平居中。字号 `20`（略大于正文 18，强化标签的"标题"属性）。

### 选中态（"拉出/凸起"）
- **位移**：选中 Tab 的容器整体 `position.y -= 8px`（向上"拉出"8px，露出下方面板边缘的视觉错觉），同时高度增加到 `64px`（净增 8px 露出量 + 8px 高度补偿，使其视觉上"盖住"书签栏与主体区域的分隔线，形成"标签插入两页之间"的效果）。
- **StyleBox**：`StyleBoxFlat`：
  - `bg_color = COL_GOLD.darkened(0.55)` ≈ `Color(0.406, 0.339, 0.131)`（暗金底色，呼应金色高亮但不刺眼）
  - `border_color = COL_GOLD`（`Color(0.902, 0.753, 0.290)`）
  - `border_width_*  = 4`（顶/左/右），`border_width_bottom = 0`（与下方主体区域视觉相连，形成"标签纸片插入"效果）
  - `corner_radius_top_left/top_right = 0`（保持 8-bit 直角风格，与 `cmd_cell_9p` 的方正边框一致）
- **文字颜色**：`COL_GOLD`，`outline_size = 2`（继承主题描边色）。
- **角标**：分类种类数 `(N)` 跟在分类名后，同色同字号，无需单独样式。

### 未选中态（"下沉/降饱和度"）
- **位移**：`position.y` 不变（基准位置），高度 `56px`。
- **StyleBox**：`StyleBoxFlat`：
  - `bg_color = Color(0.16, 0.145, 0.18)`（暗紫灰，比选中态更暗、更冷，制造"沉入面板"的层次感）
  - `border_color = Color(0.04, 0.03, 0.055)`（接近 `cmd_cell_9p` 的黑框色）
  - `border_width_* = 2`（细边，弱化存在感）
- **文字颜色**：`COL_DIM`（`Color(0.45,0.43,0.40)`），`outline_size = 0`（不描边，进一步降低视觉权重）。

**理由**：用"位移 + 边框粗细 + 颜色饱和度"三重信号区分选中态，而非仅靠颜色——满足 UX Spec 中"分类标签的选中/未选中用拉出/凸起 vs 下沉的位置+形状变化区分"的不依赖颜色原则（Accessibility）。`StyleBoxFlat` 纯程序化，零新增资产。

---

## 3. ItemGrid / ItemSlot

**网格参数**
- 列数：`5` 列（Component Inventory 标注"5~6 列"；选 5 列以保证 `1040px ÷ 5 = 208px`/列，每格 `96px` + `separation` 充裕，且 5 列在所有分类下都不会出现"最后一格悬空半格"的视觉问题，6 列在窄分类下会更拥挤）。
- 行数：根据内容自适应（`GridContainer`，`columns = 5`），最多显示行数由左侧区域可用高度决定（`784px ÷ (96+下方文字标签~24+间距8) ≈ 6 行`）；超出则需滚动——本规格暂不展开滚动条样式，`GridContainer` 包一层 `ScrollContainer`，滚动条用 Godot 默认主题（细节留给 ui-programmer，非本期视觉重点）。
- 格间距：`separation = 8`（水平/垂直一致）。

**ItemSlot 格子尺寸与 9-patch 复用**
- 格子尺寸：`96 × 96px`（图标区域）+ 下方独立 `Label`（物品名，`24px` 高，字号 `14`，居中，单行截断）。
- 复用 `cmd_cell_9p.png` 作为 `StyleBoxTexture`：
  - `texture_margin_left/top/right/bottom = 12`（与 `make_cmd_cell_style()` 一致）
  - `content_margin_left/right = 12`，`content_margin_top/bottom = 12`（背包格不需要战斗命令格那样宽的左右留白，物品图标需要居中铺满；故 content_margin 比战斗命令格的 `20/14` 更小，让 32px 图标在 96px 格内有合理留白比例）
  - 格子内部图标实际可用区 ≈ `96 - 12*2 = 72px`，32px 物品图标在其中 `STRETCH_KEEP_ASPECT_CENTERED` 显示原生大小（不放大），保持像素锐利；周围留白由格子背景色（`cmd_cell_9p` 内部的暗色）填充。

  > 备选：若 32px 图标在 72px 留白区显得过小、视觉权重不足，可整数 ×2 放大至 64px（`STRETCH_KEEP_ASPECT_CENTERED` + `custom_minimum_size` 控制）。**默认采用原生 32px**（与战斗物品列表保持图标基准尺寸一致，避免同一资源在不同界面呈现不一致的"清晰度感"）；ui-programmer 实现后若视觉过小，可在 1 处统一改为 ×2，不影响其他规格。

**焦点态 vs 选中态描边**
- **焦点态（预览，方向键移动）**：`cmd_cell_9p` 默认描边（资产自带的骨白细线）即为焦点描边，**额外叠加**一层 `StyleBoxFlat`（`bg_color = Color(0,0,0,0)` 透明，仅 `border_color = COL_BONE`, `border_width_* = 2`）作为 `focus` 主题样式覆盖在格子最外侧 —— 即细描边、骨白色，宽度 `2px`。
- **选中态（按 Z 进入操作选择）**：边框替换为 `border_color = COL_GOLD`，`border_width_* = 4`（加粗一倍）。理由：UX Spec 明确"焦点（细描边）vs 选中（加粗描边）"，金色与战斗 UI 的"我方选中/确认反馈"色一致，玩家已建立"金色=已确认操作"的心智模型。
- 实现方式：`ItemSlot` 根节点用 `Panel`，`add_theme_stylebox_override("panel", ...)` 在焦点/选中状态切换时替换 StyleBox 实例（两份预先构建好的 `StyleBoxTexture`+边框叠加，或用 `StyleBoxFlat` 边框单独作为子节点 `NinePatchRect`/`Panel` overlay，二选一由 ui-programmer 决定，视觉结果一致即可）。

**持有数量角标**
- 位置：格子右下角，`offset` 距右边缘 `4px`、距下边缘 `4px`（在 9-patch 内容区之内）。
- 字号：`14`（小于正文 18，作为辅助信息）。
- 样式：`Label`，文字 `×N`（如 `×3`），颜色 `COL_BONE`，`outline_size = 2`（继承描边，确保在物品图标背景上可读）。
- 仅消耗品/战斗道具类显示（与 UX Spec 一致，武器/防具/饰品等单件物品不显示数量角标，或显示 `×1` 也可——**决策：不显示**，因为这些分类下数量恒为 1，显示徽章是冗余信息，省略更符合"信息层级"原则）。

**50% 不透明度规则**
- `ItemData.usable == false` 的物品：`ItemSlot` 内的图标 `TextureRect.modulate = Color(1, 1, 1, 0.5)`。
- **仅图标本身**应用 0.5 alpha，格子边框（`cmd_cell_9p` 背景与描边）、物品名 `Label`、数量角标**不**降低不透明度——确保焦点/选中状态的描边变化依然清晰可辨，只有"物品本身"传达出"暗淡/不可用"的信息。这与 UX Spec 中"该规则与是否可丢弃无关"一致：不透明度只是图标层面的视觉提示，不影响交互可见性。

---

## 4. EmptySlotGhost / EmptyCategoryHint / EmptyDetailHint

**EmptySlotGhost**（空网格位占位）
- 复用 `cmd_cell_9p` 格子皮肤，但整体 `modulate = Color(1,1,1,0.35)`（比 50% 不透明度规则更淡，因为这是"位置都不存在的占位"，比"存在但暗淡的物品"更弱）。
- 内容：不放图标，仅在格子中心放一个 `··` 文本占位（沿用 ASCII 线框中的视觉意图——一个极简的"空位"标记），字号 `18`，颜色 `COL_DIM`，无描边。
- **不可聚焦**（`focus_mode = FOCUS_NONE`），方向键导航直接跳过。

**EmptyCategoryHint**（"此分类暂无物品"）
- 显示位置：替代整个 `ItemGrid`，在左侧主背包区域居中显示。
- 样式：`Label`，文字"此分类暂无物品"，字号 `18`（正文基准），颜色 `COL_DIM`，`outline_size = 2`（沿用主题描边）。
- 居中：`size_flags_horizontal/vertical = SIZE_SHRINK_CENTER`，水平垂直居中于左侧区域。

**EmptyDetailHint**（"行囊空空如也" / "什么都没有。"）
- 显示位置：替代整个右侧详情侧页内容区（羊皮纸背景仍然渲染，见 §5，但内容区为空状态文案）。
- 标题行："行囊空空如也"，字号 `22`（比正文略大，作为该状态下侧页的视觉锚点），颜色见 §5.7（羊皮纸文字色，深棕）。
- 副文本："什么都没有。"，字号 `16`（比正文略小，斜体模拟"轻声补充"的笔记感，呼应 §5.6 的 DescriptionText 风格）。
- 两行垂直居中于侧页内容区，`separation = 12`。

---

## 5. 详情侧页（羊皮纸笔记）

### 5.1 背景 StyleBox 方案（程序化羊皮纸感，不依赖新纹理）

**决策：`StyleBoxFlat` + 暖色调 + 双层边框模拟"纸张+阴影"**

```
bg_color          = Color(0.776, 0.706, 0.557)   # 暖米黄"羊皮纸"色
border_color      = Color(0.541, 0.471, 0.337)   # 深棕色边框，模拟纸张边缘磨损
border_width_*    = 4
corner_radius_*   = 0   # 保持 8-bit 直角，与外框 9-patch 风格统一
shadow_color      = Color(0.04, 0.03, 0.055, 0.4)
shadow_size       = 6
shadow_offset     = Vector2(4, 4)   # 右下阴影，模拟"纸页叠放在深色行囊格之上"的层次
```

理由：
- 暖米黄 `Color(0.776, 0.706, 0.557)` 与战斗 UI 的冷色调（灰烬/深紫/法力蓝）形成强烈材质对比，正是"行囊（冷/深）vs 笔记（暖/浅）"隐喻的核心实现手段，纯色块即可达成，零新增资产。
- `shadow_size`/`shadow_offset` 是 `StyleBoxFlat` 原生支持属性，制造"一页纸盖在深色格子上"的轻微立体感，强化材质层次而不需要额外贴图。
- 边框沿用 8-bit 直角粗边语言（`border_width=4`，比外框的 12px 细，因为这是"内部分区"而非"整体外框"，视觉上应有层级差异）。

侧页整体作为 `PanelContainer`，`add_theme_stylebox_override("panel", <上述StyleBoxFlat>)`，铺满右侧 `528px` 宽区域，内部 `content_margin_* = 16`。

### 5.2 ItemIconLarge（2x 放大）

- 物品图标（`assets/ui/items/` 32px 原生）以 `TextureRect` 显示，`expand_mode = EXPAND_IGNORE_SIZE`，`stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`，`custom_minimum_size = Vector2(64, 64)`（32px × 2 = 整数倍放大，符合 `default_texture_filter=0` Nearest 下"禁止非整数缩放"的约束）。
- 外部包一层 9-patch 边框：复用 `avatar_frame_9p.png`（已是"8px 黑框 + 2px 骨白 + 2px 暗缝"的方形头像框，64×64 内容区刚好与 ×2 图标吻合，参照 `make_avatar()` 的 `border_px=12` 用法）。
  - `holder` 尺寸 `88×88`（`64 + 12*2`），`patch_margin_* = 12`。
  - 注意：`avatar_frame_9p` 背景色是深色（接近黑），与羊皮纸暖色背景形成小范围对比框——这是**刻意保留**的"行囊格嵌入笔记页"的视觉细节（暗示这件物品本身仍是行囊里的实物，笔记页只是记录）。
- 居中放置在侧页顶部，下方紧跟 `ItemNameLabel`。

### 5.3 ItemNameLabel

- `Label`，字号 `22`（比正文 18 大，作为侧页的标题层级）。
- 颜色：`Color(0.231, 0.165, 0.094)`（深棕色，"墨水"色，在暖米黄羊皮纸背景上对比度充足）；`outline_size = 0`（羊皮纸背景明亮，不需要描边——描边是为深色背景设计的，米白字+深描边在浅色纸面上反而显脏）。

  > **局部 Theme 覆盖**：侧页内所有文本（`ItemNameLabel`/`StatBlock`/`DescriptionText`/`EquipStatusBadge`/`Divider` 文案）统一使用"墨水棕 `Color(0.231,0.165,0.094)` + 无描边"，与左侧行囊区"骨白+深描边"形成完整的两套配色体系，强化材质分区。`CategoryChip`（见 §5.4）例外，保留原 chip 配色以维持其"徽章"识别度。

- 居中对齐，位于 `ItemIconLarge` 正下方，`separation = 4`。

### 5.4 CategoryChip

- 复用 `chip_status.png`（已有的状态徽章 9-patch，紫色调小尺寸徽章）作为 `StyleBoxTexture` 背景。
- 内容：当前物品所属分类名（"消耗品"/"武器"等），字号 `14`。
- 文字颜色：沿用 `chip_status.png` 原本配色语境下的浅色文字（`COL_BONE`），`outline_size = 1`（chip 本身较暗，需要描边维持可读性，与侧页主体的"无描边"规则区分——chip 是一个独立的"贴纸"元素，不属于纸张本身）。
- 位置：与 `ItemNameLabel` 同行右侧，`HBoxContainer` 排列（`[图标下方一行：物品名 ... CategoryChip]`），或在 `ItemNameLabel` 正下方单独一行、靠右对齐——**决策：单独一行靠右对齐**，因为物品名长度不固定（见 Localization Considerations 的换行风险），同行排列在长名称下容易挤压 chip；独立一行更稳健。

### 5.5 Divider

- 程序化方案：`HSeparator` 自定义样式，或一个 `ColorRect`，`custom_minimum_size = Vector2(0, 2)`，颜色 `Color(0.541, 0.471, 0.337, 0.6)`（与羊皮纸边框同色但半透明，模拟"铅笔划线"而非印刷线）。
- 上下 `margin = 8`（与相邻文本块的间距）。
- **不做"手绘波浪线"特效**（需要新纹理才能做到真正手绘感）——纯色细线 + 半透明 + 边框同色，已能传达"笔记本上的分隔线"语义，符合"不新增资产"约束。若未来想要更强的手绘感，列入 §8 资产清单。

### 5.6 DescriptionText 字体（衬线/手写体回退方案）

**决策：不引入新字体文件，使用现有字体 + 斜体效果模拟"手写笔记"质感**

- Godot 默认字体不支持 `font_style="italic"` 的真正斜体变形（除非字体文件本身含 italic 变体或使用 `Label` 的 `OT features`）。**程序化回退方案**：
  - 字号：`16`（比正文 18 略小，符合"附注"的层级）
  - 颜色：墨水棕 `Color(0.231,0.165,0.094)`，比 `ItemNameLabel` 略浅一档：`Color(0.231,0.165,0.094).lightened(0.15)` ≈ `Color(0.345, 0.262, 0.171)`（区分"标题"与"正文描述"的视觉权重）
  - 行间距：`add_theme_constant_override("line_spacing", 6)`（比默认行距宽，模拟手写笔记的"留白感"）
  - **字间距微调**：`add_theme_constant_override("font_size", 16)` + 若 Godot 版本支持 `Label.add_theme_constant_override("outline_size", 0)` 之外的 letter-spacing（4.x 的 `Label` 本身不直接支持 letter spacing，`RichTextLabel` 可通过 BBCode 实现）。**决策：使用纯 `Label`，不追求字间距微调**——避免引入 `RichTextLabel` 的额外复杂度（不在本次范围内"零新增交互复杂度"原则下），16px 字号+宽行距已足够与正文形成层级差异。
- **未来美术资产需求**（见 §8）：若想要真正的手写体/衬线体观感，需要引入一款像素友好的衬线/手写风格字体（`.ttf`/`.otf`），并验证其在 Nearest 渲染 + 18px 基准下的可读性。当前回退方案（小字号+浅墨色+宽行距）在不引入字体文件的前提下已能实现"区别于行囊区无衬线粗体"的视觉分层目标。
- 过长滚动：`DescriptionText` 包一层 `ScrollContainer`，`vertical_scroll_mode = SCROLL_MODE_AUTO`，无自定义滚动条样式（沿用 Godot 默认，非本期重点）。

### 5.7 StatBlock（物品数值条目）

- 每条数值（如"HP +30"、"攻击力 +5"）为一行 `HBoxContainer`：左侧标签（"效果："/"攻击力："），右侧数值。
- 字号：`18`（与正文基准一致——这是"决策依据"信息，优先级高于描述文本，不应比 `DescriptionText` 小）。
- 颜色：标签部分用墨水棕 `Color(0.231,0.165,0.094)`；**数值部分**使用一个新增的语义色——**赭红 `Color(0.62, 0.30, 0.16)`**（暖色系内的"强调色"，区别于纯墨水棕，让数字在视觉扫描时更跳出，呼应"略带压力场景下快速找到数值"的 UX 优先级）。
  - 该赭红色是本文档**新增的语义色**：专用于羊皮纸侧页内的"数值强调"，不与战斗 UI 的 `COL_*` 冲突（战斗 UI 全部是冷色/原色板，赭红属于暖色系笔记专属）。建议命名 `COL_PARCHMENT_ACCENT = Color(0.62, 0.30, 0.16)`，供 ui-programmer 在脚本顶部统一定义。
- 多条数值之间 `separation = 4`（紧凑排列，体现"列表"感）。

### 5.8 EquipStatusBadge

- 文本格式：`"状态：● 未装备"` / `"状态：◆ 已装备"`（符号 + 文字，符合 UX Spec "不仅靠颜色"的可访问性要求）。
- 符号颜色：
  - `●` 未装备：`COL_DIM` 的暖色版本 `Color(0.55, 0.50, 0.42)`（与羊皮纸背景形成柔和对比，传达"未激活"）
  - `◆` 已装备：`COL_PARCHMENT_ACCENT`（赭红，`Color(0.62, 0.30, 0.16)`，与 StatBlock 数值同色——"已装备"是对玩家有利的当前状态，用强调色呼应数值的重要性）
- 文字部分（"状态："/"未装备"/"已装备"）使用墨水棕 `Color(0.231,0.165,0.094)`，字号 `18`。
- 位置：`DescriptionText` 下方，`Divider` 分隔后单独一行。仅武器/防具/饰品类显示（与 UX Spec 一致）。

---

## 6. ActionMenu（侧页内嵌操作菜单）

**视觉来源**：复用 `_render_central_options` 的高亮逻辑（`_update_menu_selection()` 中的金色描边 + `▸` 指针前缀），但**配色适配羊皮纸背景**（原战斗 UI 配色是为深色背景设计的金色高亮，直接搬到米黄背景上金色对比度会下降）。

**容器**
- `VBoxContainer`，位于侧页 `DescriptionText`（及 `EquipStatusBadge`，若有）下方。
- 外框：`StyleBoxFlat`，`bg_color = Color(0.706, 0.631, 0.475, 0.6)`（比羊皮纸主背景略深一档的半透明米色，制造"菜单是叠加在纸面上的便签"的层次），`border_color = Color(0.541, 0.471, 0.337)`，`border_width_* = 2`。
- `content_margin_* = 8`，`separation = 4`。

**选项行**
- 字号 `18`（与正文一致——操作选项是"第三层"决策信息，不应过小）。
- **未选中项**：墨水棕 `Color(0.231,0.165,0.094)`，无描边，无前缀。
- **选中项**：
  - 文字颜色 → `COL_PARCHMENT_ACCENT`（`Color(0.62, 0.30, 0.16)`，赭红）——**不直接用 `COL_GOLD`**，理由：金色 `Color(0.902,0.753,0.290)` 在暖米黄背景（`Color(0.776,0.706,0.557)`）上明度差过小，对比度不足；赭红与米黄的色相互补关系（暖黄 vs 暖红）能提供更清晰的区分,同时延续"强调色=赭红"的侧页内部一致性（与 §5.7/§5.8 呼应）。
  - 前缀 `▸ `（与战斗 UI 一致的指针符号）。
  - `outline_size = 0`（羊皮纸背景不需要描边）。
- **禁用项**（"（无可执行操作）"）：颜色 `Color(0.55, 0.50, 0.42)`（与 `EquipStatusBadge` 未装备符号同色，"暖色调置灰"），不可选中，无前缀。

**展开动画**（高度 0→目标值，~100ms ease-out）
- 实现：`ActionMenu` 容器初始 `custom_minimum_size.y = 0` 且 `clip_contents = true`，通过 `Tween` 在 ~100ms 内将 `custom_minimum_size.y` 从 `0` 过渡到内容实际高度（选项数 × 行高 `26px` + `content_margin*2`）。
- 缓动：`Tween.set_ease(Tween.EASE_OUT)` + `Tween.set_trans(Tween.TRANS_QUAD)`。
- 收起时反向（`EASE_IN`，~100ms）。
- 视觉描述："从描述文本下方像翻开笔记追加一行"——容器从上边缘固定、下边缘向下展开，给人"在已有文字下方写下新一行"的错觉，而非从中心或两侧展开。

---

## 7. DiscardConfirmDialog

**尺寸**：`560 × 240px`，居中浮于整个 Inventory 面板之上（`CanvasLayer` 内更高 layer，或同层但 `z_index` 更高）。

**9-patch 复用**：复用 `panel_central_9p.png`（与整体外框同源资产，但本次作为"小尺寸弹窗"使用——同一资产不同尺寸实例化是 9-patch 的核心优势，零新增）。`patch_margin_* = 12`（与 §1 外框一致）。

**背景遮罩**：弹窗弹出时，Inventory 主面板整体 `modulate = Color(0.6, 0.6, 0.65, 1)`（轻微变暗变冷，暗示"输入冻结"），弹窗本身保持 `modulate = Color(1,1,1,1)` 全亮，形成焦点对比。

**文案排版**
- 内容区（9-patch 内缩 12px 后 ≈ `536 × 216px`），`VBoxContainer`，`alignment = CENTER`。
- 第一行：`"确定丢弃"`，字号 `18`，`COL_BONE`（弹窗背景沿用深色 `panel_central_9p`，回到"行囊区"配色体系——**弹窗不使用羊皮纸配色**，因为它是一个独立的模态层，不属于侧页笔记的一部分）。
- 第二行：`"[物品名] ×[数量]？"`，字号 `22`（比正文大，物品名是本次确认的核心信息），`COL_GOLD`（与战斗 UI"需要玩家注意的关键信息"色一致，提示这是高风险操作的核心对象）。
- 第三行（间距 `separation = 16` 后）：`"[Z] 确认        [X] 取消"`，字号 `18`，`COL_BONE`，`outline_size = 2`，水平排列、`separation = 48`。

**弹出/关闭动画**：与 UX Spec Transitions 一致——`scale 0.8→1.0 + 淡入`（~120ms），关闭反向（~100ms）。`Tween` 同时驱动 `scale` 与 `modulate.a`。

---

## 8. 资产清单（Asset Manifest）

### 8.1 复用现有资产（本次实现直接引用，无需修改）

| 资产路径 | 用途（本规格章节） |
|---|---|
| `res://assets/ui/battle/battle_theme.tres` | 全局 Theme 基线（字体/字色/描边） |
| `res://assets/ui/battle/panel_central_9p.png` | 整体外框（§1）、`DiscardConfirmDialog` 弹窗背景（§7） |
| `res://assets/ui/battle/cmd_cell_9p.png` | `ItemSlot` 格子皮肤（§3）、`EmptySlotGhost`（§4） |
| `res://assets/ui/battle/avatar_frame_9p.png` | `ItemIconLarge` 外框（§5.2） |
| `res://assets/ui/battle/chip_status.png` | `CategoryChip`（§5.4） |
| `res://assets/ui/items/*.png`（7 个） | `ItemSlot` 图标（§3）、`ItemIconLarge`（§5.2） |

### 8.2 本次不新增、若未来需要可考虑

| 资产 | 建议尺寸/格式 | 用途 | 当前替代方案 |
|---|---|---|---|
| 衬线/手写体字体文件 | `.ttf`/`.otf`，需验证小字号下 Nearest 渲染可读性 | `DescriptionText`（§5.6）真正的"手写笔记"质感 | 现有字体 + 16px 小字号 + 浅墨色 + 宽行距（`line_spacing=6`） |
| 羊皮纸纹理（带做旧/纤维质感） | 9-patch，建议 `64×64` 或更大，米黄底+做旧边缘 | 详情侧页背景（§5.1）更真实的纸张质感 | `StyleBoxFlat` 纯色 + 边框 + 阴影 |
| 手绘波浪分隔线纹理 | 横向重复纹理条，`~8px` 高 | `Divider`（§5.5）"铅笔划线"手绘感 | `ColorRect` 半透明细线 |
| 物品分类图标（武器/防具/饰品/消耗品/重要物品 5 个小图标） | `24×24` 或 `32×32`，单色线稿风格 | `CategoryTab`（§2）若未来想要"图标+短文本"组合（应对 Localization 高风险） | 当前仅文本（"武器"/"防具"等） |
| 占位"问号格"图标 | `32×32`，与现有物品图标同规格 | `ItemSlot`/`ItemIconLarge` 图标缺失/未知物品兜底（UX Spec 已要求） | **建议尽快补齐**——这不是"锦上添花"而是 UX Spec 明确的错误兜底要求；在补齐前，ui-programmer 可临时用 `cmd_cell_9p` 内放一个 `Label` 文本 `"?"`（字号 32，`COL_DIM`）作为零资产占位 |

---

## 附：本文档新增的语义色（供 ui-programmer 统一定义）

```gdscript
# 羊皮纸侧页专属色（与战斗 UI COL_* 正交，互不影响）
const COL_PARCHMENT_BG     = Color(0.776, 0.706, 0.557)   # 羊皮纸背景
const COL_PARCHMENT_BORDER = Color(0.541, 0.471, 0.337)   # 羊皮纸边框/分隔线
const COL_INK              = Color(0.231, 0.165, 0.094)   # 墨水棕（标题/正文）
const COL_INK_LIGHT        = Color(0.345, 0.262, 0.171)   # 浅墨水棕（DescriptionText）
const COL_PARCHMENT_ACCENT = Color(0.62, 0.30, 0.16)      # 赭红强调色（数值/已装备/ActionMenu选中）
const COL_PARCHMENT_DIM    = Color(0.55, 0.50, 0.42)      # 暖色调置灰（未装备符号/禁用菜单项）
```
