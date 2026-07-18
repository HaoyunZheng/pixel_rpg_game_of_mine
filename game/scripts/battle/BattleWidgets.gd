class_name BattleWidgets
extends RefCounted
## 战斗 UI 无状态视图工厂 —— 纯静态函数：输入参数 → 返回 Control，不持有任何战斗状态。
## 从 BattleUI 抽离，集中像素缩放 / 配色 / 切片路径与控件构建，降低 BattleUI 体量。
## 这里是 UI 视觉常量的单一数据源；BattleUI 控制器侧需要的配色直接引用 BattleWidgets.COL_*。

# ── 切片资源路径 ──
const ASSET_DIR: String = "res://assets/ui/battle/"
const TEX_PIP: String = ASSET_DIR + "pip_turn.png"
const TEX_PIP_ACTIVE: String = ASSET_DIR + "pip_turn_active.png"
const TEX_RETICLE: String = ASSET_DIR + "reticle_target_gold.png"
const TEX_MARKER_LOCKED: String = ASSET_DIR + "marker_locked_red.png"
const TEX_CHIP: String = ASSET_DIR + "chip_status.png"
const TEX_BAR_HP: String = ASSET_DIR + "bar_hp_9p.png"
const TEX_BAR_MP: String = ASSET_DIR + "bar_mp_9p.png"
const TEX_BAR_TRACK: String = ASSET_DIR + "bar_track_9p.png"
const TEX_BAR_FRAME: String = ASSET_DIR + "bar_frame_9p.png"
const TEX_AVATAR_FRAME: String = ASSET_DIR + "avatar_frame_9p.png"
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
const PIXEL_SCALE: int = 4                                # 480×270 基准 ×4 → 1080p（准星/锁定标记等小件仍按此放大；面板/条/pip 切片已按屏幕尺寸烘焙、1:1 绘制）

# ───────────────────────────────────────────── 切片加载（缺失回退 null）

static func load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Texture2D

# ───────────────────────────────────────────── ① 行动顺序 pip

static func make_pip(active: bool) -> Control:
	# pip 切片已按屏幕尺寸烘焙（56/72px），1:1 绘制；非当前 pip 在条内垂直居中。
	var tex: Texture2D = load_tex(TEX_PIP_ACTIVE if active else TEX_PIP)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.stretch_mode = TextureRect.STRETCH_KEEP
		rect.custom_minimum_size = tex.get_size()
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	# 回退：金/暗骨白纯色圆点
	var dot := ColorRect.new()
	var px: int = 72 if active else 56
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = COL_GOLD if active else COL_BONE.darkened(0.4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

# ───────────────────────────────────────────── ②⑤ 敌我状态卡（头像框 + HP/MP 条）

## 我方单位卡：[头像框] | [姓名 / HP / MP]；敌方常态只保留纯立绘。
static func make_unit_card(unit, is_party: bool, is_active: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unit.is_dead():
		row.modulate = Color(0.5, 0.5, 0.5)

	# 敌方常态只显示纯立绘；我方使用头像框与状态信息。
	var avatar: Control
	if is_party:
		avatar = make_avatar(unit, true, 104 if is_active else 88, is_active)
	else:
		avatar = make_unit_sprite(unit, false, 88)
	avatar.set_meta("unit_ref", unit)
	row.add_child(avatar)
	if not is_party:
		return row

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_label)
	if is_party and unit.pending_stance != BattleUnit.Stance.ATTACK:
		var stance_label := Label.new()
		stance_label.text = "[防]" if unit.pending_stance == BattleUnit.Stance.DEFEND else "[闪]"
		stance_label.add_theme_font_size_override("font_size", 18)
		stance_label.add_theme_color_override("font_color", COL_GOLD if unit.pending_stance == BattleUnit.Stance.DEFEND else COL_ALLY.lightened(0.25))
		stance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(stance_label)
	info.add_child(name_row)

	# HP 条（底轨 + 填充，TextureProgressBar 九宫横拉）
	info.add_child(make_stat_bar(unit.hp, unit.max_hp, TEX_BAR_HP, COL_HP))
	# MP 条仅我方（敌方 max_mp 通常为 0）
	if is_party and unit.max_mp > 0:
		info.add_child(make_stat_bar(unit.mp, unit.max_mp, TEX_BAR_MP, COL_MP))

	row.add_child(info)
	return row

static func make_avatar(
		unit,
		is_party: bool,
		size_px: int = 88,
		gold_outline: bool = false) -> Control:
	# 头像框切片使用单层 8px 骨白硬边。
	var border_px: int = 8
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 头像框 9-patch 先铺底
	var frame_tex: Texture2D = load_tex(TEX_AVATAR_FRAME)
	if frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = frame_tex
		frame.patch_margin_left = border_px
		frame.patch_margin_top = border_px
		frame.patch_margin_right = border_px
		frame.patch_margin_bottom = border_px
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(frame)
	var visual := make_unit_sprite(unit, is_party, size_px - border_px * 2)
	visual.set_anchors_preset(Control.PRESET_CENTER)
	visual.offset_left = -visual.custom_minimum_size.x * 0.5
	visual.offset_top = -visual.custom_minimum_size.y * 0.5
	visual.offset_right = visual.custom_minimum_size.x * 0.5
	visual.offset_bottom = visual.custom_minimum_size.y * 0.5
	holder.add_child(visual)
	if gold_outline:
		var active_outline := Panel.new()
		active_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		active_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = Color.TRANSPARENT
		outline_style.border_color = COL_GOLD
		outline_style.set_border_width_all(6)
		active_outline.add_theme_stylebox_override("panel", outline_style)
		holder.add_child(active_outline)
	return holder

static func make_unit_sprite(unit, is_party: bool, size_px: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size = holder.custom_minimum_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait: Texture2D = get_unit_portrait(unit)
	if portrait != null:
		var rect := TextureRect.new()
		rect.texture = portrait
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		# 无外观回退：阵营色占位，不阻断战斗流程。
		var fill := ColorRect.new()
		fill.color = COL_ALLY if is_party else COL_ENEMY
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fill)
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

static func make_stat_bar(cur: int, maxv: int, fill_tex_path: String, fallback_col: Color) -> Control:
	# 平面填充与静态 texture_over 外框分层，进度变化不会收缩边框。
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 32)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.min_value = 0
	bar.max_value = maxi(1, maxv)
	bar.value = clampi(cur, 0, maxi(1, maxv))
	bar.step = 0.0
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 4
	bar.stretch_margin_right = 4
	bar.stretch_margin_top = 4
	bar.stretch_margin_bottom = 4
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
	_add_stat_value_label(bar, prefix, cur, maxv)
	# 任一切片缺失：回退用纯色 StyleBox-like ProgressBar 表达
	if track == null or fill == null or frame == null:
		return make_stat_bar_fallback(cur, maxv, fallback_col, prefix)
	return bar

static func _stat_bar_color(cur: int, maxv: int, prefix: String) -> Color:
	if prefix == "MP":
		return COL_MP
	var ratio: float = float(cur) / float(maxi(1, maxv))
	if ratio > 0.5:
		return COL_HP
	return COL_HP_MID if ratio > 0.25 else COL_HP_LOW

static func _add_stat_value_label(bar: Control, prefix: String, cur: int, maxv: int) -> void:
	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "%s %d/%d" % [prefix, cur, maxv]
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", COL_BONE)
	value_label.add_theme_constant_override("outline_size", 4)
	value_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.04))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(value_label)

static func make_stat_bar_fallback(cur: int, maxv: int, col: Color, prefix: String) -> Control:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(160, 32)
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
	_add_stat_value_label(pb, prefix, cur, maxv)
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

static func make_overlay_marker(tex: Texture2D, base_px: int, fallback_col: Color) -> Control:
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		# 必须真把纹理放大到 ×4 盒子：STRETCH_KEEP 只按原生 16px 画在盒子左上角（又小又偏位）
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = tex.get_size() * PIXEL_SCALE
		rect.size = rect.custom_minimum_size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var dot := ColorRect.new()
	var px: int = base_px * PIXEL_SCALE
	dot.custom_minimum_size = Vector2(px, px)
	dot.size = dot.custom_minimum_size
	dot.color = fallback_col
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

static func make_intent_marker(avatar: Control, lock_count: int) -> Panel:
	var marker := Panel.new()
	marker.set_meta("intent_marker", true)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.size = avatar.size + Vector2(16, 16)
	marker.position = avatar.get_global_rect().get_center() - marker.size * 0.5
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.border_color = COL_ENEMY
	outline.set_border_width_all(4)
	marker.add_theme_stylebox_override("panel", outline)
	var label := Label.new()
	label.text = "锁定 ×%d" % lock_count
	label.position = Vector2(-12, -34)
	label.size = Vector2(marker.size.x + 24, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_ENEMY.lightened(0.25))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)
	return marker

# ───────────────────────────────────────────── ③ 中央框临时视图

static func make_central_option_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.anchor_top = 0.35
	box.anchor_bottom = 1.0
	box.offset_left = -200
	box.offset_right = 200
	box.offset_bottom = -24
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

static func make_menu_option() -> Label:
	var item := Label.new()
	item.add_theme_font_size_override("font_size", 24)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
