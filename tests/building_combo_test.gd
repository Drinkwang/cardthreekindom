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
	# 基建现由新野首通解锁；组合测试仍在2号城装配原来的示例建筑。
	for idx in [1, 2, 3, 4]:
		GameState.region_state[idx] = "cleared"
		GameState.table_wins[idx] = GameState.table_count(idx)
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

func _ready() -> void:
	fixture()
	check(GameData.buildings.size() == 30, "完整30种建筑卡")
	for building in GameData.buildings:
		var id := str(building["id"])
		check(Traits.RULES.has(id) or str(building.get("effect_type", "none")) != "none", "建筑有可执行效果 " + id)
	check(GameState.city_slots(2) == 6, "低阶城市也有六槽")
	equip_chain()
	check(is_equal_approx(GameState.gold_per_hour(), 3600), "示例组合60金币/分")
	check(is_equal_approx(GameState.advance_buildings(9.9), 0), "未满10秒无收益")
	check(is_equal_approx(GameState.advance_buildings(0.1), 6), "第一次6金币")
	check(is_equal_approx(GameState.advance_buildings(10), 6), "第二次6金币")
	check(is_equal_approx(GameState.advance_buildings(10), 18), "第三次6基础+12追加")
	GameState.building_clocks.clear()
	GameState.building_ticks.clear()
	var bulk := GameState.advance_buildings(3600)
	check(is_equal_approx(bulk, 3600), "整小时精确结算")
	GameState.building_clocks.clear()
	GameState.building_ticks.clear()
	var split := 0.0
	for i in range(360):
		split += GameState.advance_buildings(10)
	check(is_equal_approx(bulk, split), "批量与逐周期结算一致")
	GameState.building_clocks.clear()
	GameState.building_ticks.clear()
	check(is_equal_approx(GameState.advance_buildings(3600, 0.5), 1800), "离线效率作用于完整组合")
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
	check(is_equal_approx(float(GameState.building_clocks[2]), 5) and GameState.building_ticks[2] == 2, "读档保留周期相位和计数")
	check(GameState.last_outcome.get("region", 0) == 5, "读档保留失败战果")
	check(is_equal_approx(GameState.advance_buildings(5), 18), "重进游戏后第3次仍触发追加")
	GameState.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path()))
	saved.last_save = Time.get_unix_time_from_system() - 3600
	saved.building_clocks = {"2": 0}
	saved.building_ticks = {"2": 0}
	rewrite_save(saved)
	check(GameState.load_game() and is_equal_approx(GameState.gold, 1800), "实际离线读取发放组合收益")
	var after := GameState.gold
	check(GameState.load_game() and is_equal_approx(GameState.gold, after), "立即再次读档不重复领取离线金币")
	fixture()
	var legacy := {"gold": 100, "owned": {}, "region_state": {"1": "cleared", "2": "cleared", "3": "cleared", "4": "cleared"}, "cities": {"2": {"buildings": ["B01", "B01"]}}, "city_lv": {"2": [2, 1]}, "last_save": Time.get_unix_time_from_system()}
	rewrite_save(legacy)
	check(GameState.load_game(), "旧建筑档可迁移")
	check(is_equal_approx(GameState.gold, 514), "旧强化费用完整返还120+174+120")
	check(GameState.city_buildings(2) == ["B01"] and GameState.building_stock("B01") == 1, "重复同城建筑安全返仓")
	check(GameState.load_game() and is_equal_approx(GameState.gold, 514), "旧强化返还只执行一次")
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
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._open_city()
	for i in range(4):
		await get_tree().process_frame
	var city = main._city
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
