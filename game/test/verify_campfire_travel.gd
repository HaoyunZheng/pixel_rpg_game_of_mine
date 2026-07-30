extends SceneTree
## 双篝火发现与实际跨场景往返验证（headless）。

const CLEARING_SCENE := "res://scenes/ForestClearing.tscn"
const FOREST_MAIN_SCENE := "res://scenes/ForestMain.tscn"
const CLEARING_SPAWN := Vector2(640, 744)
const FOREST_MAIN_SPAWN := Vector2(1280, 1152)

var _fails: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var game_data := root.get_node("GameData")
	game_data.call("discover_campfire", &"forest_ruins")

	var clearing := (load(CLEARING_SCENE) as PackedScene).instantiate()
	root.add_child(clearing)
	current_scene = clearing
	await process_frame
	await physics_frame
	var clearing_player := clearing.get_node("Player") as CharacterBody2D
	clearing.on_scene_enter({"from": "campfire", "spawn_id": "forest_clearing"})
	_check(clearing_player.is_in_group(&"player")
			and clearing_player.global_position == CLEARING_SPAWN,
			"林间空地玩家可交互且篝火落点安全")

	var clearing_campfire := clearing.get_node("Campfire_ForestClearing") as Area2D
	await _open_and_travel(clearing_campfire, clearing_player)
	_check(game_data.call("is_campfire_discovered", &"forest_clearing"),
			"触碰林间空地篝火后记录发现")
	_check(await _wait_for_scene("ForestMain"), "林间空地篝火传送至路边废墟")

	var forest_main := current_scene
	if forest_main == null or forest_main.name != "ForestMain":
		quit(_fails)
		return
	var forest_player := forest_main.get_node("Player") as CharacterBody2D
	_check(forest_player.global_position == FOREST_MAIN_SPAWN,
			"传送至路边废墟后使用篝火安全落点")

	var ruins_campfire := forest_main.get_node("Campfire_ForestRuins") as Area2D
	await _open_and_travel(ruins_campfire, forest_player)
	_check(await _wait_for_scene("ForestClearing"), "路边废墟篝火传送回林间空地")
	if current_scene != null and current_scene.name == "ForestClearing":
		_check((current_scene.get_node("Player") as CharacterBody2D).global_position
				== CLEARING_SPAWN,
				"返回林间空地后仍使用篝火安全落点")

	print("[verify_campfire_travel] 结果：%s" % (
		"全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	quit(_fails)


func _open_and_travel(campfire: Area2D, player: CharacterBody2D) -> void:
	campfire.call("_on_body_entered", player)
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	campfire.call("_unhandled_input", event)
	await process_frame
	var menu := campfire.get_node_or_null("CampfireUI")
	_check(menu != null and menu.call("is_open"), "Z 打开当前篝火菜单")
	if menu == null:
		return
	var travel_button := menu.get_node(
		"Overlay/Center/Panel/Content/TravelButton") as Button
	travel_button.pressed.emit()
	await process_frame
	_check(not paused and not menu.call("is_open"), "传送前关闭菜单并恢复场景处理")


func _wait_for_scene(scene_name: String) -> bool:
	var scene_manager := root.get_node("SceneManager")
	for _attempt in 6:
		await create_timer(0.25).timeout
		if current_scene != null and current_scene.name == scene_name \
				and scene_manager.get("_pending_scene") == "":
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[verify_campfire_travel] PASS: %s" % label)
	else:
		push_error("[verify_campfire_travel] FAIL: %s" % label)
		_fails += 1
