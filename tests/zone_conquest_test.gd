extends Node
## Godot --headless --path . tests/ZoneConquestTest.tscn -- --test-profile
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
	GameState.carry.clear()
	GameState.up.crit = 0
	GameState.up.power = 90

func clear_zone(zone: int) -> void:
	GameState.slap_cooldown_left = 0.0
	check(GameState.begin_slap_batch(), "分区%d可开始一掌" % zone)
	var targets: Array[int] = []
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == zone: targets.append(i)
	check(not targets.is_empty(), "分区%d有目标" % zone)
	for i in targets:
		check(GameState.attack(i, false), "分区%d命中牌%d" % [zone, i])
	GameState.end_slap_batch()

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-profile"):
		push_error("ZoneConquestTest必须指定--test-profile隔离正式存档")
		get_tree().quit(1)
		return
	check(GameState.save_path() != GameState.SAVE_PATH, "使用隔离测试存档")
	_test_independent_conquest()
	_test_geography()
	_test_retired_automation()
	_test_new_save_roundtrip()
	print("[Zone conquest] 检查%d项，失败%d项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_independent_conquest() -> void:
	fixture()
	check(GameState.battle.size() == 21, "新野五个未征服区同时铺21张牌")
	check(GameState.city_slots(1) == 0 and not GameState.city_unlocked(), "未征服时没有建筑位")
	var generation := GameState.battle_gen
	var zero_positions: Array[Vector2] = []
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == 0: zero_positions.append(GameState.get_enemy_world_center(i))
	clear_zone(4)
	check(GameState.table_progress(1) == 1 and GameState.zone_cleared(1, 4), "先清第5区也永久征服")
	check(not GameState.zone_cleared(1, 0) and GameState.next_zone(1) == 0, "独立征服不伪造前序区进度")
	check(GameState.city_slots(1) == 1 and GameState.city_unlocked(), "任意首区解锁1个基建位")
	check(int(GameState.owned.get("B06", 0)) == 1 and int(GameState.owned.get("B08", 0)) == 1, "任意首区赠建筑库存，不依赖第1区")
	check(GameState.in_battle and GameState.battle_gen == generation, "清一区不结束本轮也不补堆")
	check(not GameState.place_building(1, "B06"), "战斗中不能装建筑")
	GameState.retreat()
	check(GameState.place_building(1, "B06"), "休息时已征服部分城可装农田")
	check(not GameState.place_building(1, "B08"), "仅1槽时水井仍留库存")
	check(is_equal_approx(GameState.advance_buildings(10.0), 4.0), "部分征服城农田在线产出有效")
	check(GameState.gold_per_hour() > 0.0, "部分征服城具有建筑挂机收益")
	check(GameState.start_battle(1), "可以继续未征服区")
	check(GameState.battle.size() == 15, "已清第5区重开不再出现")
	var remaining_zero: Array[Vector2] = []
	for i in range(GameState.battle.size()):
		check(int(GameState.battle[i].stage) != 4, "没有已征服区的复活牌")
		if int(GameState.battle[i].stage) == 0: remaining_zero.append(GameState.get_enemy_world_center(i))
	check(remaining_zero == zero_positions, "清其他区不改变第1区固定地理位置")
	for zone in range(4): clear_zone(zone)
	check(GameState.table_progress(1) == 5 and GameState.region_status(1) == "cleared", "所有分区独立征服后完成城池")
	check(not GameState.in_battle and GameState.battle.is_empty(), "全城完成直接结算不补牌")
	check(GameState.last_outcome.reason == "city_cleared", "战果标记全城征服")
	check(not GameState.start_battle(1) and not GameState.start_practice(1), "全清城拒绝挑战和练习重刷")
	check(GameState.city_slots(1) == 5, "5区提供5个建筑位")
	check(int(GameState.owned.get("B08", 0)) == 1, "后续清区不重复发首区水井")
	var gold := GameState.gold
	GameState.settle_run()
	check(is_equal_approx(GameState.gold, gold), "重复结算不重复收入")

func _test_geography() -> void:
	fixture()
	for region in GameData.regions:
		var idx := int(region.idx)
		GameState.region_state[idx] = "available"
		if idx == 21:
			for required in [9, 12, 20]: GameState.region_state[required] = "cleared"
		else:
			for previous in region.get("unlocked_by", []): GameState.region_state[int(previous)] = "cleared"
		check(GameState.start_battle(idx), "城池%d可铺所有未征服区" % idx)
		var details := GameState.zone_details(idx)
		check(details.size() == GameState.zone_count(idx), "城池%d小地图包含每个分区" % idx)
		for i in range(GameState.battle.size()):
			var zone := int(GameState.battle[i].stage)
			check(GameState.zone_rect(idx, zone).grow(-40).has_point(GameState.get_enemy_world_center(i)), "城池%d牌%d在归属分区边界内" % [idx, i])
		for a in range(details.size()):
			check(int(details[a].difficulty) >= 1 and int(details[a].difficulty) <= 5, "分区难度在1至5")
			for b in range(a): check(not (details[a].rect as Rect2).intersects(details[b].rect), "分区矩形不重叠")
		GameState.retreat()
		GameState.region_state[idx] = "available"

func _test_retired_automation() -> void:
	fixture()
	GameState.retreat()
	GameState.gold = 100000
	check(GameState.UPGRADES.size() == 10 and GameState.SKILL_TREE.size() == 10, "只保留10项非自动升级")
	for id in ["auto", "auto_next", "auto_power"]:
		check(not GameState.buy_upgrade(id), "不能购买退役升级%s" % id)
	check(not GameState.set_automation(true) and not GameState.automation_enabled, "自动公开入口拒绝开启")
	check(not GameState.auto_unlocked() and not GameState.practice_unlocked(), "自动与练习永久关闭")
	check(is_zero_approx(GameState.practice_rate()), "没有自动或离线练习工资")
	check(GameState.start_battle(1), "手动仍可出征")
	var before := GameState.run_damage
	GameState.automation_enabled = true
	GameState.advance_round(3.0)
	check(is_equal_approx(GameState.run_damage, before), "即使遗留开关为真也不会自动出手")
	GameState.stop_automation(false)
	GameState.retreat()

func _test_new_save_roundtrip() -> void:
	fixture()
	clear_zone(4)
	GameState.retreat()
	check(GameState.place_building(1, "B06", 0, 0), "新档部分城装配")
	GameState.save_game()
	var cash := GameState.gold
	GameState.cleared_zones.clear()
	check(GameState.load_game(), "新分区存档可读回")
	check(GameState.zone_cleared(1, 4) and not GameState.zone_cleared(1, 0), "新档独立保存乱序征服")
	check(GameState.city_slots(1) == 1 and GameState._building_at(1, 0) == "B06", "新档按已清区数保存槽位与建筑")
	check(is_equal_approx(GameState.gold, cash), "读档不产生旧升级退款（保存%.8f，读回%.8f）" % [cash, GameState.gold])
	check(not GameState.automation_enabled, "新档不恢复自动拍击")
	var path := GameState.save_path()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.erase("zone_system_version")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "测试档可写")
	if file == null: return
	file.store_string(JSON.stringify(raw))
	file.close()
	check(not GameState.load_game(), "没有分区版本标记的旧结构不迁移")
	GameState.save_game()
