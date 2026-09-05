# 作者来源清单

本目录保存作者提供资料的逐字节快照。快照只读；不得格式化、压缩、重编码或覆盖。作者提供新版时，使用新文件名保存并在本清单登记替代关系。

## `map-notes.txt`

- **ID**：`source-map-notes`
- **正典状态**：Established
- **作者源路径**：`/Users/patricksapple/Desktop/map.txt`
- **快照日期**：2026-08-20
- **大小**：2219 bytes
- **SHA-256**：`a0ecacb3bd519c8318766c5028bbe741d2ebbb6c06718cd222b9f016adc600a3`
- **作用**：记录 A–P 的作者原始地理与社会提示。快照之后的解释与修订进入世界条目，不反写本文件。

## `world-map.png`

- **ID**：`source-world-map`
- **正典状态**：Established
- **作者源路径**：`/Users/patricksapple/Desktop/图像.png`
- **快照日期**：2026-08-20
- **大小**：3976703 bytes
- **尺寸**：1766 × 1334
- **SHA-256**：`ad09758aa462298772aadf25e338c12056243ff7f9bd6c396d61f8f3fb93c995`
- **作用**：当前干净校正版世界地图。图中只有 A–P 十六个聚落体；最东侧封闭盆地标为 P。

## P/Q 校正记录

早期对话上传图曾同时出现旧 P 与远东 Q。作者后续提供的 `图像.png` 已完成校正：远东封闭盆地为 P，旧标记不再存在。地理 Spec 中的 P/Q 说明是迁移历史记录，不表示当前地图仍有 Q 聚落体。

## 校验命令

```sh
shasum -a 256 world-bible/sources/map-notes.txt world-bible/sources/world-map.png
```
