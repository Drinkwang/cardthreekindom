# 独立城池地形 v26

2026-10-23。实装范围为城池地形及小地图对应地形，不替换UI主题，不调整分区、敌牌、世界坐标、存档、收益或战斗整备规则。

## 资源与绘制

- 21城各有一张整城背景`city_01.png`—`city_21.png`，以及一张独立近景地表`ground_01.png`—`ground_21.png`，位于[assets/art_v26](../../assets/art_v26/)。不是四张旧底图的镜像、调色或别名。
- 背景01—03原生1672×941，其余18张背景原生1254×1254；21张地表均为1254×1254。保留生成原图，没有放大为4K/8K，不将生成提示词中的AA目标作为成品等级证明。
- 背景负责整城外围构图，按世界比例等比覆盖裁切；中央近景地表以640世界单位为单元镜像平铺，降低纹理边缘硬接缝。背景与地表的融合带收窄为距世界边缘归一化距离0.08—0.11，减少双层图案重叠。近景不再仅依赖一张整城低分辨率图放大。
- 主图与小地图通过相同城池编号读取同一对资源，分别持有绘制材质；分区线、敌牌红点与视野框单独绘制，不套地形材质。地形层不接收鼠标。
- 风格约束为四周点景、中央平整连续；不恢复逐区建筑拼贴，也不在中央用桥、水道、围墙、台阶或建筑分割通路。

## 城池对应

编号、名称与主题以`scripts/ui/city_terrain_profiles.gd`为准，同号背景与地表成对使用。

| 编号 | 城池 | 主题 | 背景 | 地表 |
| --- | --- | --- | --- | --- |
| 01 | 新野 | 秋叶暖石 | [city_01](../../assets/art_v26/city_01.png) | [ground_01](../../assets/art_v26/ground_01.png) |
| 02 | 樊城 | 疏草灰石 | [city_02](../../assets/art_v26/city_02.png) | [ground_02](../../assets/art_v26/ground_02.png) |
| 03 | 中庐 | 桑荫黄土 | [city_03](../../assets/art_v26/city_03.png) | [ground_03](../../assets/art_v26/ground_03.png) |
| 04 | 宜城 | 柳影青石 | [city_04](../../assets/art_v26/city_04.png) | [ground_04](../../assets/art_v26/ground_04.png) |
| 05 | 宛城 | 松荫汉庭 | [city_05](../../assets/art_v26/city_05.png) | [ground_05](../../assets/art_v26/ground_05.png) |
| 06 | 襄阳 | 苔痕灰石 | [city_06](../../assets/art_v26/city_06.png) | [ground_06](../../assets/art_v26/ground_06.png) |
| 07 | 当阳 | 草坡土路 | [city_07](../../assets/art_v26/city_07.png) | [ground_07](../../assets/art_v26/ground_07.png) |
| 08 | 夏口 | 芦影青石 | [city_08](../../assets/art_v26/city_08.png) | [ground_08](../../assets/art_v26/ground_08.png) |
| 09 | 夷陵 | 山麓土坪 | [city_09](../../assets/art_v26/city_09.png) | [ground_09](../../assets/art_v26/ground_09.png) |
| 10 | 武昌 | 疏柳石路 | [city_10](../../assets/art_v26/city_10.png) | [ground_10](../../assets/art_v26/ground_10.png) |
| 11 | 沅陵 | 青石竹庭 | [city_11](../../assets/art_v26/city_11.png) | [ground_11](../../assets/art_v26/ground_11.png) |
| 12 | 公安 | 草缘空坪 | [city_12](../../assets/art_v26/city_12.png) | [ground_12](../../assets/art_v26/ground_12.png) |
| 13 | 汉寿 | 荷叶青石 | [city_13](../../assets/art_v26/city_13.png) | [ground_13](../../assets/art_v26/ground_13.png) |
| 14 | 临沅 | 林荫土路 | [city_14](../../assets/art_v26/city_14.png) | [ground_14](../../assets/art_v26/ground_14.png) |
| 15 | 攸县 | 麦草土坪 | [city_15](../../assets/art_v26/city_15.png) | [ground_15](../../assets/art_v26/ground_15.png) |
| 16 | 临湘 | 桂荫暖石 | [city_16](../../assets/art_v26/city_16.png) | [ground_16](../../assets/art_v26/ground_16.png) |
| 17 | 耒阳 | 草影青板岩 | [city_17](../../assets/art_v26/city_17.png) | [ground_17](../../assets/art_v26/ground_17.png) |
| 18 | 郴县 | 樟荫赤土 | [city_18](../../assets/art_v26/city_18.png) | [ground_18](../../assets/art_v26/ground_18.png) |
| 19 | 观阳 | 浅草白石 | [city_19](../../assets/art_v26/city_19.png) | [ground_19](../../assets/art_v26/ground_19.png) |
| 20 | 泉陵 | 蕨影青石 | [city_20](../../assets/art_v26/city_20.png) | [ground_20](../../assets/art_v26/ground_20.png) |
| 21 | 江陵 | 灰石汉庭 | [city_21](../../assets/art_v26/city_21.png) | [ground_21](../../assets/art_v26/ground_21.png) |

## 已知边界

- 这是外围场景加中心重复材质的方案，不是整张城池每个位置都独一无二的超大手绘图。拉远后可能看出地表重复，外围背景仍受原图像素数量限制；近景清晰度不能推导为外围建筑同样清晰。
- 生成式素材的纹理边缘、石缝连续性和背景/地表色差需要原生窗口人工检查，资源不重复或采样密度达标不能代替视觉验收。
- 背景按世界比例裁切，同一城市在5区、12区和不同窗口比例下外围露出范围可能不同；不因此移动牌位或改变地图几何。
- 可恢复的完整生成提示词与文件来源位于[assets/art_v26/generation](../../assets/art_v26/generation/)。并非全部早期素材都留有逐字原始提示词，不补造缺失记录。
- 当前项目没有`export_presets.cfg`，尚未验证打包。地形资源路径由城池编号动态拼接；将来若采用仅导出依赖资源的配置，需显式包含`assets/art_v26/*.png`，并另做导出后验证。

## 验收记录

2026-10-23，Godot 4.7.2、macOS Apple M2、OpenGL兼容渲染；全部使用`--test-profile`隔离存档。以下为本轮实测，不是完整回归或导出验收。

| 检查 | 运行方式 | 通过 / 失败 | 日志 |
| --- | --- | --- | --- |
| DistrictArtTest | 原生窗口 | 1717 / 0 | [district.log](../shots/city-terrain-v26/district.log) |
| RTSCameraTest | 原生窗口 | 203 / 0 | [rts.log](../shots/city-terrain-v26/rts.log) |
| AdventureUITest | 原生窗口 | 318 / 0 | [adventure.log](../shots/city-terrain-v26/adventure.log) |
| UIInteractionTest | 原生窗口 | 48 / 0 | [interaction.log](../shots/city-terrain-v26/interaction.log) |
| CityExplorationTest | headless | 230 / 0 | [exploration.log](../shots/city-terrain-v26/exploration.log) |
| RestFlowTest | headless | 145 / 0 | [rest.log](../shots/city-terrain-v26/rest.log) |

- 合计2661项检查、0失败。地形专项核对42张原文件及独立内容哈希、实际加载、mipmap、世界几何、主图/小地图材质隔离；另对21城实际GPU渲染结果分别检查横纵镜像边界的像素连续性。
- [原生截图目录](../shots/city-terrain-v26/)已保存63张地形截图：1280×800全部21城；新野、沅陵、江陵另在1280×720和1280×800覆盖默认、全景、中心及四边。截图和日志属于本机验收产物，按项目现有规则不入Git。
- 新野1280×800默认镜头地表每原像素约对应0.713屏幕像素，最大镜头约0.951；这些数值仅描述近景地表，不描述外围背景。
- 原生视觉检查发现原始直接重复的石缝硬切与宽融合带双影，已改镜像衔接并缩窄融合带。主战场卡牌可读，中心没有桥、河道或建筑阻断，底栏与小地图完整；拉远仍可辨认重复/镜像规律，外围建筑放大后仍比地表软，窄过渡带也并非逐石缝手绘连接。不能据此宣称全部画面已达到AA成品标准。

### 实机示例

- [新野默认视野](../shots/city-terrain-v26/city-01-800-default.png)、[整城](../shots/city-terrain-v26/city-01-800-overview.png)
- [沅陵默认视野](../shots/city-terrain-v26/city-11-800-default.png)、[北侧融合](../shots/city-terrain-v26/city-11-800-north.png)
- [江陵默认视野](../shots/city-terrain-v26/city-21-800-default.png)、[整城](../shots/city-terrain-v26/city-21-800-overview.png)

地形v26完成后，用户已从[三套独立概念参考](../art-direction/ui-style-v26/README.md)中选择B，真实战斗外壳另行制作[玄漆鎏金UI v27](../lacquer-ui-v27/README.md)。本页63张地形实机截图记录的是换肤前的界面；概念图本身不是实机，v27的换肤验收与截图另行记录，不改写本页地形历史结果。
