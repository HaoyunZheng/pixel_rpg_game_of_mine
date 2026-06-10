class_name StatusEffect
extends Resource
## 战斗状态效果 — 中毒/眩晕等的统一数据载体（单一数据源）
## 所有「状态类型」判定都引用 StatusEffect.Type，禁止再散落裸 int。

# 枚举顺序与旧裸 int 对齐（STUN=0, POISON=1），勿改既有项顺序，仅向后追加。
enum Type { STUN, POISON }

const DISPLAY_NAMES: Dictionary = {
	Type.STUN: "眩晕",
	Type.POISON: "中毒",
}

@export var type: Type = Type.STUN
@export var potency: int = 0   # 强度（如中毒每回合伤害）
@export var duration: int = 1  # 剩余回合数

func get_display_name() -> String:
	return DISPLAY_NAMES.get(type, "未知")
