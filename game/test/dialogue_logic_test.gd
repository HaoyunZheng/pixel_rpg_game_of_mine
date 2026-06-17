extends Node
## 对话系统 确定性逻辑单元测试（headless，不触发 Dialogic GUI）
## 覆盖：DialogueManager 注册表解析、start 守卫、结果回流（flag / 羁绊）。
## 以场景方式运行（自动加载单例须先就绪）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://test/dialogue_logic_test.tscn
## 退出码 = 失败数（0 = 全通过）。

var _fails: int = 0

func _ready() -> void:
	_test_registry()
	_test_start_guards()
	_test_end_hooks()
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

func _gd() -> Node:
	return get_node("/root/GameData")

func _test_registry() -> void:
	var dm := _dm()
	var path: String = dm.REGISTRY.get("forest_wanderer", "")
	_check("注册表含 forest_wanderer", not path.is_empty())
	_check("forest_wanderer timeline 资源存在", ResourceLoader.exists(path))

func _test_start_guards() -> void:
	var dm := _dm()
	_check("初始无对话进行", dm.is_active() == false)
	# 未登记 id：在调用 Dialogic 前就返回 false（不触发 GUI）。
	_check("未登记 id 返回 false", dm.start("__not_registered__") == false)
	_check("失败后仍无对话进行", dm.is_active() == false)

func _test_end_hooks() -> void:
	var dm := _dm()
	var gd := _gd()
	gd.flags.clear()
	gd.bond_values.clear()

	# flag 回流
	dm._apply_end_hooks({"set_flags": PackedStringArray(["met_forest_wanderer"])})
	_check("set_flags 写入 GameData.flags", gd.get_flag("met_forest_wanderer") == true)

	# 羁绊回流（增量累加）
	gd.set_bond("companion", 2)
	dm._apply_end_hooks({"bond_add": {"companion": 3}})
	_check("bond_add 在原值上累加 = 5", gd.get_bond("companion") == 5)

	# 空 context 不报错、不改状态
	dm._apply_end_hooks({})
	_check("空 context 后羁绊不变 = 5", gd.get_bond("companion") == 5)
