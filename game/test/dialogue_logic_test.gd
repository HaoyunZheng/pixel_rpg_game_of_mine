extends Node
## 对话系统 确定性逻辑单元测试（headless，不触发 Dialogic GUI）
## 覆盖：注册表、start 守卫、Dialogic 变量读写、跨场景保持与玩法状态隔离。
## 以场景方式运行（自动加载单例须先就绪）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://test/dialogue_logic_test.tscn
## 退出码 = 失败数（0 = 全通过）。

var _fails: int = 0

func _ready() -> void:
	_test_registry()
	await _test_start_guards()
	_test_variables()
	await _test_cross_scene_persistence()
	Dialogic.VAR.reset()
	print("[test] 结果：%s" % ("全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	get_tree().quit(_fails)

func _check(label: String, ok: bool) -> void:
	if ok:
		print("[test] ✅ %s" % label)
	else:
		push_error("[test] ❌ %s" % label)
		_fails += 1

# 自动加载单例在 --script/场景运行下按节点取（对齐 battle_logic_test.gd）。
func _dm() -> Node:
	return get_node("/root/DialogueManager")

func _test_registry() -> void:
	var dm := _dm()
	var path: String = dm.REGISTRY.get("forest_wanderer", "")
	_check("注册表含 forest_wanderer", not path.is_empty())
	_check("forest_wanderer timeline 资源存在", ResourceLoader.exists(path))

func _test_start_guards() -> void:
	var dm := _dm()
	_check("初始无对话进行", dm.is_active() == false)
	_check("未登记 id 返回 false", dm.start("__not_registered__") == false)
	_check("失败后仍无对话进行", dm.is_active() == false)
	GameData.flags.erase("legacy_dialogue_hook")
	GameData.set_bond("companion", 2)
	var started: bool = dm.start("forest_wanderer", {
		"set_flags": PackedStringArray(["legacy_dialogue_hook"]),
		"bond_add": {"companion": 3},
	})
	_check("已登记对话可启动", started)
	_check("启动后进入互斥状态", dm.is_active())
	_check("进行中重复启动返回 false", dm.start("forest_wanderer") == false)
	await Dialogic.end_timeline(true)
	_check("结束后解除互斥状态", dm.is_active() == false)
	_check("旧 set_flags context 不再回流 GameData", not GameData.get_flag("legacy_dialogue_hook"))
	_check("旧 bond_add context 不再修改羁绊", GameData.get_bond("companion") == 2)

func _test_variables() -> void:
	Dialogic.VAR.reset()
	_check("流浪者相遇变量默认 false", Dialogic.VAR.get_variable("story.flags.met_forest_wanderer") == false)
	_check("流浪者分支变量默认 unseen", Dialogic.VAR.get_variable("story.branches.forest_wanderer") == "unseen")
	_check("Dialogic 可写相遇变量", Dialogic.VAR.set_variable("story.flags.met_forest_wanderer", true))
	_check("Dialogic 可写分支变量", Dialogic.VAR.set_variable("story.branches.forest_wanderer", "warned"))
	_check("相遇变量写后可读", Dialogic.VAR.get_variable("story.flags.met_forest_wanderer") == true)
	_check("分支变量写后可读", Dialogic.VAR.get_variable("story.branches.forest_wanderer") == "warned")

func _test_cross_scene_persistence() -> void:
	var forest_scene := load("res://scenes/ForestClearing.tscn") as PackedScene
	var forest: Node = forest_scene.instantiate()
	add_child(forest)
	await get_tree().process_frame
	forest.queue_free()
	await get_tree().process_frame
	var wilderness_scene := load("res://scenes/Wilderness.tscn") as PackedScene
	var wilderness: Node = wilderness_scene.instantiate()
	add_child(wilderness)
	await get_tree().process_frame
	_check("切换场景节点后相遇变量保持", Dialogic.VAR.get_variable("story.flags.met_forest_wanderer") == true)
	_check("切换场景节点后分支变量保持", Dialogic.VAR.get_variable("story.branches.forest_wanderer") == "warned")
	wilderness.queue_free()
	await get_tree().process_frame
