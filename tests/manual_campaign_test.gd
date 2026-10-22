extends Node
## 跨层回归：自由清区、永久进度、战斗只读、建筑挂机与整城结束。
## Godot --headless --path . tests/ManualCampaignTest.tscn -- --test-profile
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.narrative_paused = false
	GameState.up.crit = 0

func clear_zone(zone: int) -> void:
	GameState.slap_cooldown_left = 0.0
	check(GameState.begin_slap_batch(), "清区开始有效手掌")
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == zone and float(GameState.battle[i].hp) > 0:
			check(GameState.attack(i), "手掌实际命中分区敌牌")
	GameState.end_slap_batch()

func positions_by_zone() -> Dictionary:
	var result := {}
	for i in range(GameState.battle.size()):
		var zone := int(GameState.battle[i].stage)
		if not result.has(zone): result[zone] = []
		result[zone].append(GameState.get_enemy_world_center(i))
	return result

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "测试使用隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	_test_rest_only_actions()
	_test_free_zone_campaign()
	print("[Manual campaign] checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_rest_only_actions() -> void:
	fixture()
	GameState.retreat()
	GameState.gold = 10000.0
	GameState.owned.G00 = 4
	GameState.owned.G01 = 1
	GameState.owned.G02 = 1
	GameState.owned.E01 = 1
	GameState.owned.E02 = 1
	GameState.owned.S01 = 1
	GameState.owned.S02 = 1
	GameState.up.equip = 1
	GameState.up.troops = 1
	check(GameState.carry_add("G00"), "休息可将新获得的武将上阵")
	check(GameState.carry_add("G01"), "休息可将第二名武将上阵供重排验证")
	check(GameState.equip_to("G00", "E02"), "休息可装备契合武器")
	check(GameState.troop_put("G00", "S01"), "休息可配属真实持有的士兵供撤兵验证")
	check(GameState.start_battle(1), "整备后出征")
	var carry: Array = GameState.carry.duplicate()
	var stock: Dictionary = GameState.owned.duplicate(true)
	var gear: Dictionary = GameState.hero_equip.duplicate(true)
	var troops: Dictionary = GameState.hero_troops.duplicate(true)
	var cash := GameState.gold
	check(not GameState.carry_add("G02"), "局内不能增加真实持有且有空位可上的武将")
	check(not GameState.carry_remove("G00"), "局内不能下阵")
	check(not GameState.carry_put("G01", 0), "局内不能重排已上阵的真实武将")
	GameState.carry_auto()
	check(GameState.carry == carry, "局内自动配队接口不变更队伍")
	check(not GameState.equip_to("G00", "E01"), "局内不能用真实可用装备替换现有装备")
	check(not GameState.unequip_from("G00", "E02"), "局内不能卸装")
	check(not GameState.troop_put("G01", "S02"), "局内不能向空兵位配属真实可用士兵")
	check(not GameState.troop_remove("G00", "S01"), "局内不能撤走实际已配属的士兵")
	check(not GameState.fuse_hero("G00"), "局内不能合将")
	check(GameState.synthesize(1).is_empty(), "局内不能合成")
	check(not GameState.buy_upgrade("radius"), "局内不能升级")
	check(GameState.buy_pack(0).is_empty(), "局内不能买包")
	check(GameState.carry == carry and GameState.owned == stock and GameState.hero_equip == gear and GameState.hero_troops == troops and GameState.gold == cash, "被拒操作保持队伍、库存、装备、士兵和金币快照不变")
	check(not GameState.start_practice(1) and not GameState.set_automation(true), "不开放练习与自动拍击")
	check(GameState.up_def("auto").is_empty() and GameState.up_def("auto_next").is_empty() and GameState.up_def("auto_power").is_empty(), "升级定义已去掉自动战斗")
	GameState.retreat()
	check(GameState.carry_put("G01", 0) and GameState.carry[0] == "G01", "休息后相同重排操作成功")
	check(GameState.carry_remove("G00"), "休息后相同下阵操作成功")
	check(GameState.carry_add("G02"), "休息后相同上阵操作成功")
	GameState.carry_auto()
	check(GameState.carry.size() == GameState.carry_max() and GameState.carry.has("G00") and GameState.carry.has("G01") and GameState.carry.has("G02"), "休息后自动配队实际补满三个真实武将")
	check(GameState.unequip_from("G00", "E02"), "休息后相同卸装操作成功")
	check(GameState.equip_to("G00", "E02"), "休息后恢复旧装备供替换对照")
	check(GameState.equip_to("G00", "E01") and GameState.equip_owner("E01") == "G00" and GameState.equip_owner("E02").is_empty(), "休息后相同换装操作成功并退回旧装备")
	check(GameState.troop_remove("G00", "S01"), "休息后相同撤兵操作成功")
	check(GameState.troop_put("G01", "S02"), "休息后相同派兵操作成功")

func _test_free_zone_campaign() -> void:
	fixture()
	GameState.up.power = 90
	var original := positions_by_zone()
	var world_size := GameState.battle_world_size()
	check(original.size() == GameState.zone_count(1), "整城所有未清分区同时铺出")
	check(GameState.city_slots(1) == 0, "新城未清区不送空基建位")
	var details := GameState.zone_details(1)
	check(details.size() == 5 and float(details[4].hp) > float(details[0].hp), "分区有独立厚度与难度信息")
	clear_zone(3)
	check(GameState.in_battle and GameState.round_active, "先清后面的区仍可继续本轮")
	check(GameState.zone_cleared(1, 3) and not GameState.zone_cleared(1, 0), "允许不按顺序永久征服")
	check(GameState.table_progress(1) == 1 and GameState.city_slots(1) == 1, "征服一区永久计数并解锁一个基建位")
	check(GameState.city_unlocked(), "任一区征服后可以经营基建")
	var cash := GameState.gold
	GameState.end_slap_batch()
	check(GameState.gold == cash and GameState.city_slots(1) == 1, "重复结束一掌不重复奖励和解锁")
	GameState.retreat()
	GameState.save_game()
	check(GameState.load_game() and GameState.zone_cleared(1, 3), "存读档保留乱序清区")
	check(GameState.city_slots(1) == 1, "存读档保留该城基建位")
	check(GameState.start_battle(1), "只重开未完成的城")
	var remaining := positions_by_zone()
	check(not remaining.has(3) and remaining.size() == 4, "重开不再生成已征服分区敌牌")
	check(GameState.battle_world_size() == world_size, "清区后重开不缩小全城尺寸")
	for zone in remaining:
		check(remaining[zone] == original[zone], "剩余分区保持固定地理位置")
	GameState.retreat()
	check(GameState.building_stock("B06") > 0, "首个分区提供起步建筑")
	check(GameState.place_building(1, "B06", 0, 0), "部分征服城可以休息时装配基建")
	check(not GameState.place_building(1, "B08", 0, 1), "尚未征服的第二区不能提前装配")
	var buildings := GameState.city_buildings(1).duplicate()
	var income := GameState.advance_buildings(10.0)
	check(income > 0 and not GameState.in_battle, "休息挂机由建筑产出且不启动拍击")
	check(GameState.start_battle(1), "经营后继续未清区")
	check(not GameState.place_building(1, "B08", 0, 0), "战斗不能装配基建")
	check(GameState.city_buildings(1) == buildings, "战斗拒绝装配不改变城建")
	GameState.up.power = 90
	for zone in [0, 1, 2, 4]: clear_zone(zone)
	check(not GameState.in_battle and not GameState.round_active, "全城最后一区清完立即结束本局")
	check(GameState.region_status(1) == "cleared" and GameState.table_progress(1) == 5, "城池永久征服")
	check(GameState.city_slots(1) == 5, "五区对应五个基建位")
	check(not GameState.start_battle(1) and not GameState.start_practice(1), "已通城无法重拍")
	check(GameState.region_status(2) == "available", "全城征服正常解锁后续城")
	var slaps := GameState.round_slaps
	GameState.advance_round(120.0)
	check(not GameState.in_battle and GameState.round_slaps == slaps, "等待不能偷偷重开或自动拍击")
