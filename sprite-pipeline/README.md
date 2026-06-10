# 像素 Sprite 自动化流水线（Mac / Apple Silicon 版）

把「AI 出图 → 规整成真像素 → 拼精灵表 → 生成 Godot 动画资源」这条重复劳动链路打通，
创意判断留给你自己。生成层**可插拔**，下游三段对任何后端通用。

```
①生成  →  ②后处理  →  ③打包  →  ④Godot 导入
manual/         内置          拼 sheet.png   godot --headless
drawthings/   proper-pixel    + frames.json  → SpriteFrames .tres
comfyui/      -art lite
pixellab
```

---

## 0. 你的机器（M 系列 16GB）该走哪条路线

| 路线 | 工具 | 成本 | 适合 |
|---|---|---|---|
| **本地免费（首选）** | **Draw Things** + SDXL + pixel-art-xl + lcm-lora-sdxl | 免费 | Mac 原生、比 ComfyUI 快约 20%，16GB 跑 SDXL 流畅 |
| 本地免费（进阶） | ComfyUI + 同款 LoRA（可加 MLX 加速节点） | 免费 | 想要节点式精细控制 / 批量脚本化 |
| 买断高质 | Retro Diffusion（Aseprite 扩展，约 $65 一次性） | 一次性 | 出图几乎不用后处理，授权素材训练 |
| 订阅 + 自动化 | PixelLab（MCP） | 订阅 | 边写代码边出素材（见下方 vibe coding） |

> 16GB 统一内存：SDXL（512px 出图再降采样）很稳；**别上 Flux/Z-Image**，那些更适合 24GB+。

---

## 1. 新 Mac 起步清单

1. **装 Godot 4.x** — 从 godotengine.org 下载，拖进 `/Applications`。
   二进制路径：`/Applications/Godot.app/Contents/MacOS/Godot`（已写进 `config.toml`）。
2. **装 Draw Things** — Mac App Store 搜「Draw Things」，免费。
   导入 SDXL 模型 + 两个 LoRA（来源见下）。
3. **装 Python 依赖**：
   ```bash
   pip3 install pillow numpy
   # 若你的 Python < 3.11,再装: pip3 install tomli
   ```
4. **（可选）后处理增强**：`proper-pixel-art`（网格对齐做得更准）
   ```bash
   git clone https://github.com/KennethJAllen/proper-pixel-art
   ```
   本流水线已内置一份轻量后处理（最近邻降采样 + 量化 + 抠背景），可先不用外部仓库。
5. **（可选）打包/编辑器**：Pixelorama（开源、Godot 引擎做的、有 CLI 批量导出）。

### 三个模型文件（放进 Draw Things / ComfyUI）
| 文件 | 来源（Hugging Face） | 作用 |
|---|---|---|
| `sd_xl_base_1.0.safetensors` | `stabilityai/stable-diffusion-xl-base-1.0` | 底座 |
| `pixel-art-xl.safetensors` | `nerijs/pixel-art-xl` | 像素画风（强度 1.2） |
| `pytorch_lora_weights` → 重命名 `lcm-lora-sdxl` | `latent-consistency/lcm-lora-sdxl` | 8 步加速（强度 1.0） |

出图参数：**steps 8 / cfg 1.5 / sampler LCM / 512×512**；
正向以 `pixel` 开头（LoRA 触发词），负向 `3d render, realistic`。

---

## 2. 运行流水线

```bash
cd sprite-pipeline

python3 pipeline.py                 # 跑全部四段
python3 pipeline.py process pack    # 只跑后处理 + 打包
python3 pipeline.py import          # 只把 packed/ 导入 Godot
```

**目录约定**（脚本自动创建）：
```
raw/<角色>/<动作>/frame_000.png   ← 生成层产出 / 你手动丢图
processed/<角色>/<动作>/...        ← 规整后的真像素帧
packed/<角色>/sheet.png            ← 精灵表
packed/<角色>/frames.json          ← 切片+动画元数据
<Godot项目>/assets/sprites/<角色>/ ← 复制进去 + 生成 .tres
```

### 推荐起步方式：manual 模式
先不接生成器，用 Draw Things 网页/App 随手出几张图丢进 `raw/knight/idle/` 等目录，
跑 `python3 pipeline.py process pack import`，把「后处理→打包→进 Godot」整条跑通看效果，
确认顺了再接生成层（把 `config.toml` 的 `backend` 改成 `drawthings`）。

---

## 3. Godot 端必做配置（否则像素图会被糊）

把项目设置里的默认纹理过滤改成最近邻：

- 编辑器：Project → Project Settings → Rendering → Textures →
  **Default Texture Filter = Nearest**
- 或写进 `project.godot`：
  ```ini
  [rendering]
  textures/canvas_textures/default_texture_filter=0
  ```
  （`0` = Nearest）

导入脚本已对每帧 AtlasTexture 设 `filter_clip = true`，避免边缘溢出。

### 生成的资源怎么用
第④段会在 `assets/sprites/<角色>/<角色>_frames.tres` 生成一个 `SpriteFrames`。
拖给一个 `AnimatedSprite2D` 节点的 `Sprite Frames` 属性即可，代码里：
```gdscript
$AnimatedSprite2D.play("walk")
```
（`attack` 默认设为不循环，其余循环；可在 `import_sprites.gd` 里改规则。）

---

## 4. 进阶：vibe coding（PixelLab MCP + Godot MCP）

若你想让 AI 助手**边写 GDScript 边直接生成素材**，给编辑器挂两个 MCP server：

- **PixelLab MCP** — `github.com/pixellab-code/pixellab-mcp`：
  `create_character`（4/8 方向）、`animate_character`（走/跑/待机）、`create_tileset`（Wang 瓦片）。
- **Godot MCP** — 如 `Coding-Solo/godot-mcp`（最流行）或 `tugcantopaloglu/godot-mcp`（149 工具、支持 headless）。

这条路线 PixelLab 是订阅制；本流水线是零成本替代，两者可共存。

---

## 5. 现成社区项目（可直接借鉴/接入）

- 后处理：`KennethJAllen/proper-pixel-art`、`theamusing/perfectPixel`、
  `GENKAIx/PixelArt-Processing-Nodes-for-ComfyUI`
- 精灵表生成：`0x0funky/agent-sprite-forge`（直接产出 Godot 场景+TileMap+碰撞体）、
  `blendi-remade/sprite-sheet-creator`、`lovisdotio/falsprite`、`marcelontime/spriteforge`
- 编辑/打包：Pixelorama（Orama Interactive，开源、CLI 导出）

---

## 文件清单

| 文件 | 作用 |
|---|---|
| `pipeline.py` | 编排器；生成层适配器模式，内置后处理+打包+调 Godot |
| `tools/import_sprites.gd` | Godot 4.x headless 导入器，sheet → SpriteFrames .tres |
| `config.toml` | 所有参数集中处（最易踩坑：`godot_project_path` 与 Nearest 过滤） |
| `README.md` | 本文件 |

> 现实预期：AI 这块可靠产出是「打底稿 + 批量变体」，角色一致性和动画连贯性
> 目前仍需人工或半自动修整。本流水线打通的是重复劳动，不是替你做美术决策。
