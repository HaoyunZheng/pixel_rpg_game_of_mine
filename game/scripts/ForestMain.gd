extends ExplorableMap
## 森林主地图：负责玩家、返回入口和全局相机边界。

const FOREST_CLEARING_SCENE := "res://scenes/ForestClearing.tscn"
const MAP_RECT := Rect2(0, 0, 3072, 2048)
const ENTRY_POSITION := Vector2(2368, 1888)

@onready var _player: CharacterBody2D = $Player
@onready var _gate_sensor: Area2D = $Player/GateSensor


func _ready() -> void:
	Log.info("ForestMain", "森林主地图场景已加载")
	_gate_sensor.area_entered.connect(_on_gate_sensor_area_entered)
	GameCamera.set_map(_player, MAP_RECT)


func on_scene_enter(data: Dictionary) -> void:
	Log.info("ForestMain", "进入森林主地图，数据: %s" % data)
	_is_transitioning = false
	_player.global_position = ENTRY_POSITION
	GameCamera.set_map(_player, MAP_RECT)


func _on_gate_sensor_area_entered(area: Area2D) -> void:
	if _is_transitioning or area.name != "ForestClearingGate":
		return
	Log.info("ForestMain", "玩家返回林间空地")
	_is_transitioning = true
	SceneManager.change_scene(FOREST_CLEARING_SCENE, {
		"scene_name": "ForestClearing", "from": "forest_main",
	})
