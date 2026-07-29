class_name InventoryState
extends RefCounted
## 背包与装备的运行时状态；ItemData 资源只读共享。

class Slot:
	extends RefCounted

	var item: ItemData
	var count: int

	func _init(slot_item: ItemData, slot_count: int) -> void:
		item = slot_item
		count = slot_count

	func copy() -> Slot:
		return Slot.new(item, count)

const EQUIPMENT_SLOTS: PackedStringArray = ["weapon", "armor", "accessory"]

var _slots: Array[Slot] = []
var _equipment: Dictionary = {"weapon": "", "armor": "", "accessory": ""}

func copy() -> InventoryState:
	var state := InventoryState.new()
	for slot: Slot in _slots:
		state._slots.append(slot.copy())
	state._equipment = _equipment.duplicate()
	return state

func get_slots() -> Array[Slot]:
	var result: Array[Slot] = []
	for slot: Slot in _slots:
		result.append(slot.copy())
	return result

func add_item(item: ItemData, count: int = 1) -> bool:
	if item == null or count <= 0:
		return false
	var slot := _find_slot(item.id)
	if slot != null:
		slot.count += count
	else:
		_slots.append(Slot.new(item, count))
	return true

func remove_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var slot := _find_slot(item_id)
	if slot == null or slot.count < count:
		return false
	slot.count -= count
	if slot.count == 0:
		_slots.erase(slot)
	return true

func get_item_count(item_id: String) -> int:
	var slot := _find_slot(item_id)
	return slot.count if slot != null else 0

func get_item_by_id(item_id: String) -> ItemData:
	var slot := _find_slot(item_id)
	return slot.item if slot != null else null

func get_equipped_item_id(slot: String) -> String:
	return _equipment.get(slot, "")

func set_equipped_item(slot: String, item_id: String) -> bool:
	if not _equipment.has(slot):
		return false
	_equipment[slot] = item_id
	return true

func find_equipped_slot(item_id: String) -> String:
	for slot: String in EQUIPMENT_SLOTS:
		if _equipment[slot] == item_id:
			return slot
	return ""

func _find_slot(item_id: String) -> Slot:
	for slot: Slot in _slots:
		if slot.item.id == item_id:
			return slot
	return null
