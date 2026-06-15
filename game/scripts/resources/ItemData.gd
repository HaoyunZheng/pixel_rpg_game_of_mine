class_name ItemData
extends Resource
## 物品定义资源（通用文档 §6.2 / §B.3）

enum ItemType { CONSUMABLE, BATTLE_ITEM, PALLIATIVE }
enum EffectType { HEAL_HP, HEAL_MP, DAMAGE, REDUCE_CURSE }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var effect_type: EffectType = EffectType.HEAL_HP
@export var effect_value: int = 0

enum ItemCategory { WEAPON, ARMOR, ACCESSORY, CONSUMABLE, KEY_ITEM }

@export var category: ItemCategory = ItemCategory.CONSUMABLE
@export var icon: Texture2D
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var usable: bool = true
@export var discardable: bool = true
