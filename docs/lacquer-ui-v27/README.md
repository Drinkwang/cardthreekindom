# 玄漆鎏金战斗界面 v27

后续版本见[平滑漆面精修v28](../lacquer-ui-v28/README.md)。用户反馈本版周期横纹粗糙后，v28已移除重复木纹并细化金边、卷云与朱漆；本页保留v27实现及历史验收，不代表当前材质或本轮测试结果。

用户已选择[UI方案B：玄漆鎏金](../art-direction/ui-style-v26/02-lacquer-gold.png)。本次在真实游戏控件上制作深漆底、木纹、金色双框与回纹角饰、象牙色正文和浅金次级文字；不是把概念图当作整张界面背景使用。

## 实装范围

- 顶部资源栏、城名牌匾、底部上阵栏与缩放工具栏使用玄漆鎏金样式；返回休息为朱漆主按钮，按钮保留悬停、按下、焦点与禁用状态。
- 时钟与状态文字适配深底，城名在连续状态刷新后仍保持浅色；分隔线统一为金色。
- 空同行槽改为深漆底、浅金加号与虚线；已有武将卡保留纸白卡面、原有人像和黑色名称，不对卡牌插画重新着色。
- 右下小地图仅外框换肤，仍使用[21城独立地形](../city-terrain-v26/README.md)，保留真实敌牌红点与视野框；不新增“地图”标题、图例或收起入口。
- 休息整备首页及商店、构筑、技能、基建内容保持现有纸面风格，共享的纸面按钮与装饰不切换为深色。

## 保持不变

- 底栏高度112像素，小地图220×96像素，上下各留8像素；上阵卡面88像素，满队仍横向滚动，头像44像素。
- 21城背景与近景地表、卡牌位置、世界坐标、默认0%视野及玩法数据不因换肤调整。
- 木纹、边框、角饰与徽章不接收鼠标，也不获取键盘焦点；顶部、底部留白继续支持边缘导航，缩放、小地图拖动与战场拍击保持原路径。
- 战斗中无法换将、装兵或改装备；返回休息后才能经四格整备入口操作。换肤不重新开放旧主菜单或战斗期整备入口。

## 原生验收

专项场景为`tests/LacquerUITest.tscn`，所有检查使用`--test-profile`隔离正式存档。新增检查覆盖深漆面板、文字对比度、按钮各态、装饰输入穿透、112像素底栏、满队带兵与纸面整备页。

2026-10-23，Godot 4.7.2、macOS Apple M2、OpenGL兼容渲染，已在1280×720及1280×800完成十四张专项实机截图，输出位于[本机截图目录](../shots/lacquer-ui-v27/)。截图和日志按项目现有规则不入Git。

| 场景 | 720截图 | 800截图 |
| --- | --- | --- |
| 默认战斗 | `battle-720-default.png` | `battle-800-default.png` |
| 返回休息悬停 | `battle-720-hover.png` | `battle-800-hover.png` |
| 返回休息按下 | `battle-720-pressed.png` | `battle-800-pressed.png` |
| 返回休息键盘焦点 | `battle-720-focus.png` | `battle-800-focus.png` |
| 满队、装备与带兵 | `battle-720-full-team.png` | `battle-800-full-team.png` |
| 四格休息整备首页 | `rest-720-hub.png` | `rest-800-hub.png` |
| 技能购买禁用 | `rest-720-upgrade-disabled.png` | `rest-800-upgrade-disabled.png` |

| 检查 | 方式 | 通过 / 失败 | 日志 |
| --- | --- | --- | --- |
| LacquerUITest | 原生窗口 | 412 / 0 | [skin.log](../shots/lacquer-ui-v27/skin.log) |
| RTSCameraTest | 原生窗口 | 203 / 0 | [rts.log](../shots/lacquer-ui-v27/rts.log) |
| AdventureUITest | 原生窗口 | 318 / 0 | [adventure.log](../shots/lacquer-ui-v27/adventure.log) |
| UIInteractionTest | 原生窗口 | 48 / 0 | [interaction.log](../shots/lacquer-ui-v27/interaction.log) |
| RestFlowTest | headless | 145 / 0 | [rest.log](../shots/lacquer-ui-v27/rest.log) |

合计1126项检查、0失败。专项同时抽样实际GPU帧中的深底像素，检查常态、悬停、按下和焦点文字对比度至少4.5:1，以及装饰不接输入。原生截图已人工检查默认、满队、四格休息和技能禁用页面：深底浅字可读，返回按钮使用15号正文字体，底栏与地图不压边、不遮主战场。这是本轮专项回归，不代表完成全量回归、所有设备或导出包验证。

### 实机预览

![B版720战斗界面](../shots/lacquer-ui-v27/battle-720-default.png)

![B版800满队界面](../shots/lacquer-ui-v27/battle-800-full-team.png)

## 概念图与实机的边界

[三套UI参考及生成来源](../art-direction/ui-style-v26/README.md)继续作为历史美术方向记录，原PNG和生成元数据保持不变。B已被选为制作方向，但该概念图本身始终不是实机截图；真实实现受当前控件布局、字体和交互规格约束，不逐像素复制图中的合成文字、地面或卡面。
