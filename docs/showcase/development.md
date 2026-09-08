# 星辰之烬纪元开发笔记

更新于 2026-09-07。本文记录当前制作重点与阅读路径，配合[项目首页](../../README.md)查看。

## 先验证一段体验

最初的设计同时容纳探索、战斗、成长、羁绊和诅咒。系统之间依赖越多，越难判断一处体验问题来自哪里。2026-07-30 的[范围决定](../../game/docs/superpowers/specs/星辰之烬纪元_通用文档.md)将羁绊—诅咒双表系统后置，让当前工作集中于探索、遇敌、战斗、回火整备的基础循环。

这个阶段需要回答具体问题：玩家是否知道去哪里、为什么进入战斗、一次输入何时生效，以及战斗结束后能否回到可理解的探索状态。已有系统仍在衔接，完整可玩版本尚在制作。

## 战斗中需要读懂什么

回合制负责行动选择，时机交互负责行动执行。攻击转盘与防御/闪避姿态带来直接操作，也增加了学习负担。因此，目标提示、攻击预警、有效输入窗口、命中/失败反馈需要分开检查。

[战斗捕获脚本](../../game/test/capture_battle.gd)可以构造攻击转盘、目标锁定、弹幕与受击等状态，检查界面在不同分辨率下的表现。它是专项视觉检查工具，不替代从探索开始的整段游玩测试。

## 世界观从因果关系开始

世界设定按资源与生态、生产与贸易、机构和制度、人物可观察的后果逐层推演。档案用 Established、Proposed 等状态区分确认程度，防止一个尚未确定的提案被后续内容当成既定事实。

可以从[世界规则](../../game/world-bible/rules/_index.md)和[正典状态表](../../game/world-bible/canon-status.md)开始，再进入具体地区。现有森林是系统开发场景；世界档案中的地区和制度并不代表已经加入游戏。

## 我与 AI 工具如何分工

我负责方向、规格、优先级和验收判断，并深入阅读与修改脚本、配置，处理实现与设计之间的偏差。设计讨论使用 Sol 等模型，图像生成使用 ImageGen，像素和地图素材使用 Meowa，编码使用 Opus/Fable 等模型，音乐使用 Suno；工具会随任务和阶段变化。

图像需要经过裁切、像素尺寸与色彩处理、帧打包，再导入 Godot。[素材管线](../../sprite-pipeline/README.md)把这些阶段分开，使画面问题能沿输入、处理、打包、导入定位。需求、代码和运行截图共同构成审阅依据。

## 本次展示素材

下列图片直接复制自本地开发记录，未作画面美化或重新生成。它们展示不同时间的单系统状态，没有绑定到同一个可发行版本。

| 展示文件 | 原开发记录相对路径 | 说明 |
|---|---|---|
| [forest.png](assets/forest.png) | `game/screenshots/fix-forest-main/frame_000.png` | 森林场景运行截图 |
| [attack-wheel.png](assets/attack-wheel.png) | `game/screenshots/battle-regression/attack_wheel_1920x1080.png` | 捕获脚本构造的攻击转盘测试状态；实际尺寸为 2940×1846 |
| [signpost.png](assets/signpost.png) | `game/screenshots/forest-main-signpost/stone_dialogue.png` | 路牌调查交互截图 |

## 后续验证顺序

1. 打通并复测探索—战斗—篝火短流程，处理阻断体验的问题。
2. 检查不同分辨率、键盘路径、存档/读取与失败返回。
3. 再增加角色、任务和场景内容，逐步替换占位资源。
4. 在基础体验稳定后，单独验证更复杂的成长与关系机制。

## 文档参考

本次项目介绍的结构参考 [GDQuest Open RPG](https://github.com/gdquest-demos/godot-open-rpg)、[itch.io 页面设计文档](https://itch.io/docs/creators/design)、[Carter Baker 的 RPG Prototype](https://carterbaker96.itch.io/rpg-prototype) 与 [Brett Chalupa 的原型开发日志](https://brettchalupa.itch.io/godotypes/devlog/501489/a-week-of-prototyping-to-learn-godot)：让读者先理解作品和阶段，再进入截图、源码与开发决策。项目画面均来自本仓库的本地开发记录。
