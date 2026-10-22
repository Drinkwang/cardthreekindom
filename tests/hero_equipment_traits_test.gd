extends Node

var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func fixture(ids: Array) -> void:
	GameState.new_game()
	GameState.retreat()
	GameState.gold = 100000
	GameState.carry = ids.duplicate()
	GameState.up["equip"] = 5
	for id in ids: GameState.owned[id] = 1
	for card in GameData.cards:
		if str(card.get("type", "")) == "装备": GameState.owned[str(card["id"])] = 1

func set_point(index: int, point: Vector2) -> void:
	var area := GameState.battle_world_size() - Vector2(500, 500)
	GameState.battle[index]["nx"] = (point.x - 250.0) / area.x
	GameState.battle[index]["ny"] = (point.y - 250.0) / area.y

func prepare_movement(ids: Array = ["G00"]) -> Array:
	fixture(ids)
	GameState.start_battle(1)
	var indices := []
	for index in range(GameState.battle.size()):
		GameState.battle[index]["hp"] = 10000.0
		GameState.battle[index]["hp_max"] = 10000.0
		if int(GameState.battle[index]["stage"]) == 0: indices.append(index)
	var center := GameState.zone_rect(1, 0).get_center()
	set_point(int(indices[0]), center)
	set_point(int(indices[1]), center + Vector2(180, 0))
	set_point(int(indices[2]), center + Vector2(400, 0))
	return indices

func _ready() -> void:
	GameState.set_process(false)
	if GameState.save_path() == GameState.SAVE_PATH:
		push_error("必须使用 --test-profile，不能读取或写入正式存档")
		get_tree().quit(1)
		return
	_test_matching()
	_test_movement()
	_test_female_collectibles()
	GameState.new_game()
	print("HERO EQUIPMENT TRAITS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_matching() -> void:
	fixture(["G17", "G01", "G21"])
	check(GameState.equip_to("G17", "E01"), "休息时允许装备不契合物品")
	check(is_zero_approx(float(GameState.hero_equip_mods("G17")["power_pct"])), "无拍力特性的将不能凭空获得装备拍力")
	check(GameState.equipment_effect_text("G17", "E01").contains("不契合"), "装备预览明确说明不契合")
	check(GameState.equip_to("G01", "E01"), "装备自动转移仍有效")
	check(GameState.equip_owner("E01") == "G01", "转移后只有新武将拥有装备")
	check(is_equal_approx(float(GameState.hero_equip_mods("G01")["power_pct"]), 8), "已有拍力参数加8个百分点")
	GameState.bonus["equip_pct"] = 10
	check(is_equal_approx(float(GameState.equip_mods()["power_pct"]), 8.8), "军械坊仅放大一次契合参数")
	check(GameState.equip_to("G21", "E36"), "金币将装传国玉玺")
	check(is_equal_approx(float(GameState.hero_equip_mods("G21")["gold_pct"]), 132), "已有金币参数可增加")
	check(is_zero_approx(float(GameState.hero_equip_mods("G21")["all_pct"])), "全属性不能绕过不存在的原有特性")
	check(GameState.equipment_effect_text("G21", "E36").contains("不契合：全属性"), "混合装备预览逐项说明失配")
	fixture(["G00", "G19", "G01"])
	check(GameState.equip_to("G00", "E02"), "聚拢将可装长矛")
	check(is_equal_approx(float(GameState.hero_trait_params("G00")["gather_distance"]), 26), "原有聚拢18加长矛8等于26")
	check(is_zero_approx(float(GameState.hero_equip_mods("G00")["power_pct"])), "聚拢装备没有残留旧全队拍力")
	check(GameState.equip_to("G01", "E02"), "不契合的聚拢装备可以转移")
	check(GameState.hero_trait_params("G01").is_empty(), "长矛不会给无聚拢武将新建聚拢能力")
	check(GameState.equipment_effect_text("G01", "E02").contains("没有聚拢特性"), "聚拢装备解释具体缺少的特性")
	check(is_equal_approx(float(GameState.hero_trait_params("G00")["gather_distance"]), 18), "转走装备后立即恢复本来聚拢距离")
	check(is_equal_approx(float(GameState.hero_trait_params("G19")["gather_distance"]), 26), "廖化本来拥有聚拢26")

func _test_movement() -> void:
	var indices := prepare_movement()
	var center := GameState.zone_rect(1, 0).get_center()
	var other_zone := -1
	for index in range(GameState.battle.size()):
		if int(GameState.battle[index]["stage"]) == 1:
			other_zone = index
			break
	set_point(other_zone, center + Vector2(100, 0))
	var other_before := GameState.get_enemy_world_center(other_zone)
	var distant_before := GameState.get_enemy_world_center(int(indices[2]))
	check(GameState.begin_slap_batch(), "开始一掌范围拍击")
	check(GameState.attack(int(indices[0])) and GameState.attack(int(indices[1])), "一掌命中两张牌")
	var moved := GameState.apply_slap_displacement(center, indices.slice(0, 2))
	check(not moved.is_empty(), "有效手拍后发生聚拢")
	check(GameState.round_slaps == 1, "多个基础目标仍是一掌")
	check(is_equal_approx(GameState.get_enemy_world_center(int(indices[1])).distance_to(center), 162), "一掌两个目标仅聚拢18一次")
	check(GameState.get_enemy_world_center(other_zone).is_equal_approx(other_before), "其他区域即使在作用范围内也不移动")
	check(GameState.get_enemy_world_center(int(indices[2])).is_equal_approx(distant_before), "260范围外不移动")
	check(GameState.apply_slap_displacement(center, indices).is_empty(), "同一掌重复请求不重复移动")
	check(is_equal_approx(GameState.run_damage, GameState.click_damage() * 2), "聚拢只改变牌位不添加额外伤害")
	GameState.end_slap_batch()
	indices = prepare_movement(["G00", "G19"])
	GameState.begin_slap_batch()
	GameState.attack(int(indices[0]))
	GameState.apply_slap_displacement(center, indices.slice(0, 1))
	check(is_equal_approx(GameState.get_enemy_world_center(int(indices[1])).distance_to(center), 136), "两名聚拢将18加26等于44")
	GameState.end_slap_batch()
	indices = prepare_movement(["G17"])
	GameState.begin_slap_batch()
	GameState.attack(int(indices[0]))
	check(GameState.apply_slap_displacement(center, indices).is_empty(), "没有聚拢特性的队伍不位移")
	GameState.end_slap_batch()
	indices = prepare_movement()
	var bounds := GameState.zone_rect(1, 0).grow(-80)
	var edge := bounds.position + Vector2(1, 100)
	set_point(int(indices[0]), edge)
	set_point(int(indices[1]), edge + Vector2(8, 0))
	GameState.begin_slap_batch()
	GameState.attack(int(indices[0]))
	GameState.apply_slap_displacement(edge - Vector2(40, 0), indices.slice(0, 1))
	var point := GameState.get_enemy_world_center(int(indices[1]))
	check(point.x >= bounds.position.x and point.x <= bounds.end.x, "聚拢到边缘仍夹在原分区安全范围")
	check(int(GameState.battle[int(indices[1])]["stage"]) == 0, "聚拢不改变原分区归属")
	GameState.end_slap_batch()

func _test_female_collectibles() -> void:
	fixture([])
	var female_ids := ["G57", "G58", "G59", "G60", "G61", "G62", "G63", "G64"]
	var expected_names := ["黄月英", "貂蝉", "孙尚香", "大乔", "小乔", "甄宓", "蔡文姬", "祝融"]
	for index in range(female_ids.size()):
		var id: String = female_ids[index]
		check(GameData.card_name(id) == expected_names[index], "%s使用独立卡牌ID" % expected_names[index])
		check(GameState.is_hero(id), "%s可使用武将成长与收藏规则" % expected_names[index])
		GameState.owned[id] = 1
		check(GameState.carry_add(id), "%s可实际加入上阵构筑" % expected_names[index])
		GameState.carry_remove(id)
	var starter_ids := []
	for card in GameState._pack_pool(0): starter_ids.append(str(card["id"]))
	for id in ["G57", "G58", "G60", "G61", "G63"]:
		check(starter_ids.has(id), "%s在开局基础卡包候选池" % GameData.card_name(id))
	GameState.region_state[1] = "cleared"
	for pair in [["G59", 4], ["G62", 1], ["G64", 6]]:
		var pool_ids := []
		for card in GameState._pack_pool(int(pair[1])): pool_ids.append(str(card["id"]))
		check(pool_ids.has(pair[0]), "%s进入对应阵营卡包候选池" % GameData.card_name(str(pair[0])))
	fixture(["G57"])
	check(GameState.equip_to("G57", "E02"), "黄月英可装备聚拢兵器")
	check(is_equal_approx(float(GameState.hero_trait_params("G57")["gather_distance"]), 30), "黄月英聚拢22加长矛8等于30")
	check(preload("res://scripts/build_traits.gd").team_summary(["G57"])["title"] == "聚拢拍阵", "黄月英进入聚拢构筑说明")
	fixture(["G58"])
	check(is_equal_approx(float(GameState.active_mods()["click_pct"]), 10), "貂蝉提供点击伤害10%")
	check(is_equal_approx(GameState.fortune_mult(), 1.2), "貂蝉提供金币20%")
	fixture(["G59"])
	check(is_equal_approx(GameState.crit_chance(), 0.1), "孙尚香提供实际暴击率10%")
	fixture(["G60"])
	check(is_equal_approx(GameState.round_duration_value(), 33), "大乔延长基础30秒为33秒")
	fixture(["G61"])
	check(GameState.combo_gain() == 2, "小乔增加每次命中的连击积累")
	fixture(["G62"])
	check(is_equal_approx(float(GameState.active_mods()["power_pct"]), 35), "甄宓提供拍力35%")
	fixture(["G63"])
	check(is_equal_approx(GameState.round_duration_value(), 34), "蔡文姬固定增加4秒时长")
	fixture(["G64"])
	check(is_equal_approx(GameState.crit_chance(), 0.15), "祝融提供实际暴击率15%")
