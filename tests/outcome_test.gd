extends Node
## 战后整备状态回归：使用独立测试档，不依赖界面或随机开局牌。

var checks := 0
var failures := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)


func _ready() -> void:
	GameState.set_process(false)
	check(GameState.save_path() != GameState.SAVE_PATH, "战果测试必须使用独立存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	_test_failure_and_retry()
	_test_idle_excluded()
	_test_victory()
	_test_save_restore()
	_test_old_and_invalid_saves()
	GameState.new_game()
	print("[Outcome] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _weak_start() -> void:
	GameState.new_game()
	GameState.owned = {"I01": 1, "S01": 1, "S02": 1, "S03": 1}
	GameState.carry.clear()
	GameState.carry_auto()
	GameState._idle_buffer = 0.0
	check(GameState.start_battle(GameState.START_REGION), "固定弱开局成功铺桌")
	check(GameState.last_outcome.is_empty(), "新出战没有旧战果")


func _finish_table() -> void:
	var guard := 0
	while GameState.in_battle and guard < 100:
		var target := -1
		# 优先薄牌，让弱开局实际产生击倒获金而仍然无法清桌。
		for i in range(GameState.battle.size() - 1, -1, -1):
			if float(GameState.battle[i]["hp"]) > 0.0:
				target = i
				break
		if target < 0 or not GameState.attack(target):
			break
		guard += 1
	check(not GameState.in_battle and guard < 100, "有限拍击结束当前战斗")


func _full_table() -> bool:
	if GameState.battle.size() != GameData.enemies_by_region[GameState.battle_region].size():
		return false
	for enemy in GameState.battle:
		if not is_equal_approx(float(enemy["hp"]), float(enemy["hp_max"])):
			return false
	return not GameState.battle.is_empty()


func _same_outcome(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	for field in ["region", "result", "gold", "kills"]:
		if a.get(field) != b.get(field):
			return false
	return is_equal_approx(float(a.get("damage", 0.0)), float(b.get("damage", 0.0)))


func _test_failure_and_retry() -> void:
	_weak_start()
	var initial_gold := GameState.gold
	_finish_table()
	check(GameState.last_outcome.get("result") == "settled", "弱开局记录未清桌结算")
	check(GameState.last_outcome.get("region") == GameState.START_REGION, "结算指向原区域")
	check(GameState.run_kills > 0, "弱开局实际击倒至少一张薄牌")
	check(GameState.last_outcome.get("gold") == int(GameState.gold - initial_gold), "战果包含击倒与结算的实际总获金")
	check(is_equal_approx(GameState.run_gold, GameState.gold - initial_gold), "小数击倒奖励在单趟账本中完整累加")
	var snapshot := GameState.last_outcome.duplicate(true)
	var earned := GameState.gold
	var runs := GameState.runs
	GameState.settle_run()
	GameState.retreat()
	check(is_equal_approx(GameState.gold, earned) and GameState.runs == runs,
		"重复结算与撤退不会再次发放奖励或增加趟数")
	check(_same_outcome(GameState.last_outcome, snapshot), "重复结算保留原战果")
	GameState.gold += 1000.0
	var battle_gold := GameState.run_gold
	check(GameState.buy_upgrade("stamina"), "战后可以买耐力升级")
	check(_same_outcome(GameState.last_outcome, snapshot), "买升级不覆盖未出战的战果")
	check(is_equal_approx(GameState.run_gold, battle_gold), "战后消费不扣减本趟获金统计")
	var retained_gold := GameState.gold
	var retained_up := GameState.up.duplicate(true)
	var retained_owned := GameState.owned.duplicate(true)
	var retained_carry := GameState.carry.duplicate()
	check(GameState.start_battle(int(snapshot["region"])), "从原区域重试成功")
	check(GameState.battle_region == GameState.START_REGION, "重试仍然挑战原区域")
	check(GameState.stamina == GameState.stamina_max_value() and GameState.stamina > 6,
		"重试应用已买成长并恢复全部耐力")
	check(_full_table(), "重试敌牌数量和全部血量恢复")
	check(GameState.last_outcome.is_empty() and GameState.end_reason == "" and GameState.run_gold == 0.0,
		"真正出战清空旧战果和本趟账本")
	check(GameState.up == retained_up and GameState.owned == retained_owned and GameState.carry == retained_carry,
		"重试保留成长、持有卡和上阵队伍")
	check(is_equal_approx(GameState.gold, retained_gold), "重试既不收回已赚金币也不重发旧奖金")


func _test_idle_excluded() -> void:
	_weak_start()
	GameState.region_state[2] = "cleared"
	GameState.region_state[3] = "cleared"
	GameState.region_state[4] = "cleared"
	GameState.cities = {2: {"buildings": ["B01"]}}
	GameState.city_lv = {2: [0]}
	GameState._recompute_bonus()
	var before_idle := GameState.gold
	GameState._process(3600.0)
	check(GameState.gold > before_idle, "测试确实产生在线建筑收入")
	check(GameState.run_gold == 0.0, "在线建筑收入不会计入战斗账本")
	var after_idle := GameState.gold
	_finish_table()
	check(GameState.last_outcome.get("gold") == int(GameState.gold - after_idle),
		"结算摘要排除本趟同时收到的城建收入")


func _test_victory() -> void:
	_weak_start()
	# 拍力只放大卡组战力，基础 +1 不参与；Lv.20 仍不能一拍击倒 18 血主桌牌。
	GameState.up["power"] = 30
	check(GameState.start_battle(GameState.START_REGION), "确定胜利夹具成功铺桌")
	var table_size := GameState.battle.size()
	var damage := GameState.click_damage()
	check(GameState.stamina == table_size, "胜利夹具耐力恰好等于整桌牌数")
	for enemy in GameState.battle:
		check(damage >= float(enemy["hp_max"]), "胜利夹具的轻拍必定单次击倒每张敌牌")
	var before := GameState.gold
	for i in range(table_size):
		check(GameState.attack(i), "胜利夹具逐张使用一次轻拍：%d" % i)
	check(GameState.last_outcome.get("result") == "cleared" and GameState.end_reason == "cleared",
		"胜利写入通关战果")
	check(GameState.stamina == 0, "最后一点耐力清桌优先记为胜利而非失败结算")
	check(GameState.last_outcome.get("kills") == GameData.enemies_by_region[GameState.START_REGION].size(),
		"胜利记录整桌击倒数")
	check(GameState.last_outcome.get("gold") == int(GameState.gold - before),
		"胜利获金包含击倒与首通奖金")
	var snapshot := GameState.last_outcome.duplicate(true)
	var earned := GameState.gold
	var runs := GameState.runs
	var captured := GameState.captured.duplicate()
	check(not GameState.start_battle(GameState.START_REGION), "已通关区域不能重开")
	GameState._clear_region()
	GameState.settle_run()
	check(is_equal_approx(GameState.gold, earned) and GameState.runs == runs and GameState.captured == captured,
		"拒绝重开与重复首通都不会重发奖金、囚禁或趟数")
	check(_same_outcome(GameState.last_outcome, snapshot), "拒绝重开保留胜利战果")
	GameState.save_game()
	GameState.last_outcome = {}
	GameState.in_battle = true
	check(GameState.load_game(), "胜利存档可以恢复")
	check(not GameState.in_battle and GameState.battle.is_empty() and GameState.battle_region == GameState.START_REGION,
		"胜利读档停在原区域整备状态")
	check(_same_outcome(GameState.last_outcome, snapshot), "胜利读档保持完整原战果")
	check(is_equal_approx(GameState.gold, earned), "胜利读档不会重复首通奖金")


func _test_save_restore() -> void:
	_weak_start()
	_finish_table()
	GameState.gold += 1000.0
	GameState.buy_upgrade("stamina")
	var snapshot := GameState.last_outcome.duplicate(true)
	var gold := GameState.gold
	var up := GameState.up.duplicate(true)
	GameState.save_game()
	GameState.last_outcome = {}
	GameState.end_reason = ""
	GameState.battle_region = 21
	GameState.in_battle = true
	GameState.gold = 0.0
	GameState.up["stamina"] = 0
	check(GameState.load_game(), "未清桌战果存档可以恢复")
	check(not GameState.in_battle and GameState.battle.is_empty(), "有效战果读档不擅自新开一桌")
	check(GameState.battle_region == int(snapshot["region"]) and GameState.end_reason == "settled",
		"读档恢复原区域和结算原因")
	check(_same_outcome(GameState.last_outcome, snapshot), "读档恢复未清桌的完整战果")
	check(GameState.up == up and is_equal_approx(GameState.gold, gold), "读档同时保留结算后购买的成长和剩余金币")
	GameState.settle_run()
	check(is_equal_approx(GameState.gold, gold), "读档后的重复结算不会再领奖")
	check(GameState.start_battle(int(snapshot["region"])), "恢复战果后仍可原地重试")
	check(_full_table() and GameState.stamina == GameState.stamina_max_value(), "读档后重试重新恢复完整牌桌和耐力")


func _read_save() -> Dictionary:
	var file := FileAccess.open(GameState.save_path(), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _write_save(data: Dictionary) -> void:
	data["last_save"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(GameState.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _test_old_and_invalid_saves() -> void:
	_weak_start()
	_finish_table()
	GameState.save_game()
	var legacy := _read_save()
	legacy.erase("last_outcome")
	legacy.erase("battle_region")
	var retained_gold := GameState.gold
	_write_save(legacy)
	check(GameState.load_game(), "没有战果字段的旧存档仍能读")
	check(GameState.in_battle and _full_table() and GameState.last_outcome.is_empty(),
		"旧存档保持自动铺可挑战区域的行为")
	check(is_equal_approx(GameState.gold, retained_gold), "旧档迁移不会再发旧结算奖励")
	for invalid in [
		{"region": 999, "result": "settled"},
		{"region": 1, "result": "victory"},
		{"region": "1", "result": "settled"},
		{"region": 1.5, "result": "settled"},
		{"region": 1, "result": "cleared"},
	]:
		var fixture := legacy.duplicate(true)
		fixture["last_outcome"] = invalid
		_write_save(fixture)
		check(GameState.load_game() and GameState.last_outcome.is_empty() and GameState.in_battle,
			"无效区域/结果/类型/通关状态安全回退：%s" % str(invalid))
	var sanitized := legacy.duplicate(true)
	sanitized["last_outcome"] = {"region": 1, "result": "settled", "gold": -9, "kills": -2, "damage": -3}
	_write_save(sanitized)
	check(GameState.load_game() and not GameState.in_battle, "有效区域结果仍能恢复整备")
	check(GameState.last_outcome.get("gold") == 0 and GameState.last_outcome.get("kills") == 0
		and GameState.last_outcome.get("damage") == 0.0, "坏存档的负数统计被规范化为零")
	GameState.new_game()
	check(GameState.last_outcome.is_empty() and GameState.end_reason == "" and GameState.run_gold == 0.0,
		"新周目清空旧战果")
