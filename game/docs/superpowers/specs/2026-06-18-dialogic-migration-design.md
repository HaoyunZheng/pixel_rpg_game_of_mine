# 对话/剧情分支系统迁移到 Dialogic — 设计与决策记录

> 文档版本：v1.0 · 2026-06-18
> **决策更新（2026-07-17）**：D1 的“Dialogic 接管 flags/curse/bond/cycle”已被混合权威方案取代。本文保留迁移背景；状态边界以 §2 D1 和 `2026-07-17-three-systems-baseline.md` 为准。
> 性质：迁移决策记录（ADR 风格）+ 设计方案。落地后，本文的决策会回写进
> 《星辰之烬纪元_对话系统文档》附录 B、`game/CLAUDE.md`、根 `CLAUDE.md`。
> 关联：现有对话系统规范见 `星辰之烬纪元_对话系统文档.md`；全局数据结构见《通用文档》附录 B。

---

## 1. 背景与现状

目标：把游戏后续的**对话与剧情分支系统全面迁移到 Dialogic 2**，并调整代码架构与说明文档使之适配。

开工时盘点到的现状：

- Dialogic 插件已 vendored 并提交（`res://addons/dialogic`，801 文件），`[editor_plugins]` 已启用。
- `project.godot`（未提交改动）**半接线、且有坏引用**：
  - 已加 `Dialogic` 自动加载。
  - 已加 `DialogueManager="*res://scripts/autoload/DialogueManager.gd"`，**但该文件不存在**——运行即报错。
  - Dialogic 的 `dch/dtl` 目录指向 `res://` 根的 `character.dch` / `timeline.dtl`（插件生成的空默认文件，未提交）。
  - 顺带加了 `interact` / `open_inventory` 输入动作。
- **无任何旧对话系统代码**。所谓"分支状态"目前只存在于 `GameData` 的 `flags` / `curse_values` / `bond_values` / `cycle_count`。
- 经全工程检索，`flags`/`curse`/`bond`/`cycle_count` **没有任何 `GameData` 之外的消费者**（绿地）。
- 场景流转走 `SceneManager.change_scene()` + 场景 `on_scene_enter()` 钩子。

因此本次"迁移"的实质是：**把 Dialogic 确立为对话与剧情分支的正式骨架**，补齐集成层、修掉坏引用、规整文件布局，并改写文档——而非从旧系统搬代码。

---

## 2. 关键决策（与既有规范的冲突已对齐）

现有规范《星辰之烬纪元_对话系统文档》附录 B.0/B.4 对两条核心轴有过论证，本次迁移**有意调整其中一条**。已与开发者逐项确认：

### D1. 状态权威：**Dialogic / GameData 混合权威**（2026-07-17 更新）

- **Dialogic**：剧情阶段、分支选择、NPC 叙事关系、任务叙事进度；timeline 可用原生 Condition/Set 事件直接读写。
- **GameData**：背包、装备、队伍、战斗、敌人事实、羁绊、诅咒；timeline 只能调用只读查询，不做变量镜像或结果回流。
- **理由**：剧情作者能在 Dialogic 内直接管理分支，同时避免玩法状态出现两套权威。
- **存档边界**：本轮不落盘，只保证运行期跨场景；未来通过 `Dialogic.get_full_state()` 与 GameData 玩法数据协同保存。

### D2. 包装层：**保留 DialogueManager 薄包装**（沿用旧规范）

- 触发统一收敛到 `DialogueManager.start(dialogue_id, context)`，外部场景只持有 `dialogue_id`，不直接散落调用 Dialogic API。
- 包装层职责收窄为：**注册表 + 播放互斥 + 开始/结束信号 + 恢复控制**；不承担剧情或玩法结果回流。

### D3. 范围：架构 + 文档 + 可运行样例

- 交付集成层、文件布局规整、修坏引用、文档改写，外加一个最小样例跑通"触发→分支→写 flag→结束回场景→状态持久"闭环。

---

## 3. 方案设计

### 3.1 状态层

Dialogic 只声明当前样例使用的变量：

```
story.flags.met_forest_wanderer = false
story.branches.forest_wanderer = "unseen"
```

- timeline 用 Dialogic Set 事件推进这两个叙事字段。
- `GameData` 不改为 Dialogic 代理；timeline 可直接调用其现有只读方法获取世界事实。
- 自动加载顺序不再承担状态代理前置条件。

### 3.2 包装层 `res://scripts/autoload/DialogueManager.gd`

```
start(dialogue_id: String, context := {}) -> void
  - dialogue_id → timeline：约定 res://dialogue/timelines/<id>.dtl
  - 拒绝未知 id 或并发重复播放
  - 连接 Dialogic.timeline_ended → _on_ended()
  - Dialogic.start(timeline)
_on_ended(context):
  - emit dialogue_finished(dialogue_id)
signal dialogue_finished(dialogue_id: String)
```

### 3.3 文件布局

```
res://dialogue/
  timelines/   *.dtl   （手写剧情，文本事件只写本地化 key）
  characters/  *.dch
```

- 更新 `directories/dtl_directory`、`dch_directory` 指向新目录。
- 根目录散落的 `character.dch`/`timeline.dtl`（+`.uid`）迁入新布局并替换为样例。
- **对话资产不进 `assets/`**（与 sprite-pipeline 地盘隔离）。

### 3.4 可运行样例

- 流浪者 Character + 单一 timeline：首次两个选择写 Dialogic 变量，再次交谈按 branch 变化。
- `Enemy1` 已击败时用 `GameData.is_enemy_defeated("Enemy1")` 只读条件显示额外台词。
- 文本门（`run_project` + 读控制台无错）+ 像素门（capture 截图比对）双验证。

### 3.5 文档改写

- 《星辰之烬纪元_对话系统文档》附录 B.0/B.4：改为混合权威、保留薄包装、落定 `res://dialogue/` 布局，新增运行期状态边界一节。
- `game/CLAUDE.md`：红线"不引入新插件"加 Dialogic 例外；声明 `res://dialogue/` 为手写对话资产区；明确 `project.godot` 仅可改 dialogic/autoload/input（`default_texture_filter=0` 不动）。
- 根 `CLAUDE.md`：项目结构补 Dialogic 与对话目录。

---

## 4. 范围红线（YAGNI）

- **不**建存档系统（现仓库无任何存档代码）。
- **不**建 CutsceneDirector，也不预留未使用的演出框架或信号 stub。
- 不重构既有场景/脚本结构，不改渲染/物理全局设置。

---

## 5. 待实施时核实的技术点

样例只使用预声明叶子变量，不依赖动态创建嵌套字典；实现时验证 Timeline 对 `GameData` 只读方法调用与运行期跨场景状态即可。
