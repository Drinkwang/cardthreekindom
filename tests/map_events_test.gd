extends Node
## 地图事件与奖励专项。仅允许隔离测试档，由主任务串行运行。
const Events = preload("res://scripts/map_events.gd")
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
	GameState.map_event_entries(1)

func entry(id: String) -> Dictionary:
	var idx := int(GameState.map_events[id].region)
	for item in GameState.map_event_entries(idx):
		if str(item.id) == id: return item
	return {}

func click_event(id: String) -> Dictionary:
	return GameState.interact_map_event(id, Vector2(entry(id).point))

func complete_city(idx: int) -> void:
	var zones: Array = []
	for zone in range(GameState.zone_count(idx)): zones.append(zone)
	GameState.cleared_zones[idx] = zones
	GameState.table_wins[idx] = zones.size()
	GameState.region_state[idx] = "cleared"

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "地图事件测试使用隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	_test_chests()
	_test_exchange()
	_test_timed_hunt()
	_test_hunt_timeout()
	_test_cleared_city_visit()
	_test_escort()
	print("[Map events] checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_chests() -> void:
	fixture()
	check(GameState.map_event_entries(1).size() == 3, "第一城只有宝箱、限时剿敌和兑换NPC")
	check(not GameState.map_events.has("escort_1"), "第一关不生成护卫任务")
	check(GameState.battle.size() == GameState.pile_card_count(), "NPC和宝箱独立于敌牌计数")
	var point: Vector2 = entry("chest_1").point
	var response := GameState.interact_map_event("chest_1", point + Vector2(1000, 1000))
	check(not bool(response.get("changed", false)) and GameState.round_slaps == 0, "点击远处不能隔空打开宝箱")
	response = click_event("chest_1")
	check(bool(response.get("completed", false)) and bool(GameState.map_events.chest_1.claimed), "手拍可打开宝箱并写入已领取状态")
	check(int(GameState.items.get("supply", 0)) == 1 and GameState.round_slaps == 1, "一箱只有一个军需奖励，并占一掌")
	check(GameState.player_xp == 0 and GameState.gold == 0.0 and GameState.run_damage == 0.0, "敲宝箱不领取敌牌经验或伤害金币")
	GameState.slap_cooldown_left = 0.0
	response = click_event("chest_1")
	check(not bool(response.get("completed", false)) and int(GameState.items.supply) == 1 and GameState.round_slaps == 1, "重复拍已开宝箱不重复给奖或计掌")
	GameState.retreat()
	GameState.save_game()
	check(GameState.load_game() and bool(GameState.map_events.chest_1.claimed) and int(GameState.items.supply) == 1, "宝箱状态和军需跨存档保留")
	check(GameState.start_battle(1), "开箱后可重开未征服城")
	response = click_event("chest_1")
	check(not bool(response.get("completed", false)) and int(GameState.items.supply) == 1, "读档重开不会再次领取宝箱")
	fixture()
	GameState.map_events.chest_1.reward = {"kind": "gold", "amount": 7}
	response = click_event("chest_1")
	check(bool(response.get("completed", false)) and GameState.gold == 7.0, "宝箱配置为金币时允许发金币奖励")
	check(GameState.player_xp == 0, "金币宝箱也不额外发手拍经验")

func _test_exchange() -> void:
	fixture()
	GameState.owned.S01 = 2
	GameState.items.supply = 0
	var card_count := int(GameState.owned.S01)
	var response := click_event("exchange_1")
	check(not bool(response.get("completed", false)) and int(GameState.owned.S01) == card_count, "缺道具时不先吞掉卡牌材料")
	GameState.items.supply = 1
	GameState.owned.S01 = 1
	response = click_event("exchange_1")
	check(not bool(response.get("completed", false)) and int(GameState.owned.S01) == 1 and int(GameState.items.supply) == 1, "最后一张上阵士兵受到保护，缺闲置卡不扣道具")
	GameState.carry = []
	GameState.hero_troops.G00 = ["S01"]
	response = click_event("exchange_1")
	check(not bool(response.get("completed", false)) and int(GameState.owned.S01) == 1 and int(GameState.items.supply) == 1, "挂在武将身上的士兵也不能被任务兑换吞掉")
	GameState.hero_troops = {}
	GameState.carry = ["S01", "S02", "S03"]
	GameState.owned.S01 = 2
	var reward_before := int(GameState.owned.get("E02", 0))
	response = click_event("exchange_1")
	check(bool(response.get("completed", false)) and int(GameState.owned.S01) == 1 and int(GameState.items.supply) == 0, "材料齐全时精确扣一张自由卡和一个道具")
	check(int(GameState.owned.get("E02", 0)) == reward_before + 1 and GameState.carry.has("S01"), "兑换发一张指定装备，保留上阵副本")
	check(GameState.gold == 0.0 and GameState.player_xp == 0 and GameState.round_slaps == 0, "兑换不暗扣金币，也不占拍击或刷战斗经验")
	response = click_event("exchange_1")
	check(not bool(response.get("completed", false)) and int(GameState.owned.get("E02", 0)) == reward_before + 1, "兑换任务只能完成一次")
	GameState.retreat()
	GameState.save_game()
	check(GameState.load_game() and bool(GameState.map_events.exchange_1.claimed), "兑换已完成状态跨存档保留")

func _test_timed_hunt() -> void:
	fixture()
	var event: Dictionary = GameState.map_events.hunt_1
	var target := str(event.target_card)
	check(not Events.on_enemy_killed(GameState, target), "未接任务前击杀不追溯累计")
	var response := click_event("hunt_1")
	check(bool(response.get("changed", false)) and str(event.status) == "active" and int(event.kills) == 0, "点击任务卡接取限时指定击杀")
	check(float(event.remaining) == Events.HUNT_SECONDS and GameState.round_slaps == 0, "接任务启动真实20秒，不占拍击次数")
	check(not Events.on_enemy_killed(GameState, "unrelated") and int(event.kills) == 0, "击杀非指定目标不能冒充任务进度")
	var indices: Array[int] = []
	for i in range(GameState.battle.size()):
		if str(GameState.battle[i].card_id) == target: indices.append(i)
	check(indices.size() >= 2, "当前城实际有足够的任务指定敌牌")
	if indices.size() < 2: return
	var xp_before := GameState.player_xp
	for index in indices.slice(0, 2):
		GameState.battle[index].hp = 0.01
		GameState.slap_cooldown_left = 0.0
		check(GameState.attack(index), "手动击倒指定目标，实际调用击杀任务钩子")
	check(str(event.status) == "claimable" and int(event.kills) == 2 and not bool(event.claimed), "指定击杀达标后待领奖，不提前重发奖励")
	check(GameState.player_xp == xp_before + 2, "达标前只收到有效手掌经验")
	GameState.retreat()
	check(str(event.status) == "claimable", "已达标任务不会被回营判成失败")
	GameState.save_game()
	check(GameState.load_game() and str(GameState.map_events.hunt_1.status) == "claimable", "待领取任务可以跨存档保留")
	check(GameState.start_battle(1), "待领取任务可在后续出征交付")
	response = click_event("hunt_1")
	check(bool(response.get("completed", false)) and bool(GameState.map_events.hunt_1.claimed), "再次点击任务卡领取一次经验奖")
	check(GameState.player_level() == 2 and GameState.player_xp == 7 and GameState.skill_points == 1, "两掌经验2加任务经验25等于升级后余7经验和1技能点")
	var level := GameState.player_level()
	var xp := GameState.player_xp
	var points := GameState.skill_points
	response = click_event("hunt_1")
	check(not bool(response.get("completed", false)) and GameState.player_level() == level and GameState.player_xp == xp and GameState.skill_points == points, "重复交任务不重复发经验或技能点")

func _test_hunt_timeout() -> void:
	fixture()
	click_event("hunt_1")
	var event: Dictionary = GameState.map_events.hunt_1
	GameState.advance_round(Events.HUNT_SECONDS)
	check(str(event.status) == "failed" and float(event.remaining) == 0.0, "任务20秒真实倒计时耗尽即失败")
	check(not Events.on_enemy_killed(GameState, str(event.target_card)) and int(event.kills) == 0, "超时后击杀不能补成任务")
	check(GameState.gold == 0.0 and GameState.player_xp == 0, "纯等待超时不给金币或经验")
	click_event("hunt_1")
	check(str(event.status) == "active" and float(event.remaining) == Events.HUNT_SECONDS, "目标充足时可重新接取失败任务")
	GameState.retreat()
	check(str(event.status) == "failed" and not bool(event.claimed), "未达标就回营使本次计时任务失败且不奖励")

func _test_cleared_city_visit() -> void:
	fixture()
	GameState.map_events.hunt_1.status = "claimable"
	GameState.map_events.hunt_1.kills = 2
	GameState.retreat()
	complete_city(1)
	check(not GameState.start_battle(1), "全清城仍不允许重刷敌牌")
	check(GameState.start_event_visit(1), "全清城可以单独访问宝箱和未交付NPC")
	check(GameState.in_battle and GameState.battle_mode == "visit" and GameState.battle.is_empty(), "事件访问没有敌牌，不恢复已征服区")
	var seconds := GameState.round_seconds_left
	GameState.advance_round(120.0)
	check(GameState.in_battle and GameState.round_seconds_left == seconds and GameState.player_xp == 0 and GameState.gold == 0.0, "事件访问不倒计时、不挂机产金或经验")
	var response := click_event("hunt_1")
	check(bool(response.get("completed", false)) and GameState.player_level() == 2 and GameState.player_xp == 5, "最后敌牌达标后即使清城仍可访问交任务领奖")
	response = click_event("chest_1")
	check(bool(response.get("completed", false)) and int(GameState.items.get("supply", 0)) == 1, "全清城尚未开的箱子仍可领取")
	GameState.retreat()
	check(not GameState.start_event_visit(21), "锁定城池不能被事件访问入口绕过")
	fixture()
	GameState.retreat()
	complete_city(1)
	check(GameState.start_event_visit(1), "未接任务的全清城仍可访问")
	response = click_event("hunt_1")
	check(not bool(response.get("completed", false)) and str(GameState.map_events.hunt_1.status) == "expired", "已无指定敌人的任务明确过时，不重刷敌凑数")

func _test_escort() -> void:
	fixture()
	GameState.retreat()
	complete_city(1)
	check(GameState.start_battle(2), "第二城可以承载护卫任务")
	GameState.map_event_entries(2)
	check(GameState.map_events.has("escort_2") and not GameState.map_events.escort_2.has("hp"), "护卫NPC从第二城登场且不使用敌人血量")
	var initial: Vector2 = entry("escort_2").point
	var total_hp := GameState.pile_max_health()
	var response := click_event("escort_2")
	var current: Vector2 = entry("escort_2").point
	check(bool(response.get("changed", false)) and current != initial and str(GameState.map_events.escort_2.status) == "active", "手掌推护卫NPC发生位移并接取护卫")
	check(GameState.round_slaps == 1 and GameState.player_xp == 0 and GameState.gold == 0.0 and GameState.run_damage == 0.0, "护卫位移占共享手掌但不提供攻击金币或经验")
	response = click_event("escort_2")
	check(not bool(response.get("changed", false)) and Vector2(entry("escort_2").point) == current and GameState.round_slaps == 1, "冷却内连拍不能重复移动护卫")
	response = GameState.interact_map_event("escort_2", current + Vector2(1000, 1000))
	check(not bool(response.get("changed", false)), "远离NPC的落点不能隔空护送")
	for n in range(50):
		if bool(GameState.map_events.escort_2.claimed): break
		GameState.slap_cooldown_left = 0.0
		response = click_event("escort_2")
	check(bool(GameState.map_events.escort_2.claimed) and str(GameState.map_events.escort_2.status) == "done", "持续手动朝目标推送可完成护卫任务")
	check(Vector2(entry("escort_2").point).distance_to(Vector2(entry("escort_2").target)) <= Events.ESCORT_GOAL, "护卫完成必须到达目标圈")
	check(GameState.gold == 50.0 and GameState.player_xp == 0 and GameState.run_damage == 0.0 and GameState.pile_max_health() == total_hp, "护卫只发设定的50金币任务奖，不伤敌、不额外刷成长")
	var slaps := GameState.round_slaps
	GameState.slap_cooldown_left = 0.0
	response = click_event("escort_2")
	check(not bool(response.get("completed", false)) and GameState.gold == 50.0 and GameState.round_slaps == slaps, "已完成护卫不能反复推送刷金币")
	GameState.retreat()
	GameState.save_game()
	check(GameState.load_game() and bool(GameState.map_events.escort_2.claimed) and GameState.gold == 50.0, "护卫完成状态与奖励跨档保留且不重发")
