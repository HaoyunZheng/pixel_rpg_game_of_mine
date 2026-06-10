class_name EnemyStats
extends Resource
## 敌人属性资源

enum AIType { HUNTER, BURNER, MUTANT }

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 80
@export var atk: int = 12
@export var def: int = 4
@export var spd: int = 8
@export var ai_type: AIType = AIType.MUTANT
@export var skills: Array = []
