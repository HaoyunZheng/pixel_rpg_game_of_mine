# 项目阶段分析报告

**日期**:2026-06-10
**项目**:《星辰之烬纪元》— Godot 4.x 俯视角像素回合制 RPG(monorepo:game + sprite-pipeline)
**检测阶段**:**Production(生产阶段)— Demo 里程碑 P3 进行中**
**置信度**:PASS — 信号清晰,无歧义

---

## 对照通用文档 §8.1 里程碑的进度

| 阶段 | 目标 | 状态 | 证据 |
|---|---|---|---|
| **P0** | 场景切换骨架 | ✅ 完成 | `SceneManager` autoload + Main/Wilderness/ForestClearing/Battle 场景互切 |
| **P1** | 野外探索 + 明雷敌人 | ✅ 完成 | `PlayerController`、`EnemyPatrol`(8 向 sprite 按移动方向切换朝向)、触碰进战斗 |
| **P2** | 回合制战斗最简版 | ✅ 完成(超额) | `BattleStateMachine`/`TurnStateMachine`/`DamageCalculator`/`EnemyAI`/`AttackPowerWheel`/敌方立绘头像 |
| **P3** | 队友 + 技能 + 物品 | 🟡 进行中 | 队友已入队参战(`char_companion.tres`)、技能命令已实现;「物品」命令在 `BattleUI.gd` 中占位置灰,逻辑未实现 |
| **P4** | 安全区 + 羁绊/诅咒系统 | ⬜ 未开始 | `GameData` 已预留 `curse_values`/`bond_values` 字段与读写接口;NPC 对话、篝火恢复、营火对话、诅咒战斗效果、缓解物均无代码 |
| **P5** | 痕迹叙事 + polish | ⬜ 未开始 | — |

## 完整度概览

- **设计文档 ~90%**:通用/战斗/对话三份 spec(v2.0 拆分版)+ 工程代码规范 + 3 份执行计划(战斗 UI Brief、攻击转盘 Spec、8 向敌人)。缺口:剧情大纲 v3 未入库(spec 中标注"当前仓库未收录")。
- **代码 ~50%(对 Demo 范围)**:22 个 GDScript;战斗拆分为独立子系统,符合 §9 风险缓解策略。
- **资产**:hooded_player / hunter / mutant 三角色 sprite,战斗 UI 切片(`assets/ui/battle/`),sprite-pipeline 运转正常。
- **测试**:`test/capture.gd` 等视觉验证脚本(双门:文本门 + 像素门);无逻辑层自动化测试。
- **生产管理**:无 sprint 计划文件;以 feature 分支 + session log 推进,符合 `game/CLAUDE.md` 稳健模式。

## 发现的缺口

1. **P3 收尾**:战斗内「物品」命令未实现。`GameData.inventory` 结构已存在,`assets/data/` 下有 characters/enemies/skills 但无 items 数据。
2. **P4 前置依赖**:营火对话与 NPC 对话共同依赖对话系统(《对话系统文档》已写好、零实现),P4 工期需包含"先搭对话框架"。
3. **分支状态**:`feat/battle-enemy-avatar` 已提交、工作区干净,尚未合回 `main`(待开发者审阅)。

## 建议的下一步(优先级排序)

1. 合并 `feat/battle-enemy-avatar` → `main`(开发者审完 diff 后)。
2. **完成 P3:战斗内物品系统**(本次会话启动)— ItemData 数据 → 背包接入 → BattleUI「物品」命令解灰(选物品→选目标)→ 胜利掉落。
3. P4 第一步:对话系统最小实现(逐字显示 + 翻页,Z/X 键盘闭环)。
4. P4 第二步:安全区场景(篝火恢复 + NPC + 营火对话推进羁绊)+ 诅咒值战斗效果(§4.3)。
