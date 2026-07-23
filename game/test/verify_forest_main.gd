extends SceneTree
## 森林主地图——碰撞、边界、传送与全局相机运行期冒烟测试。

const SCENE_PATH := "res://scenes/ForestMain.tscn"
const ENTRY_POSITION := Vector2(2368, 1888)

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "ForestMain 玩法场景可加载")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var player: CharacterBody2D = scene.get_node("Player")
	var map: Node2D = scene.get_node("Map")
	var obstacles: StaticBody2D = map.get_node("Obstacles")
	var bounds: StaticBody2D = map.get_node("Bounds")
	player.set_physics_process(false)

	_check(scene.y_sort_enabled and map.y_sort_enabled and map.get_node("Objects").y_sort_enabled,
			"玩家与树冠使用嵌套 Y 排序")
	var ground_below_player := true
	for index in 6:
		ground_below_player = ground_below_player and map.get_node("Ground_%d" % index).z_index < 0
	_check(ground_below_player, "6 个地表层均绘制在玩家下方")
	_check(player.global_position == ENTRY_POSITION, "玩家从南向石路内侧出生")
	_check(obstacles.get_child_count() == 1189, "1135 棵树、52 块岩石和 2 块告示牌均有碰撞")
	_check(bounds.get_child_count() == 5, "地图边界保留南侧两格宽入口缺口")

	var expected_sizes := {
		"tree_dark": Vector2(26, 12),
		"rock_single": Vector2(36, 20),
		"rock_pile": Vector2(44, 28),
		"sign_wood": Vector2(36, 16),
		"sign_stone": Vector2(42, 20),
	}
	for kind in expected_sizes:
		var sample := _find_collision(obstacles, kind)
		_check(sample != null and sample.shape.size == expected_sizes[kind] \
				and _body_at(scene, player, sample.global_position, obstacles),
				"%s 碰撞尺寸正确且可阻挡玩家" % kind)

	_check(not _blocked_at(scene, player, Vector2(1536, 448)), "代表草地位置可行走")
	_check(not _blocked_at(scene, player, ENTRY_POSITION), "代表石路与出生点可行走")
	_check(not _blocked_at(scene, player, Vector2(512, 1152)), "代表苔藓地面位置可行走")
	_check(_body_at(scene, player, Vector2(2200, 2028), bounds), "南边界非入口区域阻挡玩家")
	_check(not _body_at(scene, player, Vector2(2368, 2028), bounds), "南侧入口缺口可通行")
	_check(_body_at(scene, player, Vector2(16, 1024), bounds), "地图外边界阻挡玩家")

	var signposts := scene.get_tree().get_nodes_in_group(&"signpost_npcs")
	_check(signposts.size() == 2, "两块告示牌均实例化为 SignpostNPC")
	var expected_signs := {
		"Sign_0001": "forest_main_wood_sign",
		"Sign_0002": "forest_main_stone_sign",
	}
	for sign_name: String in expected_signs:
		var sign := map.get_node("Objects/%s" % sign_name) as Area2D
		var prompt := sign.get_node_or_null("Prompt") as Label if sign else null
		_check(sign != null and sign.get_script().resource_path.ends_with("SignpostNPC.gd")
				and sign.get("dialogue_id") == expected_signs[sign_name]
				and sign.collision_layer == 0 and sign.collision_mask == 1
				and sign.has_node("CollisionShape2D") and prompt != null and prompt.text == "Z 查看",
				"%s 具备独立信息、交互遮罩和查看提示" % sign_name)

	var wood_sign := map.get_node("Objects/Sign_0001") as Area2D
	player.global_position = wood_sign.global_position + Vector2(0, 30)
	await physics_frame
	await physics_frame
	_check(wood_sign.get("_player_in_range") == true and wood_sign.get_node("Prompt").visible,
			"玩家靠近告示牌时出现查看提示")
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	wood_sign.call("_unhandled_input", interact_event)
	await process_frame
	var dm := root.get_node("DialogueManager")
	var dialogic := root.get_node("Dialogic")
	var state_info: Dictionary = dialogic.get("current_state_info")
	_check(dm.call("is_active") and "北行通往旧猎径" in str(state_info.get("text", "")),
			"按 Z 可通过 DialogueManager 显示木牌信息")
	await dialogic.call("end_timeline", true)
	player.global_position = ENTRY_POSITION
	await physics_frame

	var cam := root.get_node_or_null("GameCamera")
	_check(cam and cam.get("_target") == player and cam.enabled and cam.zoom == Vector2(2, 2) \
			and cam.limit_left == 0 and cam.limit_top == 0 \
			and cam.limit_right == 3072 and cam.limit_bottom == 2048,
			"全局相机保持 2x 并使用 3072×2048 边界")

	var gate: Area2D = scene.get_node("ForestClearingGate")
	_check(gate.global_position == Vector2(2368, 2016) and not gate.has_node("Visual"), "南侧传送口透明且位置正确")
	scene.call("_on_gate_sensor_area_entered", gate)
	var sm := root.get_node_or_null("SceneManager")
	var pending = sm.get("_pending_scene") if sm else ""
	var pending_data: Dictionary = sm.get("_pending_data") if sm else {}
	_check(pending is String and pending.contains("ForestClearing") \
			and pending_data.get("from", "") == "forest_main", "南侧传送口返回林间空地")

	print("[verify_forest_main] 结果：%s" % ("全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	quit(_fails)


func _find_collision(obstacles: StaticBody2D, kind: String) -> CollisionShape2D:
	for collision in obstacles.get_children():
		if collision.get_meta("forest_object_kind", "") == kind:
			return collision
	return null


func _blocked_at(scene: Node2D, player: CharacterBody2D, position: Vector2) -> bool:
	var hits := _hits_at(scene, player, position)
	for hit in hits:
		var collider = hit.get("collider")
		if collider is StaticBody2D:
			return true
	return false


func _body_at(scene: Node2D, player: CharacterBody2D, position: Vector2, body: StaticBody2D) -> bool:
	for hit in _hits_at(scene, player, position):
		if hit.get("collider") == body:
			return true
	return false


func _hits_at(scene: Node2D, player: CharacterBody2D, position: Vector2) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("CollisionShape2D").shape
	query.transform = Transform2D(0.0, position)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return scene.get_world_2d().direct_space_state.intersect_shape(query, 32)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[verify_forest_main] PASS: %s" % message)
	else:
		_fails += 1
		push_error("[verify_forest_main] FAIL: %s" % message)
