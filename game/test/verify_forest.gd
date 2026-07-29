extends SceneTree
## 林间空地 —— 碰撞 / 全局相机 / 传送 运行期冒烟测试（headless）
## 跑法：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       --script res://test/verify_forest.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load("res://scenes/ForestClearing.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var player: CharacterBody2D = scene.get_node("Player")
	player.set_physics_process(false)  # 关掉自带输入驱动，手动测碰撞

	var fails := 0

	# A: 树脚碰撞（从一棵树左侧朝右扫）
	player.global_position = Vector2(560, 585)
	await physics_frame
	var col_a := player.move_and_collide(Vector2(140, 0), true)
	if col_a and col_a.get_collider() is StaticBody2D and String(col_a.get_collider().name).begins_with("Tree_"):
		print("[verify] ✅ 树脚碰撞：被 %s 挡住" % col_a.get_collider().name)
	else:
		push_error("[verify] ❌ 树脚碰撞未命中")
		fails += 1

	# B: 边界碰撞（从左臂内侧朝左扫，撞向 void 围墙）
	player.global_position = Vector2(160, 480)
	await physics_frame
	var col_b := player.move_and_collide(Vector2(-120, 0), true)
	if col_b and col_b.get_collider() is StaticBody2D and String(col_b.get_collider().name) == "Bounds":
		print("[verify] ✅ 边界碰撞：被 Bounds 挡住")
	else:
		push_error("[verify] ❌ 边界碰撞未命中")
		fails += 1

	# C: 全局相机接管（跟随该场景玩家、2x、当前激活）
	var cam := root.get_node_or_null("GameCamera")
	if cam and cam.get("_target") == player and cam.enabled and cam.zoom == Vector2(2, 2) and cam.is_current():
		print("[verify] ✅ 全局相机：跟随 Player、zoom=2x、当前激活")
	else:
		push_error("[verify] ❌ 全局相机未正确接管")
		fails += 1

	# D: 从 ForestMain 返回后落在北路内侧，不立即重新触发
	scene.on_scene_enter({"from": "forest_main"})
	if player.global_position == Vector2(768, 128):
		print("[verify] ✅ 北路返回出生点：(768,128)")
	else:
		push_error("[verify] ❌ 北路返回出生点错误：%s" % player.global_position)
		fails += 1

	# E: 东端 Wilderness 传送保持不变
	player.global_position = Vector2(1248, 480)
	for _i in 6:
		await physics_frame
	var sm := root.get_node_or_null("SceneManager")
	var pending = sm.get("_pending_scene") if sm else ""
	if pending is String and pending.contains("Wilderness"):
		print("[verify] ✅ 野外传送：SceneManager 目标 = %s" % pending)
	else:
		push_error("[verify] ❌ 野外传送未触发，pending=%s" % str(pending))
		fails += 1

	# F: 北端透明入口通往 ForestMain
	if sm:
		sm.set("_pending_scene", "")
		sm.set("_pending_data", {})
	scene.set("_is_transitioning", false)
	var forest_main_gate: Area2D = scene.get_node("ForestMainGate")
	if forest_main_gate.global_position == Vector2(768, 32) and not forest_main_gate.has_node("Visual"):
		print("[verify] ✅ 北端传送口：透明且位置正确")
	else:
		push_error("[verify] ❌ 北端传送口可见或位置错误")
		fails += 1
	scene.call("_on_gate_sensor_area_entered", forest_main_gate)
	pending = sm.get("_pending_scene") if sm else ""
	var pending_data: Dictionary = sm.get("_pending_data") if sm else {}
	if pending is String and pending.contains("ForestMain") \
			and pending_data.get("scene_name", "") == "ForestMain":
		print("[verify] ✅ 北端传送：SceneManager 目标 = %s" % pending)
	else:
		push_error("[verify] ❌ 北端传送未触发，pending=%s" % str(pending))
		fails += 1
	print("[verify] 结果：%s" % ("全部通过 ✅" if fails == 0 else "%d 项失败 ❌" % fails))
	quit(fails)
