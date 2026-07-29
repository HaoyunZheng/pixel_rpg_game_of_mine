extends Node
## GameData — 玩法状态单例门面。
## 可变队伍/背包数据仅在本类内持有；对外返回快照并提供语义化操作。

signal item_used(item_id: String)
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(item_id: String, slot: String)
signal item_discarded(item_id: String, count: int)

const INITIAL_ITEMS: Dictionary = {
	"res://assets/data/items/item_ash_salve.tres": 2,
	"res://assets/data/items/item_glimmer_water.tres": 1,
	"res://assets/data/items/item_shardstone.tres": 1,
	"res://assets/data/items/item_throwing_knives.tres": 1,
	"res://assets/data/items/item_bandage_kit.tres": 1,
	"res://assets/data/items/item_black_sack.tres": 1,
	"res://assets/data/items/item_red_pouch.tres": 1,
}

var _party_members: Array[PartyMemberState] = []
var _inventory := InventoryState.new()
var _current_scene_name: String = ""
var _flags: Dictionary = {}
var _curse_values: Dictionary = {}
var _bond_values: Dictionary = {}
var _defeated_enemies: Dictionary = {}
var _cycle_count: int = 1

func _ready() -> void:
	Log.info("GameData", "全局状态单例已加载")
	_apply_default_fullscreen()
	_init_party()
	_init_inventory()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _apply_default_fullscreen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ── 队伍与战斗会话 ──

func get_party_members() -> Array[PartyMemberState]:
	var result: Array[PartyMemberState] = []
	for member: PartyMemberState in _party_members:
		result.append(member.copy())
	return result

func get_party_member(index: int) -> PartyMemberState:
	if index < 0 or index >= _party_members.size():
		return null
	return _party_members[index].copy()

func set_party_member_vitals(index: int, hp: int, mp: int) -> bool:
	if index < 0 or index >= _party_members.size():
		return false
	var member := _party_members[index]
	member.hp = clampi(hp, 0, member.max_hp)
	member.mp = clampi(mp, 0, member.max_mp)
	return true

func set_party_member_status_effects(index: int, effects: Array[StatusEffect]) -> bool:
	if index < 0 or index >= _party_members.size():
		return false
	_party_members[index].status_effects.clear()
	for effect: StatusEffect in effects:
		_party_members[index].status_effects.append(effect.duplicate() as StatusEffect)
	return true

func create_battle_session(enemy_keys: Array[String]) -> BattleSession:
	var party_units: Array[BattleUnit] = []
	var equipment_bonuses := get_equipment_bonuses()
	for index in range(_party_members.size()):
		party_units.append(BattleUnit.from_party_member(
			_party_members[index], equipment_bonuses if index == 0 else {}))
	return BattleSession.new(party_units, _inventory.copy(), enemy_keys)

func settle_battle(session: BattleSession, outcome: BattleSession.Outcome) -> bool:
	if session == null or not session.begin_settlement():
		return false
	match outcome:
		BattleSession.Outcome.VICTORY, BattleSession.Outcome.FLED:
			_commit_party_units(session.party_units)
			_inventory = session.inventory.copy()
			if outcome == BattleSession.Outcome.VICTORY:
				for enemy_key: String in session.enemy_keys:
					mark_enemy_defeated(enemy_key)
		BattleSession.Outcome.DEFEAT:
			_reset_party_after_defeat()
	return true

func _commit_party_units(units: Array[BattleUnit]) -> void:
	for index in range(mini(units.size(), _party_members.size())):
		var unit := units[index]
		var member := _party_members[index]
		member.hp = clampi(unit.hp, 0, member.max_hp)
		member.mp = clampi(unit.mp, 0, member.max_mp)
		member.status_effects.clear()
		for effect: StatusEffect in unit.status_effects:
			member.status_effects.append(effect.duplicate() as StatusEffect)

func _reset_party_after_defeat() -> void:
	for member: PartyMemberState in _party_members:
		member.hp = member.max_hp
		member.mp = member.max_mp
		member.status_effects.clear()

# ── 场景与世界事实 ──

func set_current_scene_name(scene_name: String) -> void:
	_current_scene_name = scene_name

func get_current_scene_name() -> String:
	return _current_scene_name

func set_flag(key: String, value: bool = true) -> void:
	_flags[key] = value

func get_flag(key: String, default: bool = false) -> bool:
	return _flags.get(key, default)

func set_enemy_defeated(enemy_key: String, defeated: bool) -> void:
	if defeated:
		_defeated_enemies[enemy_key] = true
	else:
		_defeated_enemies.erase(enemy_key)

func mark_enemy_defeated(enemy_key: String) -> void:
	set_enemy_defeated(enemy_key, true)

func is_enemy_defeated(enemy_key: String) -> bool:
	return _defeated_enemies.get(enemy_key, false)

func set_curse(character_id: String, value: int) -> void:
	_curse_values[character_id] = clampi(value, 0, 100)

func get_curse(character_id: String) -> int:
	return _curse_values.get(character_id, 0)

func set_bond(character_id: String, value: int) -> void:
	_bond_values[character_id] = clampi(value, 0, 10)

func get_bond(character_id: String) -> int:
	return _bond_values.get(character_id, 0)

func get_cycle_count() -> int:
	return _cycle_count

# ── 背包门面 ──

func get_inventory_slots() -> Array[InventoryState.Slot]:
	return _inventory.get_slots()

func add_item(item: ItemData, count: int = 1) -> bool:
	return _inventory.add_item(item, count)

func remove_item(item_id: String, count: int = 1) -> bool:
	return _inventory.remove_item(item_id, count)

func get_item_count(item_id: String) -> int:
	return _inventory.get_item_count(item_id)

func get_item_by_id(item_id: String) -> ItemData:
	return _inventory.get_item_by_id(item_id)

func can_use_item(item_id: String) -> bool:
	var item := get_item_by_id(item_id)
	if item == null or not item.usable or item.effect_value <= 0 or _party_members.is_empty():
		return false
	var member := _party_members[0]
	match item.effect_type:
		ItemData.EffectType.HEAL_HP:
			return member.hp < member.max_hp
		ItemData.EffectType.HEAL_MP:
			return member.mp < member.max_mp
		_:
			return false

func use_item(item_id: String) -> bool:
	if not can_use_item(item_id):
		return false
	var item := get_item_by_id(item_id)
	if not remove_item(item_id, 1):
		return false
	var member := _party_members[0]
	match item.effect_type:
		ItemData.EffectType.HEAL_HP:
			member.hp = mini(member.max_hp, member.hp + item.effect_value)
		ItemData.EffectType.HEAL_MP:
			member.mp = mini(member.max_mp, member.mp + item.effect_value)
	item_used.emit(item_id)
	return true

func equip_item(item_id: String) -> bool:
	var item := get_item_by_id(item_id)
	if item == null:
		return false
	var slot := _equipment_slot_for(item)
	if slot.is_empty() or _inventory.get_equipped_item_id(slot) == item_id:
		return false
	if not _inventory.get_equipped_item_id(slot).is_empty():
		unequip_item(slot)
	_inventory.set_equipped_item(slot, item_id)
	item_equipped.emit(item_id, slot)
	return true

func unequip_item(slot: String) -> bool:
	var old_id := _inventory.get_equipped_item_id(slot)
	if old_id.is_empty() or not _inventory.set_equipped_item(slot, ""):
		return false
	item_unequipped.emit(old_id, slot)
	return true

func discard_item(item_id: String, count: int) -> bool:
	if count <= 0 or get_item_count(item_id) < count:
		return false
	var equipped_slot := _inventory.find_equipped_slot(item_id)
	if not equipped_slot.is_empty():
		unequip_item(equipped_slot)
	if not remove_item(item_id, count):
		return false
	item_discarded.emit(item_id, count)
	return true

func is_item_equipped(item_id: String) -> bool:
	return not _inventory.find_equipped_slot(item_id).is_empty()

func get_equipped_item_id(slot: String) -> String:
	return _inventory.get_equipped_item_id(slot)

func get_equipment_bonuses() -> Dictionary:
	var bonuses := {"atk": 0, "def": 0}
	for slot: String in InventoryState.EQUIPMENT_SLOTS:
		var item := get_item_by_id(_inventory.get_equipped_item_id(slot))
		if item == null:
			continue
		bonuses.atk += item.attack_bonus
		bonuses.def += item.defense_bonus
	return bonuses

func _equipment_slot_for(item: ItemData) -> String:
	match item.category:
		ItemData.ItemCategory.WEAPON:
			return "weapon"
		ItemData.ItemCategory.ARMOR:
			return "armor"
		ItemData.ItemCategory.ACCESSORY:
			return "accessory"
		_:
			return ""

func _init_party() -> void:
	if not _party_members.is_empty():
		return
	var player_stats := load("res://assets/data/characters/char_player.tres") as CharacterStats
	var companion_stats := load("res://assets/data/characters/char_companion.tres") as CharacterStats
	_party_members = [
		PartyMemberState.from_stats(player_stats),
		PartyMemberState.from_stats(companion_stats),
	]
	Log.info("GameData", "队伍初始化完成: %d 人" % _party_members.size())

func _init_inventory() -> void:
	if not _inventory.get_slots().is_empty():
		return
	for path: String in INITIAL_ITEMS:
		var item := load(path) as ItemData
		if item != null:
			add_item(item, INITIAL_ITEMS[path])
	Log.info("GameData", "背包初始化完成: %d 种物品" % _inventory.get_slots().size())
