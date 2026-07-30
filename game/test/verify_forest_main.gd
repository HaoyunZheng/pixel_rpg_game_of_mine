extends SceneTree
## 森林主地图——碰撞、边界、传送与全局相机运行期冒烟测试。

const SCENE_PATH := "res://scenes/ForestMain.tscn"
const ENTRY_POSITION := Vector2(2368, 1888)
const CAMPFIRE_POSITION := Vector2(1280, 1088)

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
	var game_data := root.get_node("GameData")
	var map: Node2D = scene.get_node("Map")
	var obstacles: StaticBody2D = map.get_node("Obstacles")
	var bounds: StaticBody2D = map.get_node("Bounds")
	var navigation_region: NavigationRegion2D = scene.get_node("NavigationRegion2D")
	var enemies: Array[Node] = scene.get_node("Enemies").get_children()
	var battle_sensor := player.get_node_or_null("BattleTrigger") as Area2D
	player.set_physics_process(false)

	_check(scene.y_sort_enabled and map.y_sort_enabled and map.get_node("Objects").y_sort_enabled,
			"玩家与树冠使用嵌套 Y 排序")
	var ground_below_player := true
	for index in 6:
		ground_below_player = ground_below_player and map.get_node("Ground_%d" % index).z_index < 0
	_check(ground_below_player, "6 个地表层均绘制在玩家下方")
	_check(player.global_position == ENTRY_POSITION, "玩家从南向石路内侧出生")
	_check(battle_sensor != null and battle_sensor.collision_mask == 2,
			"玩家具备仅感知敌人的战斗触发遮罩")
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
	var navigation_polygon := navigation_region.navigation_polygon
	_check(navigation_polygon != null and navigation_polygon.get_polygon_count() > 0 \
			and navigation_polygon.agent_radius == 20.0 \
			and navigation_polygon.baking_rect == Rect2(0, 0, 3072, 2048),
			"导航网格已按 20px agent 半径离线烘焙")
	await _verify_enemies(scene, player, enemies)

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

	await _verify_campfire(scene, player, game_data)

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
	var paused_enemy := scene.get_node("Enemies/Enemy1_ForestMain_01") as CharacterBody2D
	paused_enemy.set("_state", 1)
	paused_enemy.set("_player", player)
	paused_enemy.set("_chase_elapsed", 0.0)
	player.global_position = paused_enemy.global_position + Vector2(100, 0)
	paused_enemy.call("_physics_process", 0.5)
	_check(paused_enemy.velocity == Vector2.ZERO and paused_enemy.get("_chase_elapsed") == 0.0,
			"告示牌或 NPC 对话期间敌人停止移动且暂停 AI 计时")
	await dialogic.call("end_timeline", true)
	player.global_position = ENTRY_POSITION
	await physics_frame

	var cam := root.get_node_or_null("GameCamera")
	_check(cam and cam.get("_target") == player and cam.enabled and cam.zoom == Vector2(2, 2) \
			and cam.limit_left == 0 and cam.limit_top == 0 \
			and cam.limit_right == 3072 and cam.limit_bottom == 2048,
			"全局相机保持 2x 并使用 3072×2048 边界")
	await _verify_navigation_return(scene, player, obstacles, enemies)
	game_data.mark_enemy_defeated("Enemy1_ForestMain_01")
	scene.call("_remove_defeated_enemies")
	await process_frame
	_check(not scene.has_node("Enemies/Enemy1_ForestMain_01")
			and scene.has_node("Enemies/Enemy1_ForestMain_02"),
			"返回森林主地图后只移除已击败的具体敌人")
	game_data.set_enemy_defeated("Enemy1_ForestMain_01", false)

	var encountered := scene.get_node("Enemies/Enemy2_ForestMain_06") as CharacterBody2D
	scene.call("_on_battle_trigger_area_entered", encountered.get_node("BattleTrigger"))
	var sm := root.get_node_or_null("SceneManager")
	var pending = sm.get("_pending_scene") if sm else ""
	var pending_data: Dictionary = sm.get("_pending_data") if sm else {}
	_check(pending is String and pending.contains("Battle")
			and pending_data.get("enemy_key") == "Enemy2_ForestMain_06"
			and pending_data.get("return_scene_path") == "res://scenes/ForestMain.tscn"
			and pending_data.get("return_scene_name") == "ForestMain",
			"触碰森林敌人时传入唯一键和 ForestMain 返回信息")
	if sm:
		sm.set("_pending_scene", "")
		sm.set("_pending_data", {})
	scene.set("_is_transitioning", false)

	var gate: Area2D = scene.get_node("ForestClearingGate")
	_check(gate.global_position == Vector2(2368, 2016) and not gate.has_node("Visual"), "南侧传送口透明且位置正确")
	scene.call("_on_gate_sensor_area_entered", gate)
	pending = sm.get("_pending_scene") if sm else ""
	pending_data = sm.get("_pending_data") if sm else {}
	_check(pending is String and pending.contains("ForestClearing") \
			and pending_data.get("from", "") == "forest_main", "南侧传送口返回林间空地")

	print("[verify_forest_main] 结果：%s" % ("全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	quit(_fails)


func _verify_campfire(scene: Node2D, player: CharacterBody2D, game_data: Node) -> void:
	var campfire := scene.get_node_or_null("Campfire_ForestRuins") as Area2D
	_check(campfire != null and campfire.global_position == CAMPFIRE_POSITION
			and campfire.collision_layer == 0 and campfire.collision_mask == 1
			and campfire.get("campfire_id") == &"forest_ruins",
			"路边废墟篝火位于可交互的世界坐标")
	if campfire == null:
		return
	var interaction := campfire.get_node("InteractionShape") as CollisionShape2D
	var body_shape := campfire.get_node("Body/CollisionShape2D") as CollisionShape2D
	var visual := campfire.get_node("Visual") as AnimatedSprite2D
	var frames := visual.sprite_frames
	_check(interaction.shape is CircleShape2D
			and is_equal_approx((interaction.shape as CircleShape2D).radius, 56.0)
			and body_shape.shape is RectangleShape2D
			and (body_shape.shape as RectangleShape2D).size == Vector2(40, 18),
			"篝火沿用 56px 交互范围并以 40×18 底座阻挡玩家")
	_check(frames != null and frames.has_animation(&"burn")
			and frames.get_frame_count(&"burn") == 4
			and is_equal_approx(frames.get_animation_speed(&"burn"), 6.0)
			and frames.get_animation_loop(&"burn") and visual.is_playing(),
			"篝火 burn 动画以四帧 6 FPS 循环播放")

	player.global_position = CAMPFIRE_POSITION + Vector2(0, 30)
	await physics_frame
	await physics_frame
	var prompt := campfire.get_node("Prompt") as Label
	_check(campfire.get("_player_in_range") == true and prompt.visible,
			"玩家靠近篝火时显示交互提示")

	game_data.call("set_party_member_vitals", 0, 1, 0)
	game_data.call("set_party_member_vitals", 1, 2, 1)
	var poison := StatusEffect.new()
	poison.type = StatusEffect.Type.POISON
	poison.potency = 3
	poison.duration = 2
	var effects: Array[StatusEffect] = [poison]
	game_data.call("set_party_member_status_effects", 0, effects)
	game_data.call("set_curse", "player", 37)
	game_data.call("set_bond", "companion", 4)

	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	campfire.call("_unhandled_input", interact_event)
	await process_frame
	var menu := campfire.get_node_or_null("CampfireUI")
	_check(menu != null and menu.call("is_open") and paused,
			"按 Z 打开篝火菜单并暂停探索世界")
	if menu == null:
		paused = false
		return
	var content := menu.get_node("Overlay/Center/Panel/Content")
	var menu_labels: Array[String] = []
	for node_name: String in [
		"RestButton", "UpgradeButton", "SkillButton", "TravelButton", "LeaveButton",
	]:
		menu_labels.append((content.get_node(node_name) as Button).text)
	_check(menu_labels == ["休息", "升级", "技能点", "传送", "离开"],
			"篝火菜单提供五项约定入口")

	(content.get_node("RestButton") as Button).pressed.emit()
	await process_frame
	var party: Array[PartyMemberState] = game_data.call("get_party_members")
	var all_rested := true
	for member: PartyMemberState in party:
		all_rested = all_rested and member.hp == member.max_hp and member.mp == member.max_mp \
				and member.status_effects.is_empty()
	_check(all_rested and game_data.call("get_curse", "player") == 37
			and game_data.call("get_bond", "companion") == 4,
			"休息回满 HP/MP、清除异常且不改羁绊或诅咒")

	var player_before_upgrade: PartyMemberState = game_data.call("get_party_member", 0)
	var level_cost: int = game_data.call("get_level_up_cost", 0)
	var missing_embers: int = level_cost - int(game_data.call("get_ember_count"))
	if missing_embers > 0:
		game_data.call("add_embers", missing_embers)
	(content.get_node("UpgradeButton") as Button).pressed.emit()
	await process_frame
	var player_after_upgrade: PartyMemberState = game_data.call("get_party_member", 0)
	_check(player_after_upgrade.level == player_before_upgrade.level + 1
			and player_after_upgrade.skill_points == player_before_upgrade.skill_points + 1,
			"篝火菜单可消耗余烬升级并获得技能点")

	var skill := player_after_upgrade.stats_res.skills[0] as SkillData
	var rank_before: int = game_data.call("get_skill_rank", 0, skill.id)
	(content.get_node("SkillButton") as Button).pressed.emit()
	await process_frame
	_check(game_data.call("get_skill_rank", 0, skill.id) == rank_before + 1
			and game_data.call("get_party_member", 0).skill_points
				== player_after_upgrade.skill_points - 1
			and game_data.call("get_curse", "player") == 37
			and game_data.call("get_bond", "companion") == 4,
			"篝火菜单可分配技能点且不改羁绊或诅咒")

	(content.get_node("LeaveButton") as Button).pressed.emit()
	await process_frame
	_check(not menu.call("is_open") and not paused and prompt.visible,
			"选择离开后关闭菜单、恢复世界并重新显示交互提示")
	game_data.call("set_curse", "player", 0)
	game_data.call("set_bond", "companion", 0)
	player.global_position = ENTRY_POSITION
	await physics_frame


func _verify_enemies(scene: Node2D, player: CharacterBody2D, enemies: Array[Node]) -> void:
	var hunters := 0
	var mutants := 0
	var unique_keys := {}
	var excluded_sources := [Vector2(2056, 1452), Vector2(2291, 1858)]
	var all_configured := true
	var all_agents := true
	var all_visuals := true
	var all_spawns_walkable := true
	var all_patrol_targets_in_range := true
	for enemy: CharacterBody2D in enemies:
		var enemy_type: String = enemy.get_meta("enemy_type", "")
		var is_hunter := enemy_type == "hunter"
		hunters += 1 if is_hunter else 0
		mutants += 0 if is_hunter else 1
		var expected_prefix := "Enemy1_ForestMain_" if is_hunter else "Enemy2_ForestMain_"
		var encounter_key: String = enemy.get("encounter_key")
		unique_keys[encounter_key] = true
		all_configured = all_configured \
				and encounter_key == enemy.name and encounter_key.begins_with(expected_prefix) \
				and enemy.get("move_speed") == (60.0 if is_hunter else 50.0) \
				and enemy.get("patrol_radius") == 140.0 and enemy.get("wait_time") == 1.0 \
				and enemy.get("detect_range") == 220.0 and enemy.get("chase_speed") == 200.0 \
				and enemy.get("chase_duration") == 6.0 and enemy.get("chase_leash_radius") == 360.0
		for excluded: Vector2 in excluded_sources:
			all_configured = all_configured and not (enemy.get_meta("source_position") as Vector2).is_equal_approx(excluded)
		var agent := enemy.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
		all_agents = all_agents and agent != null and agent.radius == 20.0 \
				and not agent.avoidance_enabled
		var collision := enemy.get_node("CollisionShape2D") as CollisionShape2D
		var sprite := enemy.get_node("Sprite") as AnimatedSprite2D
		var frame := sprite.sprite_frames.get_frame_texture(&"idle_down", 0)
		var expected_frame_size := Vector2(64, 64) if is_hunter else Vector2(128, 128)
		var expected_offset := Vector2(0, -12) if is_hunter else Vector2(0, -24)
		all_visuals = all_visuals and collision.shape.size == Vector2(40, 40) \
				and sprite.scale == Vector2.ONE and frame.get_size() == expected_frame_size \
				and sprite.position == expected_offset
		all_spawns_walkable = all_spawns_walkable and not _blocked_at(scene, player, enemy.global_position)
		var origin: Vector2 = enemy.get("_origin")
		var patrol_target: Vector2 = enemy.get("_patrol_target")
		all_patrol_targets_in_range = all_patrol_targets_in_range \
				and patrol_target.distance_to(origin) <= 140.01

	_check(enemies.size() == 24 and hunters == 12 and mutants == 12,
			"森林主地图恰有 12 个猎手和 12 个变异兽")
	_check(unique_keys.size() == 24 and all_configured,
			"24 个敌人使用稳定唯一键、约定速度与上一轮索敌参数")
	_check(all_agents, "24 个敌人均使用 20px NavigationAgent2D 且未启用 avoidance")
	_check(all_visuals, "猎手为 64px 帧，变异兽为 128px 帧且尺寸、偏移与碰撞统一")
	_check(all_spawns_walkable, "24 个敌人的示意位置均调整到可行走落脚点")
	_check(all_patrol_targets_in_range, "所有初始巡逻目标均位于 140px 放置点半径内")

	var sample := scene.get_node("Enemies/Enemy1_ForestMain_11") as CharacterBody2D
	var origin: Vector2 = sample.get("_origin")
	var chase_target := sample.get("_player") as Node2D
	chase_target.global_position = Vector2(1600, 1655)
	sample.call("_enter_chase")
	for _frame in 30:
		await physics_frame
		if is_equal_approx(sample.velocity.length(), 200.0):
			break
	_check(sample.get("_state") == 1 and is_equal_approx(sample.velocity.length(), 200.0) \
			and sample.get("_path_refresh_timer") > 0.0 \
			and sample.get("_path_refresh_timer") <= 0.25,
			"玩家进入 220px 范围时敌人以 200px/s 追逐并按 0.25 秒刷新路径")
	sample.set("_chase_elapsed", 5.99)
	sample.call("_update_chase", 0.02)
	var timed_out: bool = sample.get("_state") == 2
	sample.set("_state", 1)
	sample.global_position = origin + Vector2(361, 0)
	sample.call("_update_chase", 0.0)
	_check(timed_out and sample.get("_state") == 2 \
			and is_equal_approx(sample.velocity.length(), sample.move_speed),
			"追逐达到 6 秒或超过 360px 后按当前行走速度归位")
	sample.global_position = origin
	sample.set("_state", 0)


func _verify_navigation_return(scene: Node2D, player: CharacterBody2D,
		obstacles: StaticBody2D, enemies: Array[Node]) -> void:
	for enemy: CharacterBody2D in enemies:
		enemy.set_physics_process(false)
		enemy.collision_layer = 0
		enemy.collision_mask = 0
	player.collision_layer = 0
	player.collision_mask = 0

	var route := _find_detour_route(scene, player, obstacles)
	_check(not route.is_empty(), "导航网格能为代表树石生成绕行路径")
	if route.is_empty():
		return
	var sample := enemies[0] as CharacterBody2D
	sample.global_position = route[0]
	sample.set("_origin", route[1])
	sample.set("_state", 2)
	sample.set("_path_refresh_timer", 0.0)
	sample.set("_player", null)
	sample.collision_mask = 1
	sample.set_physics_process(true)
	var returned := false
	for _frame in 300:
		await physics_frame
		if sample.global_position.distance_to(route[1]) <= 2.1 and sample.get("_state") == 0:
			returned = true
			break
	sample.set_physics_process(false)
	_check(returned, "至少一个敌人能沿导航路径绕过树石返回放置点")


func _find_detour_route(scene: Node2D, player: CharacterBody2D,
		obstacles: StaticBody2D) -> Array[Vector2]:
	var navigation_map := scene.get_world_2d().navigation_map
	for collision: CollisionShape2D in obstacles.get_children():
		var rectangle := collision.shape as RectangleShape2D
		if rectangle == null:
			continue
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
			var clearance: float = rectangle.size.dot(axis.abs()) * 0.5 + 64.0
			var start: Vector2 = collision.global_position - axis * clearance
			var finish: Vector2 = collision.global_position + axis * clearance
			if _blocked_at(scene, player, start) or _blocked_at(scene, player, finish):
				continue
			var path := NavigationServer2D.map_get_path(navigation_map, start, finish, true)
			if path.size() < 3:
				continue
			var path_length := 0.0
			for index in path.size() - 1:
				path_length += path[index].distance_to(path[index + 1])
			if path_length > start.distance_to(finish) + 8.0:
				return [start, finish]
	return []


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
