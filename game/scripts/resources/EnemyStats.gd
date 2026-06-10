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
## 外观：8 向 idle 的 SpriteFrames（战斗头像取 idle_down 首帧；为空则用占位色块）
@export var sprite_frames: SpriteFrames = null
