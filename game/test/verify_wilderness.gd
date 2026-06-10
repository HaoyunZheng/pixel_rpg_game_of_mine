extends SceneTree
## 野外大地图 —— 碰撞 / 全局相机 / 巡逻 / 出口传送 运行期冒烟测试（headless）
## 跑法：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       --script res://test/verify_wilderness.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load("res://scenes/Wilderness.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var player: CharacterBody2D = scene.get_node("Player")
	player.set_physics_process(false)  # 关掉自带输入驱动，手动测碰撞

	var fails := 0

	# A: 树脚碰撞（下横带朝右扫向 (18,11) 树脚；y=750 避开 Enemy1 的触发带 y>=780）
	player.global_position = Vector2(1080, 750)
	await physics_frame
	var col_a := player.move_and_collide(Vector2(140, 0), true)
	if col_a and col_a.get_collider() is StaticBody2D and String(col_a.get_collider().name).begins_with("Tree_"):
		print("[verify] ✅ 树脚碰撞：被 %s 挡住" % col_a.get_collider().name)
	else:
		push_error("[verify] ❌ 树脚碰撞未命中")
		fails += 1

	# B: 边界碰撞（下横带左端朝左扫，撞向 void 围墙；x=640 避开出口触发区 x<=584）
	player.global_position = Vector2(640, 800)
	await physics_frame
	var col_b := player.move_and_collide(Vector2(-160, 0), true)
	if col_b and col_b.get_collider() is StaticBody2D and String(col_b.get_collider().name) == "Bounds":
		print("[verify] ✅ 边界碰撞：被 Bounds 挡住")
	else:
		push_error("[verify] ❌ 边界碰撞未命中")
		fails += 1

	# C: 全局相机接管（跟随玩家、2x、激活、limit 对齐 MAP_RECT）
	var cam := root.get_node_or_null("GameCamera")
	if cam and cam.get("_target") == player and cam.enabled and cam.zoom == Vector2(2, 2) \
			and cam.is_current() and cam.limit_left == 512 and cam.limit_top == 320 \
			and cam.limit_right == 1536 and cam.limit_bottom == 896:
		print("[verify] ✅ 全局相机：跟随 Player、zoom=2x、limit=(512,320,1536,896)")
	else:
		push_error("[verify] ❌ 全局相机未正确接管")
		fails += 1

	# D: 敌人巡逻在动（30 个物理帧后位置应有位移）
	var enemy1: CharacterBody2D = scene.get_node("Enemies/Enemy1")
	var e1_start := enemy1.global_position
	for _i in 30:
		await physics_frame
	if enemy1.global_position.distance_to(e1_start) > 10.0:
		print("[verify] ✅ 敌人巡逻：Enemy1 位移 %.1f px" % enemy1.global_position.distance_to(e1_start))
	else:
		push_error("[verify] ❌ 敌人巡逻未移动")
		fails += 1

	# E: 出口传送（把玩家放到左侧出口上，等 Area2D 重叠触发）
	player.global_position = Vector2(544, 800)
	for _i in 6:
		await physics_frame
	var sm := root.get_node_or_null("SceneManager")
	var pending = sm.get("_pending_scene") if sm else ""
	if pending is String and pending.contains("ForestClearing"):
		print("[verify] ✅ 出口传送：SceneManager 目标 = %s" % pending)
	else:
		push_error("[verify] ❌ 出口传送未触发，pending=%s" % str(pending))
		fails += 1

	print("[verify] 结果：%s" % ("全部通过 ✅" if fails == 0 else "%d 项失败 ❌" % fails))
	quit(fails)
