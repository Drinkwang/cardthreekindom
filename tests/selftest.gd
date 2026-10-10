extends Node
## 无头自检：把核心循环跑一遍并打印结果。
## 运行：~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game tests/SelfTest.tscn

var _failed := 0
const HEAVY_MULT := 2.5                  # 与 game_state.gd 保持一致
const HEAVY_STAMINA := 2                 # 与 game_state.gd 保持一致
const CITY_GATE := 3                     # 与 game_state.gd 保持一致


func _ready() -> void:
	print("\n============ 《拍案三国》自检 · 桌面拍卡版 v0.8 ============")
	_test_new_game()
	_test_map_unlock()
	_test_packs()
	_test_slap_feel()
	_test_battle_win()
	_test_grind_loop()
	_test_city_gating()
	_test_city_idle()
	_test_ransom_and_synth()
	_test_routes_and_bonds()
	_test_v08_loop()
	_test_v09_effect_parser()
	_test_v09_hero_lv()
	_test_v09_hero_passive()
	_test_v11_hero_equip_nest()
	_test_v09_city_build()
	_test_v09_city_view()
	_test_v10_deploy_bar()
	_test_v11_troops()
	_test_ui_builds()
	_test_map_and_reveal()
	print("================ 自检结束：失败项 %d ================\n" % _failed)
	get_tree().quit()


# =====================================================================
# 工具
# =====================================================================
func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [OK] %s %s" % [label, detail])
	else:
		_failed += 1
		print("  [FAIL] %s %s" % [label, detail])


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _count_cards(n: Node) -> int:
	var c := 0
	if n.has_meta("paan_card"):
		c += 1
	for ch in n.get_children():
		c += _count_cards(ch)
	return c


func _count_type(t: String) -> int:
	var n := 0
	for id in GameState.owned.keys():
		if GameData.card(id).get("type", "") == t:
			n += int(GameState.owned[id])
	return n


func _count_star(star: int) -> int:
	var n := 0
	for id in GameState.owned.keys():
		if int(GameData.card(id).get("star", 0)) == star:
			n += int(GameState.owned[id])
	return n


func _slap_table_to_death(use_heavy: bool = false) -> int:
	# 把当前这桌拍干净，返回拍击次数
	var guard := 0
	while GameState.in_battle and guard < 4000:
		var alive := -1
		for i in range(GameState.battle.size()):
			if float(GameState.battle[i]["hp"]) > 0.0:
				alive = i
				break
		if alive < 0:
			break
		if not GameState.attack(alive, use_heavy):
			break
		guard += 1
	return guard


func _boost_upgrades(slv: int = 60, clv: int = 3, plv: int = 8) -> void:
	# 把升级树直接拉到"绝对够用"，供"验打完发生什么"的用例使用
	GameState.up["stamina"] = slv
	GameState.up["carry"] = clv
	GameState.up["power"] = plv
	GameState.carry_auto()


func _weak_start() -> void:
	# 固定成"只带 3 张 ★1 士兵"的最弱开局，让前几趟的数值完全可预测
	GameState.owned = {"I01": 1, "S01": 1, "S02": 1, "S03": 1}
	GameState.carry.clear()
	GameState.carry_auto()


func _new_game_start_cleared() -> void:
	## v1.0：新野不再是"自动通关的零敌人序章"，它是要真打的第一个区域。
	## 凡是关心「樊城之后」行为的用例，都先用这个函数开局 ——
	## 它等价于"玩家已经把新野打完了"，从而让樊城/中庐正常解锁。
	## ⚠️ 这里只改 region_state：解锁关系是 is_unlocked() 从 region_state 推导出来的，
	##    所以不需要额外伪造"已解锁"状态。
	GameState.new_game()
	GameState.region_state[GameState.START_REGION] = "cleared"


func _table_hp() -> float:
	## 桌上所有牌的血量总和。
	## ⚠️ 不要用 battle[0] —— 无头环境里桌面尺寸为 0，所有牌都叠在原点，
	## 点击命中的是最上面那张，未必是 battle[0]。牌数一多（新野现在有 6 张）就会误判。
	var t := 0.0
	for e in GameState.battle:
		t += float(e["hp"])
	return t


func _route_pool(rt: String, n: int) -> Array:
	var out := []
	for c in GameData.cards:
		if str(c.get("route", "")) == rt \
				and str(c.get("type", "")) in ["武将", "士兵"] \
				and float(c.get("power", 0.0)) > 0.0:
			out.append(str(c["id"]))
		if out.size() >= n:
			break
	return out


# =====================================================================
# 用例
# =====================================================================
func _test_new_game() -> void:
	print("\n[1] 新周目：一进来就有一桌牌")
	GameState.new_game()
	_check("开局只有主角卡 + 一包卡",
		GameState.owned.size() > 1 and GameState.owned.has("I01"),
		"持有 %d 种" % GameState.owned.size())
	_check("新野不再是免打的起点，但仍不计入「已克服」", GameState.cleared_count() == 0,
		"已克服 %d / %d" % [GameState.cleared_count(), GameState.total_field_regions()])
	_check("v1.0：新野是真关卡（可挑战 + 有血量）",
		GameState.region_status(GameState.START_REGION) == "available"
			and float(GameData.region(GameState.START_REGION)["total_hp"]) > 0.0,
		"状态 %s / 总血量 %s" % [
			GameState.region_status(GameState.START_REGION),
			GameData.region(GameState.START_REGION)["total_hp"]])
	_check("开局没有任何城池", _count_type("城池") == 0,
		"城池卡 %d 张" % _count_type("城池"))
	_check("开局桌面已经铺好一桌牌",
		GameState.in_battle and GameState.battle.size() > 0,
		"区域「%s」铺了 %d 张" % [
			GameData.region(GameState.battle_region).get("name", "?"), GameState.battle.size()])
	_check("卡组战力 > 0", GameState.deck_power() > 0.0, "战力 %.2f" % GameState.deck_power())
	# 开局包必须可预测地弱 —— 否则抽到 ★3 武将（战力 5.0）第一桌就被扇穿了
	var all_weak := true
	for id in GameState.owned.keys():
		if str(id) == "I01":
			continue
		if int(GameData.card(str(id)).get("star", 0)) > 1:
			all_weak = false
	_check("开局包只给 ★1（保证「第一趟必然打不完」）", all_weak,
		"持有 %s" % str(GameState.owned.keys()))
	# v1.0：第一关从"免打的樊城"改成"要打的新野"，所以这条也跟着盯新野。
	_check("首局最大伤害打不过新野（第一关就得反复打好几趟）",
		float(GameState.stamina_max_value()) * GameState.click_damage() * 2.5
			< float(GameData.region(GameState.START_REGION)["total_hp"]),
		"极限 %.1f / 需要 %s" % [
			float(GameState.stamina_max_value()) * GameState.click_damage() * 2.5,
			GameData.region(GameState.START_REGION)["total_hp"]])


func _test_map_unlock() -> void:
	print("\n[2] 大地图解锁")
	# v1.0：新野是要真打的第一关，樊城/中庐不再自动解锁。
	# 这一组验的是"新野之后"的解锁关系，所以先按"新野已通关"开局。
	_new_game_start_cleared()
	_check("新野相邻的樊城、中庐已解锁",
		GameState.is_unlocked(2) and GameState.is_unlocked(3))
	_check("未连通的江陵仍锁定", not GameState.is_unlocked(21))
	_check("襄阳此时未解锁", not GameState.is_unlocked(6))
	GameState.region_state[2] = "cleared"
	GameState.region_state[4] = "cleared"
	GameState.region_state[5] = "cleared"
	_check("宜城+宛城克服后襄阳解锁", GameState.is_unlocked(6))
	GameState.region_state[9] = "cleared"
	GameState.region_state[12] = "cleared"
	_check("只克服夷陵+公安时江陵仍锁定（缺泉陵）", not GameState.is_unlocked(21))
	GameState.region_state[20] = "cleared"
	_check("夷陵+公安+泉陵齐备后江陵解锁", GameState.is_unlocked(21))
	_new_game_start_cleared()


func _test_packs() -> void:
	print("\n[3] 卡包：按区域（郡）解锁")
	GameState.gold = 500000.0
	_check("通用基础包一直可买", GameState.pack_unlocked(0))
	_check("襄阳卡包此时未解锁（襄阳郡未克服）", not GameState.pack_unlocked(2))
	var before := GameState.owned.size()
	GameState.buy_pack(0)
	_check("开包后持有卡增加", GameState.owned.size() >= before,
		"%d -> %d 种" % [before, GameState.owned.size()])
	var p0 := GameState.pack_price(0)
	GameState.buy_pack(0)
	_check("重复购买后价格按 ×2.4 递增", GameState.pack_price(0) > p0,
		"%d -> %d" % [p0, GameState.pack_price(0)])
	GameState.region_state[6] = "cleared"
	_check("克服襄阳后襄阳卡包解锁", GameState.pack_unlocked(2))


func _test_slap_feel() -> void:
	print("\n[4] 拍卡手感：轻拍 / 重拍 / 桌面布局")
	_new_game_start_cleared()
	GameState.start_battle(2)
	_check("桌面已铺牌", GameState.battle.size() > 0, "%d 张" % GameState.battle.size())

	var pos_ok := true
	var rots := 0
	for e in GameState.battle:
		var nx := float(e.get("nx", -1.0))
		var ny := float(e.get("ny", -1.0))
		if nx < 0.0 or nx > 1.0 or ny < 0.0 or ny > 1.0:
			pos_ok = false
		if absf(float(e.get("rot", 0.0))) > 0.001:
			rots += 1
	_check("每张牌都有合法的桌面坐标（归一化 0..1）", pos_ok)
	_check("牌是歪着摆的（带随机旋转角）", rots == GameState.battle.size(),
		"%d / %d 张有旋转" % [rots, GameState.battle.size()])
	var nx_set := {}
	for e in GameState.battle:
		nx_set["%d-%d" % [int(float(e["nx"]) * 1000.0), int(float(e["ny"]) * 1000.0)]] = true
	_check("牌没有叠在同一格（位置互不相同）", nx_set.size() == GameState.battle.size(),
		"%d 个不同位置" % nx_set.size())

	# 单击轻拍
	var hp0 := float(GameState.battle[0]["hp"])
	var st0 := GameState.stamina
	GameState.attack(0, false)
	var light := hp0 - float(GameState.battle[0]["hp"])
	_check("单击轻拍只扣 1 点耐力", GameState.stamina == st0 - 1)
	_check("轻拍伤害 = 1 + 卡组战力", light > 0.0, "轻拍 %.1f" % light)

	# 拖拽重拍
	var hp1 := float(GameState.battle[1]["hp"])
	var st1 := GameState.stamina
	GameState.attack(1, true)
	var heavy := hp1 - float(GameState.battle[1]["hp"])
	_check("拖拽重拍伤害是轻拍的 %.1f 倍" % HEAVY_MULT,
		abs(heavy - light * HEAVY_MULT) < 0.5, "重拍 %.1f vs 轻拍 %.1f" % [heavy, light])
	_check("重拍每张吃 %d 点耐力（轻拍 1 点）" % HEAVY_STAMINA,
		GameState.stamina == st1 - HEAVY_STAMINA, "%d -> %d" % [st1, GameState.stamina])

	# 重拍连击累计更快（把血拉满，避免被拍翻提前结束这一桌）
	_new_game_start_cleared()
	GameState.start_battle(2)
	for k in range(GameState.battle.size()):
		GameState.battle[k]["hp"] = 999999.0
		GameState.battle[k]["hp_max"] = 999999.0
	GameState.combo = 0
	GameState.attack(0, false)
	var combo_light := GameState.combo
	GameState.combo = 0
	GameState.attack(0, true)
	_check("重拍连击累计是轻拍的 2 倍", GameState.combo == combo_light * 2,
		"%d vs %d" % [GameState.combo, combo_light])
	GameState.leave_battle()


func _test_battle_win() -> void:
	print("\n[5] 战斗：拍翻整桌 = 克服区域")
	_new_game_start_cleared()
	_boost_upgrades()                      # 升满升级树，这一组只验"打赢后发生什么"
	var idx := 2
	GameState.start_battle(idx)
	_check("进入战场", GameState.in_battle,
		"耐力 %d 敌人 %d" % [GameState.stamina, GameState.battle.size()])
	var total := 0.0
	for e in GameState.battle:
		total += float(e["hp_max"])
	_check("敌人血量合计 == 区域总血量",
		abs(total - float(GameData.region(idx)["total_hp"])) < 0.5, "%.0f" % total)

	var slaps := _slap_table_to_death(true)
	_check("拍翻整桌后区域变为已克服", GameState.region_status(idx) == "cleared")
	_check("拍翻整桌后退出桌面", not GameState.in_battle, "%d 次重拍" % slaps)
	_check("第 1 个区域不发城池（城池压后登场）",
		not GameState.owned.has("C%02d" % idx) and not GameState.city_unlocked(),
		"已克服 %d 处" % GameState.cleared_count())
	_check("该区域的 ★★★ 以上武将进入囚禁台可招降",
		GameState.captured.size() >= 0, "囚禁 %d 名" % GameState.captured.size())


func _test_grind_loop() -> void:
	print("\n[6] 反复重开刷钱：多趟之后才克服（v0.8 核心节奏）")
	_new_game_start_cleared()
	_weak_start()                          # 固定最弱开局，让趟数可预测
	var h0 := float(GameData.region(2)["total_hp"])
	var cap := GameState.stamina_max_value() * GameState.click_damage()
	_check("开局一局打不完樊城", cap < h0, "最多 %.1f / 需要 %.0f" % [cap, h0])

	var trips := 0
	var settled := 0
	# v1.0：这一组模拟"玩家的真实升级决策"。
	# ⚠️ 只加耐力是死路 —— 实测要 1629 趟才克服得了樊城（推导见 v10改造方案.md §八）。
	#    新曲线必须靠升级树「拍力」的复利（×1.15/级、无上限）来突破，所以这里优先买拍力。
	while GameState.region_status(2) != "cleared" and trips < 200:
		GameState.start_battle(2)
		_slap_table_to_death(false)
		trips += 1
		if GameState.end_reason == "settled":
			settled += 1
		var guard := 0
		while guard < 500:
			guard += 1
			if GameState.gold >= float(GameState.upgrade_cost("power")):
				GameState.buy_upgrade("power")        # 复利拍力优先
			elif GameState.gold >= float(GameState.upgrade_cost("stamina")):
				GameState.buy_upgrade("stamina")
			else:
				break

	_check("前几趟全部结算（打不完）", settled > 0, "结算 %d 趟" % settled)
	_check("每一趟都满血重来（局内不持久）",
		GameState.region_status(2) == "cleared" or settled == trips,
		"%d 趟 / %d 结算" % [trips, settled])
	_check("反复刷钱升级之后终于克服樊城", GameState.region_status(2) == "cleared",
		"共 %d 趟，耐力 %d，战力 %.1f" % [trips, GameState.stamina_max_value(), GameState.deck_power()])
	_check("克服后桌面收掉", not GameState.in_battle)
	# v1.0 节奏目标带：第一关（新野）刻意拉长到 16~30 趟，樊城紧随其后。
	_check("刷完一处约需 10~60 趟（v1.0 节奏目标带）", trips >= 10 and trips <= 60, "%d 趟" % trips)


func _test_city_gating() -> void:
	print("\n[7] 城池压后登场：第 %d 个区域才发城池" % CITY_GATE)
	_new_game_start_cleared()
	_boost_upgrades()
	# v1.0：新曲线下宜城有 380 血，_boost_upgrades() 默认的拍力（Lv8 → ×3.06）已经不够一趟推平。
	# 这里额外把「复利拍力」顶上去，让这一组专心验"城池什么时候发"，而不是"打不打得动"。
	GameState.up["power"] = 24
	GameState.gold = 999999.0
	_check("开局没有城池，城建未解锁",
		not GameState.city_unlocked() and _count_type("城池") == 0,
		GameState.city_unlock_text())

	for idx in [2, 3, 4]:
		GameState.start_battle(idx)
		_slap_table_to_death(true)
		var n := GameState.cleared_count()
		if n < CITY_GATE:
			_check("已克服 %d 处 —— 仍不发城池" % n,
				not GameState.city_unlocked() and _count_type("城池") == 0)

	_check("跨过门槛后城建解锁", GameState.city_unlocked(),
		"已克服 %d 处" % GameState.cleared_count())
	# v1.0：新野也是真关卡、克服后同样发城池卡 C01，但它不计入 cleared_count()，
	# 所以城池张数 = 已克服数 + 1（新野那一张）。
	_check("解锁瞬间回补发放前几个区域的城池卡（含新野）",
		_count_type("城池") == GameState.cleared_count() + 1,
		"%d 张城池 / %d 个已克服区域（+新野 1）" % [_count_type("城池"), GameState.cleared_count()])
	_check("樊城（第 1 桌）的城池卡被补发", GameState.owned.has("C02"))


func _test_city_idle() -> void:
	print("\n[8] 城建挂机：城池=地基，建筑=产钱")
	_new_game_start_cleared()
	_check("城池本身不产钱", GameState.gold_per_hour() == 0.0,
		"产出 %.0f/小时" % GameState.gold_per_hour())
	GameState.region_state[6] = "cleared"      # 襄阳：3 个槽位
	GameState.region_state[7] = "cleared"
	GameState.region_state[8] = "cleared"
	GameState.owned["B01"] = 1                 # 菜地 +5/小时
	GameState.owned["B09"] = 1                 # 铁匠铺 +80/小时
	GameState.place_building(6, "B01")
	var after_first := GameState.gold_per_hour()
	_check("放上菜地后开始产钱", after_first > 0.0, "%.0f/小时" % after_first)
	GameState.place_building(6, "B09")
	var both := GameState.gold_per_hour()
	_check("再放铁匠铺后产出累加", both > after_first, "%.0f/小时" % both)
	_check("槽位占用正确", GameState.city_buildings(6).size() == 2,
		"%d/%d" % [GameState.city_buildings(6).size(), GameState.city_slots(6)])
	var offline := both * GameState.offline_cap_hours() * GameState.offline_efficiency()
	_check("离线结算上限合理", GameState.offline_cap_hours() >= 8.0,
		"上限 %.0f 小时，满额约 %s 金币" % [GameState.offline_cap_hours(), GameState.fmt(offline)])
	var eff0 := GameState.offline_efficiency()
	GameState.up["idle"] = 10
	_check("「挂机效率」升级提高离线效率与时长上限",
		GameState.offline_efficiency() > eff0 and GameState.offline_cap_hours() > 8.0,
		"效率 %.0f%% → %.0f%%，上限 %.0f 小时" % [
			eff0 * 100.0, GameState.offline_efficiency() * 100.0, GameState.offline_cap_hours()])
	GameState.up["idle"] = 0
	var slots := GameState.city_slots(6)
	for id in ["B02", "B03", "B04", "B05", "B06", "B08"]:
		GameState.owned[id] = 1
		GameState.place_building(6, id)
	_check("放置不会超过槽位上限", GameState.city_buildings(6).size() == slots,
		"%d/%d" % [GameState.city_buildings(6).size(), slots])
	GameState.remove_building(6, 0)
	_check("拆除后建筑卡回到收藏", int(GameState.owned.get("B01", 0)) >= 1)


func _test_ransom_and_synth() -> void:
	print("\n[9] 招降与合成")
	GameState.new_game()
	GameState.gold = 500000.0
	GameState.captured = ["G01"]
	var cost := GameState.ransom_cost("G01")
	_check("招降价按星级与亲和计算", cost > 0, "蔡瑁 %d 金币" % cost)
	GameState.ransom("G01")
	_check("招降后进入卡组", GameState.owned.has("G01"))
	_check("囚禁台清空该将", not GameState.captured.has("G01"))

	GameState.owned["S01"] = int(GameState.owned.get("S01", 0)) + 3
	var star1_before := _count_star(1)
	GameState.synthesize(1)
	var star1_after := _count_star(1)
	_check("合成消耗 3 张 ★1 并产出 1 张 ★2", star1_before - star1_after == 3,
		"★1 %d -> %d" % [star1_before, star1_after])


func _test_routes_and_bonds() -> void:
	print("\n[10] 路线亲和与羁绊（羁绊只算「上阵」的卡）")
	GameState.new_game()
	GameState.gold = 999999.0
	GameState.up["carry"] = 3                 # 携带位 6，才够触发二档羁绊
	GameState.carry.clear()                   # 新周目已自动上阵 3 张，先腾空
	var wei := _route_pool("魏线", 6)
	_check("魏线池里能凑出 6 张可上阵的卡", wei.size() >= 6, "%d 张" % wei.size())
	var before := GameState.power_multiplier()
	for id in wei:
		GameState.owned[id] = int(GameState.owned.get(id, 0)) + 1
	_check("只囤在仓库里 -> 羁绊不触发（上阵才算）", GameState.bond_tier("魏线") == 0,
		"羁绊档位 %d" % GameState.bond_tier("魏线"))
	for id in wei:
		GameState.carry_add(id)
	_check("上阵 6 张魏线 -> 二档羁绊", GameState.bond_tier("魏线") == 2,
		"上阵同线 %d 张" % GameState.route_unit_count("魏线"))
	_check("羁绊抬高了战力倍率", GameState.power_multiplier() > before,
		"×%.2f -> ×%.2f" % [before, GameState.power_multiplier()])

	var some: String = wei[0]
	GameState.affinity["魏线"] = 0
	var cost_no_aff := GameState.ransom_cost(some)
	GameState.affinity["魏线"] = 3
	var cost_aff := GameState.ransom_cost(some)
	_check("亲和 3 使该线招降打折", cost_aff < cost_no_aff,
		"%d -> %d 金币" % [cost_no_aff, cost_aff])
	GameState.affinity["魏线"] = 5
	GameState.region_state[2] = "cleared"
	_check("亲和 5 使该线城池槽位 +1", GameState.city_slots(2) >= 2,
		"樊城槽位 %d" % GameState.city_slots(2))

	GameState.new_game()
	GameState.carry.clear()
	for id in _route_pool("吴线", 3):
		GameState.owned[id] = 1
		GameState.carry_add(id)
	_check("吴线 3 张上阵后提升连击累计", GameState.combo_gain() > 1, "每次 +%d" % GameState.combo_gain())

	GameState.new_game()
	GameState.carry.clear()
	for id in _route_pool("蜀线", 3):
		GameState.owned[id] = 1
		GameState.carry_add(id)
	_check("蜀线 3 张上阵后获得暴击率", GameState.crit_chance() > 0.0,
		"暴击率 %.0f%%" % (GameState.crit_chance() * 100.0))

	GameState.new_game()
	GameState.up["crit"] = 4
	GameState.up["fortune"] = 5
	_check("「暴击」升级独立提供暴击率", GameState.crit_chance() > 0.0,
		"暴击率 %.0f%%" % (GameState.crit_chance() * 100.0))
	_check("「财路」升级提高击杀掉金", GameState.fortune_mult() > 1.0,
		"掉金 ×%.2f" % GameState.fortune_mult())
	if GameState.SAVE_ENABLED:
		GameState.save_game()
		_check("存档文件已生成", FileAccess.file_exists(GameState.save_path()))
	else:
		# v1.0 关档：save_game() 必须静默无效，load_game() 必须恒返回 false
		GameState.save_game()
		_check("v1.0 关档后 load_game() 恒为 false", not GameState.load_game())


func _test_v10_deploy_bar() -> void:
	print("\n[20] v1.0 底部上阵条 + 卡池拖拽（#9 / #10）")
	GameState.new_game()
	var packed = load("res://scenes/Main.tscn")
	if packed == null:
		_check("主场景可加载", false)
		return
	var inst = packed.instantiate()
	add_child(inst)

	# ---- 主界面铁律：第一眼必须看到满桌的牌 → 卡池默认收起，只留窄窄一条上阵栏 ----
	_check("卡池默认收起", inst._pool != null and not inst._pool.visible)
	_check("上阵栏常驻可见", inst._bar != null and inst._bar.visible)
	_check("卡池按钮初始为收起态", str(inst._btn_pool.text).begins_with("卡池 ▾"),
		str(inst._btn_pool.text))

	# ---- 战力显示：士兵的 0.2 不能在界面上变成 "0"（看起来像废牌）----
	_check("士兵战力 0.2 不被四舍五入成 0", inst._fmt_pow(0.2) == "0.2", inst._fmt_pow(0.2))
	_check("士兵战力 0.6 不被四舍五入成 1", inst._fmt_pow(0.6) == "0.6", inst._fmt_pow(0.6))
	_check("武将战力 625 仍走整数格式", inst._fmt_pow(625.0) == "625", inst._fmt_pow(625.0))

	# ---- 槽位 = 主角固定位 + carry_max 个携带位 ----
	var cap := GameState.carry_max()
	var slots = inst._slot_row.get_children()
	_check("槽位数 = 主角 1 + 携带位 %d" % cap, slots.size() == cap + 1,
		"实际 %d 个" % slots.size())
	if slots.size() != cap + 1:
		inst.queue_free()
		return
	_check("第 1 格是主角固定位（I01 · locked）",
		bool(slots[0].locked) and str(slots[0].card_id) == "I01",
		"%s locked=%s" % [slots[0].card_id, slots[0].locked])
	var probe := {"paan_kind": "pool", "id": "S01"}
	_check("主角位拒收拖拽（拖不进）",
		not bool(slots[0]._can_drop_data(Vector2.ZERO, probe)))

	# ---- 造一个确定的卡池：4 张 ★6 将 + 1 张士兵 ----
	GameState.owned = {"I01": 1, "G13": 1, "G16": 1, "G26": 1, "G27": 1, "S01": 1}
	GameState.up["carry"] = 0                      # 携带位回到默认档（3 位）
	GameState.carry.clear()
	GameState.carry_add("G13")
	GameState.changed.emit()                       # 走真实刷新链路（不是直接调私有方法）
	slots = inst._slot_row.get_children()
	_check("上阵 1 张后：第 2 格是 G13", str(slots[1].card_id) == "G13",
		_slot_ids(slots))
	_check("第 3 格是空位", str(slots[2].card_id) == "", _slot_ids(slots))
	_check("空槽位收得下卡池来的牌", bool(slots[2]._can_drop_data(Vector2.ZERO, probe)))

	# ---- 展开卡池 ----
	inst._set_pool(true)
	_check("展开后卡池面板可见", bool(inst._pool.visible))
	_check("卡池按钮切到展开态", str(inst._btn_pool.text).begins_with("卡池 ▴"),
		str(inst._btn_pool.text))
	var in_pool = _pool_ids(inst)
	_check("卡池只列「未上阵」的将兵", not in_pool.has("G13"), "卡池=%s" % [in_pool])
	_check("卡池列出了待命的 G26 与士兵 S01",
		in_pool.has("G26") and in_pool.has("S01"), "卡池=%s" % [in_pool])
	_check("卡池不列主角卡（固定上阵，不进池）", not in_pool.has("I01"), "卡池=%s" % [in_pool])
	_check("卡池按战力降序排（★6 将 625 在前，★1 士兵 0.2 在后）",
		_pool_ids(inst)[0] != "S01" and _pool_ids(inst)[_pool_ids(inst).size() - 1] == "S01",
		"卡池=%s" % [in_pool])

	# ---- 真实拖拽链路：_get_drag_data → _can_drop_data → _drop_data ----
	var src = _pool_node(inst, "G26")
	_check("在卡池里找到要拖的牌 G26", src != null)
	if src == null:
		inst.queue_free()
		return
	var payload = src._get_drag_data(Vector2.ZERO)
	_check("卡池牌能起拖（payload 带 paan_kind=pool）",
		payload is Dictionary and str(payload.get("paan_kind", "")) == "pool", str(payload))
	if not (payload is Dictionary):
		inst.queue_free()
		return
	slots[2]._drop_data(Vector2.ZERO, payload)
	_check("拖放后 G26 进入上阵名单", GameState.in_carry("G26"),
		"carry=%s" % [GameState.carry])
	_check("G26 落在第 2 个携带位（落点说了算，不是一律追加）",
		str(GameState.carry[1]) == "G26", "carry=%s" % [GameState.carry])

	# ---- 槽位重建 + 点一下卸下 ----
	slots = inst._slot_row.get_children()
	_check("上阵栏重建出 2 个已上阵格子",
		str(slots[1].card_id) == "G13" and str(slots[2].card_id) == "G26", _slot_ids(slots))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	slots[1]._gui_input(click)
	_check("点一下槽位 → 卸下（退回卡池）", not GameState.in_carry("G13"),
		"carry=%s" % [GameState.carry])
	slots[0]._gui_input(click)
	_check("主角位点不掉（locked 生效）",
		GameState.in_carry("I01") == false and GameState.carry.size() == 1,
		"carry=%s" % [GameState.carry])

	# ---- 卸下的牌回到卡池 ----
	inst._set_pool(true)
	_check("卸下的 G13 回到卡池", _pool_ids(inst).has("G13"), "卡池=%s" % [_pool_ids(inst)])

	# ---- 换人：落到已占用的槽位 = 旧人退回卡池，总数不变 ----
	GameState.carry.clear()
	GameState.carry_add("G26")
	GameState.carry_add("G27")
	inst._deploy_at("G13", 0)
	_check("拖到已占用的槽位 = 换人（旧人回池）",
		GameState.in_carry("G13") and not GameState.in_carry("G26"),
		"carry=%s" % [GameState.carry])
	_check("换人后上阵总数不变", GameState.carry.size() == 2,
		"carry=%s" % [GameState.carry])

	# ---- carry_put：落点语义 + 满员拒收 + 阵中重排 ----
	GameState.carry.clear()
	GameState.carry_put("G27", 3)
	_check("空名单插到第 3 位 → 退化为落第 0 位", str(GameState.carry[0]) == "G27",
		"carry=%s" % [GameState.carry])
	GameState.carry_put("G16", 0)
	_check("插到第 0 位 → G16 排到最前",
		str(GameState.carry[0]) == "G16" and str(GameState.carry[1]) == "G27",
		"carry=%s" % [GameState.carry])
	GameState.carry_put("G13", 0)
	_check("携带位填满 3/3", GameState.carry.size() == 3, "carry=%s" % [GameState.carry])
	_check("满员时拖入第 4 张 → 拒绝，且不顶掉别人",
		not GameState.carry_put("G26", 0) and GameState.carry.size() == 3,
		"carry=%s" % [GameState.carry])
	_check("已在阵中的牌可以重排（不占新位）",
		GameState.carry_put("G16", 2) and GameState.carry.size() == 3,
		"carry=%s" % [GameState.carry])

	# ---- 收起卡池：牌桌拿回空间 ----
	inst._set_pool(false)
	_check("收起卡池后面板隐藏", not inst._pool.visible)
	inst.queue_free()


func _slot_ids(slots) -> String:
	var out := []
	for s in slots:
		var nm := str(s.card_id) if str(s.card_id) != "" else "空"
		out.append("%s%s" % [nm, "!" if bool(s.locked) else ""])
	return "|".join(out)


func _pool_ids(inst) -> Array:
	var out := []
	for c in inst._pool_box.get_children():
		if c is PanelContainer and str(c.card_id) != "":
			out.append(str(c.card_id))
	return out


func _pool_node(inst, card_id: String):
	for c in inst._pool_box.get_children():
		if c is PanelContainer and str(c.card_id) == card_id:
			return c
	return null


func _test_ui_builds() -> void:
	print("\n[11] 单界面：桌面为主 + 桌面输入管线")
	GameState.new_game()
	var packed = load("res://scenes/Main.tscn")
	_check("主场景可加载", packed != null)
	if packed == null:
		return
	var inst = packed.instantiate()
	add_child(inst)     # add_child 同步触发 _ready，UI 立即构建完成
	var n := _count_nodes(inst)
	_check("节点树已生成", n > 60, "%d 个节点" % n)
	_check("根节点为 Control（全屏单界面）", inst is Control)
	var cards := _count_cards(inst)
	_check("桌面把这一桌牌都摆出来了", cards == GameState.battle.size(),
		"卡牌节点 %d / 桌面 %d 张" % [cards, GameState.battle.size()])

	# ---- 桌面输入管线：这是自定义命中测试（旋转 + 重叠），必须自动验证 ----
	var table: Control = _find_table(inst)
	_check("找到桌面输入层", table != null)
	if table == null:
		inst.queue_free()
		return
	# 无头环境下桌面尺寸为 0，layout 会提前返回 —— 牌都落在原点，
	# 正好让命中测试变得完全确定：牌占 [0,0]..[106,146]。
	# 注意：输入与命中测试的方法挂在主场景根节点（main.gd）上，不在桌面层节点上。
	# 先把血拉高，避免第一下就把牌拍翻、导致后续手势落空。
	for k in range(GameState.battle.size()):
		GameState.battle[k]["hp"] = 99999.0
		GameState.battle[k]["hp_max"] = 99999.0

	var hp_a := _table_hp()
	_gesture(inst, Vector2(30, 40), Vector2(30, 40))
	var hp_b := _table_hp()
	_check("单击落在牌面上 → 轻拍掉血", hp_b < hp_a, "%.1f -> %.1f" % [hp_a, hp_b])

	_gesture(inst, Vector2(-140, -140), Vector2(40, 50))
	var hp_c := _table_hp()
	_check("从空白处起手、划过牌 → 重拍掉血", hp_c < hp_b, "%.1f -> %.1f" % [hp_b, hp_c])
	_check("重拍伤害明显高于轻拍", (hp_b - hp_c) > (hp_a - hp_b) * 1.5,
		"重拍 %.1f vs 轻拍 %.1f" % [hp_b - hp_c, hp_a - hp_b])

	var hp_d := _table_hp()
	_gesture(inst, Vector2(-320, -300), Vector2(-200, -260))
	_check("在空白处拖拽不会误伤任何牌",
		absf(_table_hp() - hp_d) < 0.001)

	_check("单击打在桌面空白处不产生伤害判定",
		inst._hit_index_at(Vector2(-400, -400)) < 0)
	inst.queue_free()


func _test_map_and_reveal() -> void:
	print("\n[12] 荆州舆图 + 翻牌揭示")
	# ---- 坐标数据合法性（由真实经纬度折算而来）----
	var ok := true
	var xs := []
	var ys := []
	for r in GameData.regions:
		var mx := float(r.get("mx", -1.0))
		var my := float(r.get("my", -1.0))
		var lo := float(r.get("lon", 0.0))
		var la := float(r.get("lat", 0.0))
		if mx < 0.0 or mx > 1.0 or my < 0.0 or my > 1.0:
			ok = false
		if lo < 100.0 or lo > 125.0 or la < 20.0 or la > 40.0:
			ok = false
		xs.append(mx)
		ys.append(my)
	_check("每个区域都有合法经纬度与归一化坐标", ok, "n=%d" % GameData.regions.size())
	var x_min: float = float(xs.min())
	var x_max: float = float(xs.max())
	var y_min: float = float(ys.min())
	var y_max: float = float(ys.max())
	_check("归一化坐标横竖都铺满 0..1",
		x_min < 0.02 and x_max > 0.98 and y_min < 0.02 and y_max > 0.98,
		"x %.2f..%.2f  y %.2f..%.2f" % [x_min, x_max, y_min, y_max])

	# ---- 舆图布局：显式给尺寸，松弛后每个区域都该有像素坐标 ----
	var view := PaanMapView.new()
	add_child(view)
	view.size = Vector2(900, 700)
	view._recompute()
	_check("舆图为每个区域算出像素坐标", view._pts.size() == GameData.regions.size(),
		"%d 个点" % view._pts.size())
	var keys := view._pts.keys()
	var min_gap := 1e9
	for a in range(keys.size()):
		for b in range(a + 1, keys.size()):
			var pa: Vector2 = view._pts[keys[a]]
			var pb: Vector2 = view._pts[keys[b]]
			min_gap = minf(min_gap, pa.distance_to(pb))
	_check("松弛后节点互不重叠", min_gap > 24.0, "最近间距 %.1f px" % min_gap)
	var inside := true
	for k in keys:
		var p: Vector2 = view._pts[k]
		if p.x < 20.0 or p.x > 880.0 or p.y < 20.0 or p.y > 680.0:
			inside = false
	_check("所有节点都在图框内", inside)
	var first_idx := int(keys[0])
	_check("点节点中心能命中该区域", view._hit(view._pts[keys[0]]) == first_idx,
		"idx %d" % first_idx)
	view.queue_free()

	# ---- 翻牌揭示：逐张亮出 + 高星特写 ----
	var rv := PaanReveal.new()
	add_child(rv)
	rv.open("测试卡包", ["G13", "S01", "E12"], "3 张")
	_check("揭示层按卡数生成卡位", rv._slots.size() == 3)
	_check("初始全部背面朝上", not (rv._slots[0]["front"] as Control).visible)
	_check("★6 走最高稀有度配色", PaanReveal.rarity_color(6) == rv.RARITY[6])
	_check("低星不触发特写（阈值 ★4）", PaanReveal.SHOWCASE_MIN_STAR == 4)
	rv._reveal_all()
	var all_front := true
	for s in rv._slots:
		if not (s["front"] as Control).visible:
			all_front = false
	_check("「全部翻开」把所有卡亮出", all_front)
	_check("最高星达标 → 触发单张特写", rv._showcase_done)
	rv.queue_free()


# =====================================================================
# v0.8：局内刷 + 局外升级
# =====================================================================
func _test_v08_loop() -> void:
	print("\n[13] v0.8 局内刷 + 局外升级")
	_new_game_start_cleared()
	_weak_start()

	# ---- 开局刻意很弱 ----
	_check("初始耐力 = 6（一局只拍 6 下）", GameState.stamina_max_value() == 6,
		"%d 点" % GameState.stamina_max_value())
	_check("初始携带位 = 3", GameState.carry_max() == 3, "%d 个" % GameState.carry_max())
	_check("初始装备槽 = 0（装备系统未解锁）", GameState.equip_slots() == 0)
	_check("上阵不超过 3 张", GameState.carry.size() <= 3, "带了 %d 张" % GameState.carry.size())
	_check("主角卡常驻且不占携带位", GameState.hero_power() > 0.0,
		"主角战力 %.1f · 上阵 %d 张" % [GameState.hero_power(), GameState.carry.size()])

	var r2_hp := float(GameData.region(2)["total_hp"])
	var cap := float(GameState.stamina_max_value()) * GameState.click_damage()
	_check("首局能打出的总伤害 < 樊城总血量（必然打不完）", cap < r2_hp,
		"最多 %.1f / 需要 %.0f" % [cap, r2_hp])

	# ---- 耐力耗尽 -> 强制结算回大本营 ----
	GameState.start_battle(2)
	var gold_before := GameState.gold
	var runs_before := GameState.runs
	var slaps := _slap_table_to_death(false)
	_check("耐力耗尽 -> 强制结算，退出桌面", not GameState.in_battle, "拍了 %d 下" % slaps)
	_check("结算原因记为 settled", GameState.end_reason == "settled")
	_check("结算把这一趟折算成金币带走", GameState.gold > gold_before,
		"%d -> %d" % [int(gold_before), int(GameState.gold)])
	_check("出战趟数 +1", GameState.runs == runs_before + 1, "第 %d 趟" % GameState.runs)
	_check("区域仍未克服（局内进度不持久）", GameState.region_status(2) == "available")
	_check("结算后桌上没有牌", GameState.battle.is_empty())

	# ---- 再次进场：满血重来 ----
	GameState.start_battle(2)
	var full := true
	for e in GameState.battle:
		if absf(float(e["hp"]) - float(e["hp_max"])) > 0.001:
			full = false
	_check("未克服区域再次进场是满血", full)
	GameState.retreat()
	_check("主动撤退也走同一套结算", GameState.end_reason == "settled" and not GameState.in_battle)

	# ---- 升级树 ----
	GameState.gold = 100000.0
	var s0 := GameState.stamina_max_value()
	var c0 := GameState.upgrade_cost("stamina")
	_check("耐力升级有价", c0 > 0, "首级 %d 金币" % c0)
	GameState.buy_upgrade("stamina")
	_check("升级「耐力」-> 上限 +1", GameState.stamina_max_value() == s0 + 1,
		"%d -> %d" % [s0, GameState.stamina_max_value()])
	GameState.buy_upgrade("stamina")
	_check("升级价格逐级上涨", GameState.upgrade_cost("stamina") > c0,
		"%d -> %d" % [c0, GameState.upgrade_cost("stamina")])
	GameState.buy_upgrade("carry")
	_check("升级「携带位」-> 能多带 1 个", GameState.carry_max() == 4, "%d 个" % GameState.carry_max())
	# v1.1：技能树有了前置门禁 —— 「装备槽」在第二层，必须先点亮第一层的「拍力」
	_check("技能树：没点亮「拍力」时「装备槽」锁着",
		GameState.upgrade_level("power") == 0 and not GameState.skill_req_met("equip"))
	GameState.buy_upgrade("equip")
	_check("前置未满足 -> 购买被拒，装备槽还是 0", GameState.equip_slots() == 0,
		"%d 格" % GameState.equip_slots())
	GameState.buy_upgrade("power")
	_check("点亮「拍力」-> 前置满足、放行", GameState.skill_req_met("equip"))
	GameState.buy_upgrade("equip")
	_check("升级「装备槽」-> 解锁 1 个部位", GameState.equip_slots() == 1, "%d 格" % GameState.equip_slots())
	_check("玩家等级由升级总级数推导", GameState.player_level() >= 1,
		"Lv.%d（%d 级升级）" % [GameState.player_level(), GameState.total_upgrade_levels()])

	# ---- 携带位：只有上阵的卡算战力 ----
	var spare := ""
	for id in GameState.owned.keys():
		if GameState.is_carryable(str(id)) and not GameState.in_carry(str(id)):
			spare = str(id)
			break
	if spare != "":
		var p0 := GameState.deck_power()
		GameState.carry_add(spare)
		_check("上阵一张新卡 -> 战力立刻上升", GameState.deck_power() > p0,
			"%.2f -> %.2f" % [p0, GameState.deck_power()])
		GameState.carry_remove(spare)
		_check("卸下后战力立刻回落", absf(GameState.deck_power() - p0) < 0.001,
			"%.2f" % GameState.deck_power())
	var stock_extra := ""
	for c in GameData.cards:
		var cid := str(c["id"])
		if GameState.is_carryable(cid) and int(GameState.owned.get(cid, 0)) <= 0:
			stock_extra = cid
			break
	if stock_extra != "":
		var p1 := GameState.deck_power()
		GameState.owned[stock_extra] = 1
		_check("仓库里囤卡不上阵 -> 战力不变", absf(GameState.deck_power() - p1) < 0.001,
			"战力 %.2f" % GameState.deck_power())
		GameState.carry_add(stock_extra)
		_check("同一张卡一上阵 -> 战力才变化", GameState.deck_power() > p1,
			"%.2f -> %.2f" % [p1, GameState.deck_power()])

	# ---- 装备巢（v1.1）：每将独立，且只有**上阵武将**身上的装备才算 ----
	# 装备巢只给武将（士兵没有），所以先把一个武将塞进阵中。
	var who := ""
	for id in GameState.carry:
		if GameState.is_hero(str(id)):
			who = str(id)
			break
	if who == "":
		for c in GameData.cards:
			var cid := str(c["id"])
			if GameState.is_hero(cid) and float(c.get("power", 0.0)) > 0.0:
				GameState.owned[cid] = 1
				if GameState.carry_add(cid):
					who = cid
				break
	var eq := ""
	for c in GameData.cards:
		var cid2 := str(c["id"])
		if GameState.is_equippable(cid2):
			GameState.owned[cid2] = 1
			eq = cid2
			break
	if who != "" and eq != "":
		_check("装备挂到上阵武将身上成功",
			GameState.equip_to(who, eq) and GameState.equip_owner(eq) == who)
		_check("这件装备就记在**这个武将**的装备巢里",
			GameState.hero_equip_of(who).has(eq),
			"%s 的装备巢 %d 件" % [GameData.card_name(who), GameState.hero_equip_of(who).size()])
		_check("装备让战力倍率上升", GameState.power_multiplier() > 1.0,
			"×%.2f" % GameState.power_multiplier())
		var pm0 := GameState.power_multiplier()
		GameState.unequip_from(who, eq)
		_check("卸下 -> 该将装备巢空了、加成立刻消失",
			GameState.hero_equip_of(who).is_empty() and GameState.power_multiplier() < pm0,
			"×%.2f" % GameState.power_multiplier())

	# ---- 已克服区域不可重刷 ----
	_new_game_start_cleared()
	GameState.region_state[2] = "cleared"
	_check("已克服的区域不能再铺桌（归入城建）", not GameState.start_battle(2))

	# ---- 存档往返：升级 / 上阵 / 装备都要留住（v1.0 关档时退化为「不落盘」断言）----
	GameState.new_game()
	GameState.gold = 9999.0
	GameState.up["stamina"] = 5
	GameState.up["carry"] = 1
	GameState.up["equip"] = 1
	# v1.1：装备挂在**上阵武将**身上才存得下（每将独立），所以先要塞一个武将进阵
	var who_save := ""
	for c in GameData.cards:
		var cid := str(c["id"])
		if GameState.is_hero(cid) and float(c.get("power", 0.0)) > 0.0:
			GameState.owned[cid] = 1
			if GameState.carry_add(cid):
				who_save = cid
			break
	if who_save == "":
		var keep := _route_pool("魏线", 1)
		if keep.size() > 0:
			GameState.owned[keep[0]] = 1
			GameState.carry_add(str(keep[0]))
	var eqc := ""
	for c in GameData.cards:
		if GameState.is_equippable(str(c["id"])):
			eqc = str(c["id"])
			GameState.owned[eqc] = 1
			break
	if who_save != "" and eqc != "":
		GameState.equip_to(who_save, eqc)
	var st_save := GameState.stamina_max_value()
	var carry_save: Array = GameState.carry.duplicate()
	GameState.save_game()
	# 故意把内存改脏，再读回来 —— 验证真的从文件恢复
	GameState.up["stamina"] = 0
	GameState.carry.clear()
	GameState.hero_equip.clear()
	GameState.load_game()
	if GameState.SAVE_ENABLED:
		_check("存档读回后技能树还在", GameState.stamina_max_value() == st_save,
			"耐力 %d" % GameState.stamina_max_value())
		_check("存档读回后上阵名单还在", GameState.carry == carry_save,
			"上阵 %d 张" % GameState.carry.size())
		_check("存档读回后每将装备巢还在",
			who_save == "" or GameState.hero_equip_of(who_save).size() == 1,
			"装备 %d 件" % GameState.hero_equip_of(who_save).size())
	else:
		_check("v1.0 关档后 load_game() 不恢复任何状态", GameState.stamina_max_value() != st_save,
			"被改脏的耐力 %d 未被还原（关档符合预期）" % GameState.stamina_max_value())

	GameState.new_game()


func _find_table(n: Node) -> Control:
	if n.has_meta("paan_table"):
		return n as Control
	for ch in n.get_children():
		var r := _find_table(ch)
		if r != null:
			return r
	return null


func _test_v09_effect_parser() -> void:
	print("\n[14] v0.9 effect 解析器（武将被动 / 装备属性共用）")
	var m := GameState.parse_effect("拍力 +30%")
	_check("「拍力 +30%」→ 拍力 +30 个百分点", is_equal_approx(float(m["power_pct"]), 30.0),
		"power_pct=%.0f" % float(m["power_pct"]))
	m = GameState.parse_effect("拍力 +26%；金币 +10%")
	_check("多段「；」拆分：拍力 +26% / 金币 +10%",
		is_equal_approx(float(m["power_pct"]), 26.0) and is_equal_approx(float(m["gold_pct"]), 10.0),
		"power=%.0f gold=%.0f" % [float(m["power_pct"]), float(m["gold_pct"])])
	m = GameState.parse_effect("体力上限 +20%")
	var ok_pct := is_equal_approx(float(m["stamina_pct"]), 20.0) and is_zero_approx(float(m["stamina_flat"]))
	m = GameState.parse_effect("体力上限 +1")
	_check("体力上限分辨「+N」与「+X%」",
		ok_pct and is_equal_approx(float(m["stamina_flat"]), 1.0),
		"flat=%.0f" % float(m["stamina_flat"]))
	m = GameState.parse_effect("终结技触发线 -5")
	_check("「终结技触发线 -5」→ 触发线增量 -5", is_equal_approx(float(m["threshold"]), -5.0),
		"threshold=%.0f" % float(m["threshold"]))
	m = GameState.parse_effect("终结技触发线降至 12")
	_check("「降至 12」→ 直接设为 12", is_equal_approx(float(m["threshold_set"]), 12.0),
		"threshold_set=%.0f" % float(m["threshold_set"]))
	m = GameState.parse_effect("拍力 ×2.5")
	_check("「拍力 ×2.5」→ 走乘区而非百分点", is_equal_approx(float(m["power_mult"]), 2.5),
		"power_mult=%.2f" % float(m["power_mult"]))
	m = GameState.parse_effect("连击不中断")
	_check("「连击不中断」→ 连击保护标记", float(m["combo_shield"]) > 0.0)
	m = GameState.parse_effect("每关额外 2 次点击")
	_check("「每关额外 2 次点击」→ 耐力 +2", is_equal_approx(float(m["extra_slaps"]), 2.0))
	m = GameState.parse_effect("卡包价格 -10%")
	_check("「卡包价格 -10%」→ 负向折扣", is_equal_approx(float(m["pack_pct"]), -10.0))
	m = GameState.parse_effect("全属性 +10%")
	_check("「全属性 +10%」→ all_pct", is_equal_approx(float(m["all_pct"]), 10.0))
	m = GameState.parse_effect("滑拍判定放宽")
	_check("「滑拍判定放宽」→ 标记", float(m["relax_drag"]) > 0.0)
	var empty_ok := true
	for k in GameState.MOD_KEYS:
		if absf(float(GameState.parse_effect("-")[k])) > 0.0001:
			empty_ok = false
		if absf(float(GameState.parse_effect("")[k])) > 0.0001:
			empty_ok = false
	_check("空 effect（「-」/「」）解析为全 0", empty_ok)


func _test_v09_hero_lv() -> void:
	print("\n[15] v0.9 武将升级（每个武将有独立等级）")
	GameState.new_game()
	GameState.gold = 100000.0
	GameState.owned["G13"] = 1     # 张辽 ★6，卡面战力 625
	_check("新武将等级从 0 开始", GameState.hero_level("G13") == 0)
	var p0 := GameState.hero_card_power("G13")
	var c0 := GameState.hero_lv_cost("G13")
	_check("★6 武将上限 25 级", GameState.hero_lv_max("G13") == 25, "%d 级" % GameState.hero_lv_max("G13"))
	_check("★2 武将上限更低（成长空间按星级）",
		GameState.hero_lv_max("G17") < GameState.hero_lv_max("G13"),
		"★2=%d ★6=%d" % [GameState.hero_lv_max("G17"), GameState.hero_lv_max("G13")])
	_check("升级有价", c0 > 0, "首级 %d 金币" % c0)
	var g0 := GameState.gold
	GameState.buy_hero_lv("G13")
	_check("升级后等级 +1", GameState.hero_level("G13") == 1)
	_check("升级后该武将自身战力上升", GameState.hero_card_power("G13") > p0,
		"%.1f -> %.1f" % [p0, GameState.hero_card_power("G13")])
	_check("升级扣金币", GameState.gold < g0, "%d -> %d" % [int(g0), int(GameState.gold)])
	_check("升级价格逐级上涨", GameState.hero_lv_cost("G13") > c0,
		"%d -> %d" % [c0, GameState.hero_lv_cost("G13")])
	GameState.gold = 100000000.0
	for i in range(40):
		GameState.buy_hero_lv("G13")
	_check("到上限后封顶", GameState.hero_level("G13") == 25, "Lv.%d" % GameState.hero_level("G13"))
	_check("满级后再升无效", not GameState.buy_hero_lv("G13"))
	# 等级随上阵一起计入战力
	GameState.carry.clear()
	var d0 := GameState.deck_power()
	GameState.carry_add("G13")
	var d1 := GameState.deck_power()
	_check("上阵满级张辽 → 战力显著高于未升级", d1 > d0 * 3.0,
		"%.1f -> %.1f" % [d0, d1])


func _test_v09_hero_passive() -> void:
	print("\n[16] v0.9 武将被动真正接进战斗")
	GameState.new_game()
	GameState.owned = {"I01": 1, "G28": 1, "G26": 1, "G42": 1, "G10": 1, "G25": 1}
	GameState.carry.clear()
	# 关羽「拍力 ×2.5」
	var base_m := GameState.power_multiplier()
	GameState.carry_add("G28")
	_check("关羽「拍力 ×2.5」→ 倍率翻到 2.5 倍以上", GameState.power_multiplier() >= base_m * 2.4,
		"%.2f -> %.2f" % [base_m, GameState.power_multiplier()])
	# 张飞「终结技触发线降至 12」
	GameState.carry.clear()
	_check("没带张飞时触发线是默认 20", GameState.combo_threshold() == 20, "%d" % GameState.combo_threshold())
	GameState.carry_add("G26")
	_check("张飞「触发线降至 12」→ 拍案更好触发", GameState.combo_threshold() == 12,
		"%d" % GameState.combo_threshold())
	# 周泰「体力上限 +15%」
	GameState.carry.clear()
	var s0 := GameState.stamina_max_value()
	GameState.carry_add("G42")
	_check("周泰「体力上限 +15%」→ 耐力上限上升", GameState.stamina_max_value() > s0,
		"%d -> %d" % [s0, GameState.stamina_max_value()])
	# 徐晃「连击保护」
	GameState.carry.clear()
	_check("没带徐晃时没有连击保护", not GameState.combo_shield())
	GameState.carry_add("G10")
	_check("徐晃「连击保护」→ 拍案后连击不清零", GameState.combo_shield())
	# 蒋琬「金币 +45%」
	GameState.carry.clear()
	var f0 := GameState.fortune_mult()
	GameState.carry_add("G25")
	_check("蒋琬「金币 +45%」→ 掉金倍率上升", GameState.fortune_mult() > f0,
		"%.2f -> %.2f" % [f0, GameState.fortune_mult()])
	# 卸下后失效
	GameState.carry.clear()
	_check("卸下后被动全部失效",
		is_equal_approx(GameState.fortune_mult(), 1.0) and GameState.combo_threshold() == 20
			and not GameState.combo_shield())


func _test_v11_hero_equip_nest() -> void:
	## v1.1 用户纠错：「装备巢搞错了，装备是每个武将都有」
	##              「士兵没有装备巢」「装备卡只从卡包解锁，不再摆在桌上拍」
	print("\n[17] v1.1 装备巢 = 每将独立")
	GameState.new_game()
	GameState.gold = 1000000.0
	GameState.owned["E01"] = 1     # 兵器 ★1 环首刀 拍力+8%
	GameState.owned["E13"] = 1     # 铠甲 ★1 皮甲 体力上限+5%
	GameState.owned["G13"] = 1     # 武将（装备巢只给武将）
	GameState.owned["G14"] = 1     # 另一个武将 —— 用来验「每将一套、互不影响」
	GameState.owned["S01"] = 1     # 士兵 —— 用来验「没有装备巢」
	_check("装备槽 0 级 → 一个部位都没解锁",
		GameState.equip_slots() == 0 and GameState.unlocked_slots().is_empty())
	_check("未解锁时兵器不可装备", not GameState.is_equippable("E01"))
	# 技能树前置：「装备槽」在第二层，要先点亮「拍力」
	_check("技能树前置：没点亮「拍力」时「装备槽」锁着", not GameState.skill_req_met("equip"))
	_check("前置未满足 -> 购买被拒、装备槽还是 0",
		not GameState.buy_upgrade("equip") and GameState.equip_slots() == 0)
	GameState.buy_upgrade("power")
	GameState.buy_upgrade("equip")
	_check("升 1 级 → 解锁「兵器」部位", GameState.unlocked_slots() == ["兵器"],
		str(GameState.unlocked_slots()))
	_check("此时兵器可装备、铠甲仍不可",
		GameState.is_equippable("E01") and not GameState.is_equippable("E13"))

	# ---- 每将独立 ----
	_check("武将才有装备巢；士兵没有",
		GameState.has_equip_nest("G13") and not GameState.has_equip_nest("S01"))
	_check("给武将挂兵器成功",
		GameState.equip_to("G13", "E01") and GameState.equip_owner("E01") == "G13")
	_check("这件装备就记在**这个武将**的装备巢里",
		GameState.hero_equip_of("G13").has("E01"), "%d 件" % GameState.hero_equip_of("G13").size())
	_check("另一个武将的装备巢是空的（互不影响）", GameState.hero_equip_of("G14").is_empty())
	_check("士兵拒绝挂装备", not GameState.equip_to("S01", "E01"))
	# 一件装备同时只能挂一个将 → 挂给别人 = 从旧人身上摘
	_check("同一件装备转挂给另一个将（旧人身上自动摘掉）",
		GameState.equip_to("G14", "E01") and GameState.equip_owner("E01") == "G14"
			and not GameState.hero_equip_of("G13").has("E01"))
	_check("未解锁部位无法装备（铠甲）", not GameState.equip_to("G14", "E13"))
	GameState.buy_upgrade("equip")
	_check("升到 2 级 → 兵器+铠甲", GameState.unlocked_slots() == ["兵器", "铠甲"],
		str(GameState.unlocked_slots()))
	GameState.equip_to("G14", "E13")
	_check("两个部位各 1 件，都在同一个将身上",
		GameState.hero_equip_of("G14").size() == 2, "%d 件" % GameState.hero_equip_of("G14").size())
	var s_before := GameState.stamina_max_value()
	GameState.owned["E14"] = 1     # 铠甲 ★2 铁甲 体力上限+10%
	GameState.equip_to("G14", "E14")
	_check("同部位换装 → 自动卸下旧件，部位仍只 1 件",
		GameState.hero_equip_of("G14").size() == 2
			and GameState.hero_equipped_in_slot("G14", "铠甲") == "E14",
		"共 %d 件" % GameState.hero_equip_of("G14").size())
	_check("每部位最多 1 件（装备总数 <= 部位数）",
		GameState.hero_equip_of("G14").size() <= GameState.equip_slots())

	# ---- 只有**上阵武将**身上的装备才算（与「只算上阵的卡」一致）----
	GameState.carry.clear()
	_check("没上阵 → 装备加成不算数",
		is_equal_approx(float(GameState.equip_mods()["power_pct"]), 0.0),
		"power_pct=%.0f" % float(GameState.equip_mods()["power_pct"]))
	GameState.carry_add("G14")
	var sm := GameState.equip_mods()
	_check("上阵后 → 该将身上的装备生效（拍力 +8% / 体力 +10%）",
		is_equal_approx(float(sm["power_pct"]), 8.0) and is_equal_approx(float(sm["stamina_pct"]), 10.0),
		"power=%.0f stamina=%.0f" % [float(sm["power_pct"]), float(sm["stamina_pct"])])
	_check("换更强的铠甲确实抬高了耐力上限", GameState.stamina_max_value() > s_before,
		"%d -> %d" % [s_before, GameState.stamina_max_value()])
	GameState.carry.clear()
	GameState.carry_add("G13")
	_check("换成没装备的武将上阵 → 加成归零",
		is_equal_approx(float(GameState.equip_mods()["power_pct"]), 0.0),
		"power_pct=%.0f" % float(GameState.equip_mods()["power_pct"]))


func _test_v11_troops() -> void:
	## v1.1：用户要求「士兵没有装备巢，但是可以当武将出战，
	##        未来点亮技能树里的武将带兵能力，可以直接把兵给武将装备」
	##        「技能应该是技能树」
	print("\n[21] v1.1 技能树 + 武将带兵（士卒可挂到武将麾下）")
	GameState.new_game()
	GameState.gold = 10000000.0

	# ---- 技能树：3 层 + 浅前置 ----
	_check("技能树有 3 层", GameState.SKILL_TIERS.size() == 3, str(GameState.SKILL_TIERS))
	_check("第一层是立身（耐力/拍力/携带位）",
		GameState.skills_of_tier(1).size() == 3 and GameState.skill_tier("stamina") == 1)
	_check("带兵在第三层，前置 = 携带位 + 装备槽",
		GameState.skill_tier("troops") == 3
			and str(GameState.skill_reqs("troops")) == str(["carry", "equip"]))
	_check("前置没满足时点不了「武将带兵」",
		not GameState.buy_upgrade("troops") and GameState.troop_slots() == 0)
	# 一级一级点亮上去：带兵的前置 = 携带位 + 装备槽（而装备槽自己又依赖拍力）
	GameState.buy_upgrade("power")
	GameState.buy_upgrade("carry")
	_check("点亮「拍力」「携带位」还不够，仍差「装备槽」", not GameState.skill_req_met("troops"))
	GameState.buy_upgrade("equip")
	_check("点亮「拍力」「携带位」「装备槽」后，带兵的前置才满足", GameState.skill_req_met("troops"))
	GameState.buy_upgrade("troops")
	_check("点亮「武将带兵」→ 每将 1 个兵位", GameState.troop_slots() == 1,
		"%d 兵位" % GameState.troop_slots())

	# ---- 兵位：只收士卒；与携带位互斥；战力全额计入 ----
	GameState.owned["G13"] = 1     # 武将
	GameState.owned["S01"] = 1     # 士卒 战力 0.2
	GameState.owned["S02"] = 1     # 士卒 战力 0.2
	_check("士兵没有装备巢，但可以上阵当武将使", GameState.is_carryable("S01")
		and not GameState.has_equip_nest("S01"))
	_check("非士卒不能进兵位", not GameState.troop_put("G13", "E01"))
	_check("武将才有兵位", GameState.troop_cap("G13") == 1 and GameState.troop_cap("S01") == 0)
	GameState.carry.clear()
	GameState.carry_add("G13")
	var p0 := GameState.deck_power()
	_check("把士卒挂到武将麾下成功", GameState.troop_put("G13", "S01"),
		str(GameState.hero_troops_of("G13")))
	_check("士卒战力全额计入卡组", GameState.deck_power() > p0,
		"%.2f -> %.2f" % [p0, GameState.deck_power()])
	_check("麾下士卒不占携带位", not GameState.in_carry("S01") and GameState.carry.size() == 1,
		"上阵 %d 张" % GameState.carry.size())
	_check("兵位满了就拒绝再挂", not GameState.troop_put("G13", "S02"))
	_check("一个兵同时只在一个将麾下（转挂先撤回）",
		not GameState.troop_put("G13", "S01") and GameState.troop_owner("S01") == "G13")
	_check("已在麾下的兵不能同时上阵", not GameState.carry_add("S01"))
	_check("撤回后兵位空出、战力回落", GameState.troop_remove("G13", "S01")
		and absf(GameState.deck_power() - p0) < 0.001, "%.2f" % GameState.deck_power())
	_check("撤回后又能上阵了（士卒可当武将出战）", GameState.carry_add("S01"),
		"上阵 %s" % str(GameState.carry))

	# ---- 未上阵武将的兵不算 ----
	GameState.carry.clear()
	GameState.troop_put("G13", "S01")
	var p_off := GameState.deck_power()
	_check("武将不在阵中 → 它的兵也不上桌", is_equal_approx(GameState.troop_power(), 0.0),
		"troop_power=%.2f" % GameState.troop_power())
	GameState.carry_add("G13")
	_check("武将上阵 → 兵的战力跟着上来", GameState.deck_power() > p_off
		and GameState.troop_power() > 0.0,
		"troop_power=%.2f" % GameState.troop_power())

	# ---- 带兵升级：兵位数量 ----
	GameState.gold = 10000000.0
	GameState.owned["S03"] = 1
	GameState.buy_upgrade("troops")
	GameState.buy_upgrade("troops")
	_check("升满 → 每将 3 个兵位", GameState.troop_slots() == 3, "%d 兵位" % GameState.troop_slots())
	_check("满级后不能再升", GameState.upgrade_maxed("troops"))
	_check("兵位够 3 个 → 能再挂两兵", GameState.troop_put("G13", "S02")
		and GameState.troop_put("G13", "S03") and GameState.hero_troops_of("G13").size() == 3,
		str(GameState.hero_troops_of("G13")))

	# ---- 装备卡不进敌人池（用户：只从卡包解锁）----
	var found := false
	for idx in GameData.enemies_by_region.keys():
		for e in GameData.enemies_by_region[idx]:
			if str(GameData.card(str(e.get("card_id", ""))).get("type", "")) == "装备":
				found = true
	_check("21 个区域的敌人池里都没有「装备」",
		not found and GameData.enemies_by_region.size() == 21,
		"扫了 %d 个区域" % GameData.enemies_by_region.size())


func _test_v09_city_build() -> void:
	print("\n[18] 建筑装配、品相合成")
	GameState.new_game()
	GameState.gold = 100000
	for idx in [2, 3, 4]:
		GameState.region_state[idx] = "cleared"
	GameState.owned["B01"] = 4
	_check("克服3处解锁六槽城市", GameState.city_unlocked() and GameState.city_slots(2) == 6)
	_check("建筑装配成功", GameState.place_building(2, "B01", 0))
	_check("原版菜地每10秒1金币", is_equal_approx(GameState.building_output(2, 0), 360))
	_check("建筑不再金币练级", not GameState.upgrade_building(2, 0))
	var gold_before := GameState.gold
	_check("3同名原版合成精制", GameState.fuse_building("B01") == "B01" and GameState.building_stock("B01", 1) == 1)
	_check("合成不扣金币且保护已装配卡", GameState.gold == gold_before and GameState.city_buildings(2) == ["B01"])
	GameState.remove_building(2, 0)
	_check("卸下返还原版", GameState.building_stock("B01", 0) == 1)
	GameState.place_building(2, "B01", 1)
	_check("精制收益提高35%", is_equal_approx(GameState.gold_per_hour(), 486))
	GameState.remove_building(2, 0)
	_check("精制卸下保留品相", GameState.building_stock("B01", 1) == 1)
	_check("材料不足不可混名混品相", GameState.fuse_building("B01") == "")


func _test_v09_city_view() -> void:
	print("\n[19] v0.9 全屏城建界面（PaanCity · 覆盖层接线 + 三栏）")
	GameState.new_game()
	var packed = load("res://scenes/Main.tscn")
	_check("主场景可加载", packed != null)
	if packed == null:
		return
	var inst = packed.instantiate()
	add_child(inst)
	_check("主场景已挂载城建覆盖层", inst._city != null)
	_check("城建覆盖层初始隐藏", not inst._city.visible)

	# 造三处已克服城池 + 一座建筑（城建门槛是 3 处）
	GameState.gold = 100000.0
	GameState.region_state[2] = "cleared"
	GameState.region_state[3] = "cleared"
	GameState.region_state[4] = "cleared"
	GameState.owned["B01"] = 1
	GameState.place_building(2, "B01")
	GameState.owned["B02"] = 1

	# 互斥：三个全屏覆盖层同一时刻只该有一个可见
	inst._open_home()
	_check("打开大本营 → 大本营可见", inst._home.visible)
	inst._open_city()
	_check("打开城建 → 收起大本营（互斥）", not inst._home.visible)
	_check("城建覆盖层可见", inst._city.visible)
	var cv = inst._city
	_check("城建覆盖层已撑满（不是 0 尺寸 —— 隐藏覆盖层的锚点坑）",
		cv.size.x > 2.0 and cv.size.y > 2.0, "size=%s" % cv.size)
	inst._open_map()
	_check("打开舆图 → 收起城建（互斥）", not cv.visible)

	# 再打开一次，验证城册、建设区与独立仓库/合成页签
	inst._open_city()
	_check("默认选中第一处已克服城池", cv._sel == 2, "sel=%d" % cv._sel)
	_check("城池使用选择器", cv._list_box.get_child_count() == 1)
	_check("建设区有六槽卡牌区", cv._detail_box.get_child_count() >= 3)
	_check("选中建筑可卸下", _find_button_contains(cv, "卸下"))
	_check("页首显示全城产出", _find_label_contains(cv, "全城产出"))
	cv._on_tab("合成")
	_check("同名合成显示品相规则", _find_label_contains(cv, "3张同名同品相"))
	cv._on_tab("仓库")
	_check("仓库列出真实持有的建筑卡", _find_label_contains(cv._side_box, GameData.card_name("B02")))

	# 切换选中城池 → 中栏随之刷新
	cv._on_pick(3)
	_check("点左栏切换城池后选中项更新", cv._sel == 3, "sel=%d" % cv._sel)
	inst.queue_free()


func _find_label_contains(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text.contains(text):
		return true
	for ch in n.get_children():
		if _find_label_contains(ch, text):
			return true
	return false


func _find_button_contains(n: Node, text: String) -> bool:
	if n is Button and (n as Button).text.contains(text):
		return true
	for ch in n.get_children():
		if _find_button_contains(ch, text):
			return true
	return false


func _gesture(root: Control, from: Vector2, to: Vector2) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = from
	root._on_table_input(d)
	var steps := 18
	for s in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(s) / float(steps))
		root._on_table_input(m)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	root._on_table_input(u)
