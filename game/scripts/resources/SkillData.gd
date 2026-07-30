class_name SkillData
extends Resource
## 技能定义资源

enum SkillType { ATTACK, HEAL }
enum DamageType { PHYSICAL, MAGIC }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var skill_type: SkillType = SkillType.ATTACK
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var power: int = 10
@export var mp_cost: int = 8
@export var target_type: String = "single_enemy"
@export_range(1, 5) var max_rank: int = 5
@export_range(0, 20) var power_per_rank: int = 5
