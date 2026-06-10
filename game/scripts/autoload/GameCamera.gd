extends Camera2D
## GameCamera — 全局持久相机（autoload）
## 跨场景存活：探索地图调用 set_map() 让它跟随该图玩家并按图设边界；
## 战斗等不需要跟随的场景调用 deactivate() 交还默认取景。
## 自己实现「中心死区 + 平滑跟随」，配合内置 limit 在地图边缘停住。

const CAM_ZOOM := Vector2(2, 2)
const FOLLOW_SPEED := 8.0
const DEAD_ZONE := Vector2(72, 48)  # 玩家在画面中心的可活动区（半尺寸，世界像素）

var _target: Node2D = null

func _ready() -> void:
	zoom = CAM_ZOOM
	position_smoothing_enabled = false  # 死区+lerp 自己来
	enabled = false  # 初始无目标，先不接管视图
	Log.info("GameCamera", "全局相机已加载")

## 进入某张探索地图时调用：设跟随目标 + 地图边界，并立即对中。
func set_map(target: Node2D, world_rect: Rect2) -> void:
	_target = target
	limit_left = int(world_rect.position.x)
	limit_top = int(world_rect.position.y)
	limit_right = int(world_rect.end.x)
	limit_bottom = int(world_rect.end.y)
	enabled = true
	make_current()
	if is_instance_valid(_target):
		global_position = _target.global_position
		reset_smoothing()

## 战斗/菜单等不跟随的场景调用：交还默认取景。
func deactivate() -> void:
	_target = null
	enabled = false

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var tp := _target.global_position
	var cam := global_position
	var diff := tp - cam
	var step := Vector2.ZERO
	if absf(diff.x) > DEAD_ZONE.x:
		step.x = diff.x - signf(diff.x) * DEAD_ZONE.x
	if absf(diff.y) > DEAD_ZONE.y:
		step.y = diff.y - signf(diff.y) * DEAD_ZONE.y
	global_position = cam.lerp(cam + step, clampf(FOLLOW_SPEED * delta, 0.0, 1.0))
