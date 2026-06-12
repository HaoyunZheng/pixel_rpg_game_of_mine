# Interaction Pattern Library

> **Status**: Living Document（首版）
> **Author**: ui-programmer + ux-designer
> **Last Updated**: 2026-06-12
> **来源**: 背包界面（Inventory）实现落地的首批 7 个模式（design/ux/inventory.md + design/art/inventory-visual-spec.md）

---

## Overview

收录已实现并验收过的可复用交互模式。新屏幕设计时**先查此库再发明新模式**；实现中产生的新模式须在标记实现完成前补录至此。

---

## Pattern Catalog

| # | 模式名 | 一句话描述 |
|---|---|---|
| 1 | 书签标签（CategoryTab） | 顶部分类标签，选中态"拉出/凸起"+金色高亮，未选中下沉降饱和 |
| 2 | 命令格物品格（ItemSlot） | cmd_cell_9p 格子 + 焦点（细骨白边）/选中（粗金边）双态描边 |
| 3 | 空槽占位（EmptySlotGhost） | 35% 不透明度格子 + "··" 占位 —— **已定义未使用** |
| 4 | 物品数值条目（StatBlock） | 羊皮纸上"标签墨水棕 + 数值赭红"两段着色数值行 |
| 5 | 装备状态徽章（EquipStatusBadge） | "状态：● 未装备 / ◆ 已装备" 符号+颜色双通道状态 |
| 6 | 侧页内嵌操作菜单（ActionMenu） | 详情侧页底部展开的动态选项列表，▸ 前缀+赭红选中 |
| 7 | 丢弃二次确认（DiscardConfirmDialog） | 居中模态小弹窗，Z/X 二键确认，主面板变暗冻结 |

---

## Patterns

### 1. 书签标签（CategoryTab）
- **适用**：横向分类导航（背包分类、未来图鉴/设置页签）。
- **要点**（visual-spec §2）：选中态暗金底 `COL_GOLD.darkened(0.55)` + 金边 4px（顶/左/右，底 0）+ 金字描边 2；未选中暗紫灰 + 黑细边 2px + `COL_DIM` 无描边。"拉出"效果用 **size_flags 实现**（栏高=选中高 64，未选中 `SIZE_SHRINK_END` 沉底 56）——HBoxContainer 会重置手动 position.y，勿用位移 hack。角标 `(N)` 直接拼入标签文本。
- **实现**：`InventoryWidgets.make_tab_style()` / `InventoryUI._build_tabs()`、`_update_tab_styles()`

### 2. 命令格物品格（ItemSlot）
- **适用**：网格化可聚焦物件（背包格、未来商店/仓库格）。
- **要点**（visual-spec §3）：96×96 `cmd_cell_9p`（texture_margin 12）；三态描边 overlay 子 Panel 切换 StyleBox——默认无边/焦点骨白 2px/选中金 4px；图标原生 32px 居中（Nearest 下禁非整数缩放）；数量角标右下仅消耗品类；`usable=false` 仅图标 `modulate.a=0.5`（边框与文字不降）。
- **实现**：`InventoryWidgets.make_item_slot_style()`、`make_item_slot_focus_overlay()` / `InventoryUI._build_item_slot()`、`_update_slot_styles()`

### 3. 空槽占位（EmptySlotGhost）⚠️ 已定义未使用
- **适用**：需要呈现"固定容量"感的网格空位。当前背包网格按内容自适应行数，未用到。
- **要点**（visual-spec §4）：cmd_cell 皮肤整体 `modulate 0.35` + 居中 "··"，不可聚焦（FOCUS_NONE），导航跳过。
- **实现**：`InventoryWidgets.make_empty_slot_ghost()`（工厂已备，无调用方）

### 4. 物品数值条目（StatBlock）
- **适用**：浅色背景上的"标签+数值"信息行。
- **要点**（visual-spec §5.7）：18px；标签 `COL_INK` / 数值 `COL_PARCHMENT_ACCENT`（赭红——金色在米黄背景对比度不足，浅色面板上的强调色一律用赭红）；按最后一个空格拆分两段着色。
- **实现**：`InventoryWidgets.get_stat_lines()` / `InventoryUI._make_stat_line()`

### 5. 装备状态徽章（EquipStatusBadge）
- **适用**：二元状态展示（已装备/未装备，未来可扩展已学会/未学会等）。
- **要点**（visual-spec §5.8）：符号+文字双通道（不依赖颜色）："● 未装备" `COL_PARCHMENT_DIM` / "◆ 已装备" `COL_PARCHMENT_ACCENT`，文字部分恒 `COL_INK` 18px。
- **实现**：`InventoryUI._make_equip_status_badge()`

### 6. 侧页内嵌操作菜单（ActionMenu）
- **适用**：在详情面板内就地展开的上下文操作（背包物品操作，未来商店买卖确认）。
- **要点**（visual-spec §6）：半透明米色"便签"底（`Color(0.706,0.631,0.475,0.6)` + 2px 棕边）；选项按数据标志动态生成；选中 `▸ ` 前缀+赭红、未选中墨水棕、禁用 `COL_PARCHMENT_DIM`；展开收起 Tween ~100ms ease-out/in（`clip_contents` + `custom_minimum_size:y`）；暂停下 Tween 需 `TWEEN_PAUSE_PROCESS`。
- **实现**：`InventoryWidgets.make_action_menu_style()` / `InventoryUI._build_action_menu()`、`_update_menu_selection()`

### 7. 丢弃二次确认（DiscardConfirmDialog）
- **适用**：不可逆操作的模态确认（丢弃，未来覆盖存档/放弃任务）。
- **要点**（visual-spec §7）：560×240 `panel_central_9p` 居中；深色体系文案（标题 18px 骨白/对象 22px 金/按键提示 18px 骨白描边）；弹出 scale 0.8→1.0+淡入 ~120ms；弹出期间主面板 `modulate(0.6,0.6,0.65)` 示意输入冻结；仅 Z 确认/X 取消。
- **实现**：`InventoryUI._open_discard_dialog()`、`_confirm_discard()`、`_cancel_discard()`

---

## Gaps & Patterns Needed

- 通用控件模式（按钮/滑条/下拉/Toast 等）尚未收录——待设置页/标题画面等屏幕落地时补充。
- 战斗 UI 既有模式（中央框二级选项、命令栏、行动顺序 pip 条等）尚未回填入库——建议随 combat-screen.md 规格落地时一并收录。

## Open Questions

- EmptySlotGhost 是否在"固定容量背包"演进时启用，或移除工厂函数（避免死代码）。
