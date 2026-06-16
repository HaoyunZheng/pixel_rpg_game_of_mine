extends Node
## 战斗 / 背包 确定性逻辑单元测试（headless，无资产依赖）
## 覆盖：DamageCalculator 公式、EnemyAI 选靶、BattleUnit 钳制、GameData 背包增删堆叠。
## 以场景方式运行（自动加载单例须先就绪，故不用 --script SceneTree）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       res://test/battle_logic_test.tscn
## 退出码 = 失败数（0 = 全通过）。

var _fails: int = 0

func _ready() -> void:
	_test_damage_calculator()
	_test_enemy_ai_targeting()
	_test_battle_unit_clamp()
	_test_inventory()
	print("[test] 结果：%s" % ("全部通过 ✅" if _fails == 0 else "%d 项失败 ❌" % _fails))
	get_tree().quit(_fails)

func _check(label: String, ok: bool) -> void:
	if ok:
		print("[test] ✅ %s" % label)
	else:
		push_error("[test] ❌ %s" % label)
		_fails += 1

func _make_unit(atk: int, def: int, spd: int, hp: int = 100) -> BattleUnit:
	var u := BattleUnit.new()
	u.atk = atk
	u.def = def
	u.spd = spd
	u.hp = hp
	u.max_hp = hp
	return u

func _make_skill(power: int, dmg_type: SkillData.DamageType) -> SkillData:
	var s := SkillData.new()
	s.power = power
	s.damage_type = dmg_type
	s.skill_type = SkillData.SkillType.ATTACK
	return s

func _test_damage_calculator() -> void:
	var calc := DamageCalculator.new()
	var atk := _make_unit(20, 0, 10)
	var tgt := _make_unit(0, 5, 10)

	# 物理：atk - def，倍率默认 1.0
	_check("calc_physical 20atk-5def = 15", calc.calc_physical(atk, tgt) == 15)

	# 力度倍率 1.5×：round((20-5)*1.5)=round(22.5)=23（half away from zero）
	atk.power_multiplier = 1.5
	_check("calc_physical ×1.5 = 23", calc.calc_physical(atk, tgt) == 23)
	atk.power_multiplier = 1.0

	# 下限保护：净值<=0 仍至少 1 点
	var weak := _make_unit(1, 0, 10)
	var tank := _make_unit(0, 99, 10)
	_check("calc_physical 下限保 1", calc.calc_physical(weak, tank) == 1)

	# 技能物理：atk + power - def
	var skill := _make_skill(10, SkillData.DamageType.PHYSICAL)
	_check("calc_skill 物理 20+10-5 = 25", calc.calc_skill(atk, tgt, skill) == 25)

	# 技能魔法：atk + power - def/2
	var mskill := _make_skill(10, SkillData.DamageType.MAGIC)
	_check("calc_skill 魔法 20+10-5/2 = 28", calc.calc_skill(atk, tgt, mskill) == 28)

func _test_enemy_ai_targeting() -> void:
	var enemy := _make_unit(10, 0, 5)
	enemy.ai_type = EnemyStats.AIType.HUNTER
	var hi := _make_unit(0, 0, 5, 30)
	hi.display_name = "高血"
	var lo := _make_unit(0, 0, 5, 10)
	lo.display_name = "低血"

	# 猎手攻击 HP 最低者
	var res := EnemyAI.decide_action(enemy, [hi, lo])
	_check("hunter 指令 = attack", res.command == BattleCommands.ATTACK)
	_check("hunter 选 HP 最低目标", res.target == lo)

	# 全员阵亡时 target = null，不崩
	hi.hp = 0
	lo.hp = 0
	var res2 := EnemyAI.decide_action(enemy, [hi, lo])
	_check("全灭时 target = null", res2.target == null)

func _test_battle_unit_clamp() -> void:
	var u := _make_unit(0, 0, 5, 50)
	u.take_damage(80)
	_check("take_damage 不低于 0", u.hp == 0)
	u.heal(999)
	_check("heal 不超过 max_hp", u.hp == 50)

func _test_inventory() -> void:
	# 自动加载单例在 --script 运行下不作为全局标识符暴露，按节点取（对齐 verify_*.gd）。
	var gd: Node = get_node("/root/GameData")
	gd.inventory.clear()
	var item := ItemData.new()
	item.id = "test_potion"
	item.category = ItemData.ItemCategory.CONSUMABLE

	gd.add_item(item, 2)
	gd.add_item(item, 3)
	_check("add_item 同 id 堆叠 = 5", gd.get_item_count("test_potion") == 5)

	_check("remove_item 足量返回 true", gd.remove_item("test_potion", 2) == true)
	_check("remove 后剩余 = 3", gd.get_item_count("test_potion") == 3)
	_check("remove_item 超量返回 false", gd.remove_item("test_potion", 99) == false)
	_check("超量 remove 不改数量", gd.get_item_count("test_potion") == 3)

	gd.remove_item("test_potion", 3)
	_check("扣到 0 移除槽位", gd.get_item_count("test_potion") == 0)
