extends SceneTree
## 篝火 v1 存档的内存往返与坏档拒绝测试（headless，不写 user://）。

var _fails: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var game_data := root.get_node("GameData")
	var dialogic := root.get_node("Dialogic")
	var dialogue_manager := root.get_node("DialogueManager")

	game_data.call("discover_campfire", &"forest_clearing")
	game_data.call("discover_campfire", &"forest_ruins")
	game_data.call("add_embers", 60)
	_check(game_data.call("upgrade_party_member", 0), "存档前主角可升至 2 级")
	_check(game_data.call("upgrade_skill", 0, "skill_slash"), "存档前可分配技能点")
	var player: PartyMemberState = game_data.call("get_party_member", 0)
	game_data.call("set_party_member_vitals", 0, player.max_hp - 7, player.max_mp - 3)
	var poison := StatusEffect.new()
	poison.type = StatusEffect.Type.POISON
	poison.potency = 3
	poison.duration = 2
	var effects: Array[StatusEffect] = [poison]
	game_data.call("set_party_member_status_effects", 0, effects)
	_check(game_data.call("equip_item", "item_throwing_knives"), "存档前可装备投掷匕首")
	game_data.call("mark_enemy_defeated", "Enemy1")
	game_data.call("mark_enemy_defeated", "Enemy2_ForestMain_12")
	game_data.call("set_curse", "player", 37)
	game_data.call("set_bond", "companion", 4)

	dialogue_manager.call("start", "forest_wanderer")
	await process_frame
	await process_frame
	await dialogic.call("end_timeline", true)
	await process_frame
	await process_frame
	var dialogic_state: Dictionary = dialogic.call("get_full_state")
	dialogic_state["variables"]["story"]["branches"]["forest_wanderer"] = "greeted"
	var snapshot: Dictionary = game_data.call(
		"_build_checkpoint_snapshot", &"forest_ruins", dialogic_state)
	_check(not snapshot.is_empty()
			and snapshot["dialogic"]["variables"]["story"]["branches"]["forest_wanderer"]
				== "greeted"
			and snapshot["dialogic"]["portraits"].is_empty()
			and snapshot["dialogic"]["text"].is_empty(),
			"篝火快照保留叙事变量并丢弃空闲表现残留")
	await dialogic.call("load_full_state", snapshot["dialogic"].duplicate(true))
	await process_frame
	await process_frame
	var variable_system: Node = dialogic.call("get_subsystem", "VAR")
	_check(variable_system.call(
			"get_variable", "story.branches.forest_wanderer") == "greeted",
			"规范化 Dialogic 状态可安全恢复叙事变量")
	_check(not snapshot["game_data"].has("curse_values")
			and not snapshot["game_data"].has("bond_values")
			and not snapshot["game_data"].has("cycle_count"),
			"v1 快照不接入长期羁绊、诅咒与周目字段")

	var expected_player: PartyMemberState = game_data.call("get_party_member", 0)
	var expected_embers: int = game_data.call("get_ember_count")
	var expected_salve_count: int = game_data.call("get_item_count", "item_ash_salve")
	game_data.call("add_embers", 13)
	game_data.call("set_party_member_vitals", 0, 1, 0)
	game_data.call("set_party_member_status_effects", 0, [] as Array[StatusEffect])
	game_data.call("remove_item", "item_ash_salve", 1)
	game_data.call("unequip_item", "weapon")
	game_data.call("set_enemy_defeated", "Enemy1", false)
	game_data.call("set_enemy_defeated", "Enemy2_ForestMain_12", false)
	game_data.call("set_flag", "campfire_discovered_forest_clearing", false)
	game_data.call("set_curse", "player", 0)
	game_data.call("set_bond", "companion", 0)

	var destination: Dictionary = game_data.call("_apply_checkpoint_snapshot", snapshot)
	var restored: PartyMemberState = game_data.call("get_party_member", 0)
	_check(destination.get("scene_path") == "res://scenes/ForestMain.tscn"
			and destination.get("spawn_id") == "forest_ruins",
			"载入点只由白名单篝火 ID 解析")
	_check(restored.level == expected_player.level
			and restored.skill_points == expected_player.skill_points
			and restored.skill_ranks == expected_player.skill_ranks
			and restored.hp == expected_player.hp and restored.mp == expected_player.mp
			and restored.status_effects.size() == 1
			and restored.status_effects[0].type == StatusEffect.Type.POISON
			and restored.status_effects[0].potency == 3
			and restored.status_effects[0].duration == 2,
			"等级、技能、生命与异常状态完整恢复")
	_check(game_data.call("get_ember_count") == expected_embers
			and game_data.call("get_item_count", "item_ash_salve") == expected_salve_count
			and game_data.call("get_equipped_item_id", "weapon") == "item_throwing_knives",
			"余烬、背包数量与装备完整恢复")
	_check(game_data.call("is_campfire_discovered", &"forest_clearing")
			and game_data.call("is_campfire_discovered", &"forest_ruins")
			and game_data.call("is_enemy_defeated", "Enemy1")
			and game_data.call("is_enemy_defeated", "Enemy2_ForestMain_12"),
			"篝火发现与敌人击败状态完整恢复")
	_check(game_data.call("get_curse", "player") == 0
			and game_data.call("get_bond", "companion") == 0,
			"载入不读取或改写休眠的羁绊、诅咒状态")

	game_data.call("add_embers", 1)
	var state_before_invalid := _capture_state(game_data)
	var invalid_version := snapshot.duplicate(true)
	invalid_version["version"] = 999
	_check(game_data.call("_apply_checkpoint_snapshot", invalid_version).is_empty()
			and _capture_state(game_data) == state_before_invalid,
			"未知版本被拒绝且不污染当前状态")

	var missing_equipment := snapshot.duplicate(true)
	missing_equipment["game_data"]["inventory"].erase("equipment")
	_check(game_data.call("_apply_checkpoint_snapshot", missing_equipment).is_empty()
			and _capture_state(game_data) == state_before_invalid,
			"缺少必填背包字段的坏档被原子拒绝")

	var active_timeline := snapshot.duplicate(true)
	active_timeline["dialogic"]["current_timeline"] = "res://dialogue/invalid.dtl"
	_check(game_data.call("_apply_checkpoint_snapshot", active_timeline).is_empty()
			and _capture_state(game_data) == state_before_invalid,
			"篝火档拒绝恢复对话中间态")
	var poisoned_portraits := snapshot.duplicate(true)
	poisoned_portraits["dialogic"]["portraits"] = 1
	_check(game_data.call("_apply_checkpoint_snapshot", poisoned_portraits).is_empty()
			and _capture_state(game_data) == state_before_invalid,
			"Dialogic 子系统坏字段不会造成半恢复")
	_check(game_data.call("save_checkpoint", &"unknown") == ERR_INVALID_PARAMETER,
			"未知篝火不能创建存档")

	print("[verify_campfire_save] 结果：%s" % (
		"全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	quit(_fails)


func _capture_state(game_data: Node) -> Dictionary:
	var player: PartyMemberState = game_data.call("get_party_member", 0)
	return {
		"hp": player.hp,
		"mp": player.mp,
		"level": player.level,
		"skill_ranks": player.skill_ranks,
		"embers": game_data.call("get_ember_count"),
		"salves": game_data.call("get_item_count", "item_ash_salve"),
		"weapon": game_data.call("get_equipped_item_id", "weapon"),
		"enemy": game_data.call("is_enemy_defeated", "Enemy1"),
	}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[verify_campfire_save] PASS: %s" % label)
	else:
		push_error("[verify_campfire_save] FAIL: %s" % label)
		_fails += 1
