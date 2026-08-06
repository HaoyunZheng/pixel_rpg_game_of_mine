extends ExplorableMap
## 森林主地图：负责玩家、返回入口和全局相机边界。

const FOREST_CLEARING_SCENE := "res://scenes/ForestClearing.tscn"
const FOREST_MAIN_SCENE := "res://scenes/ForestMain.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"
const MAP_RECT := Rect2(0, 0, 3072, 2048)
const ENTRY_POSITION := Vector2(2368, 1888)
const SOURCE_TO_BODY_OFFSET := Vector2(32, 44)
const ENEMY_SCRIPT := preload("res://scripts/characters/EnemyPatrol.gd")
const HUNTER_FRAMES := preload("res://assets/sprites/hunter/hunter_frames.tres")
const MUTANT_FRAMES := preload("res://assets/sprites/mutant/mutant_frames.tres")
const HUNTER_SOURCES: Array[Vector2] = [
	Vector2(118.9337, 673.9086), Vector2(325, 1390), Vector2(1140, 1907),
	Vector2(1770, 639), Vector2(2159, 109), Vector2(2689.6193, 817.1102),
	Vector2(2358.9947, 641.3021), Vector2(2486, 1376), Vector2(902, 740),
	Vector2(462, 1855), Vector2(1562, 1461), Vector2(1024, 1687),
]
const MUTANT_SOURCES: Array[Vector2] = [
	Vector2(252, 1670), Vector2(138, 300), Vector2(970, 450), Vector2(818, 1358),
	Vector2(691, 1825), Vector2(1579, 1770), Vector2(2595, 1737),
	Vector2(2883, 1575), Vector2(1915, 1035), Vector2(2152, 585),
	Vector2(2746, 168), Vector2(2945, 682),
]

@onready var _player: CharacterBody2D = $Player
@onready var _gate_sensor: Area2D = $Player/GateSensor
@onready var _battle_sensor: Area2D = $Player/BattleTrigger
@onready var _enemies: Node2D = $Enemies
@onready var _campfire_spawn: Marker2D = $CampfireSpawn_ForestRuins


func _ready() -> void:
	Log.info("ForestMain", "森林主地图场景已加载")
	_spawn_enemies()
	_remove_defeated_enemies()
	_gate_sensor.area_entered.connect(_on_gate_sensor_area_entered)
	_battle_sensor.area_entered.connect(_on_battle_trigger_area_entered)
	GameCamera.set_map(_player, MAP_RECT)


func on_scene_enter(data: Dictionary) -> void:
	Log.info("ForestMain", "进入森林主地图，数据: %s" % data)
	_is_transitioning = false
	if not _restore_battle_return(data, _player, _enemies):
		_player.global_position = (
			_campfire_spawn.global_position
			if data.get("spawn_id", "") == "forest_ruins"
			else ENTRY_POSITION)
	GameCamera.set_map(_player, MAP_RECT)


func _on_gate_sensor_area_entered(area: Area2D) -> void:
	if _is_transitioning or area.name != "ForestClearingGate":
		return
	Log.info("ForestMain", "玩家返回林间空地")
	_is_transitioning = true
	SceneManager.change_scene(FOREST_CLEARING_SCENE, {
		"scene_name": "ForestClearing", "from": "forest_main",
	})


func _on_battle_trigger_area_entered(area: Area2D) -> void:
	var enemy := area.get_parent()
	if _is_transitioning or area.name != "BattleTrigger" or enemy == null \
			or not enemy.name.begins_with("Enemy"):
		return
	var enemy_key: String = enemy.get("encounter_key")
	Log.info("ForestMain", "玩家触碰敌人 %s，进入战斗" % enemy_key)
	_is_transitioning = true
	SceneManager.change_scene(BATTLE_SCENE, {
		"scene_name": "Battle",
		"from": "forest_main",
		"enemy_key": enemy_key,
		"player_position": _player.global_position,
		"enemy_position": enemy.global_position,
		"return_scene_path": FOREST_MAIN_SCENE,
		"return_scene_name": "ForestMain",
	})


func _spawn_enemies() -> void:
	for index in HUNTER_SOURCES.size():
		_spawn_enemy(HUNTER_SOURCES[index], index + 1, true)
	for index in MUTANT_SOURCES.size():
		_spawn_enemy(MUTANT_SOURCES[index], index + 1, false)


func _remove_defeated_enemies() -> void:
	for enemy in _enemies.get_children():
		if GameData.is_enemy_defeated(enemy.name):
			enemy.queue_free()


func _spawn_enemy(source_position: Vector2, index: int, is_hunter: bool) -> void:
	var enemy := CharacterBody2D.new()
	enemy.name = "%s_ForestMain_%02d" % ["Enemy1" if is_hunter else "Enemy2", index]
	enemy.position = source_position + SOURCE_TO_BODY_OFFSET
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("encounter_key", enemy.name)
	enemy.set("move_speed", 60.0 if is_hunter else 50.0)
	enemy.set("sprite_frames", HUNTER_FRAMES if is_hunter else MUTANT_FRAMES)
	if not is_hunter:
		enemy.set("sprite_offset", Vector2(0, -24))
	enemy.set_meta("source_position", source_position)
	enemy.set_meta("enemy_type", "hunter" if is_hunter else "mutant")

	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	var body_collision := CollisionShape2D.new()
	body_collision.name = "CollisionShape2D"
	body_collision.shape = shape
	enemy.add_child(body_collision)

	var battle_trigger := Area2D.new()
	battle_trigger.name = "BattleTrigger"
	battle_trigger.collision_layer = 2
	battle_trigger.collision_mask = 0
	var trigger_collision := CollisionShape2D.new()
	trigger_collision.name = "CollisionShape2D"
	trigger_collision.shape = shape
	battle_trigger.add_child(trigger_collision)
	enemy.add_child(battle_trigger)

	var agent := NavigationAgent2D.new()
	agent.name = "NavigationAgent2D"
	agent.path_desired_distance = 8.0
	agent.target_desired_distance = 2.0
	agent.radius = 20.0
	agent.avoidance_enabled = false
	enemy.add_child(agent)
	_enemies.add_child(enemy)
