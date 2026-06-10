# godot-mcp 接入指南（这台 Mac · Claude Code 驱动）

目标工作流：**导入资产 → vibe coding → 游戏设计与开发**，全程稳健可审。

```
你 ──→ Claude Code（AI 在这）──→ godot-mcp（npx 桥）──→ Godot 4.x（跑工程/建场景/读报错）
        cd game && claude            @coding-solo/godot-mcp     /Applications/Godot.app
```

已确认前提：Apple Silicon M 系列 / 16GB / **已装 Godot，缺 Node**。
我已把工程骨架、`.mcp.json`、`CLAUDE.md`、`.gitignore` 都放好，你只需跑下面几步。

---

## 一、一键就位（推荐）

在 Finder 里**双击** `setup-godot-mcp.command`（或终端 `bash setup-godot-mcp.command`）。
它会：① 确认/安装 Node ② 自动把真实 Godot 路径写进 `game/.mcp.json` ③ 给 `game/` 初始化 git 并首个提交。

> 若双击报「无法打开，因为来自身份不明的开发者」：右键 → 打开 → 仍要打开；或终端跑 `bash setup-godot-mcp.command`。

跑完后直接看 **三、启动**。如果想手动来，看下面 **二**。

---

## 二、手动分步（脚本失败时的兜底）

### 1. 装 Node.js（≥18，godot-mcp 用 npx 拉起）
```bash
# 有 Homebrew:
brew install node
# 没有 Homebrew:就去 https://nodejs.org/zh-cn/download 下 LTS 安装包
node -v   # 看到 v18 以上即可
```

### 2. 确认 Godot 路径
默认是 `/Applications/Godot.app/Contents/MacOS/Godot`。若你的 app 名字不同：
```bash
ls -d /Applications/Godot*.app
```
把真实路径填进 `game/.mcp.json` 里的 `GODOT_PATH`。

### 3. 给工程建 git（稳健模式地基）
```bash
cd "/Users/patricksapple/Documents/Claude/Projects/游戏开发/game"
git init && git add -A && git commit -m "chore: 初始化 Godot 工程 + godot-mcp 配置"
```

---

## 三、启动 Claude Code 并接上 godot-mcp

### 1. 确认装了 Claude Code
```bash
claude --version
# 没装: npm install -g @anthropic-ai/claude-code
```

### 2. 在工程目录里启动
```bash
cd "/Users/patricksapple/Documents/Claude/Projects/游戏开发/game"
claude
```
因为 `game/.mcp.json` 在这里，Claude Code 会**自动发现** godot 这个 MCP。
首次会问你是否信任该项目的 MCP 服务器，选**信任/是**。

### 3. 验证
在 Claude Code 里输入：
```
/mcp
```
应看到 `godot` 且状态 connected。看不到就 §五 排错。

---

## 四、冒烟测试（确认整条链路通了）

在 Claude Code 里依次试这三句（中文直接说即可）：

1. 「用 godot 工具，列出 Godot 版本，并分析当前工程结构。」
   → 能返回版本号 + 看到 scenes/scripts/assets 结构 = 桥通了。
2. 「跑一下当前工程，把控制台输出贴给我。」
   → 控制台出现 `[Main] 游戏启动成功 ✅` = 引擎能被驱动、能回读输出。
3. 「在 main 之外开个分支，给 Main 场景加一个居中的 Label 显示 'Hello'，跑一遍确认无报错，然后停下来让我看 diff。」
   → 这一步同时验证：建/改场景、自检循环、**稳健模式的"停下等审阅"**。

跑通这三步，你的「导入资产 → vibe coding」工作流就正式可用了。

---

## 五、常见问题

- **/mcp 里没有 godot / 显示 failed**：多半是 `npx` 找不到。确认 `node -v` 正常；
  在 `game/` 目录里启动的 `claude`；改完 `.mcp.json` 要**重启 Claude Code**。
- **Godot Not Found**：`game/.mcp.json` 的 `GODOT_PATH` 路径不对，按 §二.2 校正。
- **工程打不开 / 提示版本转换**：你的 Godot 版本与 `project.godot` 的 `config/features` 不同，
  接受 Godot 的「转换工程」提示即可。
- **像素图发糊**：确认 `project.godot` 里 `default_texture_filter=0`（Nearest）没被改。

---

## 六、和资产流水线怎么衔接

资产由 `../sprite-pipeline` 产出，已把它的 `godot_project_path` 指向本工程。
出完素材后在 sprite-pipeline 目录跑：
```bash
python3 pipeline.py import
```
素材会落到 `game/assets/sprites/<角色>/`，生成 `<角色>_frames.tres`。
然后让 Claude Code：「把 knight 的 SpriteFrames 接到一个 AnimatedSprite2D 放进主场景，播放 walk。」

> 边界提醒：`assets/` 是资产层地盘，已在 `CLAUDE.md` 里写明 agent 不得擅自改删 —— 保证职责清晰、可管理。
