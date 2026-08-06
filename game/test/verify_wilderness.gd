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
	for enemy in scene.get_node("Enemies").get_children():
		enemy.get_node("BattleTrigger").monitorable = false  # 避免手动搬运玩家时误进战斗

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
	var patrol_target: Vector2 = enemy1.get("_patrol_target")
	if enemy1.global_position.distance_to(e1_start) > 10.0 \
			and patrol_target.distance_to(e1_start) <= 140.0:
		print("[verify] ✅ 敌人巡逻：Enemy1 在 140px 圆内移动")
	else:
		push_error("[verify] ❌ 敌人未在 140px 圆内巡逻")
		fails += 1

	# E: 进入 220px 感知圈后以 200px/s 追逐；追逐超时后按当前行走速度返回放置点
	player.global_position = enemy1.global_position + Vector2(100, 0)
	await physics_frame
	if is_equal_approx(enemy1.velocity.length(), 200.0) and enemy1.velocity.x > 0.0:
		print("[verify] ✅ 敌人追逐：感知圈内以 200px/s 追向玩家")
	else:
		push_error("[verify] ❌ 敌人未以固定速度追逐：velocity=%s" % enemy1.velocity)
		fails += 1

	enemy1.set("_chase_elapsed", 6.0)
	await physics_frame
	var enemy_origin: Vector2 = enemy1.get("_origin")
	if is_equal_approx(enemy1.velocity.length(), enemy1.move_speed) \
			and enemy1.velocity.dot(enemy1.global_position.direction_to(enemy_origin)) > 0.0:
		print("[verify] ✅ 敌人归位：按当前行走速度返回放置点")
	else:
		push_error("[verify] ❌ 敌人追逐超时后未归位")
		fails += 1

	# F: 战斗返回恢复原位；逃跑敌人获得三秒静止、半透明、不可再遭遇宽限。
	var returned_player_position := Vector2(960, 720)
	var returned_enemy_position := Vector2(1010, 720)
	var enemy1_trigger := enemy1.get_node("BattleTrigger") as Area2D
	enemy1_trigger.monitorable = true
	scene.call("on_scene_enter", {
		"from": "battle",
		"fled": true,
		"enemy_key": "Enemy1",
		"player_position": returned_player_position,
		"enemy_position": returned_enemy_position,
	})
	var enemy1_sprite := enemy1.get_node("Sprite") as AnimatedSprite2D
	if player.global_position == returned_player_position \
			and enemy1.global_position == returned_enemy_position \
			and enemy1.get("_state") == 3 \
			and enemy1.get("_escape_grace_remaining") == 3.0 \
			and is_equal_approx(enemy1_sprite.modulate.a, 0.5) \
			and not enemy1_trigger.monitorable:
		print("[verify] ✅ 逃跑回图：双方原位且敌人进入三秒宽限")
	else:
		push_error("[verify] ❌ 逃跑回图未正确恢复位置或宽限态")
		fails += 1
	enemy1.call("_physics_process", 1.5)
	var held_position: Vector2 = enemy1.global_position
	enemy1.call("_physics_process", 1.5)
	if held_position == returned_enemy_position and enemy1.get("_state") == 0 \
			and is_equal_approx(enemy1_sprite.modulate.a, 1.0) \
			and enemy1_trigger.monitorable:
		print("[verify] ✅ 逃跑宽限：三秒后恢复巡逻、Sprite 与遭遇触发")
	else:
		push_error("[verify] ❌ 逃跑宽限结束后未完整恢复: pos=%s state=%s alpha=%s monitorable=%s" % [
			held_position, enemy1.get("_state"), enemy1_sprite.modulate.a,
			enemy1_trigger.monitorable,
		])
		fails += 1
	var victory_position := Vector2(880, 760)
	scene.call("on_scene_enter", {
		"from": "battle", "victory": true, "player_position": victory_position,
	})
	if player.global_position == victory_position:
		print("[verify] ✅ 胜利回图：玩家保持遭遇原位")
	else:
		push_error("[verify] ❌ 胜利回图未恢复玩家原位")
		fails += 1

	# G: 玩家右向镜像（右向源图头顶被裁，应改放左向帧并 flip_h）
	player.set("_facing", Vector2.RIGHT)
	player.call("_play_idle_for_facing")
	var spr: AnimatedSprite2D = player.get_node("Sprite")
	if spr.animation == &"idle_left" and spr.flip_h:
		print("[verify] ✅ 右向镜像：idle_left + flip_h")
	else:
		push_error("[verify] ❌ 右向镜像未生效：anim=%s flip_h=%s" % [spr.animation, spr.flip_h])
		fails += 1

	# H: 出口传送（把玩家放到左侧出口上，等 Area2D 重叠触发）
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

	# I: Wilderness 遭遇也传递双方精确坐标。
	if sm:
		sm.set("_pending_scene", "")
		sm.set("_pending_data", {})
	scene.set("_is_transitioning", false)
	player.global_position = Vector2(1000, 800)
	enemy1.global_position = Vector2(1040, 800)
	scene.call("_on_battle_trigger_area_entered", enemy1_trigger)
	pending = sm.get("_pending_scene") if sm else ""
	var pending_data: Dictionary = sm.get("_pending_data") if sm else {}
	if pending is String and pending.contains("Battle") \
			and pending_data.get("enemy_key") == "Enemy1" \
			and pending_data.get("player_position") == player.global_position \
			and pending_data.get("enemy_position") == enemy1.global_position:
		print("[verify] ✅ 遭遇上下文：Wilderness 传递双方精确坐标")
	else:
		push_error("[verify] ❌ Wilderness 遭遇未传递双方坐标")
		fails += 1

	scene.queue_free()
	await process_frame
	await process_frame
	if cam and not cam.enabled and not cam.is_processing():
		print("[verify] ✅ 场景释放后全局相机停止跟随")
	else:
		push_error("[verify] ❌ 场景释放后全局相机仍在处理")
		fails += 1
	print("[verify] 结果：%s" % ("全部通过 ✅" if fails == 0 else "%d 项失败 ❌" % fails))
	quit(fails)
