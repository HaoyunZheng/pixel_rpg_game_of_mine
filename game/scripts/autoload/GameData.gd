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
const DEMO_MAX_LEVEL: int = 5
const VICTORY_EMBERS_PER_ENEMY: int = 20
const LEVEL_UP_BASE_COST: int = 20
const LEVEL_UP_COST_STEP: int = 20
const LEVEL_HP_GAIN: int = 10
const LEVEL_MP_GAIN: int = 2
const LEVEL_ATK_GAIN: int = 2
const LEVEL_DEF_GAIN: int = 1
const LEVEL_SPD_GAIN: int = 1
const CHECKPOINT_SAVE_VERSION: int = 1
const CHECKPOINT_SAVE_SLOT: String = "campfire"
const CHECKPOINT_SAVE_FILE: String = "checkpoint.dat"
const CAMPFIRE_DESTINATIONS: Dictionary = {
	&"forest_clearing": {
		"display_name": "林间空地",
		"scene_path": "res://scenes/ForestClearing.tscn",
		"scene_name": "ForestClearing",
		"spawn_id": "forest_clearing",
	},
	&"forest_ruins": {
		"display_name": "路边废墟",
		"scene_path": "res://scenes/ForestMain.tscn",
		"scene_name": "ForestMain",
		"spawn_id": "forest_ruins",
	},
}

var _party_members: Array[PartyMemberState] = []
var _inventory := InventoryState.new()
var _ember_count: int = 0
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

func rest_party() -> bool:
	if _party_members.is_empty():
		return false
	for member: PartyMemberState in _party_members:
		member.hp = member.max_hp
		member.mp = member.max_mp
		member.status_effects.clear()
	return true

func get_ember_count() -> int:
	return _ember_count

func add_embers(amount: int) -> bool:
	if amount <= 0:
		return false
	_ember_count += amount
	return true

func get_level_up_cost(member_index: int) -> int:
	if member_index != 0 or member_index >= _party_members.size():
		return 0
	var member := _party_members[member_index]
	if member.level >= DEMO_MAX_LEVEL:
		return 0
	return LEVEL_UP_BASE_COST + (member.level - 1) * LEVEL_UP_COST_STEP

func upgrade_party_member(member_index: int) -> bool:
	var cost := get_level_up_cost(member_index)
	if cost <= 0 or _ember_count < cost:
		return false
	var member := _party_members[member_index]
	_ember_count -= cost
	member.level += 1
	member.skill_points += 1
	member.max_hp += LEVEL_HP_GAIN
	member.hp += LEVEL_HP_GAIN
	member.max_mp += LEVEL_MP_GAIN
	member.mp += LEVEL_MP_GAIN
	member.atk += LEVEL_ATK_GAIN
	member.def += LEVEL_DEF_GAIN
	member.spd += LEVEL_SPD_GAIN
	return true

func get_skill_rank(member_index: int, skill_id: String) -> int:
	if member_index < 0 or member_index >= _party_members.size():
		return 0
	var member := _party_members[member_index]
	if _find_party_skill(member, skill_id) == null:
		return 0
	return maxi(1, int(member.skill_ranks.get(skill_id, 1)))

func upgrade_skill(member_index: int, skill_id: String) -> bool:
	if member_index != 0 or member_index >= _party_members.size():
		return false
	var member := _party_members[member_index]
	var skill := _find_party_skill(member, skill_id)
	if skill == null or member.skill_points <= 0:
		return false
	var rank := get_skill_rank(member_index, skill_id)
	if rank >= skill.max_rank:
		return false
	member.skill_points -= 1
	member.skill_ranks[skill_id] = rank + 1
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
				add_embers(session.enemy_keys.size() * VICTORY_EMBERS_PER_ENEMY)
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

func _find_party_skill(member: PartyMemberState, skill_id: String) -> SkillData:
	if member.stats_res == null:
		return null
	for raw_skill in member.stats_res.skills:
		var skill := raw_skill as SkillData
		if skill != null and skill.id == skill_id:
			return skill
	return null

# ── 场景与世界事实 ──

func set_current_scene_name(scene_name: String) -> void:
	_current_scene_name = scene_name

func get_current_scene_name() -> String:
	return _current_scene_name

func set_flag(key: String, value: bool = true) -> void:
	_flags[key] = value

func get_flag(key: String, default: bool = false) -> bool:
	return _flags.get(key, default)

func discover_campfire(campfire_id: StringName) -> bool:
	if campfire_id.is_empty():
		return false
	set_flag("campfire_discovered_%s" % campfire_id)
	return true

func is_campfire_discovered(campfire_id: StringName) -> bool:
	return get_flag("campfire_discovered_%s" % campfire_id)

func get_campfire_destination(campfire_id: StringName) -> Dictionary:
	if not CAMPFIRE_DESTINATIONS.has(campfire_id):
		return {}
	return Dictionary(CAMPFIRE_DESTINATIONS[campfire_id]).duplicate(true)

# ── 篝火存档 ──

func save_checkpoint(campfire_id: StringName) -> Error:
	if not CAMPFIRE_DESTINATIONS.has(campfire_id):
		return ERR_INVALID_PARAMETER
	if DisplayServer.get_name() == "headless":
		return OK
	var snapshot := _build_checkpoint_snapshot(campfire_id, Dialogic.get_full_state())
	if snapshot.is_empty():
		return ERR_INVALID_DATA
	var save_error: Error = Dialogic.Save.save_file(
		CHECKPOINT_SAVE_SLOT, CHECKPOINT_SAVE_FILE, snapshot)
	if save_error == OK:
		Log.info("GameData", "篝火存档完成: %s" % campfire_id)
	else:
		Log.error("GameData", "篝火存档失败: %s" % error_string(save_error))
	return save_error

func load_checkpoint() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	var raw = Dialogic.Save.load_file(
		CHECKPOINT_SAVE_SLOT, CHECKPOINT_SAVE_FILE, null)
	if not raw is Dictionary or raw.is_empty():
		return {}
	var destination := _apply_checkpoint_snapshot(raw)
	if destination.is_empty():
		Log.warn("GameData", "篝火存档无效，改用新游戏状态")
		return {}
	await Dialogic.load_full_state(raw["dialogic"])
	await get_tree().process_frame
	Log.info("GameData", "篝火存档已恢复: %s" % destination.campfire_id)
	return destination

func _build_checkpoint_snapshot(
		campfire_id: StringName, dialogic_state: Dictionary) -> Dictionary:
	var destination := get_campfire_destination(campfire_id)
	var checkpoint_dialogic := _make_checkpoint_dialogic_state(dialogic_state)
	if destination.is_empty() or checkpoint_dialogic.is_empty():
		return {}
	var party: Array[Dictionary] = []
	for member: PartyMemberState in _party_members:
		var effects: Array[Dictionary] = []
		for effect: StatusEffect in member.status_effects:
			effects.append({
				"type": int(effect.type),
				"potency": effect.potency,
				"duration": effect.duration,
			})
		party.append({
			"id": member.id,
			"hp": member.hp,
			"mp": member.mp,
			"level": member.level,
			"skill_ranks": member.skill_ranks.duplicate(),
			"status_effects": effects,
		})

	var inventory_slots: Array[Dictionary] = []
	for slot: InventoryState.Slot in _inventory.get_slots():
		var resource_path := slot.item.resource_path
		# ponytail: Demo 物品目录等同初始表；出现非初始掉落时再拆独立目录。
		if not INITIAL_ITEMS.has(resource_path):
			return {}
		inventory_slots.append({"resource_path": resource_path, "count": slot.count})
	var equipment: Dictionary = {}
	for slot_name: String in InventoryState.EQUIPMENT_SLOTS:
		var item_id := _inventory.get_equipped_item_id(slot_name)
		if not item_id.is_empty():
			var item := _inventory.get_item_by_id(item_id)
			if item == null or _equipment_slot_for(item) != slot_name:
				return {}
		equipment[slot_name] = item_id
	var flags: Dictionary = {}
	for known_campfire_id: StringName in CAMPFIRE_DESTINATIONS:
		if is_campfire_discovered(known_campfire_id):
			flags["campfire_discovered_%s" % known_campfire_id] = true

	# ponytail: v1 只保存已启用的 Demo 系统；长期字段随新版本迁移再加入。
	return {
		"version": CHECKPOINT_SAVE_VERSION,
		"checkpoint": String(campfire_id),
		"game_data": {
			"party": party,
			"inventory": {"slots": inventory_slots, "equipment": equipment},
			"ember_count": _ember_count,
			"flags": flags,
			"defeated_enemies": _defeated_enemies.duplicate(true),
		},
		"dialogic": checkpoint_dialogic,
	}

func _apply_checkpoint_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("version", -1) != CHECKPOINT_SAVE_VERSION \
			or not snapshot.get("checkpoint", null) is String \
			or not snapshot.get("game_data", null) is Dictionary \
			or not _is_checkpoint_dialogic_state(snapshot.get("dialogic", null)):
		return {}
	var campfire_id := StringName(snapshot["checkpoint"])
	var destination := get_campfire_destination(campfire_id)
	if destination.is_empty():
		return {}
	var game_state: Dictionary = snapshot["game_data"]
	var loaded_party := _parse_checkpoint_party(game_state.get("party", null))
	var loaded_inventory := _parse_checkpoint_inventory(
		game_state.get("inventory", null))
	var loaded_flags = _parse_checkpoint_flags(
		game_state.get("flags", null), campfire_id)
	var loaded_enemies = _parse_defeated_enemies(
		game_state.get("defeated_enemies", null))
	var ember_count = game_state.get("ember_count", -1)
	if loaded_party.size() != _party_members.size() \
			or loaded_inventory == null \
			or loaded_flags == null \
			or loaded_enemies == null \
			or not ember_count is int or ember_count < 0:
		return {}

	_party_members = loaded_party
	_inventory = loaded_inventory
	_ember_count = ember_count
	_flags = loaded_flags
	_defeated_enemies = loaded_enemies
	_current_scene_name = destination.scene_name
	destination["campfire_id"] = String(campfire_id)
	return destination

func _parse_checkpoint_party(value: Variant) -> Array[PartyMemberState]:
	var result: Array[PartyMemberState] = []
	if not value is Array or value.size() != _party_members.size():
		return result
	for index in range(value.size()):
		var raw = value[index]
		var template := _party_members[index]
		if not raw is Dictionary or raw.get("id", "") != template.id:
			return []
		var level = raw.get("level", 0)
		var hp = raw.get("hp", -1)
		var mp = raw.get("mp", -1)
		if not level is int or not hp is int or not mp is int \
				or (index == 0 and (level < 1 or level > DEMO_MAX_LEVEL)) \
				or (index != 0 and level != 1):
			return []
		var member := PartyMemberState.from_stats(template.stats_res)
		member.level = level
		if index == 0:
			var gained_levels: int = level - 1
			member.max_hp += gained_levels * LEVEL_HP_GAIN
			member.max_mp += gained_levels * LEVEL_MP_GAIN
			member.atk += gained_levels * LEVEL_ATK_GAIN
			member.def += gained_levels * LEVEL_DEF_GAIN
			member.spd += gained_levels * LEVEL_SPD_GAIN
		if hp < 0 or hp > member.max_hp or mp < 0 or mp > member.max_mp:
			return []
		member.hp = hp
		member.mp = mp

		var saved_ranks = raw.get("skill_ranks", null)
		if not saved_ranks is Dictionary:
			return []
		var known_skills: Dictionary = {}
		var spent_points: int = 0
		for raw_skill in member.stats_res.skills:
			var skill := raw_skill as SkillData
			if skill == null:
				continue
			known_skills[skill.id] = true
			var rank = saved_ranks.get(skill.id, null)
			if not rank is int or rank < 1 or rank > skill.max_rank:
				return []
			member.skill_ranks[skill.id] = rank
			spent_points += rank - 1
		if saved_ranks.size() != known_skills.size():
			return []
		for saved_id: Variant in saved_ranks:
			if not saved_id is String or not known_skills.has(saved_id):
				return []
		var earned_points: int = level - 1 if index == 0 else 0
		if spent_points > earned_points:
			return []
		member.skill_points = earned_points - spent_points

		var saved_effects = raw.get("status_effects", null)
		if not saved_effects is Array or saved_effects.size() > 16:
			return []
		for raw_effect: Variant in saved_effects:
			if not raw_effect is Dictionary:
				return []
			var type_value = raw_effect.get("type", -1)
			var potency = raw_effect.get("potency", -1)
			var duration = raw_effect.get("duration", -1)
			if not type_value is int or type_value < 0 \
					or type_value > StatusEffect.Type.POISON \
					or not potency is int or potency < 0 \
					or potency > 999 \
					or not duration is int or duration < 1 or duration > 99:
				return []
			var effect := StatusEffect.new()
			effect.type = type_value
			effect.potency = potency
			effect.duration = duration
			member.status_effects.append(effect)
		result.append(member)
	return result

func _parse_checkpoint_inventory(value: Variant) -> InventoryState:
	if not value is Dictionary:
		return null
	var raw_slots = value.get("slots", null)
	var raw_equipment = value.get("equipment", null)
	if not raw_slots is Array or not raw_equipment is Dictionary \
			or raw_equipment.size() != InventoryState.EQUIPMENT_SLOTS.size():
		return null
	var inventory := InventoryState.new()
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	for raw_slot: Variant in raw_slots:
		if not raw_slot is Dictionary:
			return null
		var resource_path = raw_slot.get("resource_path", "")
		var count = raw_slot.get("count", 0)
		if not resource_path is String or not INITIAL_ITEMS.has(resource_path) \
				or seen_paths.has(resource_path) \
				or not count is int or count <= 0:
			return null
		var item := load(resource_path) as ItemData
		if item == null or item.id.is_empty() or seen_ids.has(item.id) \
				or not inventory.add_item(item, count):
			return null
		seen_paths[resource_path] = true
		seen_ids[item.id] = true
	var equipment: Dictionary = raw_equipment
	for slot_name: String in InventoryState.EQUIPMENT_SLOTS:
		if not equipment.has(slot_name):
			return null
		var item_id = equipment.get(slot_name, "")
		if not item_id is String:
			return null
		if item_id.is_empty():
			continue
		var item := inventory.get_item_by_id(item_id)
		if item == null or _equipment_slot_for(item) != slot_name \
				or not inventory.set_equipped_item(slot_name, item_id):
			return null
	return inventory

func _make_checkpoint_dialogic_state(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("current_timeline") \
			or value.get("current_timeline") != null:
		return {}
	var variables = value.get("variables", null)
	if not _is_checkpoint_dialogic_variables(variables):
		return {}
	# 空闲篝火只需叙事变量；重置陈旧文本/立绘，拒绝恢复对话中间态。
	return {
		"manual_advance": {"enabled": true, "temp_disabled": false},
		"variables": variables.duplicate(true),
		"portraits": {},
		"jump_stack": [],
		"text": "",
		"text_reveal_skippable": {"enabled": true, "temp_enabled": true},
		"speaker": "",
		"current_event_idx": -1,
		"current_timeline": null,
	}

func _is_checkpoint_dialogic_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var normalized := _make_checkpoint_dialogic_state(value)
	return not normalized.is_empty() and value == normalized

func _is_checkpoint_dialogic_variables(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 1:
		return false
	var story = value.get("story", null)
	if not story is Dictionary or story.size() != 2:
		return false
	var branches = story.get("branches", null)
	var flags = story.get("flags", null)
	if not branches is Dictionary or branches.size() != 1 \
			or not flags is Dictionary or flags.size() != 1:
		return false
	var wanderer_branch = branches.get("forest_wanderer", null)
	return wanderer_branch is String \
			and wanderer_branch in ["unseen", "greeted"] \
			and flags.get("met_forest_wanderer", null) is bool

func _parse_checkpoint_flags(
		value: Variant, checkpoint_id: StringName) -> Variant:
	if not value is Dictionary:
		return null
	if value.size() > CAMPFIRE_DESTINATIONS.size():
		return null
	var result: Dictionary = {}
	for key: Variant in value:
		if not key is String or value[key] != true \
				or not key.begins_with("campfire_discovered_"):
			return null
		var campfire_id := StringName(key.trim_prefix("campfire_discovered_"))
		if not CAMPFIRE_DESTINATIONS.has(campfire_id):
			return null
		result[key] = value[key]
	if not result.get("campfire_discovered_%s" % checkpoint_id, false):
		return null
	return result

func _parse_defeated_enemies(value: Variant) -> Variant:
	if not value is Dictionary or value.size() > 26:
		return null
	var result: Dictionary = {}
	for key: Variant in value:
		if not key is String or value[key] != true or not _is_known_enemy_key(key):
			return null
		result[key] = true
	return result

func _is_known_enemy_key(enemy_key: String) -> bool:
	if enemy_key == "Enemy1" or enemy_key == "Enemy2":
		return true
	for prefix: String in ["Enemy1_ForestMain_", "Enemy2_ForestMain_"]:
		if enemy_key.begins_with(prefix):
			var suffix := enemy_key.trim_prefix(prefix)
			return suffix.length() == 2 and suffix.is_valid_int() \
					and int(suffix) >= 1 and int(suffix) <= 12
	return false

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
