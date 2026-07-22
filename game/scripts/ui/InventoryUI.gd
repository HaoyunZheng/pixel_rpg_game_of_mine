class_name InventoryUI
extends CanvasLayer
## 背包界面控制器（design/ux/inventory.md + design/art/inventory-visual-spec.md）。
##
## 架构（混合方案）：
## - 华丽外观全部来自手绘账簿底图 clean-plate（书封/皮革/羊皮纸页/描边/装饰），由 Stage 等比锁定铺屏。
## - 仅 5 样功能控件作为引擎控件叠在画好的槽位上：物品格、大类标签、详情图框、详情文字、弹出选择菜单。
## - 槽位坐标来自离线生成的 layout.json（tools/ui_layout_extract.py），代码读数据定位，不写死像素。
##   换美术 → 重跑工具即可，代码零改。
##
## - 暂停式覆盖层：open() 时 get_tree().paused = true，自身 process_mode = WHEN_PAUSED 仍可响应输入。
## - 状态机：PREVIEW / ACTION_MENU / DISCARD_CONFIRM。
## - 单一写入者：数据变更只经 GameData.use/equip/unequip/discard，UI 监听 4 信号刷新。
## - 纯键盘：方向键导航 + Z 确认 + X 取消/返回，逐级 X：弹窗→菜单→预览→关闭。

const CONFIRM_KEY: Key = KEY_Z
const CANCEL_KEY: Key = KEY_X
const FADE_DURATION: float = 0.15
const DIALOG_POPUP_DURATION: float = 0.12
const ACTION_MENU_ROW_HEIGHT: int = 42
const ITEMS_PER_PAGE: int = 20
const INVENTORY_MUSIC_FACTOR: float = 0.7
const SFX_UNZIP: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/unzip.wav")
const SFX_ZIP: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/zip.wav")
const SFX_MOVE: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/moving_ui.wav")
const SFX_SHIFT: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/shift_choice.wav")
const SFX_EQUIP: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/equip.wav")
const SFX_UNEQUIP: AudioStreamWAV = preload("res://assets/derived/audio/sfx/interface/unequip.wav")

enum UIState { PREVIEW, ACTION_MENU, DISCARD_CONFIRM }

# ── 节点引用 ──
@onready var _stage: Control = $Stage
@onready var _bg: TextureRect = $Stage/Background
@onready var _layers: Control = $Stage/Layers
@onready var _tabs_layer: Control = $Stage/Layers/Tabs
@onready var _grid_layer: Control = $Stage/Layers/Grid
@onready var _grid_hint_layer: Control = $Stage/Layers/GridHint
@onready var _detail_layer: Control = $Stage/Layers/Detail
@onready var _dialog_layer: Control = $Stage/DialogLayer
@onready var _dialog_panel: PanelContainer = $Stage/DialogLayer/Dialog
@onready var _sfx_player: AudioStreamPlayer = $UISFX

var _state: UIState = UIState.PREVIEW
var _category_index: int = 0
var _focus_index_by_category: Dictionary = {}
var _page_index_by_category: Dictionary = {}
var _menu_index: int = 0
var _is_open: bool = false
var _music_bus_index: int = -1
var _music_volume_before_open: float = 0.0

var _layout: Dictionary = {}
var _current_items: Array[InventoryState.Slot] = []
var _menu_options: Array = []
var _action_menu_box: GridContainer = null
var _pending_discard_item: ItemData = null
var _pending_discard_count: int = 0

var _tab_nodes: Array = []      # 5 个标签 banner（TextureRect）
var _slot_nodes: Array = []     # 当前分类物品格 holder（按索引）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 10
	visible = false
	_stage.modulate.a = 0.0
	_dialog_layer.visible = false
	_bg.texture = InventoryWidgets.load_tex(InventoryWidgets.TEX_BG_CLEAN)
	_dialog_panel.add_theme_stylebox_override("panel", InventoryWidgets.make_dialog_style())

	_layout = InventoryWidgets.load_layout()
	if _layout.is_empty():
		push_error("[InventoryUI] layout.json 缺失，请先运行 tools/ui_layout_extract.py")

	_fit_stage()
	get_viewport().size_changed.connect(_fit_stage)

	GameData.item_used.connect(_on_inventory_changed)
	GameData.item_equipped.connect(_on_inventory_changed)
	GameData.item_unequipped.connect(_on_inventory_changed)
	GameData.item_discarded.connect(_on_inventory_changed)

	_build_tabs()
	_refresh_grid()
	_refresh_detail()


## Stage 等比 contain 铺屏并居中：背景图与所有控件锁定在 1664×936 同坐标系，分辨率/宽高比无关。
func _fit_stage() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var s: float = minf(vp.x / InventoryWidgets.STAGE_W, vp.y / InventoryWidgets.STAGE_H)
	_stage.scale = Vector2(s, s)
	_stage.position = Vector2(
		(vp.x - InventoryWidgets.STAGE_W * s) * 0.5,
		(vp.y - InventoryWidgets.STAGE_H * s) * 0.5)


# ───────────────────────────────────────────── 打开 / 关闭

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_state = UIState.PREVIEW
	visible = true
	get_tree().paused = true
	_fit_stage()
	_refresh_grid()
	_refresh_detail()
	_duck_music()
	_play_ui_sfx(SFX_UNZIP, -2.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_stage, "modulate:a", 1.0, FADE_DURATION)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_restore_music()
	_play_ui_sfx(SFX_ZIP, -2.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_stage, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
	visible = false
	get_tree().paused = false


func is_open() -> bool:
	return _is_open


func _play_ui_sfx(stream: AudioStream, volume_db: float) -> void:
	_sfx_player.stream = stream
	_sfx_player.volume_db = volume_db
	_sfx_player.play()


func _duck_music() -> void:
	_music_bus_index = AudioServer.get_bus_index(&"Music")
	if _music_bus_index < 0:
		return
	_music_volume_before_open = AudioServer.get_bus_volume_db(_music_bus_index)
	var reduced_linear := db_to_linear(_music_volume_before_open) * INVENTORY_MUSIC_FACTOR
	AudioServer.set_bus_volume_db(_music_bus_index, linear_to_db(reduced_linear))


func _restore_music() -> void:
	if _music_bus_index < 0:
		return
	AudioServer.set_bus_volume_db(_music_bus_index, _music_volume_before_open)
	_music_bus_index = -1


# ───────────────────────────────────────────── 版式锚点取值（layout.json）

func _rect_of(arr) -> Rect2:
	return Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))


func _zone(zone_name: String) -> Rect2:
	var zones: Dictionary = _layout.get("zones", {})
	if zones.has(zone_name):
		return _rect_of(zones[zone_name])
	return Rect2()


# ───────────────────────────────────────────── ① 分类标签（手绘 banner 叠在标签锚点）

func _build_tabs() -> void:
	for child in _tabs_layer.get_children():
		child.queue_free()
	_tab_nodes.clear()
	for i in range(InventoryWidgets.CATEGORY_ORDER.size()):
		var banner := TextureRect.new()
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.name = "Caption"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(label)

		_tabs_layer.add_child(banner)
		_tab_nodes.append(banner)
	_update_tab_styles()


func _update_tab_styles() -> void:
	var tabs: Dictionary = _layout.get("tabs", {})
	var centers: Array = tabs.get("centers", [])
	var base_w: float = float(tabs.get("width", 112))
	var top: float = float(tabs.get("top", 55))
	var sel_scale: float = float(tabs.get("selected_scale", 1.08))
	var lift: float = float(tabs.get("selected_lift", 8))

	for i in range(_tab_nodes.size()):
		var banner: TextureRect = _tab_nodes[i]
		var selected: bool = i == _category_index
		var tex: Texture2D = InventoryWidgets.load_tab_texture(i, selected)
		banner.texture = tex

		var w: float = base_w * (sel_scale if selected else 1.0)
		var aspect: float = 1.25
		if tex != null and tex.get_width() > 0:
			aspect = float(tex.get_height()) / float(tex.get_width())
		var h: float = w * aspect
		var cx: float = float(centers[i]) if i < centers.size() else (200.0 + i * 140.0)
		banner.size = Vector2(w, h)
		banner.position = Vector2(cx - w * 0.5, top - (lift if selected else 0.0))
		banner.z_index = 1 if selected else 0
		banner.modulate = Color(1, 1, 1, 1) if selected else Color(0.82, 0.82, 0.82, 0.94)

		var label: Label = banner.get_node("Caption")
		var count: int = _count_item_kinds(InventoryWidgets.CATEGORY_ORDER[i])
		label.text = "%s\n%d" % [InventoryWidgets.get_category_name(InventoryWidgets.CATEGORY_ORDER[i]), count]
		label.add_theme_color_override("font_color", InventoryWidgets.COL_GOLD if selected else InventoryWidgets.COL_BONE)


func _count_item_kinds(category: ItemData.ItemCategory) -> int:
	var n := 0
	for slot in GameData.get_inventory_slots():
		if slot.item != null and slot.item.category == category:
			n += 1
	return n


# ───────────────────────────────────────────── ② 物品格（叠在画好的井上）

func _current_category() -> ItemData.ItemCategory:
	return InventoryWidgets.CATEGORY_ORDER[_category_index]


func _gather_current_items() -> Array[InventoryState.Slot]:
	var items: Array[InventoryState.Slot] = []
	var category: ItemData.ItemCategory = _current_category()
	for slot in GameData.get_inventory_slots():
		if slot.item != null and slot.item.category == category:
			items.append(slot)
	return items


func _refresh_grid() -> void:
	for child in _grid_layer.get_children():
		child.queue_free()
	for child in _grid_hint_layer.get_children():
		child.queue_free()
	_slot_nodes.clear()

	var category_items: Array[InventoryState.Slot] = _gather_current_items()
	var wells: Array = _layout.get("wells", [])
	var page_count: int = maxi(1, ceili(category_items.size() / float(ITEMS_PER_PAGE)))
	var page_index: int = clampi(_get_page_index(), 0, page_count - 1)
	_set_page_index(page_index)
	_current_items.clear()
	var page_start: int = page_index * ITEMS_PER_PAGE
	var page_end: int = mini(page_start + ITEMS_PER_PAGE, category_items.size())
	for i in range(page_start, page_end):
		_current_items.append(category_items[i])

	if _current_items.is_empty():
		_grid_hint_layer.add_child(_make_grid_empty_hint(wells))
		return

	for i in range(_current_items.size()):
		if i >= wells.size():
			break
		var rect: Rect2 = _rect_of(wells[i])
		var slot_node := _build_item_slot(_current_items[i], rect)
		_grid_layer.add_child(slot_node)
	if page_count > 1:
		_grid_hint_layer.add_child(_make_page_indicator(wells, page_index, page_count))

	var focus_idx: int = clampi(_get_focus_index(), 0, mini(_current_items.size(), wells.size()) - 1)
	_set_focus_index(focus_idx)
	_update_slot_styles()


func _make_grid_empty_hint(wells: Array) -> Control:
	var label := InventoryWidgets.make_empty_category_hint()
	if wells.size() >= 20:
		var first: Rect2 = _rect_of(wells[0])
		var last: Rect2 = _rect_of(wells[wells.size() - 1])
		label.position = first.position
		label.size = last.position + last.size - first.position
	else:
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return label


func _make_page_indicator(wells: Array, page_index: int, page_count: int) -> Label:
	var label := Label.new()
	label.name = "PageIndicator"
	label.text = InventoryWidgets.STR_PAGE_FMT % [page_index + 1, page_count]
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not wells.is_empty():
		var first: Rect2 = _rect_of(wells[0])
		var last: Rect2 = _rect_of(wells[wells.size() - 1])
		label.position = Vector2(first.position.x, last.end.y + 6.0)
		label.size = Vector2(last.end.x - first.position.x, 28.0)
	return label


## 物品格：井尺寸的 Control，含 焦点/选中描边 overlay + 居中图标 + 数量角标（无格底，画好的井透出）。
func _build_item_slot(slot: InventoryState.Slot, rect: Rect2) -> Control:
	var item: ItemData = slot.item
	var count: int = slot.count

	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var overlay := Panel.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_stylebox_override("panel", InventoryWidgets.make_item_slot_focus_overlay(InventoryWidgets.SlotState.DEFAULT))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.name = "Overlay"
	holder.add_child(overlay)

	var icon_px: int = int(min(rect.size.x, rect.size.y) * 0.62)
	# 用 CenterContainer 居中：容器按子节点最小尺寸逐帧居中，不依赖 PRESET_CENTER 的调用时机
	# （preset 在节点入树前以 size=0 锚定左上角，会让图标向右下方溢出半格）。
	var icon_center := CenterContainer.new()
	icon_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := InventoryWidgets.make_item_icon(item, icon_px)
	if item != null and not item.usable:
		icon.modulate.a = 0.5
	icon_center.add_child(icon)
	holder.add_child(icon_center)

	if item != null and item.category == ItemData.ItemCategory.CONSUMABLE:
		var qty := Label.new()
		qty.text = InventoryWidgets.STR_QUANTITY_FMT % count
		qty.add_theme_font_size_override("font_size", 16)
		qty.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
		qty.add_theme_constant_override("outline_size", 4)
		qty.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.offset_left = -48
		qty.offset_top = -28
		qty.offset_right = -6
		qty.offset_bottom = -4
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(qty)

	_slot_nodes.append(holder)
	return holder


func _update_slot_styles() -> void:
	var focus_idx: int = _get_focus_index()
	for i in range(_slot_nodes.size()):
		var holder: Control = _slot_nodes[i]
		if not is_instance_valid(holder):
			continue
		var overlay: Panel = holder.get_node_or_null("Overlay")
		if overlay == null:
			continue
		var slot_state: InventoryWidgets.SlotState = InventoryWidgets.SlotState.DEFAULT
		if i == focus_idx:
			slot_state = InventoryWidgets.SlotState.SELECTED if _state != UIState.PREVIEW else InventoryWidgets.SlotState.FOCUSED
		overlay.add_theme_stylebox_override("panel", InventoryWidgets.make_item_slot_focus_overlay(slot_state))


# ───────────────────────────────────────────── 页码与焦点索引（每分类记忆）

func _get_page_index() -> int:
	return _page_index_by_category.get(_category_index, 0)


func _set_page_index(idx: int) -> void:
	_page_index_by_category[_category_index] = idx

func _get_focus_index() -> int:
	return _focus_index_by_category.get(_category_index, 0)


func _set_focus_index(idx: int) -> void:
	_focus_index_by_category[_category_index] = idx


func _focused_slot() -> InventoryState.Slot:
	var idx: int = _get_focus_index()
	if idx < 0 or idx >= _current_items.size():
		return null
	return _current_items[idx]


# ───────────────────────────────────────────── ③④⑤ 详情页（图框 + 文字 + 操作菜单，叠在画好的羊皮纸页分区上）

func _place_in_zone(ctrl: Control, zone_name: String) -> void:
	var r: Rect2 = _zone(zone_name)
	ctrl.position = r.position
	ctrl.size = r.size


func _refresh_detail() -> void:
	for child in _detail_layer.get_children():
		child.queue_free()
	_action_menu_box = null

	if GameData.get_inventory_slots().is_empty():
		_add_detail_empty_hint()
		return

	var slot := _focused_slot()
	if slot == null:
		_add_detail_empty_hint()
		return

	var item: ItemData = slot.item
	var count: int = slot.count
	_build_detail_icon(item)
	_build_detail_header(item)
	_build_detail_body(item)
	if _state == UIState.ACTION_MENU:
		_build_action_menu(item, count)
	else:
		_build_detail_footer(item)


func _add_detail_empty_hint() -> void:
	var hint := InventoryWidgets.make_empty_detail_hint()
	_place_in_zone(hint, "desc")
	_detail_layer.add_child(hint)


## ③ 详情图框：物品大图标置于画好的 portrait 框内（框由底图提供，仅叠图标）。
func _build_detail_icon(item: ItemData) -> void:
	var r: Rect2 = _zone("portrait")
	var icon_px: int = mini(90, int(min(r.size.x, r.size.y) * 0.7))
	var icon := InventoryWidgets.make_item_icon(item, icon_px)
	# 同 grid：CenterContainer 按子节点最小尺寸居中，替代时机敏感的 PRESET_CENTER。
	var holder := CenterContainer.new()
	holder.position = r.position
	holder.size = r.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	_detail_layer.add_child(holder)


## ④ 详情文字（标题区）：名称 + 分类章，置于 header 分区。
func _build_detail_header(item: ItemData) -> void:
	var name_label := Label.new()
	name_label.name = "ItemName"
	name_label.text = item.display_name if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_NAME
	name_label.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_in_zone(name_label, "name")
	_detail_layer.add_child(name_label)
	_fit_label_font(name_label, 26, 18, _zone("name").size)

	if item != null:
		var chip_holder := CenterContainer.new()
		chip_holder.name = "Category"
		chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place_in_zone(chip_holder, "tag")
		var chip := Label.new()
		chip.name = "CategoryChip"
		chip.text = InventoryWidgets.get_category_name(item.category)
		chip.add_theme_font_size_override("font_size", 15)
		chip.add_theme_color_override("font_color", InventoryWidgets.COL_BONE)
		chip.add_theme_constant_override("outline_size", 1)
		chip.add_theme_stylebox_override("normal", InventoryWidgets.make_chip_style())
		chip_holder.add_child(chip)
		_detail_layer.add_child(chip_holder)


## ④ 详情文字（正文区）：数值条目 + 说明文字，置于 body 分区。
func _build_detail_body(item: ItemData) -> void:
	var stats := GridContainer.new()
	stats.name = "Stats"
	stats.columns = 2
	stats.clip_contents = true
	stats.add_theme_constant_override("h_separation", 20)
	stats.add_theme_constant_override("v_separation", 2)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_in_zone(stats, "stats")
	if item != null:
		for line in InventoryWidgets.get_stat_lines(item):
			stats.add_child(_make_stat_line(line))
	_detail_layer.add_child(stats)

	var desc := Label.new()
	desc.name = "Description"
	desc.text = item.description if item != null else InventoryWidgets.STR_UNKNOWN_ITEM_DESC
	desc.add_theme_color_override("font_color", InventoryWidgets.COL_INK_LIGHT)
	desc.add_theme_constant_override("line_spacing", 6)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_in_zone(desc, "desc")
	_detail_layer.add_child(desc)
	_fit_label_font(desc, 17, 13, _zone("desc").size)


## ④ 详情文字（页脚区）：装备状态徽章，置于 footer 分区（非菜单态）。
func _build_detail_footer(item: ItemData) -> void:
	if item == null or not InventoryWidgets.is_equipment_category(item.category):
		return
	var holder := CenterContainer.new()
	holder.name = "EquipStatus"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_in_zone(holder, "footer")
	holder.add_child(_make_equip_status_badge(item))
	_detail_layer.add_child(holder)


func _fit_label_font(label: Label, max_font_size: int, min_font_size: int,
		available_size: Vector2 = Vector2.ZERO) -> void:
	var font: Font = label.get_theme_font("font")
	var fit_size: Vector2 = label.size if available_size == Vector2.ZERO else available_size
	var font_size: int = max_font_size
	while font_size > min_font_size:
		var measured: Vector2 = font.get_multiline_string_size(
			label.text, label.horizontal_alignment, fit_size.x, font_size)
		if measured.y <= fit_size.y:
			break
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	var line_height: float = font.get_height(font_size) + label.get_theme_constant("line_spacing")
	label.max_lines_visible = maxi(1, floori(fit_size.y / line_height))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true


func _make_stat_line(text: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var split_idx: int = text.rfind(" ")
	var label_part: String = text
	var value_part: String = ""
	if split_idx != -1:
		label_part = text.substr(0, split_idx + 1)
		value_part = text.substr(split_idx + 1)

	var label_node := Label.new()
	label_node.text = label_part
	label_node.add_theme_font_size_override("font_size", 19)
	label_node.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label_node)

	if not value_part.is_empty():
		var value_node := Label.new()
		value_node.text = value_part
		value_node.add_theme_font_size_override("font_size", 19)
		value_node.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT)
		value_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value_node)
	return row


func _make_equip_status_badge(item: ItemData) -> Control:
	var equipped: bool = GameData.is_item_equipped(item.id)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var prefix := Label.new()
	prefix.text = InventoryWidgets.STR_EQUIP_STATUS_PREFIX
	prefix.add_theme_font_size_override("font_size", 19)
	prefix.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
	prefix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(prefix)

	var status := Label.new()
	status.text = InventoryWidgets.STR_EQUIP_STATUS_EQUIPPED if equipped else InventoryWidgets.STR_EQUIP_STATUS_UNEQUIPPED
	status.add_theme_font_size_override("font_size", 19)
	status.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT if equipped else InventoryWidgets.COL_PARCHMENT_DIM)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)
	return row


# ───────────────────────────────────────────── ⑤ ActionMenu（弹出选择，置于 footer 分区）

func _build_menu_options(item: ItemData, _count: int) -> Array:
	var options: Array = []
	if item == null:
		options.append({"label": InventoryWidgets.STR_ACTION_DISCARD, "action": "discard", "disabled": false})
		return options
	if item.usable:
		options.append({"label": InventoryWidgets.STR_ACTION_USE, "action": "use", "disabled": not GameData.can_use_item(item.id)})
	if InventoryWidgets.is_equipment_category(item.category):
		var equipped: bool = GameData.is_item_equipped(item.id)
		options.append({
			"label": InventoryWidgets.STR_ACTION_UNEQUIP if equipped else InventoryWidgets.STR_ACTION_EQUIP,
			"action": "unequip" if equipped else "equip", "disabled": false})
	if item.discardable:
		options.append({"label": InventoryWidgets.STR_ACTION_DISCARD, "action": "discard", "disabled": false})
	if options.is_empty():
		options.append({"label": InventoryWidgets.STR_NO_ACTION, "action": "", "disabled": true})
	return options


func _build_action_menu(item: ItemData, count: int) -> void:
	_menu_options = _build_menu_options(item, count)
	_menu_index = clampi(_menu_index, 0, _menu_options.size() - 1)
	if _menu_options[_menu_index].disabled:
		for i in range(_menu_options.size()):
			if not _menu_options[i].disabled:
				_menu_index = i
				break

	var menu_grid := GridContainer.new()
	menu_grid.name = "ActionMenu"
	menu_grid.columns = 2
	menu_grid.clip_contents = true
	menu_grid.add_theme_constant_override("h_separation", 12)
	menu_grid.add_theme_constant_override("v_separation", 8)
	for opt in _menu_options:
		menu_grid.add_child(_make_menu_option_label(opt))
	_place_in_zone(menu_grid, "footer")
	_detail_layer.add_child(menu_grid)
	_action_menu_box = menu_grid
	_update_menu_selection()


func _make_menu_option_label(opt: Dictionary) -> Label:
	var label := Label.new()
	label.text = opt.label
	label.add_theme_font_size_override("font_size", 19)
	label.custom_minimum_size = Vector2(0, ACTION_MENU_ROW_HEIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _update_menu_selection() -> void:
	if _action_menu_box == null:
		return
	for i in range(_action_menu_box.get_child_count()):
		var label: Label = _action_menu_box.get_child(i)
		var opt: Dictionary = _menu_options[i]
		if opt.disabled:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_DIM)
			label.text = opt.label
			continue
		if i == _menu_index:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_PARCHMENT_ACCENT)
			label.text = "▸ %s" % opt.label
		else:
			label.add_theme_color_override("font_color", InventoryWidgets.COL_INK)
			label.text = opt.label


# ───────────────────────────────────────────── 状态切换

func _enter_action_menu() -> void:
	var slot := _focused_slot()
	if slot == null:
		return
	var item: ItemData = slot.item
	if item != null and (item.category == ItemData.ItemCategory.CONSUMABLE \
			or InventoryWidgets.is_equipment_category(item.category)):
		_play_ui_sfx(SFX_MOVE, -8.0)
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


# ───────────────────────────────────────────── DiscardConfirmDialog

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
	body.add_theme_color_override("font_color", InventoryWidgets.COL_GOLD)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 58)
	content.add_child(body)
	call_deferred("_fit_label_font", body, 22, 14)

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
	_layers.modulate = Color(0.6, 0.6, 0.65, 1)

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
	_layers.modulate = Color(1, 1, 1, 1)
	_dialog_layer.visible = false
	_pending_discard_item = null
	_pending_discard_count = 0


func _confirm_discard() -> void:
	var item: ItemData = _pending_discard_item
	var count: int = _pending_discard_count
	_close_discard_dialog()
	_state = UIState.PREVIEW
	if item == null:
		_refresh_grid()
		_refresh_detail()
		return
	# 整组丢弃（Open Question #4 已固化：count = 持有总数，无部分丢弃）
	GameData.discard_item(item.id, count)


func _cancel_discard() -> void:
	_close_discard_dialog()
	_state = UIState.ACTION_MENU


# ───────────────────────────────────────────── 操作执行（单一写入者）

func _execute_menu_action(opt: Dictionary) -> void:
	var slot := _focused_slot()
	if slot == null:
		return
	var item: ItemData = slot.item
	var count: int = slot.count
	match opt.action:
		"use":
			GameData.use_item(item.id)
		"equip":
			if GameData.equip_item(item.id):
				_play_ui_sfx(SFX_EQUIP, -8.0)
		"unequip":
			var equip_slot: String = InventoryWidgets.EQUIP_SLOT_BY_CATEGORY.get(item.category, "")
			if not equip_slot.is_empty() and GameData.unequip_item(equip_slot):
				_play_ui_sfx(SFX_UNEQUIP, -6.0)
		"discard":
			_open_discard_dialog(item, count)
		_:
			pass


# ───────────────────────────────────────────── GameData 信号回调

func _on_inventory_changed(_a = null, _b = null) -> void:
	if not _is_open:
		return
	_update_tab_styles()
	_refresh_grid()
	if _state == UIState.ACTION_MENU and _focused_slot() == null:
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
	match _state:
		UIState.DISCARD_CONFIRM:
			_handle_discard_input(event.keycode)
		UIState.ACTION_MENU:
			_handle_action_menu_input(event.keycode)
		UIState.PREVIEW:
			_handle_preview_input(event.keycode)


func _handle_preview_input(keycode: Key) -> void:
	match keycode:
		CANCEL_KEY:  # X：预览态下再次按 X 退出背包
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
		KEY_Q:
			_switch_category(-1)
			get_viewport().set_input_as_handled()
		KEY_E:
			_switch_category(1)
			get_viewport().set_input_as_handled()
		CONFIRM_KEY:
			_enter_action_menu()
			get_viewport().set_input_as_handled()


## 方向键导航：左右在网格内移动列，到边缘列切页；上下按行移动。分类只由 Q/E 切换。
func _move_focus(dx: int, dy: int) -> void:
	if _current_items.is_empty():
		return

	var count: int = _current_items.size()
	var cols: int = InventoryWidgets.GRID_COLUMNS
	var idx: int = _get_focus_index()
	var col: int = idx % cols
	var row: int = floori(idx / float(cols))
	var row_count: int = ceili(count / float(cols))

	if dx != 0:
		var new_col: int = col + dx
		if new_col < 0 or new_col >= cols:
			_switch_page(dx, row)
			return
		var new_idx: int = row * cols + new_col
		if new_idx >= count:
			return
		_set_focus_index(new_idx)
		_update_slot_styles()
		_refresh_detail()
		_play_ui_sfx(SFX_MOVE, -12.0)
		return

	if dy != 0:
		var new_row: int = row + dy
		if new_row < 0 or new_row >= row_count:
			return
		var new_idx: int = new_row * cols + col
		if new_idx >= count:
			new_idx = count - 1
		_set_focus_index(new_idx)
		_update_slot_styles()
		_refresh_detail()
		_play_ui_sfx(SFX_MOVE, -12.0)


func _switch_page(direction: int, row: int) -> void:
	var category_items: Array = _gather_current_items()
	var page_count: int = maxi(1, ceili(category_items.size() / float(ITEMS_PER_PAGE)))
	var next_page: int = _get_page_index() + direction
	if next_page < 0 or next_page >= page_count:
		return
	_set_page_index(next_page)
	_play_ui_sfx(SFX_SHIFT, -10.0)
	_refresh_grid()
	if _current_items.is_empty():
		_refresh_detail()
		return
	var cols: int = InventoryWidgets.GRID_COLUMNS
	var target_col: int = 0 if direction > 0 else cols - 1
	_set_focus_index(mini(row * cols + target_col, _current_items.size() - 1))
	_update_slot_styles()
	_refresh_detail()


func _switch_category(direction: int) -> void:
	var n: int = InventoryWidgets.CATEGORY_ORDER.size()
	_category_index = posmod(_category_index + direction, n)
	_play_ui_sfx(SFX_SHIFT, -10.0)
	_update_tab_styles()
	_refresh_grid()
	_refresh_detail()


func _handle_action_menu_input(keycode: Key) -> void:
	match keycode:
		KEY_UP, KEY_W:
			_move_menu_selection(-2)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_move_menu_selection(2)
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_A:
			_move_menu_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
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
			if idx == _menu_index:
				return
			_menu_index = idx
			_update_menu_selection()
			_play_ui_sfx(SFX_MOVE, -12.0)
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
