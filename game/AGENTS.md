# 项目协作规则（给 Codex 读）

这是一个 **Godot 4.x 像素 RPG** 工程。你（AI agent）通过 **godot-mcp** 与引擎交互，
和我（开发者）按下面的**稳健模式**协作。本文件是你的行为边界，优先级高于临时指令。
当你开始着手工作时，必须阅读docs文件夹中的文档以了解详细信息。
---

## 0. 工作模式：稳健（分支 + 逐步审阅）

- **永远在 feature 分支上工作**，绝不直接提交到 `main`。开工先：
  `git switch -c feat/<简短描述>`
- **小步提交**：每完成一个可独立验证的逻辑单元就 `git commit`，提交信息用中文一句话说清「做了什么 / 为什么」。
- **每个逻辑步骤结束后停下来**，告诉我你改了什么、为什么、怎么验证的，**等我看完 diff 再继续**。不要一口气连做多步。
- 卡住、报错、或不确定设计意图时：**停下来问我**，不要反复瞎试。

## 1. 红线（未经我明确同意，绝对不做）

- 不修改 / 删除 `assets/` 下的任何文件 —— 那是**资产层**的地盘，由 `../sprite-pipeline` 流水线产出和管理。
- 不重构工程目录结构、不重命名既有场景/脚本。
- 不引入新的第三方插件 / addon / npm 依赖。
- 不运行破坏性命令：`git reset --hard`、`git push --force`、`rm -rf`、删除 `.git`。
- 不改 `project.godot` 的渲染/物理等全局设置（尤其 `default_texture_filter=0` 必须保持 Nearest）。

## 2. 你能做、且应该做的

- 写 / 改 GDScript（`scripts/`）、搭场景（`scenes/`）、连信号、写玩法逻辑。
- 用 godot-mcp **跑工程、读控制台报错，据此自我纠错**（这是你最大的价值）。
- 把资产流水线产出的角色接进场景（见 §4）。
- 优先把改动落在**文本文件**（`.gd` / `.tscn` / `.tres`）上，保证 `git diff` 可读可审。

## 3. 目录约定

```
game/
  project.godot          全局设置（Nearest 过滤,勿动）
  scenes/                场景 .tscn（你负责）
  scripts/               GDScript（你负责）
  assets/sprites/        角色素材 + *_frames.tres（资产层,勿动）
  tools/import_sprites.gd 资产导入器（由流水线调用）
  AGENTS.md / .mcp.json / .gitignore
```

## 4. 资产怎么来、怎么用

角色素材**不由你手搓**，而是上游 `../sprite-pipeline`（`pipeline.py`）生成：
`生成 → 后处理 → 打包 → Godot 导入`，产物是 `assets/sprites/<角色>/<角色>_frames.tres`（一个 `SpriteFrames`）。

你要用某个角色时：
```gdscript
var anim := AnimatedSprite2D.new()
anim.sprite_frames = load("res://assets/sprites/knight/knight_frames.tres")
add_child(anim)
anim.play("walk")   # 动画名 = idle / walk / attack ...
```

## 5. godot-mcp 常用能力（你手上的工具）

启动编辑器、debug 模式跑工程、抓控制台输出、列工程/取版本、工程结构分析、
建场景 / 加节点 / `load_sprite` 把贴图塞进 Sprite2D / 存场景、（4.4+）UID 管理。

**典型自检循环**：改脚本 → `run_project` → `get_debug_output` 读报错 → 修 → 再跑，直到干净，再交给我审。

## 6. 验收习惯

每次交付前自问:改动是否最小、是否只动了该动的文件、工程能否无错启动（控制台出现
`[Main] 游戏启动成功`）、`git diff` 是否清晰。满足了再 ping 我。
