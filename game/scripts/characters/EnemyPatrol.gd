extends CharacterBody2D
## 敌人巡逻 — 在放置点周围游荡，发现玩家后追逐，放弃后归位。
## 使用 CharacterBody2D + move_and_slide() 确保与障碍物碰撞。
## 外观：8 向静态 SpriteFrames（动画名 idle_<方向>），按移动方向切换朝向。

@export var move_speed: float = 80.0
@export var patrol_radius: float = 140.0
@export var wait_time: float = 1.0
@export var detect_range: float = 220.0
@export var chase_speed: float = 230.0
@export var chase_duration: float = 6.0
@export var chase_leash_radius: float = 360.0
@export var encounter_key: String = ""
@export var sprite_frames: SpriteFrames
@export var sprite_offset: Vector2 = Vector2(0, -12)

enum State { PATROL, CHASE, RETURN }

const SPRITE_NODE_NAME := "Sprite"
const ARRIVAL_DISTANCE_SQUARED := 4.0
const PATROL_TARGET_TIMEOUT := 4.0
const PATH_REFRESH_INTERVAL := 0.25
# 按 velocity.angle() 的八分圆顺序排列（0 = 右，y 轴向下，逆时针为负）
const DIRECTION_NAMES: Array[String] = [
	"right", "down_right", "down", "down_left",
	"left", "up_left", "up", "up_right",
]

var _state: State = State.PATROL
var _origin: Vector2
var _patrol_target: Vector2
var _patrol_target_timeout: float = 0.0
var _is_waiting: bool = false
var _wait_timer: float = 0.0
var _chase_elapsed: float = 0.0
var _facing_name: String = "down"
var _sprite: AnimatedSprite2D
var _player: Node2D
var _nav_agent: NavigationAgent2D
var _path_refresh_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_nav_agent = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	_setup_sprite()
	_play_idle_for_facing()
	_origin = global_position
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	_rng.randomize()
	_choose_patrol_target()

func _physics_process(delta: float) -> void:
	_path_refresh_timer -= delta
	match _state:
		State.PATROL:
			if _can_detect_player():
				_enter_chase()
			else:
				_update_patrol(delta)
		State.CHASE:
			_update_chase(delta)
		State.RETURN:
			_update_return()

	_update_facing()
	move_and_slide()

func _update_patrol(delta: float) -> void:
	if _is_waiting:
		_wait_timer -= delta
		velocity = Vector2.ZERO
		if _wait_timer <= 0.0:
			_is_waiting = false
			_choose_patrol_target()
		return

	_patrol_target_timeout -= delta
	var to_target := _patrol_target - global_position
	if to_target.length_squared() <= ARRIVAL_DISTANCE_SQUARED or _patrol_target_timeout <= 0.0:
		_is_waiting = true
		_wait_timer = wait_time
		velocity = Vector2.ZERO
		return
	_move_towards(_patrol_target, move_speed)

func _update_chase(delta: float) -> void:
	_chase_elapsed += delta
	if not is_instance_valid(_player) \
			or _chase_elapsed >= chase_duration \
			or global_position.distance_squared_to(_origin) >= chase_leash_radius * chase_leash_radius:
		_enter_return()
		return
	_move_towards(_player.global_position, chase_speed)

func _update_return() -> void:
	var to_origin := _origin - global_position
	if to_origin.length_squared() <= ARRIVAL_DISTANCE_SQUARED:
		global_position = _origin
		_state = State.PATROL
		_is_waiting = true
		_wait_timer = wait_time
		velocity = Vector2.ZERO
		return
	_move_towards(_origin, chase_speed)

func _can_detect_player() -> bool:
	return is_instance_valid(_player) \
		and global_position.distance_squared_to(_player.global_position) <= detect_range * detect_range

func _enter_chase() -> void:
	_state = State.CHASE
	_chase_elapsed = 0.0
	_is_waiting = false
	_path_refresh_timer = 0.0
	_move_towards(_player.global_position, chase_speed)

func _enter_return() -> void:
	_state = State.RETURN
	_path_refresh_timer = 0.0
	_move_towards(_origin, chase_speed)

func _choose_patrol_target() -> void:
	var offset := Vector2.from_angle(_rng.randf_range(0.0, TAU)) \
		* sqrt(_rng.randf()) * patrol_radius
	_patrol_target = _origin + offset
	_patrol_target_timeout = PATROL_TARGET_TIMEOUT
	_path_refresh_timer = 0.0

func _move_towards(target: Vector2, speed: float) -> void:
	if _nav_agent != null:
		if _path_refresh_timer <= 0.0:
			_nav_agent.target_position = target
			_path_refresh_timer = PATH_REFRESH_INTERVAL
		var next_position := _nav_agent.get_next_path_position()
		if not _nav_agent.is_navigation_finished() \
				and next_position.distance_squared_to(global_position) > ARRIVAL_DISTANCE_SQUARED:
			velocity = global_position.direction_to(next_position) * speed
			return
		velocity = Vector2.ZERO
		return
	# ponytail: Wilderness 无 Agent 时保留原直线移动，不为旧地图引入导航资源。
	velocity = global_position.direction_to(target) * speed

func _setup_sprite() -> void:
	var legacy_visual := get_node_or_null("Visual") as CanvasItem
	if legacy_visual != null and sprite_frames != null:
		legacy_visual.visible = false

	if sprite_frames == null:
		return

	_sprite = get_node_or_null(SPRITE_NODE_NAME) as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = SPRITE_NODE_NAME
		add_child(_sprite)

	_sprite.sprite_frames = sprite_frames
	_sprite.centered = true
	_sprite.position = sprite_offset

func _update_facing() -> void:
	if velocity == Vector2.ZERO:
		return
	# 把朝向角分到 8 个 45° 扇区，圆整到最近的方向
	var octant := wrapi(roundi(velocity.angle() / (PI / 4.0)), 0, 8)
	var facing_name: String = DIRECTION_NAMES[octant]
	if facing_name == _facing_name:
		return
	_facing_name = facing_name
	_play_idle_for_facing()

func _play_idle_for_facing() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var animation_name := "idle_%s" % _facing_name
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)
	elif not _sprite.is_playing():
		_sprite.play()
