# 世界圣经协作规则

本目录服从仓库根 `AGENTS.md`。这里的规则只补充世界观写作与正典治理，不覆盖 Godot 工程边界。

## 开始工作前

依次阅读：

1. `discovery.md`
2. `canon-status.md`
3. `sources/manifest.md`
4. 仓库根 `CONTEXT.md`
5. 当前任务涉及的既有条目与 ADR

不得从已标记为 `Deprecated`、`Contradicted` 或未列入来源的旧工程文档继承设定。

## 来源与正典

- `sources/` 是作者原始资料快照。只读，不得修订、压缩、重编码或覆盖；新版来源必须另存并更新清单。
- 作者是唯一正典裁定者。Agent 可以创建 `Proposed` 与 `Speculative` 条目，不能自行把它们晋升为 `Established`。
- 条目只能使用 `Established` 来源作为既定事实。引用 `Proposed` 或 `Speculative` 内容时，必须保留相同或更低的正典状态。
- 发现冲突时，不要静默调和。把双方登记到 `meta/conflicts.md`，并将受影响条目标为 `Contradicted` 或保留原状态等待裁定。
- 所有内容使用普通相对 Markdown 链接。新增、晋升、废止或改名时同步更新 `canon-status.md`、相关索引和 `meta/changelog.md`。

## 条目元数据

世界条目使用以下字段；索引、清单与协作说明不需要伪装成世界条目：

```yaml
---
id: stable-kebab-case-id
category: rule | region | polity | nonstate | species | people | institution | event | relation
canon_status: Established | Proposed | Speculative | Deprecated | Contradicted
sources: []
depends_on: []
contradicts: []
last_updated: YYYY-MM-DD
---
```

ID 一旦被其他条目引用就不再更改；名称变化只改标题与显示文本。

## 推演纪律

- 聚落体沿“生态约束 → 可排他资产 → 租权集团 → 统治联盟 → 社会冲突 → 文化后果 → 精神追问”推演。
- 同时检查直接后果、制度适应与跨代文化后果；机构必须有形成原因、经历过的危机和内部矛盾。
- 经济必须落到资源、具体劳动、产权、交换、分配、季节和危机；治理能力不得超过中世纪通信、交通与财政可支持的范围。
- 生物先属于跨境生态系统。没有任何聚落体必须拥有独有种、地方标志种或生计支柱种。
- 信仰分类只是观察工具，不是必须填满的宗教配额；民族也只能由可追溯的迁徙、征服、登记、殖民或共同抗争形成。
- 不以“商人、船主、农民、贵族”替代职业链与产权状态，不以民族性格解释社会行为。
- 作者真相与玩家表象分层书写。玩家表象应让部分因果可辨认、部分可推断、部分暂不可尽知，但不得用谜团遮挡场景理解。
- 残酷内容必须说明实施机制、参与者自洽、承受者后果与反对位置，不把痛苦当作装饰。

## 逐地审阅

A–P 按字母顺序逐地完成。每地只创建一份主档案；共享生物、机构、民族或事件另建条目。每个聚落体提交后停止，等待作者审阅，再处理下一地。
