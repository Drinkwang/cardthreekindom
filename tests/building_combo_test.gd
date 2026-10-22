extends Node
const Traits = preload("res://scripts/building_traits.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func fixture() -> void:
	GameState.new_game()
	GameState.set_process(false)
	GameState.leave_battle()
	GameState.gold = 0
	# 组合测试使用已征服全部分区的2号城。
	for idx in [1, 2, 3, 4]:
		GameState.region_state[idx] = "cleared"
		GameState.table_wins[idx] = GameState.table_count(idx)
		GameState.cleared_zones[idx] = range(GameState.zone_count(idx))
	GameState._backfill_cities()
	for building in GameData.buildings:
		GameState.owned[str(building["id"])] = 12

func equip_chain() -> void:
	for id in ["B06", "B08", "B11", "B12"]:
		check(GameState.place_building(2, id, 0), "装配示例组合 " + id)

func rewrite_save(data: Dictionary) -> void:
	var file := FileAccess.open(GameState.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func test_unlock_and_pool() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.narrative_paused = false
	GameState.up.power = 90
	check(GameState.owned == {"I01": 1} and not GameState.city_unlocked() and GameState.city_slots(1) == 0, "单人新局未征服分区时没有基建位或建筑")
	check(GameState.begin_slap_batch(), "手动征服任意首区")
	for index in range(GameState.battle.size()):
		if int(GameState.battle[index].stage) == 4:
			check(GameState.attack(index), "拍翻首个分区中的敌牌")
	GameState.end_slap_batch()
	check(GameState.city_unlocked() and GameState.city_slots(1) == 1, "先征服第5区也开放1个基建位")
	check(GameState.building_stock("B06") == 1 and GameState.building_stock("B08") == 1, "首次清区赠起步建筑库存")
	GameState._update_pile_checkpoints()
	check(GameState.building_stock("B06") == 1 and GameState.building_stock("B08") == 1, "重复检查已征服分区不重复赠建筑")
	check(not GameState.place_building(1, "B06"), "征服后仍在战斗时不能装配")
	GameState.retreat()
	check(GameState.place_building(1, "B06", 0, 0), "休息时可在部分征服城中装配")
	check(not GameState.place_building(1, "B08", 0, 1), "未征服分区不能提前装建筑")
	var pool := GameState._pack_pool(0)
	var building_count := 0
	var hero_count := 0
	for card in pool:
		if str(card.get("type", "")) == "建筑": building_count += 1
		if str(card.get("type", "")) == "武将": hero_count += 1
	check(building_count > 0 and hero_count > 0, "卡包包含建筑并保留武将收集池")
	check(GameState.start_battle(1), "装配后继续未征服分区")
	var buildings := GameState.city_buildings(1).duplicate()
	var stock := GameState.owned.duplicate(true)
	check(not GameState.remove_building(1, 0) and not GameState.move_building_slot(1, 0, 0) and GameState.fuse_building("B08") == "", "战斗中拒绝卸下、换位和合成建筑")
	check(GameState.city_buildings(1) == buildings and GameState.owned == stock, "被拒的建筑操作不损失库存或装配卡")

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "建筑回归使用隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	test_unlock_and_pool()
	fixture()
	check(GameData.buildings.size() == 30, "完整30种建筑卡")
	for building in GameData.buildings:
		var id := str(building["id"])
		check(Traits.RULES.has(id) or str(building.get("effect_type", "none")) != "none", "建筑有可执行效果 " + id)
	check(GameState.city_slots(2) == 6, "征服六区开放六槽")
	equip_chain()
	check(is_zero_approx(GameState.gold_per_hour()) and is_zero_approx(float(GameState.city_combo(2).hourly)), "装配组合不会显示挂机金币")
	var cash := GameState.gold
	var xp := GameState.player_xp
	check(is_zero_approx(GameState.advance_buildings(86400)) and is_zero_approx(GameState.advance_buildings(86400, 0.5)), "在线或离线效率参数均不能恢复建筑产金")
	GameState._process(120.0)
	check(GameState.gold == cash and GameState.player_xp == xp, "休息等待不会产生金币或经验")
	check(is_zero_approx(GameState.offline_efficiency()) and is_zero_approx(GameState.offline_cap_hours()), "基建开放后离线效率和时长仍为零")
	var additive := Traits.evaluate(["B06", "B08", "B11", "B12", "B04"], [])
	check(is_equal_approx(Traits.payout(additive, 0, 3), 31.5), "追加倍率同层相加且不递归")
	var ordered := Traits.evaluate(["B12", "B11", "B08", "B06"], [])
	check(is_equal_approx(float(ordered.hourly), 3600), "排列顺序不改变组合")
	var two_sources := Traits.evaluate(["B01", "B06", "B08"], [])
	check(is_equal_approx(float(two_sources.normal), 9), "水井分别加成两张农产来源")
	check(float(Traits.evaluate(["B08", "B11", "B12"], []).normal) == 0, "助力卡无来源不凭空产金")
	var two_types := Traits.evaluate(["B22", "B06"], [])
	var three_types := Traits.evaluate(["B22", "B06", "B09"], [])
	check(not two_types.repeats[0].active and three_types.repeats[0].active, "天坛三种来源条件实际生效")
	check(Traits.evaluate(["B06", "B11"], [0, 2]).repeats[0].period == 3, "高品相不改变触发周期")
	check(is_equal_approx(float(Traits.evaluate(["B06", "B11"], [0, 1]).repeats[0].value), 5.4), "精制粮仓只强化追加收益35%")
	fixture()
	GameState.owned["B01"] = 4
	GameState.place_building(2, "B01", 0)
	check(GameState.fuse_building("B01", 0) == "B01", "同名原版三合一")
	check(GameState.gold == 0 and GameState.building_stock("B01", 1) == 1 and GameState.building_stock("B01", 0) == 0, "无金币成本且材料精确")
	check(GameState.building_quality(2, 0) == 0 and GameState._building_at(2, 0) == "B01", "装配卡未被消费")
	check(GameState.fuse_building("B01", 0) == "", "装配卡不能凑材料")
	GameState.remove_building(2, 0)
	check(GameState.building_stock("B01", 0) == 1, "卸下返还原版")
	GameState.owned["B01"] = 3
	check(GameState.fuse_building("B01", 0) == "", "两原版一精制不能混合")
	GameState.owned["B01"] = 3
	GameState.building_refined["B01"] = [3, 0]
	check(GameState.fuse_building("B01", 1) == "B01" and GameState.building_stock("B01", 2) == 1, "三精制合成珍藏")
	check(GameState.fuse_building("B01", 2) == "", "珍藏封顶")
	check(GameState.place_building(2, "B01", 2, 5), "可放指定第六槽")
	check(GameState._building_at(2, 0) == "" and GameState.building_quality(2, 5) == 2, "空槽与品相正确对齐")
	GameState.owned["B01"] = 3
	check(not GameState.place_building(2, "B01", 0), "同城不装配重复名字")
	check(GameState.place_building(2, "B06", 0, 0) and GameState.move_building_slot(2, 5, 0), "已装配建筑可交换槽位")
	check(GameState._building_at(2, 0) == "B01" and GameState.building_quality(2, 0) == 2 and GameState._building_at(2, 5) == "B06", "交换保留双方卡与品相")
	GameState.remove_building(2, 0)
	check(GameState.building_stock("B01", 2) == 1, "珍藏卸下不降品相")
	GameState.owned = {"B01": 1, "B02": 1, "B03": 1}
	GameState.building_refined.clear()
	check(GameState.fuse_building("B01") == "" and GameState.synth_buildings(1) == "", "不同名称同星不能混合")
	check(GameState._star_candidates(1).is_empty(), "旧通用合成不消费建筑卡")
	fixture()
	GameState.place_building(2, "B23", 0)
	GameState._building_stock_change("B23", 1, 1)
	GameState.place_building(3, "B23", 1)
	check(is_equal_approx(float(GameState.bonus.combat_power_pct), 20.25), "全局唯一效果取最强品相而不重复叠加")
	var original_price := GameState.pack_price(0)
	check(GameState.place_building(2, "B24", 0), "功能建筑可在休息时装配")
	check(GameState.pack_price(0) < original_price and float(GameState.bonus.pack_price_pct) == 10.0, "市场恢复原卡包折扣效果")
	check(GameState.remove_building(3, 0) and is_equal_approx(float(GameState.bonus.combat_power_pct), 15.0), "卸下最强品相后恢复另一城的原版拍力加成")
	fixture()
	equip_chain()
	GameState.advance_buildings(25)
	GameState.last_outcome = {"region": 5, "result": "settled", "gold": 555, "kills": 3, "damage": 1101.0}
	GameState.region_state[5] = "available"
	GameState.save_game()
	var phase_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path()))
	phase_save.last_save = Time.get_unix_time_from_system() + 60
	rewrite_save(phase_save)
	check(GameState.load_game(), "存档可载入")
	check(GameState.city_buildings(2) == ["B06", "B08", "B11", "B12"], "读档保留城池装配而不无条件清空")
	check(is_zero_approx(float(GameState.building_clocks[2])) and GameState.building_ticks[2] == 0, "读档不恢复自动产金计时")
	check(GameState.last_outcome.get("region", 0) == 5, "读档保留失败战果")
	check(is_zero_approx(GameState.advance_buildings(5)), "重进游戏也不触发旧追加产金")
	GameState.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path()))
	saved.last_save = Time.get_unix_time_from_system() - 3600
	saved.building_clocks = {"2": 0}
	saved.building_ticks = {"2": 0}
	rewrite_save(saved)
	check(GameState.load_game() and is_zero_approx(GameState.gold) and GameState.player_xp == 0, "离线读取保留基建但不发金币或经验")
	var after := GameState.gold
	check(GameState.load_game() and is_equal_approx(GameState.gold, after), "立即再次读档不重复领取离线金币")
	fixture()
	GameState.owned["B01"] = 3
	GameState.building_refined["B01"] = [3, 0]
	GameState.fuse_building("B01", 1)
	GameState.place_building(2, "B01", 2)
	GameState._building_stock_change("B06", 1, 1)
	GameState.save_game()
	check(GameState.load_game() and GameState.building_quality(2, 0) == 2, "珍藏装配品相存档保留")
	check(GameState.building_stock("B06", 1) == 1 and GameState.building_stock("B01", 2) == 0, "读档保留仓库品相且不复制已装配卡")
	check(is_equal_approx(GameState.building_output(2, 0), 648), "读档后珍藏实际数值保留")
	fixture()
	check(GameState.place_building(2, "B23", 0), "拍力建筑存档夹具可装配")
	GameState.save_game()
	var limited: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path()))
	limited.cleared_zones["2"] = [0]
	limited.cities["2"].buildings = ["B23", "B23", "B06"]
	limited.city_quality["2"] = [0, 1, 2]
	limited.city_lv["2"] = [3, 3, 3]
	limited.building_system_version = 1
	rewrite_save(limited)
	check(GameState.load_game() and GameState.city_buildings(2) == ["B23"], "读档只保留已征服槽位的建筑")
	check(GameState.building_stock("B23", 1) == 1 and GameState.building_stock("B06", 2) == 1, "超出已征服槽位的建筑原品相返还仓库")
	check(is_zero_approx(GameState.gold) and GameState.player_xp == 0, "修复建筑存档不通过旧等级退款制造金币或经验")
	check(is_equal_approx(float(GameState.bonus.combat_power_pct), 15.0), "读档重算已装配建筑的战斗加成")
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._open_city()
	for i in range(4):
		await get_tree().process_frame
	var city = main._city
	city._on_pick(2)
	var target = city.find_child("CitySlot5", true, false)
	var drag := {"kind": "building_card", "id": "B06", "quality": 0, "city": -1, "slot": -1}
	check(target._can_drop_data(Vector2.ZERO, drag), "空槽接受仓库卡拖拽")
	target._drop_data(Vector2.ZERO, drag)
	check(GameState._building_at(2, 5) == "B06", "拖入第六槽实际装配")
	for i in range(4):
		await get_tree().process_frame
	check(not city.find_child("CitySlot0", true, false)._can_drop_data(Vector2.ZERO, drag), "拖拽拒绝同城重复卡")
	main.queue_free()
	print("BUILDING COMBO: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
