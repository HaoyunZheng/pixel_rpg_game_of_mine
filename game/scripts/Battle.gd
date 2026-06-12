extends Node2D
## 战斗场景主控制器 — P2 回合制战斗实现

const WILDERNESS_SCENE_PATH: String = "res://scenes/Wilderness.tscn"
const FOREST_SCENE_PATH: String = "res://scenes/ForestClearing.tscn"
const DAMAGE_CALCULATOR_PATH: String = "res://scripts/battle/DamageCalculator.gd"
const BATTLE_UNIT_SCRIPT := preload("res://scripts/battle/BattleUnit.gd")
const DEFAULT_ENEMY_KEY: String = "Enemy1"
const DATA_KEY_SCENE_NAME: String = "scene_name"
const DATA_KEY_FROM: String = "from"
const DATA_KEY_ENEMY_KEY: String = "enemy_key"
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
var _turn_order: Array = []
var _turn_index: int = 0
var _current_actor = null
var _enemy_key: String = DEFAULT_ENEMY_KEY
var _battle_started: bool = false
# §B.2 战斗数据隔离：开战时快照背包，失败时回滚物品消耗
var _inventory_snapshot: Array[Dictionary] = []

func _ready() -> void:
	Log.info("Battle", "战斗场景已加载（P2）")
	GameCamera.deactivate()  # 战斗用 1:1 默认取景，交还全局相机
	_macro_sm.state_changed.connect(_on_macro_state_changed)
	_macro_sm.turn_order_calculated.connect(_on_turn_order_calculated)
	_macro_sm.battle_ended.connect(_on_battle_ended)
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
	_enemy_key = data.get(DATA_KEY_ENEMY_KEY, data.get(LEGACY_DATA_KEY_ENEMY, DEFAULT_ENEMY_KEY))
	_init_battle()
	_macro_sm.start_battle()

func _init_battle() -> void:
	_turn_index = 0
	_turn_order.clear()
	_inventory_snapshot = GameData.duplicate_inventory()
	_party_units.clear()
	for member in GameData.party_members:
		_party_units.append(BATTLE_UNIT_SCRIPT.from_party_member(member))

	_enemy_units.clear()
	var enemy_stats = _lookup_enemy_stats(_enemy_key)
	if enemy_stats:
		_enemy_units.append(BATTLE_UNIT_SCRIPT.from_enemy_stats(enemy_stats))

	_battle_ui.setup(_party_units, _enemy_units, self, _micro_sm)
	_macro_sm.setup(self)
	_micro_sm.battle_controller = self
	_micro_sm.damage_calculator = load(DAMAGE_CALCULATOR_PATH).new()
	Log.info("Battle", "战斗初始化: %d 我方 vs %d 敌方" % [_party_units.size(), _enemy_units.size()])

func _lookup_enemy_stats(enemy_key: String):
	var enemy_resource_path: String = ENEMY_RESOURCE_PATHS.get(enemy_key, ENEMY_RESOURCE_PATHS[DEFAULT_ENEMY_KEY])
	return load(enemy_resource_path)

func get_all_units() -> Array:
	var all := _party_units.duplicate()
	all.append_array(_enemy_units)
	return all

func get_party_units() -> Array:
	return _party_units

func get_enemy_units() -> Array:
	return _enemy_units

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
		_current_actor = _turn_order[_turn_index]
		_turn_index += 1
		if not _current_actor.is_dead():
			_process_turn(_current_actor)
			return
	_macro_sm.request_next_turn()

func _process_turn(actor) -> void:
	Log.info("Battle", "轮到: %s" % actor.display_name)
	_battle_ui.show_actor_turn(actor)
	if not _micro_sm.turn_finished.is_connected(_on_turn_finished):
		_micro_sm.turn_finished.connect(_on_turn_finished, CONNECT_ONE_SHOT)
	_micro_sm.start_turn(actor)

func _on_turn_finished() -> void:
	_sync_party_to_gamedata()
	_battle_ui.refresh()
	_start_turn_loop()

func _sync_party_to_gamedata() -> void:
	for i in range(min(_party_units.size(), GameData.party_members.size())):
		GameData.party_members[i].hp = _party_units[i].hp
		GameData.party_members[i].mp = _party_units[i].mp
		GameData.party_members[i].status_effects = _party_units[i].status_effects.duplicate()

func _on_battle_ended(victory: bool) -> void:
	Log.info("Battle", "战斗结束，胜利: %s" % victory)
	_battle_ui.show_battle_result(victory)
	if victory:
		GameData.mark_enemy_defeated(_enemy_key)
	if not victory:
		_reset_party_hp_mp()
		GameData.restore_inventory(_inventory_snapshot)
	await get_tree().create_timer(2.0).timeout
	var return_scene_path := WILDERNESS_SCENE_PATH if victory else FOREST_SCENE_PATH
	var return_data := {DATA_KEY_SCENE_NAME: "Wilderness" if victory else "ForestClearing", DATA_KEY_FROM: "battle", "victory": victory}
	SceneManager.change_scene(return_scene_path, return_data)

func _reset_party_hp_mp() -> void:
	for member in GameData.party_members:
		member.hp = member.max_hp
		member.mp = member.max_mp
		member.status_effects.clear()
