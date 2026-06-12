class_name InventoryUI
extends CanvasLayer
## 背包界面控制器（design/ux/inventory.md + design/art/inventory-visual-spec.md）。
##
## - 暂停式覆盖层：open() 时 get_tree().paused = true，自身 process_mode = WHEN_PAUSED 保证仍可响应输入。
## - 状态机：PREVIEW（预览/导航）/ ACTION_MENU（操作菜单展开）/ DISCARD_CONFIRM（丢弃二次确认）。
## - 单一写入者：所有数据变更通过 GameData.use_item / equip_item / unequip_item / discard_item 调用，
##   UI 只监听 4 个信号刷新显示，不直接改 GameData.inventory / equipment。
## - 纯键盘：方向键导航 + Z 确认 + X 取消/返回，逐级 X：弹窗→菜单→预览→关闭。

const CONFIRM_KEY: Key = KEY_Z
const CANCEL_KEY: Key = KEY_X
const FADE_DURATION: float = 0.15
const MENU_EXPAND_DURATION: float = 0.1
const DIALOG_POPUP_DURATION: float = 0.12
const DISCARD_FADE_DURATION: float = 0.15
const ACTION_MENU_ROW_HEIGHT: int = 26

enum UIState { PREVIEW, ACTION_MENU, DISCARD_CONFIRM }

# ── 节点引用 ──
@onready var _mask: ColorRect = $Mask
@onready var _root_control: Control = $Root
@onready var _main_panel: PanelContainer = $Root/MainPanel
@onready var _tab_bar: HBoxContainer = $Root/MainPanel/Layout/TabBar
@onready var _grid_scroll: ScrollContainer = $Root/MainPanel/Layout/Body/GridArea/GridScroll
@onready var _item_grid: GridContainer = $Root/MainPanel/Layout/Body/GridArea/GridScroll/ItemGrid
@onready var _grid_area: Control = $Root/MainPanel/Layout/Body/GridArea
@onready var _parchment: PanelContainer = $Root/MainPanel/Layout/Body/Parchment
@onready var _parchment_content: VBoxContainer = $Root/MainPanel/Layout/Body/Parchment/Content
@onready var _dialog_layer: Control = $DialogLayer
@onready var _dialog_panel: PanelContainer = $DialogLayer/Dialog

var _state: UIState = UIState.PREVIEW
var _category_index: int = 0
var _focus_index_by_category: Dictionary = {}   # category(int) -> focus index
var _menu_index: int = 0
var _is_open: bool = false

# 当前分类下的 (item, count) 列表缓存
var _current_items: Array = []
# ActionMenu 选项缓存：{label, action(Callable), disabled}
var _menu_options: Array = []
var _action_menu_box: PanelContainer = null
var _pending_discard_item: ItemData = null
var _pending_discard_count: int = 0

# 网格中的 ItemSlot 节点缓存（按索引）
var _slot_nodes: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 10
	visible = false
	_mask.color = Color(0.05, 0.045, 0.06, 0.55)
	_mask.modulate.a = 0.0
	_root_control.modulate.a = 0.0
	_dialog_layer.visible = false
	_main_panel.add_theme_stylebox_override("panel", InventoryWidgets.make_panel_style())
	_parchment.add_theme_stylebox_override("panel", InventoryWidgets.make_parchment_style())
	_dialog_panel.add_theme_stylebox_override("panel", InventoryWidgets.make_dialog_style())
	_item_grid.columns = InventoryWidgets.GRID_COLUMNS

	GameData.item_used.connect(_on_inventory_changed)
	GameData.item_equipped.connect(_on_inventory_changed)
	GameData.item_unequipped.connect(_on_inventory_changed)
	GameData.item_discarded.connect(_on_inventory_changed)

	_build_tabs()
	_refresh_grid()
	_refresh_detail()


# ───────────────────────────────────────────── 打开 / 关闭

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_state = UIState.PREVIEW
	visible = true
	get_tree().paused = true
	_refresh_grid()
	_refresh_detail()
	_focus_current_slot()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_mask, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_root_control, "modulate:a", 1.0, FADE_DURATION)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_mask, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_property(_root_control, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
	visible = false
	get_tree().paused = false


func is_open() -> bool:
	return _is_open


# ───────────────────────────────────────────── 分类标签（① CategoryTab）

func _build_tabs() -> void:
	for child in _tab_bar.get_children():
		child.queue_free()
	for category in InventoryWidgets.CATEGORY_ORDER:
		var count: int = _count_item_kinds(category)
		var label := Label.new()
		label.text = "%s(%d)" % [InventoryWidgets.get_category_name(category), count]
		label.add_theme_font_size_override("font_size", 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var tab := PanelContainer.new()
		tab.custom_minimum_size = Vector2(0, InventoryWidgets.TAB_HEIGHT_NORMAL)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(label)
		_tab_bar.add_child(tab)
	# 书签栏固定为选中态高度：未选中标签沉底对齐，选中标签占满整高，
	# 顶边比未选中高出 8px，形成"书签拉出/凸起"效果（HBox 会重置手动 position，不能用 position.y 实现）
	_tab_bar.custom_minimum_size = Vector2(0, InventoryWidgets.TAB_HEIGHT_SELECTED)
	_update_tab_styles()


func _update_tab_styles() -> void:
	var tabs: Array = _tab_bar.get_children()
	for i in range(tabs.size()):
		var tab: PanelContainer = tabs[i]
		var label: Label = tab.get_child(0)
		var selected: bool = i == _category_index
		tab.add_theme_stylebox_override("panel", InventoryWidgets.make_tab_style(selected))
		if selected:
			tab.custom_minimum_size = Vector2(0, InventoryWidgets.TAB_HEIGHT_SELECTED)
			tab.size_flags_vertical = Control.SIZE_FILL
			label.add_theme_color_override("font_color", InventoryWidgets.COL_GOLD)
			label.add_theme_constant_override("outline_size", 2)
		else:
			tab.custom_minimum_size = Vector2(0, InventoryWidgets.TAB_HEIGHT_NORMAL)
			tab.size_flags_vertical = Control.SIZE_SHRINK_END
			label.add_theme_color_override("font_color", InventoryWidgets.COL_DIM)
			label.add_theme_constant_override("outline_size", 0)


func _count_item_kinds(category: ItemData.ItemCategory) -> int:
	var n := 0
	for slot in GameData.inventory:
		if slot.item != null and slot.item.category == category:
			n += 1
	return n


# ───────────────────────────────────────────── 主背包网格（② ItemGrid / ItemSlot）

func _current_category() -> ItemData.ItemCategory:
	return InventoryWidgets.CATEGORY_ORDER[_category_index]


func _gather_current_items() -> Array:
	var items: Array = []
	var category: ItemData.ItemCategory = _current_category()
	for slot in GameData.inventory:
		if slot.item != null and slot.item.category == category:
			items.append(slot)
	return items


func _refresh_grid() -> void:
	for child in _item_grid.get_children():
		child.queue_free()
	_slot_nodes.clear()

	_current_items = _gather_current_items()

	# 无论后续走哪个分支，先清掉上一次的空分类提示，避免连续空分类切换时叠加
	if _grid_area.has_meta("empty_hint"):
		var existing_hint = _grid_area.get_meta("empty_hint")
		if existing_hint != null and is_instance_valid(existing_hint):
			existing_hint.queue_free()
		_grid_area.remove_meta("empty_hint")

	if _current_items.is_empty():
		_grid_scroll.visible = false
		var hint := InventoryWidgets.make_empty_category_hint()
		hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_grid_area.add_child(hint)
		_grid_area.set_meta("empty_hint", hint)
		return
	_grid_scroll.visible = true

	for slot in _current_items:
		_item_grid.add_child(_build_item_slot(slot))

	# 钳制焦点索引到合法范围
	var focus_idx: int = _get_focus_index()
	focus_idx = clampi(focus_idx, 0, _current_items.size() - 1)
	_set_focus_index(focus_idx)
	_update_slot_styles()


func _build_item_slot(slot: Dictionary) -> Control:
	var item: ItemData = slot.item
	var count: int = slot.count

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(InventoryWidgets.ITEM_SLOT_SIZE, InventoryWidgets.ITEM_SLOT_SIZE)
	panel.add_theme_stylebox_override("panel", InventoryWidgets.make_item_slot_style(InventoryWidgets.SlotState.DEFAULT))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.focus_mode = Control.FOCUS_NONE

	# 焦点/选中描边 overlay（默认隐藏，_update_slot_styles 控制）
	var overlay := Panel.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_stylebox_override("panel", InventoryWidgets.make_item_slot_focus_overlay(InventoryWidgets.SlotState.DEFAULT))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.name = "Overlay"
	panel.add_child(overlay)

	# 图标（usable=false 时 50% 不透明度，仅图标本身）
	var icon := InventoryWidgets.make_item_icon(item, InventoryWidgets.ITEM_ICON_SIZE)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if item != null and not item.usable:
		icon.modulate.a = 0.5
	panel.add_child(icon)

	# 数量角标（仅 CONSUMABLE 显示，§3）
	if item != null and item.category == ItemData.ItemCategory.CONSUMABLE:
		var qty := Label.new()
		qty.text = InventoryWidgets.STR_QUANTITY_FMT % count
		qty.add_theme_font_size_override("font_size", 14)
		qty.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
		qty.add_theme_constant_override("outline_size", 2)
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.offset_left = -40
		qty.offset_top = -22
		qty.offset_right = -4
		qty.offset_bottom = -4
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(qty)

	# 容器：格子 + 名称 Label
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.add_child(panel)

	var name_label := Label.new()
	name_label.text = item.display_name if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_NAME
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(InventoryWidgets.ITEM_SLOT_SIZE, InventoryWidgets.ITEM_SLOT_NAME_HEIGHT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(name_label)

	_slot_nodes.append(panel)
	return wrap


func _update_slot_styles() -> void:
	var focus_idx: int = _get_focus_index()
	for i in range(_slot_nodes.size()):
		var panel: Panel = _slot_nodes[i]
		if not is_instance_valid(panel):
			continue
		var overlay: Panel = panel.get_node_or_null("Overlay")
		if overlay == null:
			continue
		var slot_state: InventoryWidgets.SlotState = InventoryWidgets.SlotState.DEFAULT
		if i == focus_idx:
			slot_state = InventoryWidgets.SlotState.SELECTED if _state != UIState.PREVIEW else InventoryWidgets.SlotState.FOCUSED
		overlay.add_theme_stylebox_override("panel", InventoryWidgets.make_item_slot_focus_overlay(slot_state))


# ───────────────────────────────────────────── 焦点索引（每分类记忆）

func _get_focus_index() -> int:
	return _focus_index_by_category.get(_category_index, 0)


func _set_focus_index(idx: int) -> void:
	_focus_index_by_category[_category_index] = idx


func _focused_slot() -> Dictionary:
	var idx: int = _get_focus_index()
	if idx < 0 or idx >= _current_items.size():
		return {}
	return _current_items[idx]


func _focus_current_slot() -> void:
	_update_slot_styles()


# ───────────────────────────────────────────── 详情侧页（③ 羊皮纸）

func _refresh_detail() -> void:
	for child in _parchment_content.get_children():
		child.queue_free()
	_action_menu_box = null

	if GameData.inventory.is_empty():
		_parchment_content.add_child(InventoryWidgets.make_empty_detail_hint())
		return

	var slot: Dictionary = _focused_slot()
	if slot.is_empty():
		# 当前分类为空（但背包整体非空）：显示空分类侧页提示
		_parchment_content.add_child(InventoryWidgets.make_empty_detail_hint())
		return

	var item: ItemData = slot.item
	var count: int = slot.count
	_build_detail_content(item, count)

	if _state == UIState.ACTION_MENU:
		_build_action_menu(item, count)


func _build_detail_content(item: ItemData, count: int) -> void:
	# ItemIconLarge（避免空指针：item 可能为 null → 兜底占位 + "未知物品"）
	var icon_holder := PanelContainer.new()
	icon_holder.custom_minimum_size = Vector2(InventoryWidgets.AVATAR_HOLDER_SIZE, InventoryWidgets.AVATAR_HOLDER_SIZE)
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_holder.add_theme_stylebox_override("panel", InventoryWidgets.make_avatar_frame_style())
	var icon := InventoryWidgets.make_item_icon(item, InventoryWidgets.ITEM_ICON_LARGE_SIZE)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon_holder.add_child(icon)
	var icon_row := CenterContainer.new()
	icon_row.add_child(icon_holder)
	_parchment_content.add_child(icon_row)

	# ItemNameLabel
	var display_name: String = item.display_name if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_NAME
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	name_label.add_theme_constant_override("outline_size", 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parchment_content.add_child(name_label)

	# CategoryChip（独立一行靠右对齐）
	if item != null:
		var chip_row := HBoxContainer.new()
		chip_row.alignment = BoxContainer.ALIGNMENT_END
		var chip := Label.new()
		chip.text = InventoryWidgets.get_category_name(item.category)
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
		chip.add_theme_constant_override("outline_size", 1)
		chip.add_theme_stylebox_override("normal", InventoryWidgets.make_chip_style())
		chip_row.add_child(chip)
		_parchment_content.add_child(chip_row)

	# StatBlock
	if item != null:
		var stat_lines: Array = InventoryWidgets.get_stat_lines(item)
		if not stat_lines.is_empty():
			_parchment_content.add_child(InventoryWidgets.make_divider())
			for line in stat_lines:
				_parchment_content.add_child(_make_stat_line(line))

	_parchment_content.add_child(InventoryWidgets.make_divider())

	# DescriptionText
	var desc_text: String = item.description if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_DESC
	var desc_scroll := ScrollContainer.new()
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var desc_label := Label.new()
	desc_label.text = desc_text
	desc_label.add_theme_font_size_override("font_size", 16)
	desc_label.add_theme_color_override("font_color", InventoryWidgets.COL_INK_LIGHT)
	desc_label.add_theme_constant_override("outline_size", 0)
	desc_label.add_theme_constant_override("line_spacing", 6)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_scroll.add_child(desc_label)
	_parchment_content.add_child(desc_scroll)

	# EquipStatusBadge（仅装备类）
	if item != null and InventoryWidgets.is_equipment_category(item.category):
		_parchment_content.add_child(InventoryWidgets.make_divider())
		_parchment_content.add_child(_make_equip_status_badge(item))


func _make_stat_line(text: String) -> Control:
	# text 形如 "效果： HP +30" / "攻击力 +4" —— 拆分标签/数值两段着色（按第一个空白后分割数值段）。
	var row := HBoxContainer.new()
	var split_idx: int = text.rfind(" ")
	var label_part: String = text
	var value_part: String = ""
	if split_idx != -1:
		label_part = text.substr(0, split_idx + 1)
		value_part = text.substr(split_idx + 1)

	var label_node := Label.new()
	label_node.text = label_part
	label_node.add_theme_font_size_override("font_size", 18)
	label_node.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	label_node.add_theme_constant_override("outline_size", 0)
	row.add_child(label_node)

	if not value_part.is_empty():
		var value_node := Label.new()
		value_node.text = value_part
		value_node.add_theme_font_size_override("font_size", 18)
		value_node.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT)
		value_node.add_theme_constant_override("outline_size", 0)
		row.add_child(value_node)

	return row


func _make_equip_status_badge(item: ItemData) -> Control:
	var equipped: bool = GameData.is_item_equipped(item.id)
	var row := HBoxContainer.new()

	var prefix := Label.new()
	prefix.text = InventoryWidgets.STR_EQUIP_STATUS_PREFIX
	prefix.add_theme_font_size_override("font_size", 18)
	prefix.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	prefix.add_theme_constant_override("outline_size", 0)
	row.add_child(prefix)

	var status := Label.new()
	status.text = InventoryWidgets.STR_EQUIP_STATUS_EQUIPPED if equipped else InventoryWidgets.STR_EQUIP_STATUS_UNEQUIPPED
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT if equipped else InventoryWidgets.COL_PARCHMENT_DIM)
	status.add_theme_constant_override("outline_size", 0)
	row.add_child(status)

	return row


# ───────────────────────────────────────────── ActionMenu（④ §6）

## 根据物品 usable/discardable/装备状态动态生成选项；全无可执行操作则返回单条置灰提示。
func _build_menu_options(item: ItemData, count: int) -> Array:
	var options: Array = []

	if item == null:
		# 未知物品兜底：仅"丢弃"
		options.append({"label": InventoryWidgets.STR_ACTION_DISCARD, "action": "discard", "disabled": false})
		return options

	if item.usable:
		options.append({"label": InventoryWidgets.STR_ACTION_USE, "action": "use", "disabled": false})

	if InventoryWidgets.is_equipment_category(item.category):
		var equipped: bool = GameData.is_item_equipped(item.id)
		var label: String = InventoryWidgets.STR_ACTION_UNEQUIP if equipped else InventoryWidgets.STR_ACTION_EQUIP
		var action: String = "unequip" if equipped else "equip"
		options.append({"label": label, "action": action, "disabled": false})

	if item.discardable:
		options.append({"label": InventoryWidgets.STR_ACTION_DISCARD, "action": "discard", "disabled": false})

	if options.is_empty():
		options.append({"label": InventoryWidgets.STR_NO_ACTION, "action": "", "disabled": true})

	return options


func _build_action_menu(item: ItemData, count: int) -> void:
	_menu_options = _build_menu_options(item, count)
	_menu_index = clampi(_menu_index, 0, _menu_options.size() - 1)
	# 若当前选中项被禁用（仅可能是单条"无可执行操作"），不影响——X 仍可退出。

	# 容器用 PanelContainer 承载背景 StyleBox（VBoxContainer 无 "panel" override）。
	var menu_panel := PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", InventoryWidgets.make_action_menu_style())
	menu_panel.clip_contents = true
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	for opt in _menu_options:
		inner.add_child(_make_menu_option_label(opt))
	menu_panel.add_child(inner)
	_parchment_content.add_child(menu_panel)
	_action_menu_box = menu_panel

	_update_menu_selection()

	# 展开动画：高度 0 -> 目标值，~100ms ease-out（决策：依赖节点 process_mode=WHEN_PAUSED 下 Tween 默认随场景树暂停而暂停，
	# 故显式 set_pause_mode(TWEEN_PAUSE_PROCESS) 让其在 paused 状态下继续播放）。
	var target_height: int = _menu_options.size() * ACTION_MENU_ROW_HEIGHT + 16
	menu_panel.custom_minimum_size = Vector2(0, 0)
	menu_panel.clip_contents = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(menu_panel, "custom_minimum_size:y", float(target_height), MENU_EXPAND_DURATION)


func _make_menu_option_label(opt: Dictionary) -> Label:
	var label := Label.new()
	label.text = opt.label
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 0)
	label.custom_minimum_size = Vector2(0, ACTION_MENU_ROW_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _update_menu_selection() -> void:
	if _action_menu_box == null:
		return
	var inner: VBoxContainer = _action_menu_box.get_child(0)
	for i in range(inner.get_child_count()):
		var label: Label = inner.get_child(i)
		var opt: Dictionary = _menu_options[i]
		if opt.disabled:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_DIM)
			label.text = opt.label
			continue
		var is_sel: bool = i == _menu_index
		if is_sel:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT)
			label.text = "▸ %s" % opt.label
		else:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
			label.text = opt.label


# ───────────────────────────────────────────── 状态切换

func _enter_action_menu() -> void:
	var slot: Dictionary = _focused_slot()
	if slot.is_empty():
		return  # 空分类：无法进入操作选择态
	_state = UIState.ACTION_MENU
	_menu_index = 0
	_update_slot_styles()
	_refresh_detail()


func _exit_action_menu() -> void:
	_state = UIState.PREVIEW
	_menu_options.clear()
	_action_menu_box = null
	_update_slot_styles()
	_refresh_detail()


# ───────────────────────────────────────────── DiscardConfirmDialog（⑤ §7）

func _open_discard_dialog(item: ItemData, count: int) -> void:
	_pending_discard_item = item
	_pending_discard_count = count
	_state = UIState.DISCARD_CONFIRM

	for child in _dialog_panel.get_children():
		child.queue_free()

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.text = InventoryWidgets.STR_DISCARD_TITLE
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var item_name: String = item.display_name if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_NAME
	var body := Label.new()
	body.text = InventoryWidgets.STR_DISCARD_BODY_FMT % [item_name, count]
	body.add_theme_font_size_override("font_size", 22)
	body.add_theme_color_override("font_color", InventoryWidgets.COL_GOLD)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(body)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	content.add_child(spacer)

	var hint := Label.new()
	hint.text = InventoryWidgets.STR_DISCARD_HINT
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
	hint.add_theme_constant_override("outline_size", 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

	_dialog_panel.add_child(content)

	_dialog_layer.visible = true
	_main_panel.modulate = Color(0.6, 0.6, 0.65, 1)

	_dialog_panel.scale = Vector2(0.8, 0.8)
	_dialog_panel.modulate.a = 0.0
	_dialog_panel.pivot_offset = _dialog_panel.size * 0.5
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_dialog_panel, "scale", Vector2.ONE, DIALOG_POPUP_DURATION)
	tween.tween_property(_dialog_panel, "modulate:a", 1.0, DIALOG_POPUP_DURATION)


func _close_discard_dialog() -> void:
	_main_panel.modulate = Color(1, 1, 1, 1)
	_dialog_layer.visible = false
	_pending_discard_item = null
	_pending_discard_count = 0


func _confirm_discard() -> void:
	var item: ItemData = _pending_discard_item
	var count: int = _pending_discard_count
	_close_discard_dialog()
	_state = UIState.PREVIEW
	if item == null:
		# 未知物品兜底：用 inventory 中记录的 item 引用直接 discard（item_id 取自 ItemData.id 不可用时跳过）
		_refresh_grid()
		_refresh_detail()
		return

	# TODO(ux): Open Question #4 —— 整组丢弃，待确认是否需部分丢弃
	GameData.discard_item(item.id, count)
	# 物品格淡出由 _on_inventory_changed -> _refresh_grid 间接处理（即时刷新即满足"消失"反馈，
	# ~150ms 淡出效果留待资产/特效阶段补充，不阻塞当前验收标准）。


func _cancel_discard() -> void:
	_close_discard_dialog()
	_state = UIState.ACTION_MENU


# ───────────────────────────────────────────── 操作执行（单一写入者：调用 GameData 方法）

func _execute_menu_action(opt: Dictionary) -> void:
	var slot: Dictionary = _focused_slot()
	if slot.is_empty():
		return
	var item: ItemData = slot.item
	var count: int = slot.count

	match opt.action:
		"use":
			GameData.use_item(item.id)
		"equip":
			GameData.equip_item(item.id)
		"unequip":
			var equip_slot: String = InventoryWidgets.EQUIP_SLOT_BY_CATEGORY.get(item.category, "")
			if not equip_slot.is_empty():
				GameData.unequip_item(equip_slot)
		"discard":
			_open_discard_dialog(item, count)
			return
		_:
			pass


# ───────────────────────────────────────────── GameData 信号回调（刷新）

func _on_inventory_changed(_a = null, _b = null) -> void:
	if not _is_open:
		return
	# 焦点回退：若当前分类物品种类数减少且焦点越界，clamp 到相邻物品
	_build_tabs()

	# equip/unequip/use 后，若仍在 ACTION_MENU，重建菜单选项（数量变化、装备状态变化）
	_refresh_grid()

	if _state == UIState.ACTION_MENU:
		var slot: Dictionary = _focused_slot()
		if slot.is_empty():
			# 物品已被消耗完/移除：退回预览态
			_state = UIState.PREVIEW
			_menu_options.clear()
			_action_menu_box = null

	_refresh_detail()


# ───────────────────────────────────────────── 输入处理

func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var keycode: Key = event.keycode

	match _state:
		UIState.DISCARD_CONFIRM:
			_handle_discard_input(keycode)
		UIState.ACTION_MENU:
			_handle_action_menu_input(keycode)
		UIState.PREVIEW:
			_handle_preview_input(keycode)


func _handle_preview_input(keycode: Key) -> void:
	match keycode:
		KEY_TAB, CANCEL_KEY:
			close()
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_A:
			_move_focus(-1, 0)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			_move_focus(1, 0)
			get_viewport().set_input_as_handled()
		KEY_UP, KEY_W:
			_move_focus(0, -1)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_move_focus(0, 1)
			get_viewport().set_input_as_handled()
		CONFIRM_KEY:
			_enter_action_menu()
			get_viewport().set_input_as_handled()


## 方向键导航：dx/dy 为 -1/0/1。左右在网格内移动列；到达边缘列继续按方向键切换分类。
## 上下在网格内按行移动；上下边界不切换分类（仅分类用左右边缘切换，符合 UX Spec）。
func _move_focus(dx: int, dy: int) -> void:
	if _current_items.is_empty():
		# 空分类：仍可通过左右切换分类（边缘导航可达空分类）
		if dx != 0:
			_switch_category(dx)
		return

	var count: int = _current_items.size()
	var cols: int = InventoryWidgets.GRID_COLUMNS
	var idx: int = _get_focus_index()
	var col: int = idx % cols
	var row: int = idx / cols
	var row_count: int = (count - 1) / cols + 1

	if dx != 0:
		var new_col: int = col + dx
		if new_col < 0 or new_col >= cols:
			_switch_category(dx)
			return
		var new_idx: int = row * cols + new_col
		if new_idx >= count:
			return  # 该行没有更多格子（半行末尾），不移动
		_set_focus_index(new_idx)
		_focus_current_slot()
		_refresh_detail()
		return

	if dy != 0:
		var new_row: int = row + dy
		if new_row < 0 or new_row >= row_count:
			return  # 上下边缘不切换分类
		var new_idx: int = new_row * cols + col
		if new_idx >= count:
			new_idx = count - 1
		_set_focus_index(new_idx)
		_focus_current_slot()
		_refresh_detail()


## 切换分类：落到该分类记忆焦点（默认 0/首物品），空分类也可到达。
func _switch_category(direction: int) -> void:
	var n: int = InventoryWidgets.CATEGORY_ORDER.size()
	_category_index = posmod(_category_index + direction, n)
	_update_tab_styles()
	_refresh_grid()
	_focus_current_slot()
	_refresh_detail()


func _handle_action_menu_input(keycode: Key) -> void:
	match keycode:
		KEY_UP, KEY_W:
			_move_menu_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_move_menu_selection(1)
			get_viewport().set_input_as_handled()
		CONFIRM_KEY:
			_activate_menu_option()
			get_viewport().set_input_as_handled()
		CANCEL_KEY:
			_exit_action_menu()
			get_viewport().set_input_as_handled()


func _move_menu_selection(step: int) -> void:
	if _menu_options.is_empty():
		return
	var n: int = _menu_options.size()
	var idx: int = _menu_index
	for _i in range(n):
		idx = posmod(idx + step, n)
		if not _menu_options[idx].disabled:
			_menu_index = idx
			_update_menu_selection()
			return


func _activate_menu_option() -> void:
	if _menu_index < 0 or _menu_index >= _menu_options.size():
		return
	var opt: Dictionary = _menu_options[_menu_index]
	if opt.disabled:
		return
	_execute_menu_action(opt)


func _handle_discard_input(keycode: Key) -> void:
	match keycode:
		CONFIRM_KEY:
			_confirm_discard()
			get_viewport().set_input_as_handled()
		CANCEL_KEY:
			_cancel_discard()
			get_viewport().set_input_as_handled()
