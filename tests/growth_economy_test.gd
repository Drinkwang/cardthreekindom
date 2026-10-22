extends Node
## 手动成长与经济专项。使用 --test-profile；不读取或写入正式玩家存档。
## Godot --headless --path . tests/GrowthEconomyTest.tscn -- --test-profile
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

func durable_targets() -> void:
	for enemy in GameState.battle:
		enemy.hp = 100000.0
		enemy.hp_max = 100000.0

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "测试必须使用隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	_test_no_passive_income()
	_test_level_and_skill_points()
	_test_manual_experience()
	_test_manual_gold_source()
	_test_chain_flip_reward()
	_test_damage_over_time()
	_test_growth_save_roundtrip()
	print("[Growth economy] checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_no_passive_income() -> void:
	fixture()
	check(GameState.gold == 0.0 and GameState.player_level() == 1, "新游戏没有启动金币，玩家为1级")
	check(GameState.player_xp == 0 and GameState.skill_points == 0, "新游戏经验与技能点为0")
	check(GameState.owned == {"I01": 1} and GameState.carry.is_empty(), "新游戏只有主角，不附送士兵或武将")
	check(GameState.hero_equip.is_empty() and GameState.hero_troops.is_empty(), "新游戏没有附着装备或带兵")
	check(not GameState.hero_xp.has(GameState.HERO_ALWAYS), "固定主角使用玩家成长，不另外创建武将经验")
	GameState.cleared_zones[1] = [0]
	GameState.table_wins[1] = 1
	GameState.cities[1] = {"buildings": ["B06", "B08"]}
	GameState.city_quality[1] = [0, 0]
	GameState.city_lv[1] = [0, 0]
	GameState._recompute_bonus()
	check(is_zero_approx(GameState.advance_buildings(86400.0)), "装配建筑等待一天也不产生挂机金币")
	check(is_zero_approx(GameState.gold_per_hour()), "全局每小时金币为0")
	check(is_zero_approx(GameState.offline_efficiency()), "离线金币效率为0")
	check(is_zero_approx(GameState.offline_cap_hours()), "离线金币时长为0")
	GameState._process(120.0)
	check(GameState.gold == 0.0 and GameState.player_xp == 0 and GameState.skill_points == 0, "不拍卡等待只结束回合，不产生金币、经验或技能点")
	GameState.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path()))
	data.last_save = Time.get_unix_time_from_system() - 14 * 86400
	var file := FileAccess.open(GameState.save_path(), FileAccess.WRITE)
	check(file != null, "可写隔离档的离线时间夹具")
	if file == null: return
	file.store_string(JSON.stringify(data))
	file.close()
	check(GameState.load_game(), "本轮新格式可以重新载入")
	check(GameState.gold == 0.0 and GameState.player_xp == 0, "离线两周重新载入不支付金币或经验")
	check(GameState.load_game() and GameState.gold == 0.0, "重复读档也不发离线奖励")

func _test_level_and_skill_points() -> void:
	fixture()
	GameState.retreat()
	check(GameState.player_xp_required() == 20, "玩家首级需要20经验")
	GameState.gain_player_xp(19)
	check(GameState.player_level() == 1 and GameState.player_xp == 19 and GameState.skill_points == 0, "不足阈值不提前升级")
	GameState.gain_player_xp(1)
	check(GameState.player_level() == 2 and GameState.player_xp == 0 and GameState.skill_points == 1, "达到阈值升一级并给1技能点")
	check(GameState.player_xp_required() == 30, "第二级经验需求增加至30")
	GameState.gain_player_xp(70)
	check(GameState.player_level() == 4 and GameState.player_xp == 0 and GameState.skill_points == 3, "一笔经验跨两级，逐级扣经验并各给1点")
	GameState.gain_player_xp(-100)
	check(GameState.player_level() == 4 and GameState.player_xp == 0 and GameState.skill_points == 3, "负经验不能降级或制造技能点")
	GameState.gold = 123.0
	check(GameState.upgrade_cost("power") == 1 and GameState.upgrade_cost("radius") == 1, "基础技能每级消耗1技能点")
	check(GameState.buy_upgrade("power"), "休息时可用技能点升级拍力")
	check(GameState.skill_points == 2 and GameState.gold == 123.0 and GameState.upgrade_level("power") == 1, "学技能只减1点，不扣金币")
	check(GameState.player_level() == 4, "技能等级不再反向产生玩家等级")
	check(GameState.buy_upgrade("radius") and GameState.buy_upgrade("speed"), "剩余两点可自行分配基础技能")
	check(GameState.skill_points == 0 and GameState.gold == 123.0, "多次升级技能点守恒且金币不变")
	check(not GameState.buy_upgrade("power") and GameState.upgrade_level("power") == 1, "金币充足但没技能点时不能学习")
	GameState.skill_points = 2
	GameState.up.radius = 20
	check(not GameState.buy_upgrade("radius") and GameState.skill_points == 2, "满级技能拒绝且不扣点")
	check(not GameState.buy_upgrade("missing") and GameState.skill_points == 2, "无效技能拒绝且不扣点")
	check(GameState.up_def("idle").is_empty() and not GameState.buy_upgrade("idle"), "挂机效率技能彻底退休")
	GameState.up.power = 0
	check(not GameState.buy_upgrade("crit") and GameState.skill_points == 2, "前置未满足时不能绕过技能树扣点")
	check(GameState.start_battle(1), "技能学习后可继续出征")
	check(not GameState.buy_upgrade("power") and GameState.skill_points == 2 and GameState.gold == 123.0, "战斗中拒绝学习，不改变技能点或金币")

func _test_manual_experience() -> void:
	fixture()
	GameState.owned.G00 = 1
	GameState.owned.G04 = 1
	GameState.owned.G05 = 1
	GameState.owned.S01 = 1
	GameState.carry = ["G00", "G04", "S01"]
	durable_targets()
	check(GameState.hero_xp_required("G00") == 10 and is_equal_approx(GameState.hero_lv_mult("G00"), 1.0), "武将首级需10经验且初始倍率1")
	check(GameState.begin_slap_batch(), "一次多目标手掌可以开始")
	check(GameState.attack(0) and GameState.attack(1), "同一掌可命中两个不同敌牌")
	check(not GameState.attack(0), "同一掌不能重复命中同一张牌")
	GameState.end_slap_batch()
	check(GameState.player_xp == 0 and GameState.round_slaps == 1 and GameState.gold == 0.0, "只打伤而未拍翻时没有金币或玩家经验")
	check(GameState.hero_xp_of("G00") == 0 and GameState.hero_xp_of("G04") == 0 and not GameState.first_flip_reward, "未拍翻不发武将经验或首翻奖励")
	check(GameState.combo > 0 and int(GameState.build_counts.get("G04", 0)) == 2, "未拍翻仍可积累本轮连击和构筑触发次数")
	GameState.slap_cooldown_left = 0.0
	GameState.battle[0].hp = 1.0
	GameState.battle[1].hp = 1.0
	check(GameState.begin_slap_batch(), "拍翻多目标手掌可以开始")
	check(GameState.attack(0) and GameState.attack(1), "同一掌实际拍翻两张敌牌")
	GameState.end_slap_batch()
	check(GameState.player_xp == 1 and GameState.round_slaps == 2, "一掌拍翻多张牌只给一次玩家经验")
	check(GameState.hero_xp_of("G00") == 1 and GameState.hero_xp_of("G04") == 1, "两位上阵武将每人各得一次经验")
	check(GameState.hero_xp_of("G05") == 0 and not GameState.hero_xp.has("S01") and not GameState.hero_xp.has(GameState.HERO_ALWAYS), "未上阵武将、士兵及固定主角不获得独立武将经验")
	var cash := GameState.gold
	check(not GameState.attack(2) and not GameState.attack(2, false, true), "共享冷却和自动攻击均被拒绝")
	check(not GameState.attack(-1) and not GameState.attack(GameState.battle.size()), "无效目标不算攻击")
	check(GameState.player_xp == 1 and GameState.hero_xp_of("G00") == 1 and GameState.gold == cash, "所有无效输入不发经验或金币")
	GameState.slap_cooldown_left = 0.0
	check(not GameState.attack(0) and GameState.player_xp == 1, "反复拍死牌不刷经验")
	for index in [3, 4, 6, 7, 8, 10, 11, 12, 15]:
		GameState.slap_cooldown_left = 0.0
		GameState.battle[index].hp = 1.0
		check(GameState.attack(index), "实际拍翻获得成长：%d" % index)
	check(GameState.player_xp == 10, "10次有翻牌的手掌等于10玩家经验")
	check(GameState.hero_level("G00") == 2 and GameState.hero_xp_of("G00") == 0, "上阵武将第10次翻牌手掌升到2级并扣除本级经验")
	check(GameState.hero_xp_required("G00") == 15 and is_equal_approx(GameState.hero_lv_mult("G00"), 1.08), "武将升级提高后续需求与自身拍力")
	check(GameState.hero_level("G04") == 2 and GameState.hero_level("G05") == 1, "同行武将共同成长，仓库武将不能白升级")
	check(not GameState.buy_hero_lv("G00"), "金币不能直接购买武将经验等级")
	GameState.hero_lv.G00 = 20
	GameState.hero_xp.G00 = 0
	GameState.slap_cooldown_left = 0.0
	GameState.battle[16].hp = 1.0
	check(GameState.attack(16) and GameState.hero_level("G00") == 20, "武将达到20级后拍翻不能突破上限")
	GameState.retreat()
	var xp := GameState.player_xp
	check(not GameState.attack(1) and GameState.player_xp == xp, "结束回合后不接受拍击经验")

func _test_manual_gold_source() -> void:
	fixture()
	GameState.first_flip_reward = true
	GameState.battle[0].hp = 5.0
	GameState.battle[0].hp_max = 5.0
	check(GameState.attack(0) and float(GameState.battle[0].hp) > 0.0, "普通手掌只打伤厚牌")
	check(GameState.gold == 0.0 and GameState.run_gold == 0.0 and GameState.player_xp == 0, "厚牌未翻时所有手拍进度收益为零")
	check(is_zero_approx(float(GameState.last_slap.get("gold_gain", -1.0))), "未翻牌反馈不显示虚假金币")
	while float(GameState.battle[0].hp) > 0.0:
		GameState.slap_cooldown_left = 0.0
		check(GameState.attack(0), "持续手拍拍翻受伤厚牌")
	var flip_reward := 5.0 * (GameState.Progression.DAMAGE_PAY + GameState.Progression.KILL_PAY) * GameState.fortune_mult()
	check(is_equal_approx(GameState.gold, flip_reward) and is_equal_approx(GameState.run_gold, flip_reward), "拍翻才一次发放整张牌的金币，保留原总收益")
	check(GameState.player_xp == 1, "多掌打伤直到拍翻只发一次成长")
	GameState.slap_cooldown_left = 0.0
	check(not GameState.attack(0) and is_equal_approx(GameState.gold, flip_reward) and GameState.player_xp == 1, "重复拍翻已死牌不重复领奖")
	fixture()
	durable_targets()
	GameState.first_flip_reward = true
	var targets: Array[int] = []
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == 0:
			GameState.battle[i].hp = 1.0
			GameState.battle[i].hp_max = 1.0
			targets.append(i)
	var expected := targets.size() * (GameState.Progression.DAMAGE_PAY + GameState.Progression.KILL_PAY) * GameState.fortune_mult()
	check(GameState.begin_slap_batch(), "金币来源夹具开始范围手掌")
	for index in targets:
		check(GameState.attack(index), "手掌实际击倒区内敌牌")
	GameState.end_slap_batch()
	check(GameState.zone_cleared(1, 0), "金币来源夹具确实征服完整分区")
	check(is_equal_approx(GameState.gold, expected) and is_equal_approx(GameState.run_gold, expected), "范围拍翻逐牌结算，没有额外城建或清区款")

func _test_chain_flip_reward() -> void:
	fixture()
	GameState.owned.G24 = 1
	GameState.carry = ["G24"]
	durable_targets()
	for index in [0, 1]:
		GameState.battle[index].hp = 1.0
		GameState.battle[index].hp_max = 1.0
	GameState.battle[0].mark_remaining = 6.0
	var expected := 2.0 * (GameState.Progression.DAMAGE_PAY + GameState.Progression.KILL_PAY) * GameState.fortune_mult() + 8.0
	check(GameState.attack(0), "手动翻牌触发标记追击")
	check(GameState.run_kills == 2 and float(GameState.battle[1].hp) == 0.0, "同一手掌连锁实际拍翻两张牌")
	check(is_equal_approx(GameState.gold, expected) and is_equal_approx(GameState.run_gold, expected), "连锁逐牌结算且首翻奖励只发一次")
	check(GameState.player_xp == 1 and GameState.hero_xp_of("G24") == 1, "连锁多次翻牌共用本次手掌成长")

func _test_damage_over_time() -> void:
	fixture()
	GameState.owned.G30 = 1
	GameState.carry = ["G30", "S01", "S02"]
	durable_targets()
	check(GameState.attack(0, true), "手动重拍可触发现有燃烧特性")
	check(float(GameState.battle[0].get("burn_remaining", 0.0)) > 0.0, "燃烧夹具确实生效")
	var cash := GameState.gold
	var xp := GameState.player_xp
	var hero_xp := GameState.hero_xp_of("G30")
	check(cash == 0.0 and xp == 0 and hero_xp == 0, "点燃但没有拍翻时不发收益")
	var hp := float(GameState.battle[0].hp)
	GameState.advance_round(1.01)
	check(float(GameState.battle[0].hp) < hp, "等待推进现有燃烧伤害")
	check(GameState.gold == cash and GameState.player_xp == xp and GameState.hero_xp_of("G30") == hero_xp, "持续伤害不产生等待金币或额外经验")
	GameState.battle[0].hp = 0.01
	GameState.advance_round(1.01)
	check(float(GameState.battle[0].hp) == 0.0, "燃烧可正常击倒已有受伤敌牌")
	check(GameState.gold == cash and GameState.player_xp == xp, "持续伤害击倒不支付击杀金币或经验")
	check(not GameState.first_flip_reward, "燃烧击倒不能领取手动首翻金币")
	GameState.slap_cooldown_left = 0.0
	GameState.battle[1].hp = 1.0
	check(GameState.attack(1) and GameState.gold > cash and GameState.player_xp == xp + 1, "恢复手动拍击后正常产金币与经验")

func _test_growth_save_roundtrip() -> void:
	fixture()
	GameState.owned.G00 = 1
	GameState.carry = ["G00", "S01", "S02"]
	durable_targets()
	for index in range(13):
		GameState.slap_cooldown_left = 0.0
		GameState.battle[index].hp = 1.0
		check(GameState.attack(index), "存档成长夹具真实拍翻%d" % (index + 1))
	GameState.retreat()
	GameState.gain_player_xp(11)
	check(GameState.player_level() == 2 and GameState.player_xp == 4 and GameState.skill_points == 1, "存档前玩家等级、余量、点数各自有值")
	check(GameState.hero_level("G00") == 2 and GameState.hero_xp_of("G00") == 3, "存档前武将等级、余量各自有值")
	var cash := GameState.gold
	GameState.save_game()
	GameState.player_lv = 1
	GameState.player_xp = 0
	GameState.skill_points = 0
	GameState.hero_lv = {}
	GameState.hero_xp = {}
	check(GameState.load_game(), "真实成长存档可重新载入")
	check(GameState.player_level() == 2 and GameState.player_xp == 4 and GameState.skill_points == 1, "存读档保留玩家真实成长，不能从技能数重算")
	check(GameState.hero_level("G00") == 2 and GameState.hero_xp_of("G00") == 3, "存读档不再清空武将等级和经验")
	check(is_equal_approx(GameState.gold, cash), "存读档不额外支付离线或旧档返还金币")
