# 怀旧印刷新美术资源

资源由 ImageGen 生成，界面标题、名称、星级、数值与技能文本由 Godot 渲染，不烧录在图像中。

| 文件 | 图集布局 | 卡牌顺序 |
| --- | --- | --- |
| buildings_a.png | 4 列 × 3 行 | B01–B12，逐行从左至右 |
| buildings_b.png | 4 列 × 3 行 | B13–B24，逐行从左至右 |
| buildings_c.png | 3 列 × 2 行 | B25–B30，逐行从左至右 |
| heroes.png | 3 列 × 2 行 | G04 朱灵、G05 文聘、G30 韩玄、G40 程普、G20 周仓、G24 马良 |
| deck_scene.png | 单张场景 | 构筑界面布景 |
| paper.png | 单张场景 | 纸面背景 |

建筑图集的每格均为完整场景。`scripts/ui/print_art.gd` 在旧资源映射之后应用新图，仅更改图集路径、格位和 1% 裁边，保留每张卡原有数据。尚未生成、未导入、路径无效或尺寸无效的资源不会覆盖原图。

- `Art.image(id, minimum)`：完整居中的普通卡片插图。
- `Art.scenic(id, minimum)`：铺满画框的场景插图，使用 `KEEP_ASPECT_COVERED`。
- `Art.paper_background()`：新纸面背景，缺失时回退现有纸纹。
- `Art.background("deck_scene")`：构筑场景，缺失时返回 `null`，使用方应保留原布景。

生成提示词、来源及实机检查记录由本次美术任务的总说明统一记录。
