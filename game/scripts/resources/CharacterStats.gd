class_name CharacterStats
extends Resource
## 我方角色基础属性资源

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 100
@export var max_mp: int = 50
@export var atk: int = 15
@export var def: int = 5
@export var spd: int = 10
@export var skills: Array = []
## 可选战斗外观；为空时 HUD 使用阵营色占位。
@export var sprite_frames: SpriteFrames = null
