extends Node2D
## 野外区场景 — 梦召道沿途的废墟/森林
## P1：玩家 4 方向移动、敌人巡逻、触碰敌人触发战斗、走到左侧出口返回林间空地。

const FOREST_SCENE_PATH: String = "res://scenes/ForestClearing.tscn"
const BATTLE_SCENE_PATH: String = "res://scenes/Battle.tscn"
const DATA_KEY_SCENE_NAME: String = "scene_name"
const DATA_KEY_FROM: String = "from"
const DATA_KEY_ENEMY_KEY: String = "enemy_key"
const FALLBACK_ENEMY_KEY: String = "Enemy1"
const MAP_RECT := Rect2(512, 320, 1024, 576)  # 可走区域外接矩形（相机边界，对齐 WildernessMap）

@onready var _player: CharacterBody2D = $Player
@onready var _battle_trigger: Area2D = $Player/BattleTrigger

var _is_transitioning: bool = false

func _ready() -> void:
	Log.info("Wilderness", "野外区场景已加载")
	_battle_trigger.area_entered.connect(_on_battle_trigger_area_entered)
	GameCamera.set_map(_player, MAP_RECT)

func on_scene_enter(data: Dictionary) -> void:
	Log.info("Wilderness", "进入野外区，数据: %s" % data)
	_is_transitioning = false
	GameCamera.set_map(_player, MAP_RECT)

func _on_battle_trigger_area_entered(area: Area2D) -> void:
	if _is_transitioning:
		return

	var area_name: String = area.name
	var parent_node: Node = area.get_parent()
	var parent_name: String = ""
	if parent_node:
		parent_name = parent_node.name

	if area_name == "ExitTrigger" or parent_name == "ExitTrigger":
		Log.info("Wilderness", "玩家进入左侧出口，返回林间空地")
		_is_transitioning = true
		SceneManager.change_scene(FOREST_SCENE_PATH, {DATA_KEY_SCENE_NAME: "ForestClearing", DATA_KEY_FROM: "wilderness"})
	elif area_name == "BattleTrigger" and parent_name.begins_with("Enemy"):
		var enemy_key: String = _get_enemy_key(parent_node)
		Log.info("Wilderness", "玩家触碰敌人 %s，进入战斗" % enemy_key)
		_is_transitioning = true
		SceneManager.change_scene(BATTLE_SCENE_PATH, {
			DATA_KEY_SCENE_NAME: "Battle",
			DATA_KEY_FROM: "wilderness",
			DATA_KEY_ENEMY_KEY: enemy_key,
		})

func _get_enemy_key(enemy_node: Node) -> String:
	if enemy_node == null:
		return FALLBACK_ENEMY_KEY
	var encounter_key = enemy_node.get("encounter_key")
	if encounter_key is String and not encounter_key.is_empty():
		return encounter_key
	return enemy_node.name
