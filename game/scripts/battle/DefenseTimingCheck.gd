class_name DefenseTimingCheck
extends Control
## 秒制受击动作场：固定流程 + 冻结参数驱动预警、物理遮罩与防御输入。

signal timing_resolved(hit_results: Array)
signal impact_feedback(amplitude: float)

const MOVE_SPEED: float = 320.0
const DASH_SPEED: float = 960.0
const PLAYER_RADIUS: float = 10.0
const PARRY_DURATION: float = 0.25
const DODGE_DURATION: float = 0.20
const PERFECT_DURATION: float = 0.05
const HIT_INVULNERABILITY: float = 0.50
const HIT_STOP_FAILURE: float = 0.07
const HIT_STOP_BLOCK: float = 0.035
const HIT_STOP_PARRY: float = 0.06
const BLOCK_SFX: Array[AudioStream] = [
	preload("res://assets/derived/audio/sfx/combat/sword_hit_01.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_02.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_03.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_04.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_05.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_06.wav"),
	preload("res://assets/derived/audio/sfx/combat/sword_hit_07.wav"),
]
const PERFECT_SLASH_SFX: AudioStreamWAV = preload("res://assets/derived/audio/sfx/combat/perfect_defense_slash.wav")
const HEAVY_IMPACT_SFX: AudioStreamWAV = preload("res://assets/derived/audio/sfx/combat/heavy_iron_impact.wav")
const INPUT_BUFFER_SECONDS: float = 0.10
const PARRY_ACTION: StringName = &"ui_accept"
const DODGE_ACTION: StringName = &"run"
const ENEMY_ORIGIN_INSET: float = 32.0
const MAX_BARRAGE_BULLETS: int = 36
const BARRAGE_AIM_SPREAD_RADIANS: float = PI / 18.0
# ponytail: 单一比例在统一相位入口缩放，避免逐攻击模板复制时长。
const ACTION_DURATION_SCALE: float = 1.5
# ponytail: 只限制碰撞采样距离；流程时长仍按秒累计，不依赖固定 tick。
const MAX_ACTIVE_SUBSTEP_SECONDS: float = PLAYER_RADIUS / DASH_SPEED
const MAX_FRONT_SAMPLE_DISTANCE: float = 4.0
const SLASH_MAX_LOCAL_SPEED: float = 600.0
const SLASH_FRONT_SPAN_SCALE: float = 2.2
const SLASH_FRAME_HEIGHT: float = 47.0
const ATTACK_SPRITE_FRAMES: SpriteFrames = preload(
	"res://assets/derived/combat_vfx/combat_attack_frames.tres")
const VFX_BONE_WHITE := Color(0.82, 0.79, 0.70)
const VFX_COLD_BLUE := Color(0.32, 0.70, 0.80)
const VFX_DARK_BLOOD := Color(0.68, 0.46, 0.46)
const VFX_EMBER := Color(0.94, 0.52, 0.28)
# alpha >= 0.5 的最大连续实心区域，经逐帧剔除孤立粒子后记录；坐标以 64x47 帧中心为原点。
const SLASH_FRONT_POINTS: Array[Vector2] = [
	Vector2(-26.0, -15.5), Vector2(-20.0, -19.5),
	Vector2(-29.0, -12.5), Vector2(-22.0, -18.5),
	Vector2(21.0, 3.5), Vector2(27.0, -6.5),
	Vector2(-1.0, 13.5), Vector2(10.0, 11.5),
	Vector2(-1.0, 13.5), Vector2(10.0, 11.5),
	Vector2(-19.0, 8.5), Vector2(-1.0, 13.5),
	Vector2(-19.0, 8.5), Vector2(-1.0, 13.5),
	Vector2(-19.0, 8.5), Vector2(-1.0, 13.5),
	Vector2(-19.0, 8.5), Vector2(-1.0, 13.5),
]
const SLASH_FRONT_WIDTHS: Array[float] = [3.0, 5.0, 6.0, 7.0, 7.0, 5.0, 5.0, 4.0, 3.0]
# 两个抓痕关键帧各保留三条平行窄前沿；右侧高亮头部伤人，左侧尾迹不纳入遮罩。
const CLAW_FRONT_POINTS: Array[Vector2] = [
	Vector2(12.0, -8.0), Vector2(24.0, -8.0),
	Vector2(14.0, 0.0), Vector2(27.0, 0.0),
	Vector2(12.0, 8.0), Vector2(24.0, 8.0),
	Vector2(18.0, -8.0), Vector2(30.0, -8.0),
	Vector2(20.0, 0.0), Vector2(33.0, 0.0),
	Vector2(18.0, 8.0), Vector2(30.0, 8.0),
]
const CLAW_FRONT_WIDTHS: Array[float] = [3.0, 4.0]

enum Phase { TELEGRAPH, ACTIVE, GAP }

var _stance: BattleUnit.Stance = BattleUnit.Stance.ATTACK
var _running: bool = false
var _pattern_id: String = EnemyAI.PATTERN_FALLBACK_THRUST
var _arena_rect: Rect2 = Rect2()
var _player_position: Vector2 = Vector2.ZERO
var _enemy_origin: Vector2 = Vector2.ZERO
var _last_direction: Vector2 = Vector2.DOWN
var _stages: Array[Dictionary] = []
var _stage_index: int = 0
var _phase: Phase = Phase.TELEGRAPH
var _phase_elapsed: float = 0.0
var _active_progress: float = 0.0
var _total_elapsed: float = 0.0
var _reaction_started_at: float = -1.0
var _reaction_ends_at: float = -1.0
# ponytail: 单槽覆盖足够处理停顿/动作尾端抢输入；期限与锁定共用动作场时钟。
var _buffered_action: StringName = &""
var _buffered_direction: Vector2 = Vector2.ZERO
var _buffered_until_elapsed: float = 0.0
var _last_physics_tick_usec: int = 0
var _last_physics_delta: float = 1.0 / 60.0
var _hit_invulnerable_until: float = -1.0
var _stage_contact_resolved: bool = false
var _hit_results: Array = []
var _stage_start: Vector2 = Vector2.ZERO
var _stage_end: Vector2 = Vector2.ZERO
var _hazard_draw_from: Vector2 = Vector2.ZERO
var _hazard_draw_to: Vector2 = Vector2.ZERO
var _hazard_draw_center: Vector2 = Vector2.ZERO
var _hazard_draw_radius: float = 0.0
var _pattern_label: String = "直线突击"
var _attack_color: Color = Color(1.0, 0.38, 0.22)
var _feedback_text: String = ""
var _feedback_color: Color = Color.WHITE
var _feedback_until: float = -1.0
var _hit_stop_remaining: float = 0.0
var _contact_position: Vector2 = Vector2.ZERO
var _incoming_direction: Vector2 = Vector2.ZERO
var _front_progress: float = 0.0
var _visual_frame: int = -1
var _sweep_radius: float = 0.0
var _front_segment_count: int = 0
var _sampled_front_width: float = 0.0
var _sampled_visual_frame: int = -1
var _max_front_sample_displacement: float = 0.0
var _front_local_segments := PackedVector2Array()
var _front_world_previous := PackedVector2Array()
var _front_world_current := PackedVector2Array()
@export var debug_attack_front: bool = false

# ponytail: 36 发共享一个 Control 的紧凑数组；超过此上限再考虑独立弹幕组件或池。
var _bullet_positions: PackedVector2Array = PackedVector2Array()
var _bullet_previous_positions: PackedVector2Array = PackedVector2Array()
var _bullet_base_velocities: PackedVector2Array = PackedVector2Array()
var _bullet_velocities: PackedVector2Array = PackedVector2Array()
var _bullet_ages: PackedFloat32Array = PackedFloat32Array()
var _bullet_active: PackedByteArray = PackedByteArray()
var _bullets_spawned: int = 0
var _bullet_subtype: String = EnemyAI.BARRAGE_STRAIGHT
var _bullet_seed: int = 1
var _bullet_speed: float = 240.0
var _bullet_radius: float = 8.0
var _bullet_spawn_interval: float = 0.10
var _bullet_wander_interval: float = 0.22
var _bullet_wander_speed: float = 110.0
var _barrage_hit_count: int = 3
var _barrage_results_recorded: int = 0

var _player_area: Area2D
var _hazard_area: Area2D
var _hazard_shape: Shape2D
var _hazard_shape_node: CollisionShape2D
var _hazard_rect_shape: RectangleShape2D
var _hazard_circle_shape: CircleShape2D
# ponytail: Demo 上限为 36 发，同一判定器内复用查询参数直到场景释放。
var _hazard_query := PhysicsShapeQueryParameters2D.new()
var _trail_particles: GPUParticles2D
var _impact_particles: GPUParticles2D
# ponytail: 单元测试会脱离场景直接实例化脚本，此时音效节点可缺省。
@onready var _block_sfx_player: AudioStreamPlayer = get_node_or_null("BlockSFX")
@onready var _perfect_sfx_player: AudioStreamPlayer = get_node_or_null("PerfectSFX")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 110
	_create_collision_areas()
	_front_local_segments.resize(6)
	_front_world_previous.resize(6)
	_front_world_current.resize(6)
	var particles: Array[GPUParticles2D] = DefenseTimingVFX.create(self)
	_trail_particles = particles[0]
	_impact_particles = particles[1]

func start(
		stance: BattleUnit.Stance,
		focus_rect: Rect2,
		pattern_id: String = EnemyAI.PATTERN_FALLBACK_THRUST,
		pattern_params: Dictionary = {}) -> void:
	_stance = stance
	_pattern_id = pattern_id
	var pattern_style: Dictionary = DefenseAttackPatterns.style(pattern_id)
	_pattern_label = pattern_style.label
	_attack_color = pattern_style.color
	_arena_rect = Rect2(
		focus_rect.position + Vector2(48.0, 176.0),
		focus_rect.size - Vector2(96.0, 304.0))
	if _arena_rect.size.x < 240.0 or _arena_rect.size.y < 120.0:
		_arena_rect = focus_rect.grow(-32.0)
	_player_position = _arena_rect.get_center() + Vector2(0.0, _arena_rect.size.y * 0.24)
	_enemy_origin = Vector2(_arena_rect.end.x - ENEMY_ORIGIN_INSET, _arena_rect.get_center().y)
	_player_area.position = _player_position
	_stages = DefenseAttackPatterns.build(
		pattern_id, pattern_params, _arena_rect, _player_position, _enemy_origin)
	_stage_index = 0
	_phase = Phase.TELEGRAPH
	_phase_elapsed = 0.0
	_active_progress = 0.0
	_total_elapsed = 0.0
	_reaction_started_at = -1.0
	_reaction_ends_at = -1.0
	_clear_reaction_buffer()
	_last_physics_tick_usec = Time.get_ticks_usec()
	_last_physics_delta = 1.0 / float(Engine.physics_ticks_per_second)
	_hit_invulnerable_until = -1.0
	_feedback_text = ""
	_feedback_until = -1.0
	_hit_stop_remaining = 0.0
	_max_front_sample_displacement = 0.0
	_clear_barrage()
	_hit_results.clear()
	_running = true
	_prepare_stage()
	set_physics_process(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_last_physics_delta = delta
	var remaining: float = delta
	# ponytail: 只暂停动作场，让镜头噪声与粒子继续播放，不引入全局 time_scale。
	if _hit_stop_remaining > 0.0:
		var paused: float = minf(remaining, _hit_stop_remaining)
		_hit_stop_remaining -= paused
		remaining -= paused
		if remaining <= 0.0:
			_last_physics_tick_usec = Time.get_ticks_usec()
			queue_redraw()
			return
	_try_consume_reaction_buffer()
	while remaining > 0.0 and _running:
		var duration: float = _phase_duration()
		var step: float = minf(remaining, maxf(0.0, duration - _phase_elapsed))
		if _phase == Phase.ACTIVE:
			step = minf(step, MAX_ACTIVE_SUBSTEP_SECONDS)
		if _buffered_action != &"" and _reaction_locked():
			step = minf(step, maxf(0.0, _reaction_ends_at - _total_elapsed))
		_phase_elapsed += step
		_total_elapsed += step
		_try_consume_reaction_buffer()
		_move_player(step)
		remaining -= step
		if _phase == Phase.ACTIVE:
			var stage: Dictionary = _stages[_stage_index]
			if stage.kind == "barrage":
				_update_barrage(step)
			else:
				var contacted: bool = _update_active_hazard()
				if not _stage_contact_resolved and contacted:
					_resolve_contact()
		if _phase_elapsed + 0.0001 >= duration:
			_advance_phase()
		elif step <= 0.0:
			break
	_last_physics_tick_usec = Time.get_ticks_usec()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _running or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var action: StringName = &""
	if _stance == BattleUnit.Stance.DEFEND and event.is_action_pressed(PARRY_ACTION):
		action = PARRY_ACTION
	elif _stance == BattleUnit.Stance.DODGE and event.is_action_pressed(DODGE_ACTION):
		action = DODGE_ACTION
	if action == &"":
		return
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if direction == Vector2.ZERO:
		direction = _last_direction
	else:
		direction = direction.normalized()
	if _hit_stop_remaining > 0.0 or _reaction_locked():
		_buffer_reaction(action, direction)
	else:
		_begin_reaction(action, direction, _estimated_input_time())
	get_viewport().set_input_as_handled()

func _reaction_locked() -> bool:
	return _reaction_started_at >= 0.0 and _total_elapsed < _reaction_ends_at

func _reaction_active() -> bool:
	return _reaction_started_at >= 0.0 \
		and _total_elapsed >= _reaction_started_at and _total_elapsed < _reaction_ends_at

func _buffer_reaction(action: StringName, direction: Vector2) -> void:
	_buffered_action = action
	_buffered_direction = direction
	_buffered_until_elapsed = _total_elapsed + INPUT_BUFFER_SECONDS

func _try_consume_reaction_buffer() -> void:
	if _buffered_action == &"":
		return
	if _total_elapsed > _buffered_until_elapsed:
		_clear_reaction_buffer()
		return
	if _hit_stop_remaining > 0.0 or _reaction_locked():
		return
	var action: StringName = _buffered_action
	var direction: Vector2 = _buffered_direction
	_clear_reaction_buffer()
	_begin_reaction(action, direction, _total_elapsed)

func _clear_reaction_buffer() -> void:
	_buffered_action = &""
	_buffered_direction = Vector2.ZERO
	_buffered_until_elapsed = 0.0

func _begin_reaction(action: StringName, direction: Vector2, started_at: float) -> void:
	_reaction_started_at = started_at
	if action == DODGE_ACTION:
		_last_direction = direction
		_reaction_ends_at = started_at + DODGE_DURATION
	else:
		_reaction_ends_at = started_at + PARRY_DURATION

func _estimated_input_time() -> float:
	var elapsed_usec: int = maxi(0, Time.get_ticks_usec() - _last_physics_tick_usec)
	return estimate_input_time(_total_elapsed, elapsed_usec, _last_physics_delta)

static func estimate_input_time(total_elapsed: float, elapsed_usec: int, physics_delta: float) -> float:
	return total_elapsed + clampf(float(elapsed_usec) / 1_000_000.0, 0.0, physics_delta)

static func classify_contact(
		stance: BattleUnit.Stance,
		reaction_age: float,
		hit_invulnerable: bool = false) -> DefenseTimingRules.Outcome:
	if hit_invulnerable:
		return DefenseTimingRules.Outcome.SUCCESS
	if stance == BattleUnit.Stance.ATTACK or reaction_age < 0.0:
		return DefenseTimingRules.Outcome.FAILURE
	var active_duration: float = PARRY_DURATION if stance == BattleUnit.Stance.DEFEND else DODGE_DURATION
	if reaction_age <= PERFECT_DURATION:
		return DefenseTimingRules.Outcome.PERFECT
	if reaction_age <= active_duration:
		return DefenseTimingRules.Outcome.SUCCESS
	return DefenseTimingRules.Outcome.FAILURE

func _create_collision_areas() -> void:
	_player_area = Area2D.new()
	_player_area.collision_layer = 0
	_player_area.collision_mask = 0
	_player_area.set_collision_layer_value(31, true)
	var player_shape_node := CollisionShape2D.new()
	var player_shape := CircleShape2D.new()
	player_shape.radius = PLAYER_RADIUS
	player_shape_node.shape = player_shape
	_player_area.add_child(player_shape_node)
	add_child(_player_area)

	_hazard_area = Area2D.new()
	_hazard_area.collision_layer = 0
	_hazard_area.collision_mask = 0
	_hazard_rect_shape = RectangleShape2D.new()
	_hazard_rect_shape.size = Vector2.ONE
	_hazard_circle_shape = CircleShape2D.new()
	_hazard_circle_shape.radius = 1.0
	_hazard_shape = _hazard_rect_shape
	_hazard_shape_node = CollisionShape2D.new()
	_hazard_shape_node.shape = _hazard_shape
	_hazard_area.add_child(_hazard_shape_node)
	_hazard_area.position = Vector2(-10000.0, -10000.0)
	add_child(_hazard_area)
	_hazard_query.collision_mask = 1 << 30
	_hazard_query.collide_with_areas = true
	_hazard_query.collide_with_bodies = false

func _prepare_stage() -> void:
	if _stage_index >= _stages.size():
		_finish()
		return
	var stage: Dictionary = _stages[_stage_index]
	_stage_contact_resolved = false
	_contact_position = Vector2.ZERO
	_incoming_direction = Vector2.ZERO
	_front_progress = 0.0
	_visual_frame = -1
	_front_segment_count = 0
	_stage_start = Vector2(stage.origin)
	_stage_end = Vector2(_arena_rect.position.x, _enemy_origin.y)
	match stage.kind:
		"aimed":
			var target: Vector2 = _player_position + Vector2(stage.offset)
			target = Vector2(
				clampf(target.x, _arena_rect.position.x, _arena_rect.end.x),
				clampf(target.y, _arena_rect.position.y, _arena_rect.end.y))
			var direction: Vector2 = (target - _enemy_origin).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.LEFT
			_stage_end = _enemy_origin + direction * _distance_to_arena_edge(_enemy_origin, direction)
		"cross":
			var direction := Vector2.LEFT.rotated(float(stage.angle))
			_stage_end = _enemy_origin + direction * _distance_to_arena_edge(_enemy_origin, direction)
		"cleave":
			var sprite_scale: float = 2.0 if _stage_index == 0 else 1.0
			var vertical_inset: float = SLASH_FRAME_HEIGHT * sprite_scale * 0.5
			_stage_start = Vector2(float(stage.x), _arena_rect.position.y + vertical_inset)
			_stage_end = Vector2(float(stage.x), _arena_rect.end.y - vertical_inset)
		"sweep":
			var direction := Vector2.from_angle(float(stage.angle_from))
			_sweep_radius = _enemy_origin.distance_to(_player_position)
			_stage_end = _enemy_origin + direction * _sweep_radius
		"area":
			_hazard_draw_center = Vector2(stage.center)
			_hazard_draw_radius = float(stage.radius)
		"barrage":
			_prepare_barrage(stage)
	_hazard_area.position = Vector2(-10000.0, -10000.0)
	_hazard_draw_from = _stage_start
	_hazard_draw_to = _stage_end

func _phase_duration() -> float:
	var stage: Dictionary = _stages[_stage_index]
	match _phase:
		Phase.TELEGRAPH: return maxf(0.01, float(stage.telegraph) * ACTION_DURATION_SCALE)
		Phase.ACTIVE: return maxf(0.01, float(stage.active) * ACTION_DURATION_SCALE)
		_: return maxf(0.01, float(stage.gap) * ACTION_DURATION_SCALE)

func _advance_phase() -> void:
	_phase_elapsed = 0.0
	match _phase:
		Phase.TELEGRAPH:
			_phase = Phase.ACTIVE
			_active_progress = 0.0
			if _stages[_stage_index].kind != "barrage":
				_update_active_hazard()
			_emit_attack_particles()
		Phase.ACTIVE:
			if _stages[_stage_index].kind == "barrage":
				_finish_barrage_results()
				_clear_barrage()
			elif not _stage_contact_resolved:
				_record_result(false, DefenseTimingRules.Outcome.SUCCESS)
			_hazard_area.position = Vector2(-10000.0, -10000.0)
			_phase = Phase.GAP
		Phase.GAP:
			_stage_index += 1
			_phase = Phase.TELEGRAPH
			_prepare_stage()

func _update_active_hazard() -> bool:
	var stage: Dictionary = _stages[_stage_index]
	var progress: float = clampf(_phase_elapsed / _phase_duration(), 0.0, 1.0)
	var previous_progress: float = _active_progress
	_active_progress = progress
	var front_animation: StringName = _front_animation_for_stage(stage)
	if front_animation != &"":
		return _update_attack_front(stage, front_animation, previous_progress, progress)
	# ponytail: 同一 stage 参数驱动物理遮罩、绘制与粒子，避免三套配置漂移。
	if stage.kind == "sweep":
		var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), progress)
		var direction := Vector2.from_angle(angle)
		var radius: float = _distance_to_arena_edge(_enemy_origin, direction)
		_set_hazard_segment(_enemy_origin, _enemy_origin + direction * radius, float(stage.width))
	elif stage.kind == "area":
		_set_hazard_circle(Vector2(stage.center), float(stage.radius))
	else:
		var from: Vector2 = _stage_start.lerp(_stage_end, previous_progress)
		var to: Vector2 = _stage_start.lerp(_stage_end, progress)
		_set_hazard_segment(from, to, float(stage.width))
	if _stage_contact_resolved or not _hazard_hits_player():
		return false
	var incoming: Vector2 = _hazard_draw_from.direction_to(_hazard_draw_to)
	if incoming == Vector2.ZERO:
		incoming = _stage_start.direction_to(_stage_end)
	var frame: int = -1
	if _pattern_id == EnemyAI.PATTERN_HUNTER_LOCK_THRUST \
			or _pattern_id == EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
		frame = _animation_frame_at_progress(&"hunter_ray", progress)
	_capture_contact(incoming, progress, frame)
	return true

func _front_animation_for_stage(stage: Dictionary) -> StringName:
	if _pattern_id == EnemyAI.PATTERN_MUTANT_CLEAVE and stage.kind == "cleave":
		return &"mutant_slash"
	if _pattern_id == EnemyAI.PATTERN_MUTANT_SWEEP and stage.kind == "sweep":
		return &"mutant_claw"
	return &""

func _update_attack_front(
		stage: Dictionary,
		animation: StringName,
		previous_progress: float,
		progress: float) -> bool:
	_sample_front_world(stage, animation, previous_progress, _front_world_previous)
	if _stage_contact_resolved:
		_sample_front_world(stage, animation, progress, _front_world_current)
		_set_hazard_segment(
			_front_world_current[(_front_segment_count - 1) * 2],
			_front_world_current[(_front_segment_count - 1) * 2 + 1],
			_sampled_front_width)
		return false
	var travel: float = _front_travel_bound(stage, previous_progress, progress)
	var sample_count: int = maxi(1, ceili(travel / MAX_FRONT_SAMPLE_DISTANCE))
	for sample_index in range(1, sample_count + 1):
		var sample_progress: float = lerpf(
			previous_progress, progress, float(sample_index) / float(sample_count))
		_sample_front_world(stage, animation, sample_progress, _front_world_current)
		var incoming := Vector2.ZERO
		for point_index in range(_front_segment_count * 2):
			var displacement: float = _front_world_previous[point_index].distance_to(
				_front_world_current[point_index])
			_max_front_sample_displacement = maxf(_max_front_sample_displacement, displacement)
			if point_index % 2 == 0:
				incoming += (_front_world_current[point_index] + _front_world_current[point_index + 1]) * 0.5 \
					- (_front_world_previous[point_index] + _front_world_previous[point_index + 1]) * 0.5
		for segment_index in range(_front_segment_count):
			var from: Vector2 = _front_world_current[segment_index * 2]
			var to: Vector2 = _front_world_current[segment_index * 2 + 1]
			_set_hazard_segment(from, to, _sampled_front_width)
			if _hazard_hits_player():
				_capture_contact(incoming, sample_progress, _sampled_visual_frame)
				return true
		for point_index in range(_front_segment_count * 2):
			_front_world_previous[point_index] = _front_world_current[point_index]
	return false

func _sample_front_world(
		stage: Dictionary,
		animation: StringName,
		progress: float,
		output: PackedVector2Array) -> void:
	_sample_attack_front(animation, progress, _front_local_segments)
	var anchor: Vector2
	var rotation: float = 0.0
	var scale := Vector2.ONE
	if stage.kind == "sweep":
		var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), progress)
		anchor = _enemy_origin + Vector2.from_angle(angle) * _sweep_radius
		rotation = angle + PI * 0.5
		scale = Vector2(2.0, float(stage.width) / 16.0)
	else:
		anchor = _stage_start.lerp(_stage_end, progress)
		scale = Vector2.ONE * (2.0 if _stage_index == 0 else 1.0)
	for point_index in range(_front_segment_count * 2):
		var local_point := Vector2(
			_front_local_segments[point_index].x * scale.x,
			_front_local_segments[point_index].y * scale.y)
		output[point_index] = anchor + local_point.rotated(rotation)
	_sampled_front_width *= scale.x
	if stage.kind == "cleave":
		var midpoint: Vector2 = (output[0] + output[1]) * 0.5
		var direction: Vector2 = output[0].direction_to(output[1])
		var span: float = minf(float(stage.width), output[0].distance_to(output[1]) * SLASH_FRONT_SPAN_SCALE)
		output[0] = midpoint - direction * span * 0.5
		output[1] = midpoint + direction * span * 0.5

func _sample_attack_front(
		animation: StringName,
		progress: float,
		output: PackedVector2Array) -> void:
	var slash: bool = animation == &"mutant_slash"
	var points: Array[Vector2] = SLASH_FRONT_POINTS if slash else CLAW_FRONT_POINTS
	var widths: Array[float] = SLASH_FRONT_WIDTHS if slash else CLAW_FRONT_WIDTHS
	_front_segment_count = 1 if slash else 3
	var frame_count: int = ATTACK_SPRITE_FRAMES.get_frame_count(animation)
	var target_time: float = clampf(progress, 0.0, 1.0) * _animation_duration(animation)
	var elapsed: float = 0.0
	var frame: int = frame_count - 1
	var next_frame: int = frame
	var blend: float = 0.0
	var speed: float = maxf(0.001, ATTACK_SPRITE_FRAMES.get_animation_speed(animation))
	for frame_index in range(frame_count):
		var duration: float = ATTACK_SPRITE_FRAMES.get_frame_duration(animation, frame_index) / speed
		if target_time < elapsed + duration or frame_index == frame_count - 1:
			frame = frame_index
			next_frame = mini(frame + 1, frame_count - 1)
			blend = clampf((target_time - elapsed) / duration, 0.0, 1.0) if next_frame != frame else 0.0
			break
		elapsed += duration
	var points_per_frame: int = _front_segment_count * 2
	for point_index in range(points_per_frame):
		output[point_index] = points[frame * points_per_frame + point_index].lerp(
			points[next_frame * points_per_frame + point_index], blend)
	_sampled_front_width = lerpf(widths[frame], widths[next_frame], blend)
	_sampled_visual_frame = frame

func _front_travel_bound(stage: Dictionary, from_progress: float, to_progress: float) -> float:
	var progress_delta: float = absf(to_progress - from_progress)
	if stage.kind == "sweep":
		var arc_distance: float = absf(float(stage.angle_to) - float(stage.angle_from)) \
			* (_sweep_radius + float(stage.width))
		return progress_delta * (arc_distance + 48.0)
	var sprite_scale: float = 2.0 if _stage_index == 0 else 1.0
	return progress_delta * (_stage_start.distance_to(_stage_end)
		+ SLASH_MAX_LOCAL_SPEED * sprite_scale + float(stage.width) * 9.0)

static func attack_front_frame_times(animation: StringName) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var elapsed: float = 0.0
	var speed: float = maxf(0.001, ATTACK_SPRITE_FRAMES.get_animation_speed(animation))
	for frame_index in range(ATTACK_SPRITE_FRAMES.get_frame_count(animation)):
		times.append(elapsed)
		elapsed += ATTACK_SPRITE_FRAMES.get_frame_duration(animation, frame_index) / speed
	return times

static func _animation_duration(animation: StringName) -> float:
	var duration: float = 0.0
	var speed: float = maxf(0.001, ATTACK_SPRITE_FRAMES.get_animation_speed(animation))
	for frame_index in range(ATTACK_SPRITE_FRAMES.get_frame_count(animation)):
		duration += ATTACK_SPRITE_FRAMES.get_frame_duration(animation, frame_index) / speed
	return duration

static func _animation_frame_at_progress(animation: StringName, progress: float) -> int:
	var target_time: float = clampf(progress, 0.0, 1.0) * _animation_duration(animation)
	var elapsed: float = 0.0
	var frame_count: int = ATTACK_SPRITE_FRAMES.get_frame_count(animation)
	var speed: float = maxf(0.001, ATTACK_SPRITE_FRAMES.get_animation_speed(animation))
	for frame_index in range(frame_count):
		elapsed += ATTACK_SPRITE_FRAMES.get_frame_duration(animation, frame_index) / speed
		if target_time < elapsed or frame_index == frame_count - 1:
			return frame_index
	return frame_count - 1

func _capture_contact(incoming: Vector2, progress: float, frame: int) -> void:
	_incoming_direction = incoming.normalized()
	if _incoming_direction == Vector2.ZERO:
		_incoming_direction = _enemy_origin.direction_to(_player_position)
	_contact_position = _player_position - _incoming_direction * PLAYER_RADIUS
	_front_progress = clampf(progress, 0.0, 1.0)
	_visual_frame = frame

func _prepare_barrage(stage: Dictionary) -> void:
	var bullet_count: int = clampi(int(stage.bullet_count), 1, MAX_BARRAGE_BULLETS)
	_bullet_positions.resize(bullet_count)
	_bullet_previous_positions.resize(bullet_count)
	_bullet_base_velocities.resize(bullet_count)
	_bullet_velocities.resize(bullet_count)
	_bullet_ages.resize(bullet_count)
	_bullet_active.resize(bullet_count)
	_bullet_active.fill(0)
	_bullets_spawned = 0
	_bullet_subtype = String(stage.subtype)
	_bullet_seed = int(stage.seed)
	_bullet_speed = maxf(1.0, float(stage.bullet_speed))
	_bullet_radius = maxf(1.0, float(stage.bullet_radius))
	_bullet_spawn_interval = maxf(0.01, float(stage.spawn_interval))
	_bullet_wander_interval = maxf(0.01, float(stage.wander_interval))
	_bullet_wander_speed = maxf(0.0, float(stage.wander_vertical_speed))
	_barrage_hit_count = clampi(int(stage.hit_count), 1, 3)
	_barrage_results_recorded = 0

func _clear_barrage() -> void:
	_bullet_positions.clear()
	_bullet_previous_positions.clear()
	_bullet_base_velocities.clear()
	_bullet_velocities.clear()
	_bullet_ages.clear()
	_bullet_active.clear()
	_bullets_spawned = 0

func _update_barrage(delta: float) -> void:
	while _bullets_spawned < _bullet_positions.size() \
			and float(_bullets_spawned) * _bullet_spawn_interval <= _phase_elapsed + 0.0001:
		_spawn_barrage_bullet(_bullets_spawned)
		_bullets_spawned += 1
	var top: float = _arena_rect.position.y + _bullet_radius
	var bottom: float = _arena_rect.end.y - _bullet_radius
	for index in range(_bullets_spawned):
		if _bullet_active[index] == 0:
			continue
		var previous: Vector2 = _bullet_positions[index]
		var age: float = _bullet_ages[index] + delta
		var base_velocity: Vector2 = _bullet_base_velocities[index]
		var velocity: Vector2 = base_velocity
		if _bullet_subtype == EnemyAI.BARRAGE_MONTE_CARLO:
			var segment: int = floori(age / _bullet_wander_interval)
			velocity += base_velocity.orthogonal().normalized() * barrage_vertical_speed(
				_bullet_seed, index, segment, _bullet_wander_speed)
		var position: Vector2 = previous + velocity * delta
		if position.y < top:
			position.y = top
			velocity.y = absf(velocity.y)
			base_velocity.y = absf(base_velocity.y)
		elif position.y > bottom:
			position.y = bottom
			velocity.y = -absf(velocity.y)
			base_velocity.y = -absf(base_velocity.y)
		_bullet_previous_positions[index] = previous
		_bullet_positions[index] = position
		_bullet_base_velocities[index] = base_velocity
		_bullet_velocities[index] = velocity
		_bullet_ages[index] = age
		if position.x < _arena_rect.position.x - _bullet_radius:
			_bullet_active[index] = 0
			continue
		if swept_circle_hits(previous, position, _player_position, PLAYER_RADIUS + _bullet_radius):
			_bullet_active[index] = 0
			var bolt_duration: float = _animation_duration(&"hunter_bolt")
			var bolt_progress: float = fposmod(age, bolt_duration) / bolt_duration
			_capture_contact(
				velocity, clampf(_phase_elapsed / _phase_duration(), 0.0, 1.0),
				_animation_frame_at_progress(&"hunter_bolt", bolt_progress))
			_resolve_barrage_contact()

func _spawn_barrage_bullet(index: int) -> void:
	var aim_direction: Vector2 = _enemy_origin.direction_to(_player_position)
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.LEFT
	var aim_offset: float = barrage_vertical_speed(
		_bullet_seed, index, -1, BARRAGE_AIM_SPREAD_RADIANS)
	var velocity: Vector2 = aim_direction.rotated(aim_offset) * _bullet_speed
	_bullet_positions[index] = _enemy_origin
	_bullet_previous_positions[index] = _enemy_origin
	_bullet_base_velocities[index] = velocity
	_bullet_velocities[index] = velocity
	_bullet_ages[index] = 0.0
	_bullet_active[index] = 1

static func barrage_vertical_speed(
		seed_value: int, bullet_index: int, segment_index: int, max_speed: float) -> float:
	var sample_hash: int = hash(Vector3i(seed_value, bullet_index, segment_index))
	var normalized: float = float(posmod(sample_hash, 20_001)) / 10_000.0 - 1.0
	return normalized * max_speed

static func swept_circle_hits(
		from: Vector2, to: Vector2, target: Vector2, combined_radius: float) -> bool:
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target, from, to)
	return closest.distance_squared_to(target) <= combined_radius * combined_radius

func _set_hazard_segment(from: Vector2, to: Vector2, width: float) -> void:
	var delta: Vector2 = to - from
	if _hazard_shape != _hazard_rect_shape:
		_hazard_shape = _hazard_rect_shape
		_hazard_shape_node.shape = _hazard_shape
	_hazard_rect_shape.size = Vector2(maxf(width, delta.length() + width), width)
	_hazard_area.position = (from + to) * 0.5
	_hazard_area.rotation = delta.angle()
	_hazard_draw_from = from
	_hazard_draw_to = to

func _set_hazard_circle(center: Vector2, radius: float) -> void:
	if _hazard_shape != _hazard_circle_shape:
		_hazard_shape = _hazard_circle_shape
		_hazard_shape_node.shape = _hazard_shape
	if not is_equal_approx(_hazard_circle_shape.radius, radius):
		_hazard_circle_shape.radius = radius
	_hazard_area.position = center
	_hazard_area.rotation = 0.0
	_hazard_draw_center = center
	_hazard_draw_radius = radius

func _distance_to_arena_edge(origin: Vector2, direction: Vector2) -> float:
	var distance: float = INF
	if direction.x > 0.0001:
		distance = minf(distance, (_arena_rect.end.x - origin.x) / direction.x)
	elif direction.x < -0.0001:
		distance = minf(distance, (_arena_rect.position.x - origin.x) / direction.x)
	if direction.y > 0.0001:
		distance = minf(distance, (_arena_rect.end.y - origin.y) / direction.y)
	elif direction.y < -0.0001:
		distance = minf(distance, (_arena_rect.position.y - origin.y) / direction.y)
	return maxf(0.0, distance)

func _hazard_hits_player() -> bool:
	_hazard_query.shape = _hazard_shape
	_hazard_query.transform = _hazard_area.global_transform
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_hazard_query, 2):
		if hit.get("collider") == _player_area:
			return true
	return false

func _resolve_contact() -> void:
	var invulnerable: bool = _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _hit_invulnerable_until
	var outcome := _classify_current_contact(invulnerable)
	_apply_contact_impact(outcome)
	_record_result(not invulnerable, outcome)
	if _stance == BattleUnit.Stance.DEFEND and outcome == DefenseTimingRules.Outcome.FAILURE:
		# ponytail: 失败后只保留当前段，让受击反馈有时间播完。
		_stages.resize(_stage_index + 1)
		_stages[_stage_index].gap = maxf(0.35, float(_stages[_stage_index].gap))

func _resolve_barrage_contact() -> void:
	if _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _hit_invulnerable_until:
		return
	var outcome := _classify_current_contact(false)
	_apply_contact_impact(outcome)
	if _stance == BattleUnit.Stance.DODGE and outcome != DefenseTimingRules.Outcome.FAILURE:
		# ponytail: 成功闪避保留反馈与奖励，但不消耗最多三个实际受击槽。
		_append_hit_result(
			_hit_results.size(), _barrage_hit_count, true, outcome)
		return
	if _barrage_results_recorded >= _barrage_hit_count:
		return
	_append_hit_result(
		_barrage_results_recorded, _barrage_hit_count, true, outcome)
	_barrage_results_recorded += 1
	if _stance == BattleUnit.Stance.DEFEND and outcome == DefenseTimingRules.Outcome.FAILURE:
		while _barrage_results_recorded < _barrage_hit_count:
			_append_hit_result(
				_barrage_results_recorded, _barrage_hit_count, true,
				DefenseTimingRules.Outcome.FAILURE)
			_barrage_results_recorded += 1
		_phase_elapsed = _phase_duration()

func _finish_barrage_results() -> void:
	while _barrage_results_recorded < _barrage_hit_count:
		_append_hit_result(
			_barrage_results_recorded, _barrage_hit_count, false,
			DefenseTimingRules.Outcome.SUCCESS)
		_barrage_results_recorded += 1

func _classify_current_contact(hit_invulnerable: bool) -> DefenseTimingRules.Outcome:
	var reaction_age: float = _total_elapsed - _reaction_started_at \
		if _reaction_started_at >= 0.0 else -1.0
	return classify_contact(_stance, reaction_age, hit_invulnerable)

func _apply_contact_impact(outcome: DefenseTimingRules.Outcome) -> void:
	_emit_impact_particles(outcome)
	if outcome == DefenseTimingRules.Outcome.FAILURE:
		_hit_stop_remaining = HIT_STOP_FAILURE
		impact_feedback.emit(12.0)
	elif _stance == BattleUnit.Stance.DEFEND:
		_hit_stop_remaining = HIT_STOP_PARRY if outcome == DefenseTimingRules.Outcome.PERFECT else HIT_STOP_BLOCK
		impact_feedback.emit(16.0 if outcome == DefenseTimingRules.Outcome.PERFECT else 7.0)
		_play_block_sfx(outcome)
	if _stance == BattleUnit.Stance.DODGE and outcome == DefenseTimingRules.Outcome.FAILURE:
		_hit_invulnerable_until = _total_elapsed + HIT_INVULNERABILITY

func _play_block_sfx(outcome: DefenseTimingRules.Outcome) -> void:
	if _block_sfx_player == null \
			or (outcome == DefenseTimingRules.Outcome.PERFECT and _perfect_sfx_player == null):
		return
	if outcome == DefenseTimingRules.Outcome.PERFECT:
		_block_sfx_player.stream = HEAVY_IMPACT_SFX
		_block_sfx_player.volume_db = -8.0
		_block_sfx_player.play()
		_perfect_sfx_player.stream = PERFECT_SLASH_SFX
		_perfect_sfx_player.volume_db = -5.0
		_perfect_sfx_player.play()
	else:
		_block_sfx_player.stream = BLOCK_SFX.pick_random()
		_block_sfx_player.volume_db = -4.0
		_block_sfx_player.play()

func _record_result(contact: bool, outcome: DefenseTimingRules.Outcome) -> void:
	if _stage_contact_resolved:
		return
	_stage_contact_resolved = true
	_append_hit_result(_stage_index, _stages.size(), contact, outcome)

func _append_hit_result(
		hit_index: int,
		hit_count: int,
		contact: bool,
		outcome: DefenseTimingRules.Outcome) -> void:
	_set_feedback(contact, outcome)
	_hit_results.append({
		"hit_index": hit_index,
		"hit_count": hit_count,
		"contact": contact,
		"contact_time": _total_elapsed,
		"reaction_time": _reaction_started_at,
		"outcome": outcome,
		"contact_position": _contact_position if contact else Vector2.ZERO,
		"incoming_direction": _incoming_direction if contact else Vector2.ZERO,
		"front_progress": _front_progress if contact else 0.0,
		"visual_frame": _visual_frame if contact else -1,
	})

func _move_player(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		_last_direction = direction.normalized()
	var parrying: bool = _stance == BattleUnit.Stance.DEFEND and _reaction_active()
	var dashing: bool = _stance == BattleUnit.Stance.DODGE and _reaction_active()
	if not parrying:
		_player_position += (_last_direction * DASH_SPEED if dashing else direction * MOVE_SPEED) * delta
	var bounds := _arena_rect.grow(-PLAYER_RADIUS)
	_player_position = Vector2(
		clampf(_player_position.x, bounds.position.x, bounds.end.x),
		clampf(_player_position.y, bounds.position.y, bounds.end.y))
	_player_area.position = _player_position

func _finish() -> void:
	if not _running:
		return
	_running = false
	set_physics_process(false)
	timing_resolved.emit(_hit_results.duplicate(true))
	queue_free()

func _emit_attack_particles() -> void:
	var stage: Dictionary = _stages[_stage_index]
	# ponytail: 五种 sprite 攻击直接绘制既有 SpriteFrames，不再叠一套程序尾迹。
	if _pattern_id in [
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST,
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST,
		EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE,
		EnemyAI.PATTERN_MUTANT_SWEEP,
		EnemyAI.PATTERN_MUTANT_CLEAVE,
	]:
		return
	_trail_particles.modulate = _attack_color
	var material := _trail_particles.process_material as ParticleProcessMaterial
	if stage.kind == "area":
		_trail_particles.position = Vector2(stage.center)
		_trail_particles.rotation = 0.0
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = float(stage.radius) * 0.78
		material.direction = Vector3(0.0, -1.0, 0.0)
	else:
		var delta: Vector2 = _stage_end - _stage_start
		_trail_particles.position = (_stage_start + _stage_end) * 0.5
		_trail_particles.rotation = delta.angle()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		material.emission_box_extents = Vector3(delta.length() * 0.5, float(stage.width) * 0.32, 1.0)
		material.direction = Vector3(1.0, 0.0, 0.0)
	_trail_particles.restart()
	_trail_particles.emitting = true

func _emit_impact_particles(outcome: DefenseTimingRules.Outcome) -> void:
	_impact_particles.position = _contact_position if _contact_position != Vector2.ZERO else _player_position
	match outcome:
		DefenseTimingRules.Outcome.PERFECT:
			_impact_particles.modulate = Color(1.0, 0.86, 0.32)
		DefenseTimingRules.Outcome.SUCCESS:
			_impact_particles.modulate = Color(0.42, 0.88, 1.0)
		_:
			_impact_particles.modulate = Color(1.0, 0.24, 0.20)
	_impact_particles.restart()
	_impact_particles.emitting = true

func _set_feedback(contact: bool, outcome: DefenseTimingRules.Outcome) -> void:
	if not contact:
		_feedback_text = "避开"
		_feedback_color = Color(0.55, 0.86, 1.0)
	elif outcome == DefenseTimingRules.Outcome.PERFECT:
		_feedback_text = "完美弹反" if _stance == BattleUnit.Stance.DEFEND else "完美闪避"
		_feedback_color = Color(1.0, 0.86, 0.30)
	elif outcome == DefenseTimingRules.Outcome.SUCCESS:
		_feedback_text = "格挡" if _stance == BattleUnit.Stance.DEFEND else "闪避"
		_feedback_color = Color(0.46, 0.86, 1.0)
	else:
		_feedback_text = "受击"
		_feedback_color = Color(1.0, 0.28, 0.22)
	_feedback_until = _total_elapsed + 0.55

func _draw_attack_texture(
		animation: StringName,
		frame: int,
		position: Vector2,
		rotation: float,
		scale: Vector2,
		tint: Color) -> void:
	var texture: Texture2D = ATTACK_SPRITE_FRAMES.get_frame_texture(animation, frame)
	if texture == null:
		return
	draw_set_transform(position.round(), rotation, scale)
	draw_texture(texture, -texture.get_size() * 0.5, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_attack_sprites(stage: Dictionary) -> bool:
	if _pattern_id == EnemyAI.PATTERN_HUNTER_LOCK_THRUST \
			or _pattern_id == EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
		var direction: Vector2 = _stage_start.direction_to(_stage_end)
		var position: Vector2 = _stage_start.lerp(_stage_end, _active_progress)
		var scale_y: float = float(clampi(roundi(float(stage.width) / 10.0), 3, 4))
		_draw_attack_texture(
			&"hunter_ray", _animation_frame_at_progress(&"hunter_ray", _active_progress),
			position, direction.angle(), Vector2(3.0, scale_y), VFX_COLD_BLUE)
		return true
	if _pattern_id == EnemyAI.PATTERN_HUNTER_SLOW_BARRAGE:
		var duration: float = _animation_duration(&"hunter_bolt")
		for index in range(_bullets_spawned):
			if _bullet_active[index] == 0:
				continue
			var progress: float = fposmod(_bullet_ages[index], duration) / duration
			_draw_attack_texture(
				&"hunter_bolt", _animation_frame_at_progress(&"hunter_bolt", progress),
				_bullet_positions[index], _bullet_velocities[index].angle(),
				Vector2.ONE * 2.0, VFX_COLD_BLUE)
		return true
	if _pattern_id == EnemyAI.PATTERN_MUTANT_SWEEP:
		var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), _active_progress)
		var rotation: float = angle + PI * 0.5
		var anchor: Vector2 = _enemy_origin + Vector2.from_angle(angle) * _sweep_radius
		var frame: int = _animation_frame_at_progress(&"mutant_claw", _active_progress)
		for index in range(3):
			var offset: float = lerpf(-float(stage.width) * 0.5, float(stage.width) * 0.5, float(index) * 0.5)
			_draw_attack_texture(
				&"mutant_claw", frame, anchor + Vector2(0.0, offset).rotated(rotation),
				rotation, Vector2.ONE * 2.0, Color(VFX_DARK_BLOOD, 0.92 - float(index) * 0.08))
		return true
	if _pattern_id == EnemyAI.PATTERN_MUTANT_CLEAVE:
		var scale_value: float = 2.0 if _stage_index == 0 else 1.0
		_draw_attack_texture(
			&"mutant_slash", _animation_frame_at_progress(&"mutant_slash", _active_progress),
			_stage_start.lerp(_stage_end, _active_progress), 0.0,
			Vector2.ONE * scale_value, VFX_BONE_WHITE if _stage_index == 0 else VFX_EMBER)
		return true
	return false

func _draw() -> void:
	if _arena_rect.size == Vector2.ZERO:
		return
	draw_rect(_arena_rect, Color(0.025, 0.02, 0.035, 0.92), true)
	draw_rect(_arena_rect, Color(0.72, 0.63, 0.42, 0.65), false, 3.0)
	if _running and _stage_index < _stages.size():
		var stage: Dictionary = _stages[_stage_index]
		if _phase == Phase.TELEGRAPH:
			if stage.kind == "barrage":
				for lane in range(5):
					var lane_y: float = lerpf(
						_arena_rect.position.y + 24.0, _arena_rect.end.y - 24.0,
						float(lane) / 4.0)
					draw_line(_enemy_origin, Vector2(_arena_rect.position.x, lane_y),
						Color(_attack_color, 0.10), 4.0, false)
			elif stage.kind == "area":
				var warning_progress: float = clampf(_phase_elapsed / _phase_duration(), 0.0, 1.0)
				draw_circle(_hazard_draw_center, _hazard_draw_radius, Color(_attack_color, 0.12))
				draw_arc(_hazard_draw_center, _hazard_draw_radius, 0.0, TAU, 64, Color(_attack_color, 0.82), 5.0, true)
				draw_arc(_hazard_draw_center, lerpf(_hazard_draw_radius * 1.35, _hazard_draw_radius, warning_progress),
					0.0, TAU, 64, Color(_attack_color.lightened(0.55), 0.85), 3.0, true)
			elif stage.kind == "sweep":
				var width: float = float(stage.width)
				for index in range(9):
					var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), float(index) / 8.0)
					var direction := Vector2.from_angle(angle)
					var center: Vector2 = _enemy_origin + direction * _sweep_radius
					var tangent: Vector2 = direction.orthogonal() * width * 0.32
					draw_line(center - tangent, center + tangent,
						Color(_attack_color, 0.22), maxf(2.0, width * 0.10), false)
			else:
				var width: float = float(stage.width)
				draw_line(_hazard_draw_from, _hazard_draw_to, Color(_attack_color, 0.13),
					width + 8.0, false)
				draw_dashed_line(_hazard_draw_from, _hazard_draw_to, Color(_attack_color, 0.50),
					maxf(3.0, width * 0.22), 18.0, false)
		elif _phase == Phase.ACTIVE:
			var sprites_drawn: bool = _draw_attack_sprites(stage)
			if not sprites_drawn and stage.kind == "area":
				draw_circle(_hazard_draw_center, _hazard_draw_radius, Color(_attack_color, 0.52))
				draw_arc(_hazard_draw_center, _hazard_draw_radius, 0.0, TAU, 64,
					_attack_color.lightened(0.55), 7.0, true)
			elif not sprites_drawn:
				var width: float = float(stage.width)
				draw_line(_hazard_draw_from, _hazard_draw_to, Color(_attack_color, 0.72), width + 8.0, true)
				draw_line(_hazard_draw_from, _hazard_draw_to, _attack_color.lightened(0.55), maxf(3.0, width * 0.22), true)
		if debug_attack_front and _phase == Phase.ACTIVE and _front_segment_count > 0:
			for segment_index in range(_front_segment_count):
				draw_line(
					_front_world_current[segment_index * 2],
					_front_world_current[segment_index * 2 + 1],
					Color(0.20, 1.0, 0.78, 0.95), maxf(2.0, _sampled_front_width), false)
	draw_circle(_enemy_origin, 9.0, Color(0.18, 0.03, 0.04, 0.96))
	draw_arc(_enemy_origin, 11.0, 0.0, TAU, 24, Color(0.96, 0.28, 0.24), 3.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, _arena_rect.position + Vector2(16.0, 28.0),
		"%s  %d/%d" % [_pattern_label, mini(_stage_index + 1, _stages.size()), _stages.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.86, 0.82, 0.74))
	var player_color := Color(0.98, 0.78, 0.22) if _reaction_active() else Color(0.48, 0.78, 1.0)
	if _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _hit_invulnerable_until:
		player_color.a = 0.35 if int(_total_elapsed * 20.0) % 2 == 0 else 1.0
	var dashing: bool = _stance == BattleUnit.Stance.DODGE and _reaction_active()
	if dashing:
		for index in range(1, 4):
			draw_circle(_player_position - _last_direction * index * 14.0, PLAYER_RADIUS - index,
				Color(0.38, 0.76, 1.0, 0.34 / index))
	draw_circle(_player_position, PLAYER_RADIUS, player_color)
	if _stance == BattleUnit.Stance.DEFEND and _reaction_active():
		draw_arc(_player_position, PLAYER_RADIUS + 12.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.28), 4.0)
	if _total_elapsed <= _feedback_until:
		draw_string(font, _arena_rect.position + Vector2(_arena_rect.size.x * 0.5 - 180.0, 58.0),
			_feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 26, _feedback_color)
