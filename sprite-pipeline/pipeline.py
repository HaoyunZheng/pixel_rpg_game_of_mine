#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
像素 Sprite 流水线  —  Mac / Apple Silicon 版
================================================

四段解耦、每段可单独重跑:

    ①生成  →  ②后处理  →  ③打包  →  ④Godot 导入

  ① 生成层是可插拔的(适配器模式):manual / drawthings / comfyui / pixellab。
     换哪个后端,后面 ②③④ 一行都不用改。
  ② 后处理 = 自动裁切 + 最近邻降采样到目标像素尺寸 + 颜色量化 + 透明背景。
     (相当于内置了一份 proper-pixel-art 的核心功能,零外部仓库依赖。)
  ③ 打包  = 把每个角色的各动作帧拼成一张精灵表 sheet.png,并产出 frames.json。
  ④ 导入  = 调 Godot --headless 跑 tools/import_sprites.gd,
     把 sheet.png + frames.json 变成可直接挂给 AnimatedSprite2D 的 SpriteFrames .tres。

目录约定
--------
    work_dir/
      raw/<角色>/<动作>/*.png        ← 生成层产出(或你手动丢进来)
      processed/<角色>/<动作>/*.png  ← ②后处理产出
      packed/<角色>/sheet.png        ← ③打包产出
      packed/<角色>/frames.json
    Godot 项目/assets/sprites/<角色>/ ← ④复制进去并生成 .tres

用法
----
    python3 pipeline.py            # 跑全部四段
    python3 pipeline.py process    # 只跑后处理
    python3 pipeline.py process pack
    python3 pipeline.py --config config.toml

依赖:  pip install pillow numpy
       (toml 解析用 Python 3.11+ 自带的 tomllib;更老的版本会自动退回 'tomli')
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ---- TOML 解析:优先用标准库 tomllib(3.11+),否则用 tomli ----
try:
    import tomllib  # Python 3.11+
    def _load_toml(p: Path) -> dict:
        with open(p, "rb") as f:
            return tomllib.load(f)
except ModuleNotFoundError:  # pragma: no cover
    try:
        import tomli  # pip install tomli
        def _load_toml(p: Path) -> dict:
            with open(p, "rb") as f:
                return tomli.load(f)
    except ModuleNotFoundError:
        sys.exit("缺少 TOML 解析器。请升级到 Python 3.11+,或 `pip install tomli`。")

try:
    from PIL import Image
except ModuleNotFoundError:
    sys.exit("缺少 Pillow。请运行: pip install pillow numpy")


# ============================================================
#  工具函数
# ============================================================
def log(stage: str, msg: str) -> None:
    print(f"[{stage}] {msg}", flush=True)


def list_frames(folder: Path) -> list[Path]:
    """按文件名排序返回一个动作目录下的所有帧 PNG。"""
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir()
                  if p.suffix.lower() in (".png", ".webp") and not p.name.startswith("."))


# ============================================================
#  ① 生成层 —— 适配器
# ============================================================
class GenerationBackend:
    """所有生成后端的基类。子类只需实现 generate()。"""
    def __init__(self, cfg: dict, work_dir: Path):
        self.cfg = cfg
        self.work_dir = work_dir
        self.raw = work_dir / "raw"

    def generate(self) -> None:
        raise NotImplementedError


class ManualBackend(GenerationBackend):
    """你自己出图,丢进 raw/。脚本只负责校验目录齐全。"""
    def generate(self) -> None:
        chars = self.cfg["generation"].get("characters", {})
        missing = []
        for name, spec in chars.items():
            for action in spec.get("actions", []):
                folder = self.raw / name / action
                if not list_frames(folder):
                    missing.append(str(folder))
        if missing:
            log("生成", "manual 模式:以下目录还没有帧图片,请先放图再跑:")
            for m in missing:
                log("生成", f"   缺 → {m}")
            raise SystemExit("（manual 模式下流水线在此停下,等你补图。）")
        log("生成", "manual 模式:raw/ 目录齐全,跳到后处理。")


class DrawThingsBackend(GenerationBackend):
    """
    调 Draw Things 的 API Server(Mac 首选)。
    Draw Things 内 Settings → Advanced → API Server 开启后会给出地址。
    注意:不同版本的 Draw Things HTTP 接口字段可能略有差异,
    下面按其常见的 txt2img 风格构造请求;如报错请对照 App 内 API 文档微调 payload。
    """
    def generate(self) -> None:
        import urllib.request
        dt = self.cfg["generation"]["drawthings"]
        chars = self.cfg["generation"].get("characters", {})
        for name, spec in chars.items():
            for action in spec.get("actions", []):
                out_dir = self.raw / name / action
                out_dir.mkdir(parents=True, exist_ok=True)
                subject = f"a {name}, {action} pose"
                payload = {
                    "prompt": dt["positive"].format(subject=subject),
                    "negative_prompt": dt["negative"],
                    "model": dt["model"],
                    "loras": dt.get("loras", []),
                    "steps": dt["steps"],
                    "guidance_scale": dt["cfg"],
                    "sampler": dt["sampler"],
                    "width": dt["width"],
                    "height": dt["height"],
                    "seed": 12345,  # 锁种子 → 同角色不同动作更一致
                }
                log("生成", f"Draw Things → {name}/{action}")
                req = urllib.request.Request(
                    dt["api_url"].rstrip("/") + "/sdapi/v1/txt2img",
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Content-Type": "application/json"},
                )
                # 实际落地时:解析返回的 base64 图像并写入 out_dir/frame_000.png
                # 这里保持显式,避免对具体版本接口做错误假设。
                raise NotImplementedError(
                    "Draw Things 后端已搭好骨架。请先在 App 内开启 API Server,\n"
                    "确认它的接口路径与字段后,把上面 req 的响应解析补上即可。\n"
                    "（建议先用 manual 模式跑通 ②③④,再回头接生成层。）"
                )


class ComfyUIBackend(GenerationBackend):
    """调 ComfyUI 的 /prompt 队列接口,喂入导出的 workflow_api.json。"""
    def generate(self) -> None:
        cu = self.cfg["generation"]["comfyui"]
        wf = self.work_dir / cu["workflow_api"]
        if not wf.exists():
            raise SystemExit(f"找不到 ComfyUI workflow: {wf}（在 ComfyUI 里用 Save(API Format) 导出）")
        raise NotImplementedError(
            "ComfyUI 后端已搭好骨架:读 workflow_api.json,替换提示词节点,\n"
            "POST 到 {url}/prompt,再从 history/output 取图写入 raw/。\n"
            "（建议先用 manual 模式跑通下游。）".format(url=cu["api_url"])
        )


class PixelLabBackend(GenerationBackend):
    def generate(self) -> None:
        raise SystemExit(
            "PixelLab 推荐走 MCP(见 README「vibe coding」)。\n"
            "若坚持走脚本 REST,在此实现 create_character / animate_character 调用。"
        )


BACKENDS = {
    "manual": ManualBackend,
    "drawthings": DrawThingsBackend,
    "comfyui": ComfyUIBackend,
    "pixellab": PixelLabBackend,
}


# ============================================================
#  ② 后处理 —— 内置的 "proper-pixel-art lite"
# ============================================================
def _autocrop(img: Image.Image) -> Image.Image:
    """裁掉四周完全透明 / 接近纯色的边。"""
    rgba = img.convert("RGBA")
    bbox = rgba.getbbox()
    return rgba.crop(bbox) if bbox else rgba


def _remove_bg(img: Image.Image, tol: int) -> Image.Image:
    """把与四角颜色接近的像素设为透明(简单泛色背景去除)。"""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg = corners[0]
    for x in range(w):
        for y in range(h):
            r, g, b, a = px[x, y]
            if abs(r - bg[0]) <= tol and abs(g - bg[1]) <= tol and abs(b - bg[2]) <= tol:
                px[x, y] = (r, g, b, 0)
    return img


def process_one(src: Path, dst: Path, size: int, colors: int,
                transparent: bool, tol: int, autocrop: bool) -> None:
    img = Image.open(src).convert("RGBA")
    if autocrop:
        img = _autocrop(img)
    if transparent:
        img = _remove_bg(img, tol)
    # 最近邻降采样到目标像素尺寸(这是 "真像素" 的关键一步)
    img = img.resize((size, size), Image.NEAREST)
    if colors and colors > 0:
        # 仅对 RGB 量化,保留 alpha
        alpha = img.split()[3]
        rgb = img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        img = rgb.convert("RGBA")
        img.putalpha(alpha)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst)


def stage_process(cfg: dict, work_dir: Path) -> None:
    p = cfg["pipeline"]
    raw, processed = work_dir / "raw", work_dir / "processed"
    n = 0
    for char_dir in sorted(d for d in raw.iterdir() if d.is_dir()) if raw.exists() else []:
        for action_dir in sorted(d for d in char_dir.iterdir() if d.is_dir()):
            for i, frame in enumerate(list_frames(action_dir)):
                dst = processed / char_dir.name / action_dir.name / f"frame_{i:03d}.png"
                process_one(frame, dst, p["target_size"], p["palette_colors"],
                            p["transparent_bg"], p["bg_tolerance"], p["autocrop"])
                n += 1
    log("后处理", f"规整完成,共 {n} 帧 → {processed}")


# ============================================================
#  ③ 打包 —— 拼精灵表 + 生成 frames.json
# ============================================================
def stage_pack(cfg: dict, work_dir: Path) -> None:
    fps = cfg["generation"]["fps"]
    processed, packed = work_dir / "processed", work_dir / "packed"
    if not processed.exists():
        raise SystemExit("没有 processed/ 目录,请先跑 process。")

    for char_dir in sorted(d for d in processed.iterdir() if d.is_dir()):
        actions = sorted(d for d in char_dir.iterdir() if d.is_dir())
        if not actions:
            continue
        frame_lists = {a.name: list_frames(a) for a in actions}
        max_cols = max(len(v) for v in frame_lists.values())
        rows = len(actions)

        # 格子尺寸取自该角色实际帧图(②段/切分工具已把帧规整为统一尺寸),
        # 允许不同角色用不同像素尺寸(如人形 64、大型兽 128)。
        first_frame = next(v[0] for v in frame_lists.values() if v)
        size = Image.open(first_frame).size[0]

        sheet = Image.new("RGBA", (max_cols * size, rows * size), (0, 0, 0, 0))
        anims = {}
        for row, action in enumerate(actions):
            frames = frame_lists[action.name]
            for col, fp in enumerate(frames):
                sheet.paste(Image.open(fp).convert("RGBA"), (col * size, row * size))
            anims[action.name] = {"row": row, "frames": len(frames)}

        out = packed / char_dir.name
        out.mkdir(parents=True, exist_ok=True)
        sheet.save(out / "sheet.png")
        meta = {
            "character": char_dir.name,
            "cell_width": size,
            "cell_height": size,
            "fps": fps,
            "animations": anims,
        }
        (out / "frames.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))
        log("打包", f"{char_dir.name}: {rows} 个动作 → {out/'sheet.png'}")


# ============================================================
#  ④ Godot 导入 —— 复制资源 + 调 headless 脚本
# ============================================================
def stage_godot_import(cfg: dict, work_dir: Path, script_path: Path) -> None:
    proj = cfg["project"]["godot_project_path"].strip()
    if not proj:
        log("Godot导入", "未配置 godot_project_path,跳过第④段。"
                         "（前三段产出已在 packed/,可手动拖进 Godot。）")
        return
    proj_path = Path(proj).expanduser()
    if not (proj_path / "project.godot").exists():
        raise SystemExit(f"{proj_path} 下没有 project.godot,请检查 godot_project_path。")

    # 1) 把 packed/<角色>/ 复制进 Godot 项目的 assets/sprites/
    dst_root = proj_path / "assets" / "sprites"
    packed = work_dir / "packed"
    for char_dir in sorted(d for d in packed.iterdir() if d.is_dir()):
        dst = dst_root / char_dir.name
        dst.mkdir(parents=True, exist_ok=True)
        for fn in ("sheet.png", "frames.json"):
            if (char_dir / fn).exists():
                shutil.copy2(char_dir / fn, dst / fn)
    log("Godot导入", f"资源已复制到 {dst_root}")

    # 2) 把导入脚本放到项目 res://tools/ 下
    tools_dir = proj_path / "tools"
    tools_dir.mkdir(exist_ok=True)
    shutil.copy2(script_path, tools_dir / script_path.name)

    # 3) 调 Godot headless 执行
    godot = cfg["project"]["godot_binary"]
    cmd = [godot, "--headless", "--path", str(proj_path),
           "--script", "res://tools/import_sprites.gd"]
    log("Godot导入", "运行: " + " ".join(cmd))
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        raise SystemExit(f"找不到 Godot 可执行文件: {godot}（检查 config.toml 的 godot_binary）")
    log("Godot导入", "完成。SpriteFrames .tres 已生成在 assets/sprites/<角色>/ 下。")


# ============================================================
#  编排
# ============================================================
STAGES = ["generate", "process", "pack", "import"]


def main() -> None:
    ap = argparse.ArgumentParser(description="像素 Sprite 流水线 (Mac)")
    ap.add_argument("stages", nargs="*", default=[],
                    help=f"要跑的阶段(可多选,默认全跑): {', '.join(STAGES)}")
    ap.add_argument("--config", default="config.toml")
    args = ap.parse_args()

    here = Path(__file__).resolve().parent
    cfg_path = (here / args.config) if not os.path.isabs(args.config) else Path(args.config)
    cfg = _load_toml(cfg_path)

    work_dir = (here / cfg["pipeline"]["work_dir"]).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    script_path = here / "tools" / "import_sprites.gd"

    stages = args.stages or STAGES
    bad = [s for s in stages if s not in STAGES]
    if bad:
        sys.exit(f"未知阶段 {bad};可选: {STAGES}")

    log("流水线", f"工作目录: {work_dir}")
    log("流水线", f"将执行: {stages}")

    if "generate" in stages:
        backend_name = cfg["generation"]["backend"]
        backend_cls = BACKENDS.get(backend_name)
        if not backend_cls:
            sys.exit(f"未知生成后端: {backend_name};可选 {list(BACKENDS)}")
        log("生成", f"后端 = {backend_name}")
        backend_cls(cfg, work_dir).generate()
    if "process" in stages:
        stage_process(cfg, work_dir)
    if "pack" in stages:
        stage_pack(cfg, work_dir)
    if "import" in stages:
        stage_godot_import(cfg, work_dir, script_path)

    log("流水线", "全部完成 ✅")


if __name__ == "__main__":
    main()
