class_name BattleWidgets
extends RefCounted
## 战斗 UI 无状态视图工厂 —— 纯静态函数：输入参数 → 返回 Control，不持有任何战斗状态。
## 从 BattleUI 抽离，集中像素缩放 / 配色 / 切片路径与控件构建，降低 BattleUI 体量。
## 这里是 UI 视觉常量的单一数据源；BattleUI 控制器侧需要的配色直接引用 BattleWidgets.COL_*。

# ── 切片资源路径 ──
const ASSET_DIR: String = "res://assets/ui/battle/"
const TEX_RETICLE: String = ASSET_DIR + "reticle_target_gold.png"
const TEX_MARKER_LOCKED: String = ASSET_DIR + "marker_locked_red.png"
const TEX_CHIP: String = ASSET_DIR + "chip_status.png"
const TEX_BAR_HP: String = ASSET_DIR + "bar_hp_9p.png"
const TEX_BAR_MP: String = ASSET_DIR + "bar_mp_9p.png"
const TEX_BAR_TRACK: String = ASSET_DIR + "bar_track_9p.png"
const TEX_BAR_FRAME: String = ASSET_DIR + "bar_frame_9p.png"
const TEX_CMD_CELL: String = ASSET_DIR + "cmd_cell_9p.png"

# ── 配色（Brief §1.1，骨白/血红/法力蓝/金/余烬橙）──
const COL_BONE: Color = Color(0.847, 0.812, 0.753)       # 骨白
const COL_GOLD: Color = Color(0.902, 0.753, 0.290)       # 金色反馈（我锁敌/选中）
const COL_DIM: Color = Color(0.45, 0.43, 0.40)           # 置灰
const COL_ALLY: Color = Color(0.22, 0.52, 0.82)          # 友蓝占位
const COL_ENEMY: Color = Color(0.82, 0.22, 0.22)         # 敌红占位
const COL_HP: Color = Color(0.46, 0.12, 0.15)            # HP >50%：暗血红
const COL_HP_MID: Color = Color(0.82, 0.34, 0.12)        # HP 26%~50%：余烬橙
const COL_HP_LOW: Color = Color(0.95, 0.10, 0.12)        # HP <=25%：亮血红
const COL_MP: Color = Color(0.31, 0.52, 0.66)            # MP 法力蓝
const PIXEL_SCALE: int = 4                                # 480×270 设计倍率换算为 1080p HUD 倍率。
const CIRCLE_SHADER_CODE: String = """
shader_type canvas_item;
void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	color.a *= 1.0 - step(0.5, length(UV - vec2(0.5)));
	COLOR = color;
}
"""
const HIT_FLASH_SHADER_CODE: String = """
shader_type canvas_item;
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
"""

static var _circle_shader: Shader = null
static var _hit_flash_shader: Shader = null

# ───────────────────────────────────────────── 切片加载（缺失回退 null）

static func load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Texture2D

# ───────────────────────────────────────────── ②⑤ 敌我状态卡（头像框 + HP/MP 条）

## 我方单位卡：[圆形头像] | [HP / MP]；敌方常态只保留纯立绘。
static func make_unit_card(
		unit,
		is_party: bool,
		is_active: bool = false,
		size_px: int = 88,
		ui_scale: float = 1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", maxi(4, roundi(12.0 * ui_scale)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unit.is_dead():
		row.modulate = Color(0.5, 0.5, 0.5)

	# 敌方常态只显示纯立绘；我方使用圆形头像与状态信息。
	var avatar: Control
	if is_party:
		avatar = make_avatar(unit, true, size_px, is_active, ui_scale)
	else:
		avatar = make_unit_sprite(unit, false, size_px)
	avatar.set_meta("unit_ref", unit)
	row.add_child(avatar)
	if not is_party:
		return row

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", maxi(2, roundi(4.0 * ui_scale)))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# HP 条（底轨 + 填充，TextureProgressBar 九宫横拉）
	info.add_child(make_stat_bar(unit.hp, unit.max_hp, TEX_BAR_HP, COL_HP, ui_scale))
	# MP 条仅我方（敌方 max_mp 通常为 0）
	if is_party and unit.max_mp > 0:
		info.add_child(make_stat_bar(unit.mp, unit.max_mp, TEX_BAR_MP, COL_MP, ui_scale))

	row.add_child(info)
	return row

static func make_avatar(
		unit,
		is_party: bool,
		size_px: int = 88,
		gold_outline: bool = false,
		ui_scale: float = 1.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = (COL_ALLY if is_party else COL_ENEMY).darkened(0.68)
	background_style.set_corner_radius_all(roundi(size_px * 0.5))
	background.add_theme_stylebox_override("panel", background_style)
	holder.add_child(background)
	var inset: int = maxi(2, roundi(4.0 * ui_scale))
	var visual := make_unit_sprite(unit, is_party, size_px - inset * 2, true, true)
	visual.set_anchors_preset(Control.PRESET_CENTER)
	visual.offset_left = -visual.custom_minimum_size.x * 0.5
	visual.offset_top = -visual.custom_minimum_size.y * 0.5
	visual.offset_right = visual.custom_minimum_size.x * 0.5
	visual.offset_bottom = visual.custom_minimum_size.y * 0.5
	holder.add_child(visual)
	var outline := Panel.new()
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color.TRANSPARENT
	outline_style.border_color = COL_GOLD if gold_outline else COL_BONE
	outline_style.set_border_width_all(maxi(2, roundi((6.0 if gold_outline else 4.0) * ui_scale)))
	outline_style.set_corner_radius_all(roundi(size_px * 0.5))
	outline.add_theme_stylebox_override("panel", outline_style)
	holder.add_child(outline)
	return holder

static func make_unit_sprite(
		unit,
		is_party: bool,
		size_px: int,
		prefer_battle_portrait: bool = false,
		circular: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size = holder.custom_minimum_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait: Texture2D = get_battle_portrait(unit) if prefer_battle_portrait else get_unit_portrait(unit)
	var visual: Control
	if portrait != null:
		var rect := TextureRect.new()
		rect.texture = portrait
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if circular:
			rect.material = make_circle_material()
		visual = rect
	else:
		# 无外观回退：阵营色占位，不阻断战斗流程。
		var fill := ColorRect.new()
		fill.color = COL_ALLY if is_party else COL_ENEMY
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if circular:
			fill.material = make_circle_material()
		visual = fill
	holder.add_child(visual)
	if not is_party:
		var flash_overlay := visual.duplicate() as Control
		flash_overlay.material = make_hit_flash_material()
		flash_overlay.modulate.a = 0.001
		flash_overlay.set_meta("hit_flash_overlay", true)
		holder.add_child(flash_overlay)
	return holder

static func make_stage_actor(unit, is_party: bool) -> Control:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual := make_unit_sprite(unit, is_party, 256)
	visual.set_anchors_preset(Control.PRESET_CENTER)
	visual.offset_left = -128
	visual.offset_top = -128
	visual.offset_right = 128
	visual.offset_bottom = 128
	holder.add_child(visual)
	return holder

## 取单位头像纹理：stats_res 带 sprite_frames（8 向 idle）时取 idle_down 首帧，否则 null。
static func get_unit_portrait(unit) -> Texture2D:
	if unit.stats_res == null:
		return null
	var frames = unit.stats_res.get("sprite_frames")
	if frames is SpriteFrames and frames.has_animation("idle_down") and frames.get_frame_count("idle_down") > 0:
		return frames.get_frame_texture("idle_down", 0)
	return null

static func get_battle_portrait(unit) -> Texture2D:
	if unit.stats_res != null:
		var portrait = unit.stats_res.get("battle_portrait")
		if portrait is Texture2D:
			return portrait
	return get_unit_portrait(unit)

static func make_circle_material() -> ShaderMaterial:
	if _circle_shader == null:
		_circle_shader = Shader.new()
		_circle_shader.code = CIRCLE_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _circle_shader
	return material

static func make_hit_flash_material() -> ShaderMaterial:
	if _hit_flash_shader == null:
		_hit_flash_shader = Shader.new()
		_hit_flash_shader.code = HIT_FLASH_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _hit_flash_shader
	return material

static func make_stat_bar(
		cur: int,
		maxv: int,
		fill_tex_path: String,
		fallback_col: Color,
		ui_scale: float = 1.0) -> Control:
	# 平面填充与静态 texture_over 外框分层，进度变化不会收缩边框。
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 32) * ui_scale
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.min_value = 0
	bar.max_value = maxi(1, maxv)
	bar.value = clampi(cur, 0, maxi(1, maxv))
	bar.step = 0.0
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	var stretch_margin: int = maxi(1, roundi(4.0 * ui_scale))
	bar.stretch_margin_left = stretch_margin
	bar.stretch_margin_right = stretch_margin
	bar.stretch_margin_top = stretch_margin
	bar.stretch_margin_bottom = stretch_margin
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track: Texture2D = load_tex(TEX_BAR_TRACK)
	var fill: Texture2D = load_tex(fill_tex_path)
	var frame: Texture2D = load_tex(TEX_BAR_FRAME)
	if track != null:
		bar.texture_under = track
	if fill != null:
		bar.texture_progress = fill
	if frame != null:
		bar.texture_over = frame
	var prefix: String = "HP" if fill_tex_path == TEX_BAR_HP else "MP"
	bar.tint_progress = _stat_bar_color(cur, maxv, prefix)
	_add_stat_value_label(bar, prefix, cur, maxv, ui_scale)
	# 任一切片缺失：回退用纯色 StyleBox-like ProgressBar 表达
	if track == null or fill == null or frame == null:
		return make_stat_bar_fallback(cur, maxv, fallback_col, prefix, ui_scale)
	return bar

static func _stat_bar_color(cur: int, maxv: int, prefix: String) -> Color:
	if prefix == "MP":
		return COL_MP
	var ratio: float = float(cur) / float(maxi(1, maxv))
	if ratio > 0.5:
		return COL_HP
	return COL_HP_MID if ratio > 0.25 else COL_HP_LOW

static func _add_stat_value_label(
		bar: Control,
		prefix: String,
		cur: int,
		maxv: int,
		ui_scale: float) -> void:
	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "%s %d/%d" % [prefix, cur, maxv]
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", maxi(10, roundi(16.0 * ui_scale)))
	value_label.add_theme_color_override("font_color", COL_BONE)
	value_label.add_theme_constant_override("outline_size", maxi(2, roundi(4.0 * ui_scale)))
	value_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.04))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(value_label)

static func make_stat_bar_fallback(
		cur: int,
		maxv: int,
		col: Color,
		prefix: String,
		ui_scale: float) -> Control:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(160, 32) * ui_scale
	pb.min_value = 0
	pb.max_value = maxi(1, maxv)
	pb.value = clampi(cur, 0, maxi(1, maxv))
	pb.step = 0.0
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.13)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	_add_stat_value_label(pb, prefix, cur, maxv, ui_scale)
	return pb

# ───────────────────────────────────────────── ④ 命令格底框
static func make_command_cell(text: String, disabled: bool) -> Label:
	var cell := Label.new()
	cell.text = text
	cell.add_theme_font_size_override("font_size", 30)
	cell.add_theme_stylebox_override("normal", make_cmd_cell_style())
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if disabled:
		cell.modulate = COL_DIM
	return cell

## 单个命令格的 StyleBox（cmd_cell_9p 切片：8px 黑框 + 2px 骨白 + 2px 暗缝）。
## 每格独立带框，格与格之间由 HBox separation 拉开，文字经 content margin 居中于框内。
static func make_cmd_cell_style() -> StyleBox:
	var tex: Texture2D = load_tex(TEX_CMD_CELL)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 8
		sb.texture_margin_top = 8
		sb.texture_margin_right = 8
		sb.texture_margin_bottom = 8
		sb.content_margin_left = 20
		sb.content_margin_top = 14
		sb.content_margin_right = 20
		sb.content_margin_bottom = 14
		return sb
	# 回退：纯色平框（黑粗边 + 暗紫内部）
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.24, 0.22, 0.27)
	flat.border_color = Color(0.04, 0.03, 0.055)
	flat.set_border_width_all(8)
	flat.set_content_margin_all(16)
	return flat

# ───────────────────────────────────────────── ⑥ 准星 / 锁敌叠加标记

static func make_overlay_marker(tex: Texture2D, size_px: int, fallback_col: Color) -> Control:
	var target_size := Vector2.ONE * maxi(1, size_px)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = target_size
		rect.size = target_size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var dot := ColorRect.new()
	dot.custom_minimum_size = target_size
	dot.size = target_size
	dot.color = fallback_col
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

static func make_intent_marker(avatar: Control, lock_count: int) -> Control:
	var avatar_size: float = maxf(avatar.size.x, avatar.size.y)
	var padding: int = maxi(8, roundi(avatar_size * 16.0 / 120.0))
	var marker := make_overlay_marker(
		load_tex(TEX_MARKER_LOCKED), roundi(avatar_size) + padding, COL_ENEMY)
	marker.set_meta("intent_marker", true)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.position = avatar.get_global_rect().get_center() - marker.size * 0.5
	marker.pivot_offset = marker.size * 0.5
	var label := Label.new()
	label.text = "×%d" % lock_count
	label.position = Vector2(marker.size.x - 48, marker.size.y - 30)
	label.size = Vector2(52, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_ENEMY.lightened(0.25))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)
	return marker

# ───────────────────────────────────────────── ③ 中央框临时视图

static func make_central_option_box(ui_scale: float = 1.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = roundi(48.0 * ui_scale)
	box.offset_top = roundi(84.0 * ui_scale)
	box.offset_right = -roundi(48.0 * ui_scale)
	box.offset_bottom = -roundi(28.0 * ui_scale)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", maxi(8, roundi(12.0 * ui_scale)))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

static func make_menu_option(ui_scale: float = 1.0) -> Label:
	var item := Label.new()
	item.custom_minimum_size.y = maxi(36, roundi(56.0 * ui_scale))
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size", maxi(23, roundi(34.0 * ui_scale)))
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

static func make_timing_overlay() -> Dictionary:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 2
	var result_label := Label.new()
	result_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	result_label.offset_left = -460
	result_label.offset_top = -126
	result_label.offset_right = 460
	result_label.offset_bottom = -76
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 26)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(result_label)
	return {"overlay": overlay, "result_label": result_label}
