---
name: visual-loop
description: 视觉自愈循环 —— 跑工程、截图、把画面与文字描述比对、修改，循环到对齐。当用户要你「让画面长成某个样子」「按这个描述把场景做出来/调对」「截个图看看对不对」「视觉验收」时使用。godogen「截图自我修复」在 godot-mcp 工作流上的移植。
---

# 视觉自愈循环（Visual Self-Heal Loop）

把 godogen 的「frame-grounded self-repair」搬到本工程的 godot-mcp 工作流上：
**不靠代码自我感觉良好，靠看截图判断画面是否与文字描述对齐，再改。**

核心铁律（来自 godogen，必须遵守）：
- **代码和画面打架时，信画面。** `get_debug_output` 干净 ≠ 画面对。
- **向失败倾斜。** 描述里要的东西在截图里没【清楚】看到，就当没做完，继续修。别脑补、别替它解释。
- **读日志，别只看退出码。** 缺资源、导入失败、相机/节点缺失都是真失败。

## 为什么不是「run_project 直接截图」

本工程的 MCP（`@coding-solo/godot-mcp`）**没有截图工具**：`run_project` / `get_debug_output` 只给你
*控制台文字*，给不了像素。所以像素得由 Godot 侧的捕获脚本写成 PNG 落盘，再由你（Read 工具能看图）读回来评估。
于是这条循环是**两道闸**：MCP 那道管「能不能跑、有没有报错」，截图那道管「画面对不对」。

## 输入（开始前先和用户确认齐这三样）

- **目标场景**：`res://scenes/<X>.tscn`（默认 `res://scenes/Main.tscn`）
- **文字描述**：这次要画面长成什么样——枚举该出现的对象、位置、相对大小、颜色/风格、HUD。
  （写得越像「一张游戏截图的说明」越好；含糊的描述无法做视觉验收。）
- **task slug**：本轮的短名，决定截图目录 `screenshots/<slug>/`

## 前置

- 在 feature 分支上工作（`git switch -c feat/<描述>`），遵守 `AGENTS.md` 稳健模式：每个逻辑步停下等审。
- 截图脚本是 `res://test/capture.gd`（已就位）。它只活在 `test/`，不碰 `scenes/`/`scripts/` 的游戏逻辑。
- 红线不变：不动 `assets/`、不改 `project.godot` 全局设置、不加插件/依赖。

## 循环（每一轮）

### ① 文字闸 —— 先确保能跑、无脚本错（MCP）

用 godot-mcp：
1. `run_project`（debug 模式跑工程）
2. `get_debug_output` 读控制台。应看到 `[Main] 游戏启动成功 ✅`；有 parse/脚本/资源报错先修到干净。
3. `stop_project` 收尾。

> 注意 `run_project` 跑的是 `project.godot` 里的 `run/main_scene`。要验的若不是主场景，这一步只当「语法/资源体检」，画面以 ② 为准。

### ② 截图（直接调 Godot 二进制，**不经 MCP、不要 --headless**）

MCP 的 `run_project` 不能传 `--script`，所以截图走已放行的 Godot 二进制。
**务必不加 `--headless`**——headless 用哑渲染器，回读 viewport 会是空白帧。

```bash
cd "/Users/patricksapple/Documents/Codex/Projects/游戏开发/game"
/Applications/Godot.app/Contents/MacOS/Godot --path . \
    --script res://test/capture.gd -- \
    --scene res://scenes/Main.tscn --task <slug> --frames 8 --shots 1
```

- 静态场景（布局/装饰/UI）：`--shots 1`。
- 动态场景（移动/动画/物理）：`--shots 3 --interval 8`，看变化是否真的在动，而不是卡住。
- 输出：`screenshots/<slug>/frame_000.png ...`，控制台会打印每张的绝对路径和分辨率。

### ③ 读图评估

用 **Read 工具**打开 `screenshots/<slug>/frame_00*.png`，逐条对照「文字描述」核：
- 该出现的对象是否都在？位置/相对大小对不对？
- 像素是否清晰（没被抗锯齿糊——`default_texture_filter=0` 已设为 Nearest）？
- 颜色/风格符合描述？HUD 元素到位？
- 多张之间该动的有没有动（动态场景）？

判定时**向失败倾斜**：只要描述里的要素没清楚看到，就算这轮没过。

### ④ 修 → 回到 ①

按差异改 `scenes/`/`scripts/`（信画面，不信「代码看起来没错」）。改完重跑①②③。

## 停止条件

- 截图里**清楚**呈现了文字描述的全部关键要素；
- `get_debug_output` 无 actionable 报错；
- 把对齐的那张 `frame_000.png` 连同「逐条核对结论」交给用户，停下等审（稳健模式）。
- 若连续若干轮卡在同一处对不齐、或不确定设计意图：**停下来问用户**，别反复瞎试。

## 自驱动（可选）

可以用 `/loop`（不带间隔，自定步）把「①→②→③→④」自动迭代到对齐或到设定的最大轮数；
每轮结束按稳健模式向用户汇报这一轮改了什么、截图对齐到什么程度。

## 与资产流水线的边界

画面里的角色素材来自上游 `../sprite-pipeline`（见 `AGENTS.md` §4），本循环只调度「接入 + 摆放 + 视觉验收」，
不在循环里手搓/改 `assets/`。素材本身不对，是流水线的事，不是这条循环的事。
