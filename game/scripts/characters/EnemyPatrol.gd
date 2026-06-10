extends CharacterBody2D
## 敌人巡逻 — 固定路径点间往返移动
## P1：简单巡逻，到达路径点后转向下一个点。
## 使用 CharacterBody2D + move_and_slide() 确保与障碍物碰撞。

@export var patrol_points: Array[Vector2] = []
@export var move_speed: float = 80.0
@export var wait_time: float = 1.0
@export var encounter_key: String = ""

var _current_index: int = 0
var _direction: int = 1  # 1 = 正向, -1 = 反向
var _is_waiting: bool = false
var _wait_timer: float = 0.0

func _ready() -> void:
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
	var dist := to_target.length()

	if dist < 2.0:
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
	move_and_slide()
