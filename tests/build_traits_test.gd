extends Node
## 六将构筑实际行为回归：独立测试档、固定生命值、不依赖掉包运气。

const Traits := preload("res://scripts/build_traits.gd")
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _ready() -> void:
	GameState.set_process(false)
	check(GameState.save_path() != GameState.SAVE_PATH, "构筑回归必须隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	_test_descriptions()
	_test_thunder()
	_test_fire()
	_test_mark_and_chase()
	_test_damage_budget()
	_test_not_deployed_and_clear()
	_test_reset_and_save()
	GameState.new_game()
	print("[BuildTraits] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func prepare(ids: Array = []) -> float:
	GameState.new_game()
	GameState.carry = ids.duplicate()
	GameState.owned = {"I01": 1}
	for id in ids:
		GameState.owned[id] = 1
	GameState.up["stamina"] = 60
	GameState.up["carry"] = 3
	GameState.start_battle(1)
	for i in range(GameState.battle.size()):
		GameState.battle[i]["hp"] = 10000.0 + float(i) * 1000.0
		GameState.battle[i]["hp_max"] = GameState.battle[i]["hp"]
		GameState.battle[i]["boss"] = false
	return GameState.click_damage()


func _test_descriptions() -> void:
	for id in ["G04", "G05", "G30", "G40", "G20", "G24"]:
		var info := Traits.describe(id)
		check(not info.is_empty() and info.has("description") and info.has("summary") and info.has("role"), "六将说明完整：" + id)
	check(Traits.describe("G28").is_empty(), "未实现武将不声明新技能")
	check(Traits.team_summary(["G04", "G05"])["missing"].is_empty(), "完整雷队无缺项")
	check(Traits.team_summary(["G24"])["missing"].size() == 1, "追击队提示缺少标记")
	check(Traits.team_summary(["G04", "G05", "G30", "G40"])["title"] == "混搭连锁", "混搭可以同时形成两套联动")
	check(Traits.team_summary(["G04", "G30", "G40"])["title"] == "烈火联动", "不完整雷队不能覆盖完整烈火队名称")


func _test_thunder() -> void:
	prepare(["G04"])
	for ignored in range(3):
		GameState.attack(0)
	check(int(GameState.battle[5]["thunder"]) == 1, "朱灵第三拍为最厚存活牌附印")
	for ignored in range(12):
		GameState.attack(0)
	check(int(GameState.battle[5]["thunder"]) == 3, "雷印封顶三层")
	prepare([])
	GameState.owned["G04"] = 1
	for ignored in range(3):
		GameState.attack(0)
	check(int(GameState.battle[5]["thunder"]) == 0, "仅拥有朱灵不会附印")
	var base := prepare(["G05"])
	GameState.battle[0]["thunder"] = 3
	var before := float(GameState.battle[0]["hp"])
	GameState.attack(0, true)
	check(near(before - float(GameState.battle[0]["hp"]), 5.5 * base), "文聘重拍追加两层雷印共3B")
	check(int(GameState.battle[0]["thunder"]) == 1, "文聘最多消耗两印")
	before = float(GameState.battle[0]["hp"])
	GameState.attack(0, true)
	check(near(before - float(GameState.battle[0]["hp"]), 2.5 * base), "文聘冷却内不引爆")
	check(int(GameState.battle[0]["thunder"]) == 1, "冷却不会消耗雷印")
	GameState._tick_build_effects(6.0)
	before = float(GameState.battle[0]["hp"])
	GameState.attack(0, true)
	check(near(before - float(GameState.battle[0]["hp"]), 4.0 * base), "六秒后文聘可再引爆")


func _test_fire() -> void:
	var base := prepare(["G30", "G40"])
	GameState.attack(0, true)
	check(near(float(GameState.battle[0]["burn_remaining"]), 6.0), "韩玄重拍点燃六秒")
	var before := float(GameState.battle[0]["hp"])
	GameState._tick_build_effects(0.5)
	check(near(before, float(GameState.battle[0]["hp"])), "燃烧不足一秒不扣血")
	GameState._tick_build_effects(0.5)
	check(near(before - float(GameState.battle[0]["hp"]), 0.3 * base), "燃烧每秒0.3B")
	check(int(GameState.build_counts.get("G40", 0)) == 1, "燃烧不算基础拍击")
	GameState.attack(1, true)
	check(float(GameState.battle[1]["burn_remaining"]) == 0.0, "点火冷却四秒")
	GameState.attack(1)
	GameState.attack(1)
	check(near(float(GameState.battle[5]["burn_remaining"]), 5.0), "程普第四拍复制剩余燃烧时间")
	check(near(float(GameState.battle[5]["burn_dps"]), 0.3 * base), "扩散保留伤害快照")
	GameState.up["power"] = 4
	before = float(GameState.battle[0]["hp"])
	GameState._tick_build_effects(1.0)
	check(near(before - float(GameState.battle[0]["hp"]), 0.3 * base), "升级拍力不改变已有燃烧伤害")
	GameState._tick_build_effects(4.0)
	check(float(GameState.battle[0]["burn_remaining"]) == 0.0, "燃烧六秒结束")
	check(float(GameState.battle[5]["burn_remaining"]) == 0.0, "扩散不重新得到六秒持续")
	prepare(["G40"])
	for ignored in range(4):
		GameState.attack(0)
	check(float(GameState.battle[5]["burn_remaining"]) == 0.0, "只有程普不能凭空点火")


func _test_mark_and_chase() -> void:
	var base := prepare(["G20", "G24"])
	GameState.attack(0, true)
	check(int(GameState.build_counts.get("G20", 0)) == 0, "周仓仅统计轻拍")
	for ignored in range(3):
		GameState.attack(0)
	check(near(float(GameState.battle[5]["mark_remaining"]), 6.0), "三次轻拍标记最厚牌")
	var before := float(GameState.battle[5]["hp"])
	GameState.attack(5)
	check(near(before - float(GameState.battle[5]["hp"]), 1.2 * base), "基础拍击对标记牌增伤20%")
	GameState.battle[5]["hp"] = base
	GameState.battle[1]["hp"] = 0.5 * base
	GameState.battle[1]["mark_remaining"] = 6.0
	GameState.battle[2]["hp"] = 0.75 * base
	GameState.battle[2]["boss"] = true
	var kills := GameState.run_kills
	var damage := GameState.run_damage
	GameState.attack(5)
	check(GameState.run_kills == kills + 2, "标记翻牌触发追击再次翻牌")
	check(float(GameState.battle[2]["hp"]) > 0.0, "追击排除首领且同链不重复追击")
	check(near(GameState.run_damage - damage, 1.5 * base), "连锁只计算实际扣血")
	var effects: Array = GameState.last_slap["effects"]
	check(effects.size() >= 2, "UI收到原拍与追击两个目标事件")
	prepare(["G20"])
	for ignored in range(3):
		GameState.attack(0)
	GameState._tick_build_effects(6.0)
	check(float(GameState.battle[5]["mark_remaining"]) == 0.0, "标记六秒后结束")


func _test_damage_budget() -> void:
	var base := prepare([])
	GameState.stamina = 1
	var before := float(GameState.battle[0]["hp"])
	check(not GameState.attack(0, true), "一点耐力不能重拍")
	check(near(before, float(GameState.battle[0]["hp"])) and GameState.stamina == 1, "拒绝重拍不会扣血或耐力")
	GameState.battle[0]["hp"] = 0.1
	GameState.attack(0)
	check(not GameState.in_battle and near(GameState.run_damage, 0.1), "最后一拍结算不按超额伤害发工资")
	check(GameState.last_outcome["result"] == "settled", "实际伤害修正保留失败结算")
	prepare(["G30"])
	GameState.stamina = 2
	GameState.attack(0, true)
	check(not GameState.in_battle, "最后重拍立即结算，不等待残余燃烧")
	var damage := GameState.run_damage
	GameState._tick_build_effects(6.0)
	check(near(damage, GameState.run_damage), "结算后燃烧不继续产金币")
	base = prepare(["G30", "G24"])
	GameState.battle[0]["hp"] = 0.2 * base
	GameState.battle[0]["burn_remaining"] = 1.0
	GameState.battle[0]["burn_dps"] = 0.3 * base
	GameState.battle[0]["burn_base"] = base
	GameState.battle[0]["mark_remaining"] = 6.0
	GameState.battle[1]["hp"] = 0.5 * base
	GameState._tick_build_effects(1.0)
	check(GameState.run_kills == 2, "燃烧翻牌可接马良追击")
	check(near(GameState.run_damage, 0.7 * base), "燃烧及追击均限制实际伤害")
	check(GameState.last_slap.get("source", "") == "dot", "DOT通过独立UI事件反馈")
	var seq := int(GameState.last_slap["effect_seq"])
	GameState._tick_build_effects(0.1)
	check(int(GameState.last_slap["effect_seq"]) == seq, "无伤害帧不重复增加事件批次")


func _test_not_deployed_and_clear() -> void:
	var base := prepare([])
	for id in ["G05", "G30", "G40", "G20", "G24"]:
		GameState.owned[id] = 1
	GameState.battle[0]["thunder"] = 2
	GameState.attack(0, true)
	check(int(GameState.battle[0]["thunder"]) == 2, "文聘未上阵不消耗雷印")
	check(float(GameState.battle[0]["burn_remaining"]) == 0.0, "韩玄未上阵不点火")
	for ignored in range(4):
		GameState.attack(0)
	check(float(GameState.battle[5]["mark_remaining"]) == 0.0, "周仓未上阵不标记")
	GameState.battle[0]["hp"] = 0.5 * base
	GameState.battle[0]["mark_remaining"] = 6.0
	var before := float(GameState.battle[1]["hp"])
	GameState.attack(0)
	check(near(before, float(GameState.battle[1]["hp"])), "马良未上阵不追击")
	prepare(["G30"])
	for i in range(GameState.battle.size()):
		GameState.battle[i]["hp"] = 0.0
		GameState.battle[i]["kill_rewarded"] = true
	GameState.battle[0]["hp"] = 0.1
	GameState.battle[0]["kill_rewarded"] = false
	GameState.battle[0]["burn_remaining"] = 1.0
	GameState.battle[0]["burn_dps"] = 10.0
	var runs := GameState.runs
	GameState._tick_build_effects(1.0)
	check(not GameState.in_battle and GameState.last_outcome.get("result", "") == "cleared", "燃烧可以完成整桌首通")
	check(GameState.runs == runs + 1 and GameState.run_kills == 1, "燃烧首通只结算一次")
	var reward := GameState.gold
	GameState._tick_build_effects(1.0)
	GameState.settle_run()
	check(near(GameState.gold, reward) and GameState.runs == runs + 1, "首通后重复tick或结算不重复发奖")


func _test_reset_and_save() -> void:
	prepare(["G04", "G30"])
	GameState.attack(0, true)
	GameState.attack(0)
	GameState.build_ready_at["G05"] = 100.0
	GameState.save_game()
	check(GameState.load_game(), "新能力不影响旧存档读回")
	check(GameState.build_counts.is_empty() and GameState.build_ready_at.is_empty(), "读档按满血新桌重置能力计数和冷却")
	check(float(GameState.battle[0]["burn_remaining"]) == 0.0 and float(GameState.battle[0]["hp"]) == float(GameState.battle[0]["hp_max"]), "局内状态不跨读档留下幽灵燃烧")
	GameState.leave_battle()
	check(GameState.build_counts.is_empty() and GameState.build_clock == 0.0, "离桌清理构筑运行状态")
