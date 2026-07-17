class_name DefenseTimingCheck
extends Control
## 秒制受击动作场：固定流程 + 冻结参数驱动预警、物理遮罩与防御输入。

signal timing_resolved(hit_results: Array)

const MOVE_SPEED: float = 320.0
const DASH_SPEED: float = 960.0
const PLAYER_RADIUS: float = 10.0
const PARRY_DURATION: float = 0.25
const DODGE_DURATION: float = 0.20
const PERFECT_DURATION: float = 0.05
const HIT_INVULNERABILITY: float = 0.50

enum Phase { TELEGRAPH, ACTIVE, GAP }

var _stance: BattleUnit.Stance = BattleUnit.Stance.ATTACK
var _running: bool = false
var _arena_rect: Rect2 = Rect2()
var _player_position: Vector2 = Vector2.ZERO
var _last_direction: Vector2 = Vector2.DOWN
var _stages: Array[Dictionary] = []
var _stage_index: int = 0
var _phase: Phase = Phase.TELEGRAPH
var _phase_elapsed: float = 0.0
var _active_progress: float = 0.0
var _total_elapsed: float = 0.0
var _reaction_started_at: float = -1.0
var _reaction_ends_at: float = -1.0
var _hit_invulnerable_until: float = -1.0
var _stage_contact_resolved: bool = false
var _hit_results: Array = []
var _stage_start: Vector2 = Vector2.ZERO
var _stage_end: Vector2 = Vector2.ZERO
var _hazard_draw_from: Vector2 = Vector2.ZERO
var _hazard_draw_to: Vector2 = Vector2.ZERO
var _pattern_label: String = "直线突击"
var _attack_color: Color = Color(1.0, 0.38, 0.22)
var _feedback_text: String = ""
var _feedback_color: Color = Color.WHITE
var _feedback_until: float = -1.0

var _player_area: Area2D
var _hazard_area: Area2D
var _hazard_shape: RectangleShape2D
var _trail_particles: GPUParticles2D
var _impact_particles: GPUParticles2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110
	_create_collision_areas()
	_create_particles()

func start(
		stance: BattleUnit.Stance,
		focus_rect: Rect2,
		pattern_id: String = EnemyAI.PATTERN_FALLBACK_THRUST,
		pattern_params: Dictionary = {}) -> void:
	_stance = stance
	_set_pattern_style(pattern_id)
	_arena_rect = Rect2(
		focus_rect.position + Vector2(48.0, 176.0),
		focus_rect.size - Vector2(96.0, 304.0))
	if _arena_rect.size.x < 240.0 or _arena_rect.size.y < 120.0:
		_arena_rect = focus_rect.grow(-32.0)
	_player_position = _arena_rect.get_center() + Vector2(0.0, _arena_rect.size.y * 0.24)
	_player_area.position = _player_position
	_stages = _build_stages(pattern_id, pattern_params)
	_stage_index = 0
	_phase = Phase.TELEGRAPH
	_phase_elapsed = 0.0
	_active_progress = 0.0
	_total_elapsed = 0.0
	_reaction_started_at = -1.0
	_reaction_ends_at = -1.0
	_hit_invulnerable_until = -1.0
	_feedback_text = ""
	_feedback_until = -1.0
	_hit_results.clear()
	_running = true
	_prepare_stage()
	set_physics_process(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_total_elapsed += delta
	_move_player(delta)
	var remaining: float = delta
	while remaining > 0.0 and _running:
		var duration: float = _phase_duration()
		var step: float = minf(remaining, maxf(0.0, duration - _phase_elapsed))
		_phase_elapsed += step
		remaining -= step
		if _phase == Phase.ACTIVE:
			_update_active_hazard()
			if not _stage_contact_resolved and _hazard_hits_player():
				_resolve_contact()
		if _phase_elapsed + 0.0001 >= duration:
			_advance_phase()
		elif step <= 0.0:
			break
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _running or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _total_elapsed <= _reaction_ends_at:
		return
	if _stance == BattleUnit.Stance.DEFEND and event.is_action_pressed("ui_accept"):
		_reaction_started_at = _total_elapsed
		_reaction_ends_at = _total_elapsed + PARRY_DURATION
		get_viewport().set_input_as_handled()
	elif _stance == BattleUnit.Stance.DODGE and event.is_action_pressed("run"):
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if direction != Vector2.ZERO:
			_last_direction = direction.normalized()
			_reaction_started_at = _total_elapsed
			_reaction_ends_at = _total_elapsed + DODGE_DURATION
			get_viewport().set_input_as_handled()

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
	_hazard_shape = RectangleShape2D.new()
	_hazard_shape.size = Vector2.ONE
	var hazard_shape_node := CollisionShape2D.new()
	hazard_shape_node.shape = _hazard_shape
	_hazard_area.add_child(hazard_shape_node)
	_hazard_area.position = Vector2(-10000.0, -10000.0)
	add_child(_hazard_area)

func _build_stages(pattern_id: String, params: Dictionary) -> Array[Dictionary]:
	var stages: Array[Dictionary] = []
	var telegraph: float = float(params.get("telegraph", 0.75))
	var active: float = float(params.get("active", 0.30))
	var width: float = float(params.get("width", 28.0))
	match pattern_id:
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST:
			for index in range(int(params.get("hit_count", 2))):
				stages.append({"kind": "aimed", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.16)), "width": width,
					"offset": Vector2(params.get("aim_offset", Vector2.ZERO)).rotated(index * 0.9)})
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			var angle: float = deg_to_rad(float(params.get("angle_degrees", 26.0)))
			for index in range(2):
				stages.append({"kind": "cross", "telegraph": telegraph, "active": active,
					"gap": float(params.get("stagger", 0.22)), "width": width,
					"angle": angle if index == 0 else -angle})
		EnemyAI.PATTERN_MUTANT_SWEEP:
			var arc: float = deg_to_rad(float(params.get("arc_degrees", 120.0)))
			var clockwise: bool = bool(params.get("clockwise", true))
			for index in range(2):
				var forward: bool = clockwise if index == 0 else not clockwise
				stages.append({"kind": "sweep", "telegraph": telegraph, "active": active,
					"gap": float(params.get("gap", 0.25)), "width": width,
					"angle_from": PI * 0.5 + (arc * 0.5 if forward else -arc * 0.5),
					"angle_to": PI * 0.5 + (-arc * 0.5 if forward else arc * 0.5)})
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			var center_x: float = _arena_rect.get_center().x + float(params.get("offset_x", 0.0))
			var spacing: float = float(params.get("aftershock_spacing", 128.0))
			for offset_x in [0.0, -spacing, spacing]:
				stages.append({"kind": "cleave", "telegraph": telegraph if offset_x == 0.0 else float(params.get("aftershock_delay", 0.24)),
					"active": active, "gap": 0.12, "width": width * (1.0 if offset_x == 0.0 else 0.55),
					"x": center_x + offset_x})
		_:
			stages.append({"kind": "cleave", "telegraph": telegraph, "active": active,
				"gap": 0.15, "width": width, "x": _arena_rect.get_center().x})
	return stages

func _prepare_stage() -> void:
	if _stage_index >= _stages.size():
		_finish()
		return
	var stage: Dictionary = _stages[_stage_index]
	_stage_contact_resolved = false
	match stage.kind:
		"aimed":
			var target: Vector2 = _player_position + Vector2(stage.offset)
			target = Vector2(
				clampf(target.x, _arena_rect.position.x, _arena_rect.end.x),
				clampf(target.y, _arena_rect.position.y, _arena_rect.end.y))
			var direction: Vector2 = (target - Vector2(_arena_rect.get_center().x, _arena_rect.position.y)).normalized()
			_stage_start = target - direction * _distance_to_arena_edge(target, -direction)
			_stage_end = target + direction * _distance_to_arena_edge(target, direction)
		"cross":
			var direction := Vector2.DOWN.rotated(float(stage.angle))
			_stage_start = _arena_rect.get_center() - direction * _distance_to_arena_edge(_arena_rect.get_center(), -direction)
			_stage_end = _arena_rect.get_center() + direction * _distance_to_arena_edge(_arena_rect.get_center(), direction)
		"cleave":
			_stage_start = Vector2(float(stage.x), _arena_rect.position.y)
			_stage_end = Vector2(float(stage.x), _arena_rect.end.y)
		"sweep":
			_stage_start = _arena_rect.get_center()
			var direction := Vector2.from_angle(float(stage.angle_from))
			_stage_end = _stage_start + direction * _distance_to_arena_edge(_stage_start, direction)
	_hazard_area.position = Vector2(-10000.0, -10000.0)
	_hazard_draw_from = _stage_start
	_hazard_draw_to = _stage_end

func _phase_duration() -> float:
	var stage: Dictionary = _stages[_stage_index]
	match _phase:
		Phase.TELEGRAPH: return maxf(0.01, float(stage.telegraph))
		Phase.ACTIVE: return maxf(0.01, float(stage.active))
		_: return maxf(0.01, float(stage.gap))

func _advance_phase() -> void:
	_phase_elapsed = 0.0
	match _phase:
		Phase.TELEGRAPH:
			_phase = Phase.ACTIVE
			_active_progress = 0.0
			_update_active_hazard()
			_emit_attack_particles()
		Phase.ACTIVE:
			if not _stage_contact_resolved:
				_record_result(false, DefenseTimingRules.Outcome.SUCCESS)
			_hazard_area.position = Vector2(-10000.0, -10000.0)
			_phase = Phase.GAP
		Phase.GAP:
			_stage_index += 1
			_phase = Phase.TELEGRAPH
			_prepare_stage()

func _update_active_hazard() -> void:
	var stage: Dictionary = _stages[_stage_index]
	var progress: float = clampf(_phase_elapsed / maxf(0.01, float(stage.active)), 0.0, 1.0)
	var previous_progress: float = _active_progress
	_active_progress = progress
	if stage.kind == "sweep":
		var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), progress)
		var direction := Vector2.from_angle(angle)
		var radius: float = _distance_to_arena_edge(_arena_rect.get_center(), direction)
		_set_hazard_segment(_arena_rect.get_center(), _arena_rect.get_center() + direction * radius, float(stage.width))
	else:
		_set_hazard_segment(
			_stage_start.lerp(_stage_end, previous_progress),
			_stage_start.lerp(_stage_end, progress),
			float(stage.width))

func _set_hazard_segment(from: Vector2, to: Vector2, width: float) -> void:
	var delta: Vector2 = to - from
	_hazard_shape.size = Vector2(maxf(width, delta.length() + width), width)
	_hazard_area.position = (from + to) * 0.5
	_hazard_area.rotation = delta.angle()
	_hazard_draw_from = from
	_hazard_draw_to = to

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
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _hazard_shape
	query.transform = _hazard_area.global_transform
	query.collision_mask = 1 << 30
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 2):
		if hit.get("collider") == _player_area:
			return true
	return false

func _resolve_contact() -> void:
	var invulnerable: bool = _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _hit_invulnerable_until
	var reaction_age: float = _total_elapsed - _reaction_started_at if _reaction_started_at >= 0.0 else -1.0
	var outcome := classify_contact(_stance, reaction_age, invulnerable)
	_emit_impact_particles(outcome)
	if invulnerable:
		_record_result(false, outcome)
	else:
		_record_result(true, outcome)
	if _stance == BattleUnit.Stance.DODGE and outcome == DefenseTimingRules.Outcome.FAILURE:
		_hit_invulnerable_until = _total_elapsed + HIT_INVULNERABILITY
	if _stance == BattleUnit.Stance.DEFEND and outcome == DefenseTimingRules.Outcome.FAILURE:
		# ponytail: 失败后只保留当前段，让受击反馈有时间播完。
		_stages.resize(_stage_index + 1)
		_stages[_stage_index].gap = maxf(0.35, float(_stages[_stage_index].gap))

func _record_result(contact: bool, outcome: DefenseTimingRules.Outcome) -> void:
	if _stage_contact_resolved:
		return
	_stage_contact_resolved = true
	_set_feedback(contact, outcome)
	_hit_results.append({
		"hit_index": _stage_index,
		"hit_count": _stages.size(),
		"contact": contact,
		"contact_time": _total_elapsed,
		"reaction_time": _reaction_started_at,
		"outcome": outcome,
	})

func _move_player(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		_last_direction = direction.normalized()
	var parrying: bool = _stance == BattleUnit.Stance.DEFEND and _total_elapsed <= _reaction_ends_at
	var dashing: bool = _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _reaction_ends_at
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

func _set_pattern_style(pattern_id: String) -> void:
	match pattern_id:
		EnemyAI.PATTERN_HUNTER_LOCK_THRUST:
			_pattern_label = "猎手·锁定连刺"
			_attack_color = Color(0.42, 0.82, 1.0)
		EnemyAI.PATTERN_HUNTER_CROSS_THRUST:
			_pattern_label = "猎手·交叉穿刺"
			_attack_color = Color(0.62, 0.72, 1.0)
		EnemyAI.PATTERN_MUTANT_SWEEP:
			_pattern_label = "变异体·交替横扫"
			_attack_color = Color(0.92, 0.30, 0.48)
		EnemyAI.PATTERN_MUTANT_CLEAVE:
			_pattern_label = "变异体·蓄力重劈"
			_attack_color = Color(1.0, 0.42, 0.18)
		_:
			_pattern_label = "直线突击"
			_attack_color = Color(1.0, 0.38, 0.22)

func _create_particles() -> void:
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 12
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var texture_gradient := Gradient.new()
	texture_gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	texture_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.8),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	texture.gradient = texture_gradient

	_trail_particles = GPUParticles2D.new()
	_trail_particles.amount = 28
	_trail_particles.lifetime = 0.34
	_trail_particles.one_shot = true
	_trail_particles.explosiveness = 1.0
	_trail_particles.fixed_fps = 30
	_trail_particles.local_coords = false
	_trail_particles.visibility_rect = Rect2(-2200.0, -1400.0, 4400.0, 2800.0)
	_trail_particles.texture = texture
	_trail_particles.z_index = 121
	var trail_material := ParticleProcessMaterial.new()
	trail_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	trail_material.emission_box_extents = Vector3(16.0, 4.0, 1.0)
	trail_material.direction = Vector3(1.0, 0.0, 0.0)
	trail_material.spread = 24.0
	trail_material.initial_velocity_min = 28.0
	trail_material.initial_velocity_max = 92.0
	trail_material.gravity = Vector3.ZERO
	trail_material.damping_min = 4.0
	trail_material.damping_max = 8.0
	trail_material.scale_min = 0.35
	trail_material.scale_max = 0.85
	_trail_particles.process_material = trail_material
	add_child(_trail_particles)

	_impact_particles = GPUParticles2D.new()
	_impact_particles.amount = 18
	_impact_particles.lifetime = 0.42
	_impact_particles.one_shot = true
	_impact_particles.explosiveness = 1.0
	_impact_particles.fixed_fps = 30
	_impact_particles.local_coords = false
	_impact_particles.visibility_rect = Rect2(-320.0, -320.0, 640.0, 640.0)
	_impact_particles.texture = texture
	_impact_particles.z_index = 122
	var impact_material := ParticleProcessMaterial.new()
	impact_material.direction = Vector3(0.0, -1.0, 0.0)
	impact_material.spread = 180.0
	impact_material.initial_velocity_min = 90.0
	impact_material.initial_velocity_max = 210.0
	impact_material.gravity = Vector3(0.0, 180.0, 0.0)
	impact_material.damping_min = 3.0
	impact_material.damping_max = 7.0
	impact_material.scale_min = 0.4
	impact_material.scale_max = 1.0
	_impact_particles.process_material = impact_material
	add_child(_impact_particles)

func _emit_attack_particles() -> void:
	var delta: Vector2 = _stage_end - _stage_start
	_trail_particles.position = (_stage_start + _stage_end) * 0.5
	_trail_particles.rotation = delta.angle()
	_trail_particles.modulate = _attack_color
	var material := _trail_particles.process_material as ParticleProcessMaterial
	material.emission_box_extents = Vector3(delta.length() * 0.5, float(_stages[_stage_index].width) * 0.32, 1.0)
	_trail_particles.restart()
	_trail_particles.emitting = true

func _emit_impact_particles(outcome: DefenseTimingRules.Outcome) -> void:
	_impact_particles.position = _player_position
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

func _draw() -> void:
	if _arena_rect.size == Vector2.ZERO:
		return
	draw_rect(_arena_rect, Color(0.025, 0.02, 0.035, 0.92), true)
	draw_rect(_arena_rect, Color(0.72, 0.63, 0.42, 0.65), false, 3.0)
	if _running and _stage_index < _stages.size():
		var stage: Dictionary = _stages[_stage_index]
		var width: float = float(_stages[_stage_index].width)
		if _phase == Phase.TELEGRAPH:
			if stage.kind == "sweep":
				for index in range(9):
					var angle: float = lerpf(float(stage.angle_from), float(stage.angle_to), float(index) / 8.0)
					var direction := Vector2.from_angle(angle)
					var radius: float = _distance_to_arena_edge(_arena_rect.get_center(), direction)
					draw_line(_arena_rect.get_center(), _arena_rect.get_center() + direction * radius,
						Color(_attack_color, 0.10), maxf(2.0, width * 0.16), true)
			else:
				draw_dashed_line(_hazard_draw_from, _hazard_draw_to, Color(_attack_color, 0.50),
					maxf(3.0, width * 0.34), 18.0, true)
		else:
			draw_line(_hazard_draw_from, _hazard_draw_to, Color(_attack_color, 0.72), width + 8.0, true)
			draw_line(_hazard_draw_from, _hazard_draw_to, _attack_color.lightened(0.55), maxf(3.0, width * 0.22), true)
	var font := ThemeDB.fallback_font
	draw_string(font, _arena_rect.position + Vector2(16.0, 28.0),
		"%s  %d/%d" % [_pattern_label, mini(_stage_index + 1, _stages.size()), _stages.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.86, 0.82, 0.74))
	var player_color := Color(0.98, 0.78, 0.22) if _total_elapsed <= _reaction_ends_at else Color(0.48, 0.78, 1.0)
	if _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _hit_invulnerable_until:
		player_color.a = 0.35 if int(_total_elapsed * 20.0) % 2 == 0 else 1.0
	var dashing: bool = _stance == BattleUnit.Stance.DODGE and _total_elapsed <= _reaction_ends_at
	if dashing:
		for index in range(1, 4):
			draw_circle(_player_position - _last_direction * index * 14.0, PLAYER_RADIUS - index,
				Color(0.38, 0.76, 1.0, 0.34 / index))
	draw_circle(_player_position, PLAYER_RADIUS, player_color)
	if _stance == BattleUnit.Stance.DEFEND and _total_elapsed <= _reaction_ends_at:
		draw_arc(_player_position, PLAYER_RADIUS + 12.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.28), 4.0)
	if _total_elapsed <= _feedback_until:
		draw_string(font, _arena_rect.position + Vector2(_arena_rect.size.x * 0.5 - 180.0, 58.0),
			_feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 26, _feedback_color)
