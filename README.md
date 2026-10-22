# 《拍案三国》Godot 工程

引擎：Godot 4.7.2。当前版本是主动手拍的分区征服游戏：玩家拍翻敌牌才获得金币与经验，在休息期使用技能点、调整武将，再继续征服未完成城池。

## 当前玩法

- 每城由多个可自由选择的分区组成；已征服分区和全清城不会再刷敌。
- 新游戏只有主角I01，不附送卡包、士兵或武将，初始轻拍伤害1.3。
- 金币只在玩家手动拍翻敌牌时一次结算；只打伤没有金币或经验。
- 一掌拍翻至少一张敌牌，玩家与上阵武将各得1经验；范围与追击翻多牌共用本次成长。玩家升级给技能点，武将最高Lv.20。
- 地图宝箱与任务的底层数据保留，当前隐藏展示与交互；全清城后可巡城，不生成敌牌或倒计时。
- 启动直接进入牌桌或续档休息，不再打开旧主菜单；休息营地为商店、构筑、技能、基建四格。
- 战斗中只保留拍击、镜头、小地图和返回休息；所有整备页只在本轮结束后出现。
- 每征服一区开放一个基建位，支持装配、组合收藏和功能建筑加成；没有建筑计时、在线或离线产金。
- 新增黄月英、貂蝉、孙尚香、大乔、小乔、甄宓、蔡文姬、祝融；通过现有卡包收集。
- 小地图在底栏右侧常驻220×148，没有“卡牌 / 视野”图例、收起按钮或M键折叠。
- RTS式导航：窗口四边16像素即时滚屏，中键或空格+左键跨HUD拖图，滚轮锚点缩放；“回目标区”恢复0%并定位未清分区。
- 城池使用连续地面、贯通道路和固定世界比例透明景物，不再拼接旧城大图与分区矩形。
- 剧情、札记与教学提示目前未接入，等待后续撰写。

完整当前策划和下一轮修改入口在[游戏策划](游戏策划/README.md)。

[修炼图设计](docs/cultivation-district-v13/README.md)保留九圆章节点与右侧技能点升级；当前连续地图和RTS鼠标验收见[存档与验证](游戏策划/10_存档兼容与验证.md#save-04rts鼠标与连续地图验收)。

## 运行

本机使用：

```sh
/Users/arthurwang/Downloads/Godot.app/Contents/MacOS/Godot --path .
```

正式存档是 `user://save_paan_adventure.json`。本版本不读取或迁移旧存档。

## 当前专项验证

```sh
/Users/arthurwang/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . tests/GrowthEconomyTest.tscn -- --test-profile
/Users/arthurwang/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . tests/MapEventsTest.tscn -- --test-profile
/Users/arthurwang/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . tests/AdventureUITest.tscn -- --test-profile
/Users/arthurwang/Downloads/Godot.app/Contents/MacOS/Godot --path . tests/RTSCameraTest.tscn -- --test-profile
```

旧基线与新版拍翻收益、单人开局、基建女将、RTS鼠标和连续地图的分项结果见[存档与验证](游戏策划/10_存档兼容与验证.md)，不要把旧规则的通过数当作当前验收结果。
