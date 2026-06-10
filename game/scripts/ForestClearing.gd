extends Node2D
## 林间空地 — 工程初始可玩场景（由 Meowa/Tiled 地图导入并适配）。
## P1：玩家 4 方向移动，被空地边界（Map/Bounds）与树脚挡住；
##     走到十字路右端的传送点 WildGate 进入野外（Wilderness）大地图。

const WILDERNESS_SCENE: String = "res://scenes/Wilderness.tscn"
const MAP_RECT := Rect2(0, 0, 1536, 1024)  # 地图世界尺寸（相机边界）

@onready var _player: CharacterBody2D = $Player
@onready var _gate_sensor: Area2D = $Player/GateSensor

var _is_transitioning: bool = false

func _ready() -> void:
	Log.info("ForestClearing", "林间空地场景已加载")
	_gate_sensor.area_entered.connect(_on_gate_sensor_area_entered)
	GameCamera.set_map(_player, MAP_RECT)

func on_scene_enter(data: Dictionary) -> void:
	Log.info("ForestClearing", "进入林间空地，数据: %s" % data)
	_is_transitioning = false
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
