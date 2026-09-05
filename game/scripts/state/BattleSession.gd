class_name BattleSession
extends RefCounted
## 一场战斗的独占可变状态；结算前不写回 GameData。

enum Outcome { VICTORY, DEFEAT, FLED }

var party_units: Array[BattleUnit]
var enemy_units: Array[BattleUnit] = []
var inventory: InventoryState
var enemy_keys: Array[String]
var _settled: bool = false

func _init(
		initial_party: Array[BattleUnit],
		initial_inventory: InventoryState,
		initial_enemy_keys: Array[String]) -> void:
	party_units = initial_party
	inventory = initial_inventory
	enemy_keys = initial_enemy_keys.duplicate()

func begin_settlement() -> bool:
	if _settled:
		return false
	_settled = true
	return true
