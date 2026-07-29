extends ExplorableMap
## 林间空地 — 工程初始可玩场景（由 Meowa/Tiled 地图导入并适配）。
## P1：玩家 4 方向移动，被空地边界（Map/Bounds）与树脚挡住；
##     十字路右端通往 Wilderness，北端通往 ForestMain。
## 背包开关与切换互斥标志继承自 ExplorableMap。

const WILDERNESS_SCENE: String = "res://scenes/Wilderness.tscn"
const FOREST_MAIN_SCENE: String = "res://scenes/ForestMain.tscn"
const MAP_RECT := Rect2(0, 0, 1536, 1024)  # 地图世界尺寸（相机边界）
const FOREST_MAIN_RETURN_POSITION := Vector2(768, 128)

@onready var _player: CharacterBody2D = $Player
@onready var _gate_sensor: Area2D = $Player/GateSensor

func _ready() -> void:
	Log.info("ForestClearing", "林间空地场景已加载")
	_gate_sensor.area_entered.connect(_on_gate_sensor_area_entered)
	GameCamera.set_map(_player, MAP_RECT)

func on_scene_enter(data: Dictionary) -> void:
	Log.info("ForestClearing", "进入林间空地，数据: %s" % data)
	_is_transitioning = false
	if data.get("from", "") == "forest_main":
		_player.global_position = FOREST_MAIN_RETURN_POSITION
	GameCamera.set_map(_player, MAP_RECT)

func _on_gate_sensor_area_entered(area: Area2D) -> void:
	if _is_transitioning:
		return
	if area.name == "WildGate":
		Log.info("ForestClearing", "玩家进入野外传送点，前往野外")
		_is_transitioning = true
		SceneManager.change_scene(WILDERNESS_SCENE, {
			"scene_name": "Wilderness", "from": "forest",
		})
	elif area.name == "ForestMainGate":
		Log.info("ForestClearing", "玩家进入北端传送点，前往森林主地图")
		_is_transitioning = true
		SceneManager.change_scene(FOREST_MAIN_SCENE, {
			"scene_name": "ForestMain", "from": "forest",
		})
