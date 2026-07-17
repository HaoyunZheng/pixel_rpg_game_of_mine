class_name DefenseTimingCheck
extends Control
## 单次 60 tick 占位判定。只采集首次正确按键并回传 tick；伤害规则在 DefenseTimingRules。

signal timing_resolved(input_tick: int)

const TIMING_RULES := preload("res://scripts/battle/DefenseTimingRules.gd")
const HIT_TICK: int = TIMING_RULES.HIT_TICK
const DEFEND_KEY: Key = KEY_Z
const DODGE_KEY: Key = KEY_SHIFT

var _stance: BattleUnit.Stance = BattleUnit.Stance.ATTACK
var _tick: int = 0
var _input_tick: int = -1
var _running: bool = false
var _bar_rect: Rect2 = Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110

func start(stance: BattleUnit.Stance, focus_rect: Rect2) -> void:
	_stance = stance
	_tick = 0
	_input_tick = -1
	_running = true
	_bar_rect = Rect2(
		focus_rect.get_center() - Vector2(320.0, 12.0),
		Vector2(640.0, 24.0))
	set_physics_process(true)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if not _running:
		return
	_tick += 1
	queue_redraw()
	if _tick >= HIT_TICK:
		_finish()

func _input(event: InputEvent) -> void:
	if not _running or not (event is InputEventKey) or not event.pressed:
		return
	if not event.echo:
		_record_input(event.keycode)
	accept_event()

func _record_input(keycode: Key) -> bool:
	if _input_tick >= 0:
		return false
	var expected_key: Key = DEFEND_KEY if _stance == BattleUnit.Stance.DEFEND else DODGE_KEY
	if _stance == BattleUnit.Stance.ATTACK or keycode != expected_key:
		return false
	_input_tick = _tick
	queue_redraw()
	return true

func _finish() -> void:
	if not _running:
		return
	_running = false
	set_physics_process(false)
	timing_resolved.emit(_input_tick)
	queue_free()

func _draw() -> void:
	if _bar_rect.size == Vector2.ZERO:
		return
	draw_rect(_bar_rect, Color(0.04, 0.03, 0.05, 0.92), true)
	var progress: float = clampf(float(_tick) / HIT_TICK, 0.0, 1.0)
	var fill_rect := Rect2(_bar_rect.position + Vector2(2, 2), Vector2((_bar_rect.size.x - 4) * progress, _bar_rect.size.y - 4))
	draw_rect(fill_rect, Color(0.55, 0.60, 0.68, 1.0), true)
	var hit_x: float = _bar_rect.end.x - 2.0
	draw_line(Vector2(hit_x, _bar_rect.position.y - 8), Vector2(hit_x, _bar_rect.end.y + 8), Color(0.90, 0.75, 0.29), 4.0)
	if _input_tick >= 0:
		var input_x: float = _bar_rect.position.x + _bar_rect.size.x * float(_input_tick) / HIT_TICK
		draw_line(Vector2(input_x, _bar_rect.position.y - 5), Vector2(input_x, _bar_rect.end.y + 5), Color(0.85, 0.81, 0.75), 3.0)
