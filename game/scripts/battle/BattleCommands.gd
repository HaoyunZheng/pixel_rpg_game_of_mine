class_name BattleCommands
extends RefCounted
## 战斗指令字符串单一数据源
## 原先 "attack"/"skill"/"item"/"flee" 散落在 TurnStateMachine / BattleUI / EnemyAI 三处，
## 统一在此声明，避免同义字面量多源漂移。

const ATTACK: String = "attack"
const SKILL: String = "skill"
const ITEM: String = "item"
const FLEE: String = "flee"
