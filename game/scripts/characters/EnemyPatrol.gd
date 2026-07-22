extends CharacterBody2D
## 敌人巡逻 — 固定路径点间往返移动
## P1：简单巡逻，到达路径点后转向下一个点。
## 使用 CharacterBody2D + move_and_slide() 确保与障碍物碰撞。
## 外观：8 向静态 SpriteFrames（动画名 idle_<方向>），按移动方向切换朝向。

@export var patrol_points: Array[Vector2] = []
@export var move_speed: float = 80.0
@export var wait_time: float = 1.0
@export var encounter_key: String = ""
@export var sprite_frames: SpriteFrames
@export var sprite_offset: Vector2 = Vector2(0, -12)

const SPRITE_NODE_NAME := "Sprite"
# 按 velocity.angle() 的八分圆顺序排列（0 = 右，y 轴向下，逆时针为负）
const DIRECTION_NAMES: Array[String] = [
	"right", "down_right", "down", "down_left",
	"left", "up_left", "up", "up_right",
]

var _current_index: int = 0
var _direction: int = 1  # 1 = 正向, -1 = 反向
var _is_waiting: bool = false
var _wait_timer: float = 0.0
var _facing_name: String = "down"
var _sprite: AnimatedSprite2D

func _ready() -> void:
	_setup_sprite()
	_play_idle_for_facing()
	# 如果未设置路径点，用当前位置作为起点
	if patrol_points.is_empty():
		patrol_points = [global_position]
	else:
		# 将路径点转换为世界坐标（相对于父节点）
		for i in range(patrol_points.size()):
			patrol_points[i] = global_position + patrol_points[i]

func _physics_process(delta: float) -> void:
	if patrol_points.size() < 2 or _is_waiting:
		if _is_waiting:
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_is_waiting = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target := patrol_points[_current_index]
	var to_target := target - global_position

	if to_target.length_squared() < 4.0:
		# 到达当前目标点，切换到下一个
		_current_index += _direction
		if _current_index >= patrol_points.size():
			_current_index = patrol_points.size() - 2
			_direction = -1
		elif _current_index < 0:
			_current_index = 1
			_direction = 1
		_is_waiting = true
		_wait_timer = wait_time
		velocity = Vector2.ZERO
		move_and_slide()
		return

	velocity = to_target.normalized() * move_speed
	_update_facing()
	move_and_slide()

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
