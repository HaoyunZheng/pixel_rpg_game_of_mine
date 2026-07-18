class_name TurnArcBar
extends Control
## 上凸弧线行动顺序条：最多显示当前行动者前后各 3 个单位。

const ROLL_SECONDS: float = 0.25
const ORB_SIZE: float = 72.0
const SLOT_SIZES: Array[float] = [72.0, 56.0, 44.0, 32.0]
const SLOT_SPACING: float = 96.0
const ARC_TOP: float = 32.0
const ARC_CURVE: float = 5.5
const CIRCLE_SHADER_CODE: String = """
shader_type canvas_item;
void fragment() {
	vec4 color = texture(TEXTURE, UV);
	color.a *= 1.0 - step(0.5, length(UV - vec2(0.5)));
	COLOR = color;
}
"""

var _orbs: Dictionary = {}
var _roll_tween: Tween = null
var _flash_tween: Tween = null


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var points := PackedVector2Array()
	for i in range(49):
		points.append(_slot_center(lerpf(-3.25, 3.25, float(i) / 48.0)))
	draw_polyline(points, Color(0.90, 0.87, 0.80, 0.32), 4.0)


func show_order(order: Array, active_actor) -> void:
	_kill_tweens()
	var living: Array = order.filter(func(unit): return unit != null and not unit.is_dead())
	var active_index: int = living.find(active_actor)
	if active_index < 0:
		_clear_orbs()
		return
	var targets: Dictionary = {}
	for index in range(living.size()):
		var slot: int = index - active_index
		if absi(slot) <= 3:
			targets[living[index]] = slot

	_roll_tween = create_tween().set_parallel(true)
	_roll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for unit in _orbs.keys():
		var orb: Control = _orbs[unit]
		_set_orb_active(orb, unit, false)
		if targets.has(unit):
			_continue_orb(orb, int(targets[unit]))
		else:
			_exit_orb(unit, orb)
	for unit in targets:
		if _orbs.has(unit):
			continue
		_enter_orb(unit, int(targets[unit]), _orbs.size() > 0)
	_roll_tween.tween_callback(_finish_roll.bind(active_actor)).set_delay(ROLL_SECONDS)


func _continue_orb(orb: Control, slot: int) -> void:
	_roll_tween.tween_property(orb, "position", _orb_position(slot), ROLL_SECONDS)
	_roll_tween.tween_property(orb, "scale", _orb_scale(slot), ROLL_SECONDS)
	_roll_tween.tween_property(orb, "modulate:a", 1.0, ROLL_SECONDS)
	orb.set_meta("turn_slot", slot)


func _enter_orb(unit, slot: int, slide_from_right: bool) -> void:
	var orb := _make_orb(unit)
	_orbs[unit] = orb
	add_child(orb)
	orb.position = _orb_position(slot + 1) if slide_from_right else _orb_position(slot)
	orb.scale = Vector2.ZERO
	orb.modulate.a = 0.0
	orb.set_meta("turn_slot", slot)
	_continue_orb(orb, slot)


func _exit_orb(unit, orb: Control) -> void:
	var slot: int = int(orb.get_meta("turn_slot", -3))
	_roll_tween.tween_property(orb, "position", _orb_position(slot - 1), ROLL_SECONDS)
	_roll_tween.tween_property(orb, "scale", Vector2.ZERO, ROLL_SECONDS)
	_roll_tween.tween_property(orb, "modulate:a", 0.0, ROLL_SECONDS)
	_roll_tween.tween_callback(_remove_orb.bind(unit, orb)).set_delay(ROLL_SECONDS)


func _finish_roll(active_actor) -> void:
	for unit in _orbs:
		_set_orb_active(_orbs[unit], unit, unit == active_actor)
	var active: Control = _orbs.get(active_actor)
	if active == null:
		return
	var flash: Panel = active.get_node("Flash")
	flash.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash, "modulate:a", 0.0, 0.16)


func _make_orb(unit) -> Control:
	var orb := Control.new()
	orb.custom_minimum_size = Vector2(ORB_SIZE, ORB_SIZE)
	orb.size = orb.custom_minimum_size
	orb.pivot_offset = orb.size * 0.5
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.set_meta("unit_ref", unit)

	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = _faction_color(unit).darkened(0.58)
	background_style.set_corner_radius_all(36)
	background.add_theme_stylebox_override("panel", background_style)
	orb.add_child(background)

	var portrait: Texture2D = BattleWidgets.get_unit_portrait(unit)
	if portrait != null:
		var portrait_rect := TextureRect.new()
		portrait_rect.texture = portrait
		portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait_rect.offset_left = 4
		portrait_rect.offset_top = 4
		portrait_rect.offset_right = -4
		portrait_rect.offset_bottom = -4
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := Shader.new()
		shader.code = CIRCLE_SHADER_CODE
		var circle_material := ShaderMaterial.new()
		circle_material.shader = shader
		portrait_rect.material = circle_material
		orb.add_child(portrait_rect)

	var border := Panel.new()
	border.name = "Border"
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.set_corner_radius_all(36)
	border.add_theme_stylebox_override("panel", border_style)
	orb.add_child(border)

	var flash := Panel.new()
	flash.name = "Flash"
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	var flash_style := StyleBoxFlat.new()
	flash_style.bg_color = Color.TRANSPARENT
	flash_style.border_color = BattleWidgets.COL_GOLD.lightened(0.25)
	flash_style.set_border_width_all(8)
	flash_style.set_corner_radius_all(36)
	flash.add_theme_stylebox_override("panel", flash_style)
	orb.add_child(flash)

	var indicator := Polygon2D.new()
	indicator.name = "Indicator"
	indicator.polygon = PackedVector2Array([Vector2(30, 78), Vector2(42, 78), Vector2(36, 88)])
	indicator.color = BattleWidgets.COL_GOLD
	indicator.visible = false
	orb.add_child(indicator)
	_set_orb_active(orb, unit, false)
	return orb


func _set_orb_active(orb: Control, unit, active: bool) -> void:
	var border: Panel = orb.get_node("Border")
	var style := border.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = BattleWidgets.COL_GOLD if active else _faction_color(unit)
	style.set_border_width_all(6 if active else 4)
	orb.get_node("Indicator").visible = active


func _faction_color(unit) -> Color:
	return BattleWidgets.COL_ALLY if unit.is_player else BattleWidgets.COL_ENEMY


func _slot_center(slot: float) -> Vector2:
	return Vector2(size.x * 0.5 + slot * SLOT_SPACING, ARC_TOP + slot * slot * ARC_CURVE)


func _orb_position(slot: int) -> Vector2:
	return _slot_center(float(slot)) - Vector2(ORB_SIZE, ORB_SIZE) * 0.5


func _orb_scale(slot: int) -> Vector2:
	var factor: float = SLOT_SIZES[mini(3, absi(slot))] / ORB_SIZE
	return Vector2(factor, factor)


func _remove_orb(unit, orb: Control) -> void:
	if _orbs.get(unit) != orb:
		return
	_orbs.erase(unit)
	orb.queue_free()


func _kill_tweens() -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()


func _clear_orbs() -> void:
	_kill_tweens()
	for orb in _orbs.values():
		orb.queue_free()
	_orbs.clear()
