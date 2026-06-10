# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a monorepo for a **Godot 4.x pixel-art RPG** consisting of two sub-projects:

- **`game/`** — The Godot game project (scenes, scripts, assets). This is the primary work area for gameplay development.
- **`sprite-pipeline/`** — A Python pipeline that turns AI-generated (or hand-drawn) images into Godot-ready `SpriteFrames` animation resources.

The two projects are coupled at the asset boundary: the pipeline outputs to `game/assets/sprites/`, and the game consumes `.tres` files produced by the pipeline's stage ④ (Godot import).

There is also a game-specific agent rules file at `game/CLAUDE.md` (written in Chinese) that governs collaboration boundaries for the Godot project — feature branch workflow, red lines (what not to touch), and the visual self-heal loop. **Read it before making any changes to `game/`**.

## Common Commands

### Game (Godot)

All Godot commands assume the working directory is `game/` and Godot is installed at `/Applications/Godot.app/Contents/MacOS/Godot` (configured in `game/.mcp.json`).

```bash
# Run the game (debug mode, used by godot-mcp)
cd game
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Headless sprite import (stage ④ of the pipeline)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://tools/import_sprites.gd

# Screenshot capture for visual verification (DO NOT use --headless)
/Applications/Godot.app/Contents/MacOS/Godot --path . \
    --script res://test/capture.gd -- \
    --scene res://scenes/Main.tscn --task <slug> --frames 8 --shots 1
```

The capture script writes to `game/screenshots/<task>/frame_000.png`. It must **not** run with `--headless` (headless uses a dummy renderer that produces blank frames). For dynamic scenes, use `--shots 3 --interval 8`.

### Sprite Pipeline (Python)

```bash
cd sprite-pipeline

# Run all four stages (generate → process → pack → import)
python3 pipeline.py

# Run only processing + packing (skip generation and Godot import)
python3 pipeline.py process pack

# Run only Godot import (copy packed assets and generate .tres)
python3 pipeline.py import

# Use a custom config file
python3 pipeline.py --config config.toml
```

Dependencies: `pip install pillow numpy` (Python 3.11+ for built-in `tomllib`; older versions also need `pip install tomli`).

### MCP / godot-mcp

This project uses `@coding-solo/godot-mcp` (configured in `game/.mcp.json`). Launch Claude Code from `game/` so the MCP is auto-discovered.

```bash
cd game
claude
```

In Claude Code:
- `/mcp` — Check MCP server status (look for `godot` connected).
- `run_project` / `get_debug_output` / `stop_project` — Run the game and read console output.

The typical self-check loop: modify script → `run_project` → `get_debug_output` → fix errors → repeat until clean.

### Git Workflow

- **Always work on feature branches**, never commit directly to `main`:
  ```bash
  cd game && git switch -c feat/<short-description>
  ```
- Small, atomic commits with Chinese messages describing what and why.
- Stop after each logical step for review before continuing.

## High-Level Architecture

### Asset Pipeline: Four Decoupled Stages

```
① generate   →  ② process   →  ③ pack   →  ④ Godot import
raw/            processed/      packed/     game/assets/sprites/
```

1. **Generate** (`pipeline.py` backend adapter) — Images land in `raw/<character>/<action>/`. The backend is pluggable: `manual` (you drop images), `drawthings`, `comfyui`, or `pixellab`. Currently defaults to `manual`.
2. **Process** — Auto-crop, nearest-neighbor downsample to target pixel size (32×32), color quantize, remove background. Output goes to `processed/`.
3. **Pack** — Stitch each character's action frames into a single `sheet.png` and emit `frames.json` (describes row offsets, frame counts, FPS). Output goes to `packed/`.
4. **Godot Import** — Copy `sheet.png` + `frames.json` into `game/assets/sprites/<character>/`, then run `import_sprites.gd` headless to generate `<character>_frames.tres` (a `SpriteFrames` resource).

The `import_sprites.gd` script uses `AtlasTexture` to window into the sheet — zero extra texture memory overhead. Each animation defaults to looping except `attack`.

### Game Project Structure

```
game/
  project.godot              # Global settings. Critical: default_texture_filter=0 (Nearest)
  scenes/                    # .tscn scenes (agent-owned)
  scripts/                   # .gd scripts (agent-owned)
  assets/sprites/            # Pipeline output: sheet.png, frames.json, *_frames.tres (DO NOT MODIFY)
  tools/import_sprites.gd    # Headless importer (called by pipeline stage ④)
  test/capture.gd            # Screenshot capture for visual verification
```

The main scene is `scenes/Main.tscn` (configured in `project.godot`), running `scripts/Main.gd`.

### Visual Self-Heal Loop

A custom skill is defined at `.claude/skills/visual-loop/SKILL.md`. Since `godot-mcp` does not provide screenshot capture, visual verification is done in two gates:

1. **Text gate** — `run_project` + `get_debug_output` to confirm no script/resource errors.
2. **Pixel gate** — Run `capture.gd` (without `--headless`) to write screenshots, then `Read` the PNGs to compare against a textual description of what the scene should look like.

The loop iterates: run → screenshot → read image → evaluate against description → modify scene/script → repeat until aligned. When code and image disagree, trust the image.

### Asset Boundary Rules

- **`game/assets/` is owned by the pipeline.** Do not create, modify, or delete files under `assets/sprites/`. If sprite assets are wrong, fix the pipeline (`sprite-pipeline/`), not the game.
- The pipeline's `config.toml` points `godot_project_path` at this `game/` directory, so stage ④ knows where to copy assets.
- In game code, load sprite assets like:
  ```gdscript
  var anim := AnimatedSprite2D.new()
  anim.sprite_frames = load("res://assets/sprites/knight/knight_frames.tres")
  anim.play("walk")
  ```

## Key Configuration Files

| File | Purpose |
|---|---|
| `game/.mcp.json` | MCP server config (godot-mcp path, `GODOT_PATH` env var) |
| `game/project.godot` | Godot project settings. `default_texture_filter=0` (Nearest) must not change |
| `sprite-pipeline/config.toml` | Pipeline parameters: `godot_project_path`, `godot_binary`, target size, colors, backend |
| `sprite-pipeline/tools/import_sprites.gd` | Headless Godot script that reads `frames.json` + `sheet.png` and writes `.tres` |
