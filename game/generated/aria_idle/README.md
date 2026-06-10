# Aria idle sprite frames

Generated review asset for Aria's four-direction idle animation.

- Frame sizes: 64 x 64 px and 32 x 32 px
- Format: PNG with alpha
- Directions: `down`, `left`, `up`, `right`
- Frames per direction: 4
- Suggested animation names: `idle_down`, `idle_left`, `idle_up`, `idle_right`
- Suggested FPS: 4 to 6
- Post-processing: `generate2dsprite` / Sprite Forge shared-scale feet alignment, chroma-key despill, hard alpha, shared-palette quantization.
- Palette: 64 px frames use up to 48 visible RGB colors; 32 px frames use up to 32 visible RGB colors.

Files:

- `frames_64/aria_idle_<direction>_<frame>_64.png`: individual 64 x 64 Godot-ready frame PNGs.
- `frames_32/aria_idle_<direction>_<frame>_32.png`: individual 32 x 32 Godot-ready frame PNGs.
- `sheet/aria_idle_sheet_4dir_idle_64.png`: 4 x 4 transparent spritesheet, row order `down`, `left`, `up`, `right`.
- `sheet/aria_idle_sheet_4dir_idle_32.png`: 4 x 4 transparent spritesheet, row order `down`, `left`, `up`, `right`.
- `preview/aria_idle_contact_sheet_64.png`: checker-background preview for 64 px frames.
- `preview/aria_idle_contact_sheet_32.png`: checker-background preview for 32 px frames.
- `preview/aria_idle_contact_sheet_64_zoom4.png`: 4x nearest-neighbor preview for checking 64 px frames.
- `preview/aria_idle_contact_sheet_32_zoom8.png`: 8x nearest-neighbor preview for checking 32 px frames.
- `source/aria_idle_source_chroma.png`: original chroma-key generation source.
- `source/aria_idle_source_alpha_clean.png`: despilled transparent source used for Sprite Forge processing.
- `source/aria_idle_source_magenta.png`: magenta/alpha source passed to Sprite Forge.
- `sheet/aria_idle_sheet_alpha_raw.png`: transparent unnormalized source sheet.
- `spriteforge_64/pipeline-meta.json`: alignment and frame QC metadata from Sprite Forge.

These files are intentionally outside `assets/` so the asset pipeline can review or ingest them without Codex modifying the managed asset layer directly.
