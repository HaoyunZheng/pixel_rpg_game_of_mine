extends Node2D
## 战斗场景主控制器 — P2 回合制战斗实现

const WILDERNESS_SCENE_PATH: String = "res://scenes/Wilderness.tscn"
const FOREST_SCENE_PATH: String = "res://scenes/ForestClearing.tscn"
const DEFAULT_ENEMY_KEY: String = "Enemy1"
const DATA_KEY_SCENE_NAME: String = "scene_name"
const DATA_KEY_FROM: String = "from"
const DATA_KEY_ENEMY_KEY: String = "enemy_key"
const DATA_KEY_ENEMY_KEYS: String = "enemy_keys"  # 多敌：进场数据可传敌人 key 列表
const DATA_KEY_RETURN_SCENE_PATH: String = "return_scene_path"
const DATA_KEY_RETURN_SCENE_NAME: String = "return_scene_name"
const LEGACY_DATA_KEY_ENEMY: String = "enemy"

const ENEMY_RESOURCE_PATHS: Dictionary = {
	"Enemy1": "res://assets/data/enemies/enemy_hunter.tres",
	"Enemy2": "res://assets/data/enemies/enemy_mutant.tres",
}

@onready var _macro_sm = $BattleStateMachine
@onready var _micro_sm = $TurnStateMachine
@onready var _battle_ui = $UI/BattleUI

var _party_units: Array = []
var _enemy_units: Array = []
var _session: BattleSession = null
var _turn_order: Array = []
var _turn_index: int = 0
var _enemy_keys: Array[String] = []          # 本场敌方阵容 key 列表（1~N 体）
var _enemy_intents: Dictionary = {}
var _battle_started: bool = false
var _battle_exiting: bool = false
var _return_scene_path: String = WILDERNESS_SCENE_PATH
var _return_scene_name: String = "Wilderness"

func _ready() -> void:
	Log.info("Battle", "战斗场景已加载（P2）")
	GameCamera.deactivate()  # 战斗用 1:1 默认取景，交还全局相机
	_macro_sm.state_changed.connect(_on_macro_state_changed)
	_macro_sm.turn_order_calculated.connect(_on_turn_order_calculated)
	_macro_sm.battle_ended.connect(_on_battle_ended)
	_micro_sm.action_executed.connect(_on_action_executed)
	# [TEST] 直接启动 Battle 场景时自动初始化测试战斗
	call_deferred("_auto_test_init")

## [TEST] 直接启动 Battle 场景时自动初始化
func _auto_test_init() -> void:
	await get_tree().create_timer(0.1).timeout
	if not _battle_started and _party_units.is_empty():
		on_scene_enter({DATA_KEY_ENEMY_KEY: DEFAULT_ENEMY_KEY})

func on_scene_enter(data: Dictionary) -> void:
	if _battle_started:
		Log.info("Battle", "战斗已初始化，忽略重复进入数据: %s" % data)
		return
	_battle_started = true
	Log.info("Battle", "进入战斗，数据: %s" % data)
	var return_path = data.get(DATA_KEY_RETURN_SCENE_PATH)
	var return_name = data.get(DATA_KEY_RETURN_SCENE_NAME)
	if return_path is String and not return_path.is_empty():
		_return_scene_path = return_path
	if return_name is String and not return_name.is_empty():
		_return_scene_name = return_name
	_enemy_keys = _resolve_enemy_keys(data)
	_init_battle()
	_macro_sm.start_battle()

func _init_battle() -> void:
	_turn_index = 0
	_turn_order.clear()
	_session = GameData.create_battle_session(_enemy_keys)
	_party_units = _session.party_units
	_enemy_units = _session.enemy_units
	_enemy_intents.clear()
	for key in _enemy_keys:
		var enemy_stats = _lookup_enemy_stats(key)
		if enemy_stats:
			_enemy_units.append(BattleUnit.from_enemy_stats(enemy_stats))

	_battle_ui.setup(_party_units, _enemy_units, self, _micro_sm)
	_macro_sm.setup(self)
	_micro_sm.battle_controller = self
	_micro_sm.damage_calculator = DamageCalculator.new()
	Log.info("Battle", "战斗初始化: %d 我方 vs %d 敌方" % [_party_units.size(), _enemy_units.size()])

## 解析进场数据中的敌方阵容：优先多敌列表 enemy_keys，回退单敌 enemy_key / 旧版 enemy。
## 让 Wilderness（或未来的遭遇配置）以低耦合方式传入 1~N 体敌人，战斗主循环无需感知数量。
func _resolve_enemy_keys(data: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	var raw = data.get(DATA_KEY_ENEMY_KEYS, null)
	if raw is Array:
		for k in raw:
			if k is String and not (k as String).is_empty():
				keys.append(k)
	if keys.is_empty():
		var fallback = data.get(DATA_KEY_ENEMY_KEY, data.get(LEGACY_DATA_KEY_ENEMY, DEFAULT_ENEMY_KEY))
		keys.append(fallback if fallback is String and not fallback.is_empty() else DEFAULT_ENEMY_KEY)
	return keys

func _lookup_enemy_stats(enemy_key: String):
	var resource_key := enemy_key
	# ponytail: 前缀足够区分现有两类敌人；出现第三类或放弃前缀键时再拆分 encounter_id/enemy_type。
	if enemy_key.begins_with("Enemy1_"):
		resource_key = "Enemy1"
	elif enemy_key.begins_with("Enemy2_"):
		resource_key = "Enemy2"
	var enemy_resource_path: String = ENEMY_RESOURCE_PATHS.get(resource_key, ENEMY_RESOURCE_PATHS[DEFAULT_ENEMY_KEY])
	return load(enemy_resource_path)

func _get_return_destination(victory: bool, fled: bool = false) -> Dictionary:
	var returns_to_source := victory or fled
	return {
		"path": _return_scene_path if returns_to_source else FOREST_SCENE_PATH,
		"scene_name": _return_scene_name if returns_to_source else "ForestClearing",
	}

func get_all_units() -> Array:
	var all := _party_units.duplicate()
	all.append_array(_enemy_units)
	return all

func get_party_units() -> Array:
	return _party_units

func get_enemy_units() -> Array:
	return _enemy_units

func get_turn_order() -> Array:
	return _turn_order.duplicate()

func get_inventory_slots() -> Array[InventoryState.Slot]:
	return _session.inventory.get_slots() if _session != null else []

func consume_item(item_id: String) -> bool:
	return _session != null and _session.inventory.remove_item(item_id, 1)

func freeze_enemy_intents(turn_order: Array) -> void:
	_enemy_intents.clear()
	for enemy in _enemy_units:
		if enemy.is_dead():
			continue
		_enemy_intents[enemy] = EnemyAI.decide_intent(enemy, _party_units)
	Log.info("Battle", "本轮敌方意图已冻结: %d" % _enemy_intents.size())
	await _battle_ui.show_enemy_intents(_enemy_intents, turn_order)

func get_enemy_intent(enemy: BattleUnit) -> Dictionary:
	var intent: Dictionary = _enemy_intents.get(enemy, {})
	return intent.duplicate(true)

func run_timing_check(
		attacker: BattleUnit,
		target: BattleUnit,
		base_damage: int,
		intent: Dictionary = {}) -> Array:
	return await _battle_ui.run_timing_check(attacker, target, base_damage, intent)

func finish_timing_check(target: BattleUnit, timing_result: Dictionary) -> void:
	await _battle_ui.finish_timing_check(target, timing_result)

func play_player_hit(target: BattleUnit, strength: float) -> void:
	await _battle_ui.play_player_hit(target, strength)

func _on_turn_order_calculated(order: Array) -> void:
	_turn_order = order.duplicate()
	_turn_index = 0

func _on_macro_state_changed(state) -> void:
	if state == BattleStateMachine.MacroState.TURN_LOOP:
		_start_turn_loop()

func _start_turn_loop() -> void:
	if _macro_sm.check_battle_end():
		return
	while _turn_index < _turn_order.size():
		var current_actor: BattleUnit = _turn_order[_turn_index]
		_turn_index += 1
		if not current_actor.is_dead():
			_process_turn(current_actor)
			return
	_macro_sm.request_next_turn()

func _process_turn(actor: BattleUnit) -> void:
	Log.info("Battle", "轮到: %s" % actor.display_name)
	_battle_ui.show_actor_turn(actor)
	if not _micro_sm.turn_finished.is_connected(_on_turn_finished):
		_micro_sm.turn_finished.connect(_on_turn_finished, CONNECT_ONE_SHOT)
	_micro_sm.start_turn(actor)
	_battle_ui.call_deferred("refresh")

func _on_turn_finished() -> void:
	if _battle_exiting:
		return
	_battle_ui.refresh()
	_start_turn_loop()

func _on_action_executed(result: Dictionary) -> void:
	if not result.get("fled", false) or _battle_exiting:
		return
	_battle_exiting = true
	GameData.settle_battle(_session, BattleSession.Outcome.FLED)
	Log.info("Battle", "逃跑成功，立即返回来源地图")
	var destination := _get_return_destination(false, true)
	SceneManager.change_scene(destination.path, {
		DATA_KEY_SCENE_NAME: destination.scene_name,
		DATA_KEY_FROM: "battle",
		"victory": false,
		"fled": true,
	})

func _on_battle_ended(victory: bool) -> void:
	Log.info("Battle", "战斗结束，胜利: %s" % victory)
	var ember_reward: int = (
		_enemy_keys.size() * GameData.VICTORY_EMBERS_PER_ENEMY if victory else 0)
	_battle_ui.show_battle_result(victory, ember_reward)
	GameData.settle_battle(
		_session,
		BattleSession.Outcome.VICTORY if victory else BattleSession.Outcome.DEFEAT)
	await get_tree().create_timer(2.0).timeout
	var destination := _get_return_destination(victory)
	var return_data := {DATA_KEY_SCENE_NAME: destination.scene_name, DATA_KEY_FROM: "battle", "victory": victory}
	SceneManager.change_scene(destination.path, return_data)
