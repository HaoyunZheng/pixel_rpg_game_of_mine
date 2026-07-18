# assets/ui — 手绘 UI 资产例外区

本目录是 [game/CLAUDE.md](../../CLAUDE.md) §1 红线的**经批准例外**：
`assets/` 下其余目录由 `../sprite-pipeline` 流水线产出、不可手改；
**本目录例外**，承载界面用的 Theme 切片素材，由 UI 工作流（agent4 出图 → agent1 接入）读写。

## 内容约定（首轮：战斗 command_select 静态 HUD）

| 子目录/文件 | 用途 |
|---|---|
| `battle/` | 战斗界面切片素材 |
| `battle/*.png` | 9-patch 面板、命令格底框、左下状态列底板、金/红准星、状态 chip、HP/MP 条；旧行动条 pip 仅保留不再使用 |
| `battle/bg_battle_forest.png` | 战斗背景图（阴郁森林空地，场景里以 50% 不透明度铺最底层） |
| `battle/battle_theme.tres` | 引用上述切片的 `Theme` / `StyleBoxTexture` 资源 |

## 来源与流程

- 出图：agent4 调 Meowa API（`api.meowa.ai`，key 见 `secrets/meowa.cfg`），Meowa 优先、不达标经开发者同意可兜底。
- **2026-06 起**：切片与背景改由 `../../sprite-pipeline/tools/gen_battle_ui_slices.py` / `gen_battle_bg.py` 程序化重绘（按屏幕像素尺寸烘焙方形硬像素边框与平面状态条，修复首轮 Meowa 切片的 NinePatch 细边与裁切问题）；改样式跑脚本再生成即可，不要手改 PNG。
- 顶部行动顺序条按 UX Spec 使用 `TurnArcBar._draw()` 与圆形头像球实时绘制；`pip_turn*.png` 已退役但因资产删除需单独授权而保留。
- 验收：agent3（godot-game-architect）按《战斗系统文档 §B.3》比对配色 / 分层 / 中文标签后交付。
- 接入：agent1（godot-ui-designer）增量改造 `scripts/battle/BattleUI.gd` + `scenes/Battle.tscn`，保留占位回退。
