extends Node
## 对话系统 确定性逻辑单元测试（headless，不触发 Dialogic GUI）
## 覆盖：注册表、start 守卫、Dialogic 变量读写、跨场景保持、像素字体接入、样板分支与玩法状态隔离。
## 以场景方式运行（自动加载单例须先就绪）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://test/dialogue_logic_test.tscn
## 退出码 = 失败数（0 = 全通过）。

var _fails: int = 0
var _texts: Array[String] = []
var _question: Dictionary = {}

const PIXEL_FONT_PATH := "res://assets/ui/fonts/fusion-pixel-font/fusion-pixel-12px-proportional-zh_hans.ttf"
const SHARED_THEME_PATH := "res://assets/ui/battle/battle_theme.tres"

func _ready() -> void:
	_test_registry()
	await _test_start_guards()
	_test_variables()
	await _test_cross_scene_persistence()
	_test_pixel_font_resources()
	_test_sample_resources_and_inputs()
	await _test_sample_branch_loop()
	Dialogic.VAR.reset()
	await get_tree().process_frame
	await get_tree().process_frame
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
	GameData.set_flag("legacy_dialogue_hook", false)
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

func _test_pixel_font_resources() -> void:
	var pixel_font := load(PIXEL_FONT_PATH) as FontFile
	_check("简体中文像素字体可加载", pixel_font != null)
	_check("像素字体关闭抗锯齿、MSDF 与子像素定位", pixel_font != null
		and pixel_font.antialiasing == 0
		and not pixel_font.multichannel_signed_distance_field
		and pixel_font.subpixel_positioning == 0)
	var shared_theme := load(SHARED_THEME_PATH) as Theme
	_check("战斗与背包共享 Theme 使用像素字体", shared_theme != null and shared_theme.default_font == pixel_font)

	var forest := (load("res://scenes/ForestClearing.tscn") as PackedScene).instantiate()
	_check("林间空地文字使用像素字体", _labels_use_font(forest, PackedStringArray([
		"WildGate/Label", "Wanderer/Prompt",
	]), pixel_font))
	forest.free()

	var wilderness := (load("res://scenes/Wilderness.tscn") as PackedScene).instantiate()
	_check("野外场景文字使用像素字体", _labels_use_font(wilderness, PackedStringArray([
		"Enemies/Enemy1/Label", "Enemies/Enemy2/Label", "ExitTrigger/Label",
		"UI/Title", "UI/Subtitle", "UI/Hint",
	]), pixel_font))
	wilderness.free()

	var style := load("res://dialogue/styles/project_dialogue_style.tres") as DialogicStyle
	var base_overrides: Dictionary = style.get_layer_info("").overrides if style != null else {}
	_check("Dialogic 项目样式覆写 global_font", base_overrides.get("global_font", "") == var_to_str(PIXEL_FONT_PATH))

func _labels_use_font(root_node: Node, paths: PackedStringArray, pixel_font: Font) -> bool:
	for path: String in paths:
		var label := root_node.get_node_or_null(NodePath(path)) as Label
		if label == null or label.get_theme_font("font") != pixel_font:
			return false
	return true

func _test_sample_resources_and_inputs() -> void:
	var character := load("res://dialogue/characters/forest_wanderer.dch")
	var style := load("res://dialogue/styles/project_dialogue_style.tres")
	_check("流浪者 Character 可加载", character is DialogicCharacter)
	_check("项目 Dialogic Style 可加载", style is DialogicStyle)
	_check("项目 Style 继承内建 Speaker Textbox", style != null and style.inherits != null)
	_check("Z 可推进和确认选择", _action_has_key("ui_accept", KEY_Z))
	_check("W/上方向可向上选择", _action_has_key("ui_up", KEY_W) and _action_has_key("ui_up", KEY_UP))
	_check("S/下方向可向下选择", _action_has_key("ui_down", KEY_S) and _action_has_key("ui_down", KEY_DOWN))

func _action_has_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == key or event.physical_keycode == key):
			return true
	return false

func _test_sample_branch_loop() -> void:
	Dialogic.Text.text_started.connect(_on_text_started)
	Dialogic.Choices.question_shown.connect(_on_question_shown)
	Dialogic.VAR.reset()
	GameData.set_enemy_defeated("Enemy1", false)

	var first_cautious := await _play_sample(1)
	_check("首次对话显示两个选择", first_cautious and _question.get("choices", []).size() == 2)
	_check("谨慎选择记录相遇状态", Dialogic.VAR.get_variable("story.flags.met_forest_wanderer") == true)
	_check("谨慎选择写入 cautious 分支", Dialogic.VAR.get_variable("story.branches.forest_wanderer") == "cautious")
	_check("谨慎选择进入对应回应", _texts.any(func(text: String) -> bool: return "看见没有影子的火" in text))

	var cautious_repeat := await _play_sample()
	_check("谨慎重复分支可结束", cautious_repeat)
	_check("谨慎重复分支命中", _texts.any(func(text: String) -> bool: return "谨慎不是退缩" in text))
	_check("重复分支不再显示首次选择", _question.is_empty())

	Dialogic.VAR.reset()
	var first_defiant := await _play_sample(2)
	_check("强行前进选择可结束", first_defiant)
	_check("强行前进写入 defiant 分支", Dialogic.VAR.get_variable("story.branches.forest_wanderer") == "defiant")
	_check("强行前进进入对应回应", _texts.any(func(text: String) -> bool: return "勇气错当成不死" in text))

	var defiant_repeat := await _play_sample()
	_check("强行前进重复分支可结束", defiant_repeat)
	_check("强行前进重复分支命中", _texts.any(func(text: String) -> bool: return "承担代价" in text))

	GameData.mark_enemy_defeated("Enemy1")
	var enemy_condition := await _play_sample()
	_check("Enemy1 世界条件分支可结束", enemy_condition)
	_check("Timeline 读取 Enemy1 世界事实", _texts.any(func(text: String) -> bool: return "荒野里的猎手已经倒下" in text))

	GameData.set_enemy_defeated("Enemy1", false)
	Dialogic.Text.text_started.disconnect(_on_text_started)
	Dialogic.Choices.question_shown.disconnect(_on_question_shown)

func _play_sample(choice_index: int = 0) -> bool:
	_texts.clear()
	_question.clear()
	if not _dm().start("forest_wanderer"):
		return false
	var selected := false
	for _step in 160:
		await get_tree().process_frame
		Dialogic.Inputs.stop_timers()
		if not _dm().is_active():
			return true
		if Dialogic.current_state == Dialogic.States.AWAITING_CHOICE:
			if choice_index == 0:
				return false
			if not selected:
				await get_tree().create_timer(0.22).timeout
				Dialogic.Choices.select_choice(choice_index)
				selected = true
		else:
			Dialogic.Inputs.handle_input()
	if _dm().is_active():
		await Dialogic.end_timeline(true)
	return false

func _on_text_started(info: Dictionary) -> void:
	_texts.append(str(info.get("text", "")))

func _on_question_shown(info: Dictionary) -> void:
	_question = info.duplicate(true)
