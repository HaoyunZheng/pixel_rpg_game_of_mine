class_name InventoryWidgets
extends RefCounted
## 背包 UI 无状态视图工厂 —— 纯静态函数：StyleBox / 占位控件 / 调色板 / 文案常量。
## 与 BattleWidgets.gd 同一模式：集中视觉常量与切片路径，控制器（InventoryUI）只引用本类常量与工厂函数。
## 全部中文 UI 字符串集中定义于本文件，便于未来本地化抽取。

# ── 切片资源路径（复用战斗 UI 资产，零新增）──
const ASSET_DIR_BATTLE: String = "res://assets/ui/battle/"
const ASSET_DIR_ITEMS: String = "res://assets/ui/items/"
const TEX_PANEL_CENTRAL: String = ASSET_DIR_BATTLE + "panel_central_9p.png"
const TEX_CMD_CELL: String = ASSET_DIR_BATTLE + "cmd_cell_9p.png"
const TEX_AVATAR_FRAME: String = ASSET_DIR_BATTLE + "avatar_frame_9p.png"
const TEX_CHIP: String = ASSET_DIR_BATTLE + "chip_status.png"

# ── 背包专属手绘资产（账簿底图 + 离线生成的版式数据层）──
const ASSET_DIR_INV: String = "res://assets/ui/inventory/"
const TEX_BG_CLEAN: String = ASSET_DIR_INV + "bg_inventory_field_ledger_clean.png"  # clean-plate（铲掉画死的静态标签）
const LAYOUT_PATH: String = ASSET_DIR_INV + "layout.json"                            # tools/ui_layout_extract.py 产出
const STAGE_W: float = 1664.0   # 背景图原生宽（Stage 锁定坐标系，控件与底图同坐标）
const STAGE_H: float = 936.0
const TAB_DIR: String = ASSET_DIR_INV + "tabs/"
# 分类标签 banner 前缀（按手绘色序 赭/灰/棕/紫/橄榄，与 CATEGORY_ORDER 一一对应；_selected/_unselected 两态）
const TAB_TEX_PREFIX: Array[String] = [
	"category_tab_01_ochre",
	"category_tab_02_gray",
	"category_tab_03_brown",
	"category_tab_04_purple",
	"category_tab_05_olive",
]

# ── 战斗 UI 基线配色（复用，§0）──
const COL_BONE: Color = Color(0.847, 0.812, 0.753)
const COL_GOLD: Color = Color(0.902, 0.753, 0.290)
const COL_DIM: Color = Color(0.45, 0.43, 0.40)

# ── 羊皮纸侧页专属语义色（visual-spec 附录）──
const COL_PARCHMENT_BG: Color = Color(0.776, 0.706, 0.557)
const COL_PARCHMENT_BORDER: Color = Color(0.541, 0.471, 0.337)
const COL_INK: Color = Color(0.231, 0.165, 0.094)
const COL_INK_LIGHT: Color = Color(0.345, 0.262, 0.171)
const COL_PARCHMENT_ACCENT: Color = Color(0.62, 0.30, 0.16)
const COL_PARCHMENT_DIM: Color = Color(0.55, 0.50, 0.42)

# ── 尺寸常量 ──
const ITEM_ICON_SIZE: int = 32          # 物品图标原生尺寸（决策②：默认原生 32px，仅改此处统一 ×2）
const ITEM_ICON_LARGE_SIZE: int = 64    # 侧页大图标（×2）
const AVATAR_HOLDER_SIZE: int = 88      # avatar_frame_9p 整体尺寸（64 内容 + 12*2 边框）
const AVATAR_BORDER_PX: int = 12
const ITEM_SLOT_SIZE: int = 96
const ITEM_SLOT_NAME_HEIGHT: int = 24
const GRID_COLUMNS: int = 5
const PANEL_WIDTH: int = 1600
const PANEL_HEIGHT: int = 880
const PARCHMENT_WIDTH: int = 528
const TAB_HEIGHT_NORMAL: int = 96
const TAB_HEIGHT_SELECTED: int = 112

# ── 物品分类显示名（CategoryTab / CategoryChip 共用）──
const CATEGORY_NAMES: Dictionary = {
	ItemData.ItemCategory.WEAPON: "武器",
	ItemData.ItemCategory.ARMOR: "防具",
	ItemData.ItemCategory.ACCESSORY: "饰品",
	ItemData.ItemCategory.CONSUMABLE: "消耗品",
	ItemData.ItemCategory.KEY_ITEM: "重要物品",
}

# 分类标签的固定显示顺序（与 ItemCategory 枚举顺序一致）
const CATEGORY_ORDER: Array[ItemData.ItemCategory] = [
	ItemData.ItemCategory.WEAPON,
	ItemData.ItemCategory.ARMOR,
	ItemData.ItemCategory.ACCESSORY,
	ItemData.ItemCategory.CONSUMABLE,
	ItemData.ItemCategory.KEY_ITEM,
]

# 装备槽位映射（与 GameData.equipment 字典键一致）
const EQUIP_SLOT_BY_CATEGORY: Dictionary = {
	ItemData.ItemCategory.WEAPON: "weapon",
	ItemData.ItemCategory.ARMOR: "armor",
	ItemData.ItemCategory.ACCESSORY: "accessory",
}

# ── UI 文案（全部中文字符串集中于此，未来本地化抽取入口）──
const STR_EMPTY_CATEGORY: String = "此分类暂无物品"
const STR_EMPTY_INVENTORY_TITLE: String = "行囊空空如也"
const STR_EMPTY_INVENTORY_BODY: String = "什么都没有。"
const STR_UNKNOWN_ITEM_NAME: String = "未知物品"
const STR_UNKNOWN_ITEM_DESC: String = "无法辨认的东西。"
const STR_NO_ACTION: String = "（无可执行操作）"
const STR_ACTION_USE: String = "使用"
const STR_ACTION_EQUIP: String = "装备"
const STR_ACTION_UNEQUIP: String = "卸下"
const STR_ACTION_DISCARD: String = "丢弃"
const STR_EQUIP_STATUS_PREFIX: String = "状态："
const STR_EQUIP_STATUS_EQUIPPED: String = "◆ 已装备"
const STR_EQUIP_STATUS_UNEQUIPPED: String = "● 未装备"
const STR_STAT_HEAL_HP: String = "效果： HP +%d"
const STR_STAT_HEAL_MP: String = "效果： MP +%d"
const STR_STAT_DAMAGE: String = "效果： 伤害 %d"
const STR_STAT_ATTACK: String = "攻击力 +%d"
const STR_STAT_DEFENSE: String = "防御力 +%d"
const STR_DISCARD_TITLE: String = "确定丢弃"
const STR_DISCARD_BODY_FMT: String = "%s ×%d？"
const STR_DISCARD_HINT: String = "[Z] 确认　[X] 取消"
const STR_PLACEHOLDER_ICON: String = "?"
const STR_QUANTITY_FMT: String = "×%d"

# ───────────────────────────────────────────── 切片加载（缺失回退 null）

static func load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Texture2D

## 分类标签 banner 贴图：category_index 0~4 + 选中态 → 对应 PNG（缺失回退 null）。
static func load_tab_texture(category_index: int, selected: bool) -> Texture2D:
	if category_index < 0 or category_index >= TAB_TEX_PREFIX.size():
		return null
	var suffix: String = "_selected.png" if selected else "_unselected.png"
	return load_tex(TAB_DIR + TAB_TEX_PREFIX[category_index] + suffix)

## 版式数据层：读 layout.json（井格/标签锚点/页矩形/页内分区，背景图原生像素坐标）。
## 由 tools/ui_layout_extract.py 离线生成；缺失返回空字典（调用方应回退或报错）。
static func load_layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

# ───────────────────────────────────────────── ① 整体外框 / 遮罩

## 主面板外框：暖色皮革书封（深棕 + 黑边 + 圆角），承载顶部书签栏与左右双栏。
static func make_panel_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.137, 0.105, 0.086)        # 深棕皮革
	sb.border_color = Color(0.043, 0.031, 0.024)    # 近黑书脊边
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.set_content_margin_all(24)
	return sb

## 左侧网格底板：比书封更深的内陷皮革（让物品格在其上分明）。
static func make_grid_panel_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.082, 0.063, 0.055)
	sb.border_color = Color(0.043, 0.031, 0.024)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	return sb

# ───────────────────────────────────────────── ② CategoryTab（书签标签，§2）

## CategoryTab StyleBox：选中态"拉出/凸起"——暗金底+金边（顶/左/右）；未选中态下沉暗紫灰+黑细边。
static func make_tab_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if selected:
		sb.bg_color = COL_GOLD.darkened(0.55)
		sb.border_color = COL_GOLD
		sb.border_width_top = 4
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_bottom = 0
	else:
		sb.bg_color = Color(0.16, 0.145, 0.18)
		sb.border_color = Color(0.04, 0.03, 0.055)
		sb.set_border_width_all(2)
	return sb

# ───────────────────────────────────────────── ③ ItemSlot（行囊格，§3）

enum SlotState { DEFAULT, FOCUSED, SELECTED }

## ItemSlot 三态 StyleBox：cmd_cell_9p 9-patch 叠加边框颜色/粗细随状态切换。
## 决策③：预先构建三份 StyleBoxTexture 实例，控制器用 add_theme_stylebox_override("panel", ...) 切换。
static func make_item_slot_style(state: SlotState) -> StyleBox:
	var tex: Texture2D = load_tex(TEX_CMD_CELL)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 12
		sb.texture_margin_top = 12
		sb.texture_margin_right = 12
		sb.texture_margin_bottom = 12
		sb.content_margin_left = 12
		sb.content_margin_top = 12
		sb.content_margin_right = 12
		sb.content_margin_bottom = 12
		match state:
			SlotState.FOCUSED:
				sb.modulate_color = Color(1, 1, 1, 1)
				sb.draw_center = true
			_:
				pass
		return sb
	# 回退：纯色平框
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.24, 0.22, 0.27)
	flat.border_color = Color(0.04, 0.03, 0.055)
	flat.set_border_width_all(4)
	flat.set_content_margin_all(12)
	return flat

## 焦点/选中态描边 overlay：透明背景 + 描边色/宽度，叠加在 ItemSlot 之上的子 Panel。
## 默认态：无 overlay（返回 null，调用方应隐藏该子节点）。
static func make_item_slot_focus_overlay(state: SlotState) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	match state:
		SlotState.FOCUSED:
			sb.border_color = COL_BONE
			sb.set_border_width_all(2)
		SlotState.SELECTED:
			sb.border_color = COL_GOLD
			sb.set_border_width_all(4)
		_:
			sb.border_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(0)
	return sb

# ───────────────────────────────────────────── ④ EmptySlotGhost / Hint 文本

## EmptySlotGhost：cmd_cell_9p 皮肤 + 35% 整体不透明度 + 居中 ".." 占位文本。
static func make_empty_slot_ghost() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(ITEM_SLOT_SIZE, ITEM_SLOT_SIZE)
	panel.add_theme_stylebox_override("panel", make_item_slot_style(SlotState.DEFAULT))
	panel.modulate = Color(1, 1, 1, 0.35)
	panel.focus_mode = Control.FOCUS_NONE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "··"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_DIM)
	label.add_theme_constant_override("outline_size", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel

static func make_empty_category_hint() -> Label:
	var label := Label.new()
	label.text = STR_EMPTY_CATEGORY
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_DIM)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## EmptyDetailHint：标题"行囊空空如也" + 副文本"什么都没有。"，垂直居中。
static func make_empty_detail_hint() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = STR_EMPTY_INVENTORY_TITLE
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_INK)
	title.add_theme_constant_override("outline_size", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var body := Label.new()
	body.text = STR_EMPTY_INVENTORY_BODY
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", COL_INK_LIGHT)
	body.add_theme_constant_override("outline_size", 0)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)

	return box

# ───────────────────────────────────────────── 图标缺失兜底（"?" 占位）

## 统一占位图标：32px "?" 文本，COL_DIM，无描边（§ 图标缺失兜底，决策：临时用 Label "?"）。
static func make_placeholder_icon(size_px: int = ITEM_ICON_SIZE) -> Control:
	var label := Label.new()
	label.text = STR_PLACEHOLDER_ICON
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", COL_DIM)
	label.add_theme_constant_override("outline_size", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(size_px, size_px)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## 物品图标控件：item 为 null 或 icon 缺失时返回占位 "?"；否则原生尺寸居中显示。
static func make_item_icon(item: ItemData, size_px: int = ITEM_ICON_SIZE) -> Control:
	var tex: Texture2D = null
	if item != null:
		tex = item.icon
	if tex == null:
		return make_placeholder_icon(size_px)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size_px, size_px)
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# ───────────────────────────────────────────── ⑤ 羊皮纸侧页（§5）
# 注：混合方案下羊皮纸页背景由手绘账簿底图提供，不再程序化生成（make_parchment_style 已移除）。

## ItemIconLarge 外框：复用 avatar_frame_9p（88×88，64px 内容区，§5.2）。
static func make_avatar_frame_style() -> StyleBox:
	var tex: Texture2D = load_tex(TEX_AVATAR_FRAME)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = AVATAR_BORDER_PX
		sb.texture_margin_top = AVATAR_BORDER_PX
		sb.texture_margin_right = AVATAR_BORDER_PX
		sb.texture_margin_bottom = AVATAR_BORDER_PX
		return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.10, 0.09, 0.12)
	flat.border_color = Color(0.04, 0.03, 0.055)
	flat.set_border_width_all(AVATAR_BORDER_PX)
	return flat

## CategoryChip StyleBox：复用 chip_status.png（14×9 小尺寸，§5.4）。
static func make_chip_style() -> StyleBox:
	var tex: Texture2D = load_tex(TEX_CHIP)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 3
		sb.texture_margin_top = 3
		sb.texture_margin_right = 3
		sb.texture_margin_bottom = 3
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.30, 0.22, 0.42)
	flat.set_content_margin_all(6)
	return flat

## Divider：2px 半透明棕色细线（§5.5）。
static func make_divider() -> ColorRect:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(0, 2)
	rect.color = Color(COL_PARCHMENT_BORDER.r, COL_PARCHMENT_BORDER.g, COL_PARCHMENT_BORDER.b, 0.6)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# ───────────────────────────────────────────── ⑥ ActionMenu（§6）

## ActionMenu 容器外框：半透明米色"便签"叠层。
static func make_action_menu_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.706, 0.631, 0.475, 0.6)
	sb.border_color = COL_PARCHMENT_BORDER
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.set_content_margin_all(8)
	return sb

# ───────────────────────────────────────────── ⑦ DiscardConfirmDialog（§7）

## 弹窗背景：复用 panel_central_9p（与外框同源资产，560×240 小尺寸实例）。
static func make_dialog_style() -> StyleBox:
	return make_panel_style()

# ───────────────────────────────────────────── 数值/分类辅助查表

static func get_category_name(category: ItemData.ItemCategory) -> String:
	return CATEGORY_NAMES.get(category, STR_UNKNOWN_ITEM_NAME)

## 生成 StatBlock 行文案（标签部分用 COL_INK，数值部分用 COL_PARCHMENT_ACCENT；
## 调用方按返回的 (label, value) 元组分别上色）。
static func get_stat_lines(item: ItemData) -> Array:
	var lines: Array = []
	match item.category:
		ItemData.ItemCategory.CONSUMABLE:
			match item.effect_type:
				ItemData.EffectType.HEAL_HP:
					lines.append(STR_STAT_HEAL_HP % item.effect_value)
				ItemData.EffectType.HEAL_MP:
					lines.append(STR_STAT_HEAL_MP % item.effect_value)
				ItemData.EffectType.DAMAGE:
					lines.append(STR_STAT_DAMAGE % item.effect_value)
				_:
					pass
		ItemData.ItemCategory.WEAPON:
			if item.attack_bonus != 0:
				lines.append(STR_STAT_ATTACK % item.attack_bonus)
		ItemData.ItemCategory.ARMOR, ItemData.ItemCategory.ACCESSORY:
			if item.defense_bonus != 0:
				lines.append(STR_STAT_DEFENSE % item.defense_bonus)
			if item.attack_bonus != 0:
				lines.append(STR_STAT_ATTACK % item.attack_bonus)
		_:
			pass
	return lines

## 是否为装备类（武器/防具/饰品）——决定是否显示 EquipStatusBadge。
static func is_equipment_category(category: ItemData.ItemCategory) -> bool:
	return EQUIP_SLOT_BY_CATEGORY.has(category)
