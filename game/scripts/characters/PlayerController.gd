extends CharacterBody2D
## 玩家控制器 — 4 方向移动
## P1：WASD / 方向键控制，支持跑步（Shift）。

@export var walk_speed: float = 200.0
@export var run_speed: float = 350.0
@export var sprite_frames: SpriteFrames

const SPRITE_NODE_NAME := "Sprite"

var _facing: Vector2 = Vector2.DOWN
var _sprite: AnimatedSprite2D

func _ready() -> void:
	_setup_sprite()
	_play_idle_for_facing()

func _physics_process(_delta: float) -> void:
	if DialogueManager.is_active():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input := _get_movement_input()
	var is_running := Input.is_action_pressed(&"run")
	var speed := run_speed if is_running else walk_speed

	velocity = input * speed
	if input != Vector2.ZERO:
		var facing := _cardinal_from_input(input)
		if facing != _facing:
			_facing = facing
			_play_idle_for_facing()
	move_and_slide()

## 获取当前朝向（用于后续偷袭判定等扩展）
func get_facing() -> Vector2:
	return _facing

func _get_movement_input() -> Vector2:
	# Input Map 动作驱动，支持重映射与手柄；get_vector 自带归一化。
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

func _setup_sprite() -> void:
	var legacy_visual := get_node_or_null("Visual") as CanvasItem
	if legacy_visual != null:
		legacy_visual.visible = false

	_sprite = get_node_or_null(SPRITE_NODE_NAME) as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = SPRITE_NODE_NAME
		add_child(_sprite)

	_sprite.sprite_frames = sprite_frames
	_sprite.centered = true
	_sprite.position = Vector2(0, -12)

func _cardinal_from_input(input: Vector2) -> Vector2:
	if absf(input.x) > absf(input.y):
		return Vector2.RIGHT if input.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if input.y > 0.0 else Vector2.UP

func _play_idle_for_facing() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	# 右向源图头顶被裁（素材缺陷，流水线无源可重出），改放左向帧并水平镜像
	var dir := _direction_name(_facing)
	var animation_name := "idle_left" if dir == "right" else "idle_%s" % dir
	_sprite.flip_h = dir == "right"
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)
	elif not _sprite.is_playing():
		_sprite.play()

func _direction_name(facing: Vector2) -> String:
	if facing == Vector2.LEFT:
		return "left"
	if facing == Vector2.RIGHT:
		return "right"
	if facing == Vector2.UP:
		return "up"
	return "down"
