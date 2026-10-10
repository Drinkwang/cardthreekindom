extends Node
## 当前主自检：限时整城拍堆、范围成长、古代设定与实际页面入口。
const Art = preload("res://scripts/ui/print_art.gd")
const Story = preload("res://scripts/story_book.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func fixture() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.narrative_paused = false
	GameState.stop_automation(false)
	GameState.up["crit"] = 0
	# 页面测试不弹一次性剧情；剧情触发由独立设定测试验证。
	GameState.story_seen = []
	for event in Story.events():
		GameState.story_seen.append(str(event.id))

func live_index() -> int:
	for i in range(GameState.battle.size()):
		if float(GameState.battle[i]["hp"]) > 0.0:
			return i
	return -1

func flip_pile() -> void:
	GameState.advance_round(GameState.slap_interval())
	check(GameState.begin_slap_batch(), "范围拍堆能在冷却结束后开始")
	var generation := GameState.battle_gen
	var count := GameState.battle.size()
	for i in range(count):
		check(GameState.attack(i), "同一掌范围轻拍可以击中不同牌 %d" % i)
	check(GameState.battle_gen == generation, "本掌所有目标结算前不补出新牌堆")
	GameState.end_slap_batch()
	check(GameState.in_battle and GameState.battle_gen == generation + 1, "全城牌堆清空只补牌一次，限时轮继续")

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "测试自动使用独立存档")
	_test_round()
	_test_upgrades()
	_test_replenish()
	_test_last_second()
	_test_automation()
	_test_save()
	_test_setting()
	await _test_ui()
	print("[Incremental v2.2] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_round() -> void:
	fixture()
	check(GameState.in_battle and GameState.round_active, "开局直接进入赚钱轮")
	check(is_equal_approx(GameState.round_duration, 30.0), "基础轮长30秒")
	check(is_equal_approx(GameState.round_seconds_left, 30.0), "倒计时从完整轮长开始")
	check(is_equal_approx(GameState.slap_interval(), 0.6), "基础拍击间隔0.6秒")
	var before := GameState.gold
	check(GameState.attack(0), "第一掌即时命中")
	check(GameState.gold > before and GameState.run_gold > 0.0, "伤害即时赚钱，无需等清空全城")
	check(GameState.last_slap.get("gold_gain", 0.0) > 0.0, "反馈包含本次金币")
	var damage := GameState.run_damage
	var gold := GameState.gold
	check(not GameState.attack(0), "重复输入被共享冷却拦住")
	check(GameState.gold == gold and GameState.run_damage == damage and GameState.round_slaps == 1, "被拦输入不发钱不计次数")
	GameState.advance_round(0.2)
	check(not GameState.attack(live_index()), "未结束冷却不能拍另一张绕过限制")
	GameState.advance_round(0.4)
	GameState.stamina = 0
	check(GameState.attack(live_index()), "旧耐力为0也不截断限时轮")
	var left := GameState.round_seconds_left
	GameState.narrative_paused = true
	GameState.advance_round(10.0)
	check(is_equal_approx(GameState.round_seconds_left, left), "整备暂停时不消耗轮时间")
	check(not GameState.attack(live_index()), "暂停时不能凭点击发钱")
	GameState.narrative_paused = false
	GameState.advance_round(1.0)
	check(GameState.round_gold_per_second() > 0.0, "每秒收入使用真实轮收益")
	gold = GameState.gold
	var earned := GameState.run_gold
	GameState.advance_round(100.0)
	check(not GameState.in_battle and not GameState.round_active, "时间到自动结束轮")
	check(is_zero_approx(GameState.round_seconds_left), "到期倒计时截在0")
	check(is_equal_approx(GameState.gold, gold), "到期不会再次发放已入账金币")
	check(is_equal_approx(float(GameState.last_outcome.gold), earned), "结算精确保留本轮收入")
	check(str(GameState.last_outcome.get("reason", "")) == "time_up", "到期结算使用时间结束原因")
	check(not GameState.attack(0), "已结束轮不能继续获金")
	GameState.settle_run()
	check(is_equal_approx(GameState.gold, gold), "重复结算不会重复发钱")

func _test_upgrades() -> void:
	fixture()
	GameState.retreat()
	GameState.gold = 10000.0
	var interval := GameState.slap_interval()
	var duration := GameState.round_duration_value()
	var power := GameState.click_damage()
	var radius := GameState.slap_radius()
	var cash := GameState.gold
	check(GameState.buy_upgrade("speed"), "金币可购买拍速升级")
	check(GameState.gold < cash and GameState.slap_interval() < interval, "拍速升级扣款并提升单位时间拍数")
	check(GameState.buy_upgrade("stamina"), "旧耐力升级ID迁移为时长")
	check(GameState.round_duration_value() > duration, "时长升级延长下一轮")
	check(GameState.buy_upgrade("power") and GameState.click_damage() > power, "拍力升级提高每次产出基础")
	check(GameState.buy_upgrade("radius") and GameState.slap_radius() > radius, "范围升级扩大每次拍卡圆圈")
	var owned := GameState.owned.duplicate(true)
	check(GameState.start_battle(1), "购买升级后可再开一轮")
	check(GameState.round_duration > duration and GameState.round_slaps == 0, "下一轮用新时长并重置轮计数")
	check(GameState.owned == owned and GameState.up.speed == 1 and GameState.up.radius == 1, "开轮保留收藏与拍速范围升级")

func _test_replenish() -> void:
	fixture()
	GameState.up["power"] = 90
	var expected_tables := GameState.table_count(1)
	check(GameState.pile_card_count() == 21, "首次赚钱轮一次铺新野全部五段二十一牌")
	var slaps := GameState.round_slaps
	flip_pile()
	check(GameState.round_slaps == slaps + 1, "整城多牌范围轻拍按一掌计算")
	check(GameState.round_tables_flipped == expected_tables, "一次清堆记录全城五段完成")
	check(GameState.region_status(1) == "cleared", "清空整城牌堆推进区域")
	check(GameState.in_battle and GameState.round_seconds_left > 0.0, "城市首次完成后仍能继续赚钱")
	check(GameState.round_first_clears.size() == 1, "一轮记录城市首次完成")
	check(GameState.is_unlocked(2), "城市完成解锁相邻区域")
	var roster := GameState.owned.duplicate(true)
	var affinities := GameState.affinity.duplicate(true)
	var tables := GameState.round_tables_flipped
	flip_pile()
	check(GameState.round_tables_flipped == tables + expected_tables, "同城整堆能继续循环采集")
	check(GameState.owned == roster and GameState.affinity == affinities, "重复采集不重复发首通牌和亲和奖励")
	var cash := GameState.gold
	var round_gain := GameState.run_gold
	GameState.retreat()
	check(is_equal_approx(GameState.gold, cash), "主动收钱不重复发已入账收益")
	check(is_equal_approx(float(GameState.last_outcome.gold), round_gain), "多堆收益在本轮累计结算")
	check(GameState.start_battle(1), "已完成区域可继续赚钱")
	check(GameState.table_progress(1) == expected_tables, "重刷不退回城市进度")
	GameState.up["power"] = 0
	GameState.advance_round(GameState.slap_interval())
	var index := live_index()
	var hp := float(GameState.battle[index].hp)
	check(GameState.begin_slap_batch() and GameState.attack(index), "正常范围轻拍批次命中")
	check(not GameState.attack(index), "同一范围批次不能重复拍同一张牌")
	check(float(GameState.battle[index].hp) < hp, "范围轻拍正确减少卡牌厚度")
	GameState.end_slap_batch()
	check(not GameState.begin_slap_batch(), "下一次单击仍须等待冷却")

func _test_automation() -> void:
	fixture()
	GameState.up["power"] = 90
	flip_pile()
	GameState.retreat()
	GameState.up["auto"] = 1
	GameState.up["auto_next"] = 1
	GameState.up["power"] = 2
	check(GameState.set_automation(true), "自动采集可开始")
	check(GameState.auto_ratio() < 1.0, "自动拍效率低于手动")
	var cash := GameState.gold
	GameState.advance_round(10.0)
	check(GameState.gold > cash and GameState.round_slaps > 1, "自动轮按时间推进产金")
	check(GameState.round_slaps <= int(ceil(10.0 / GameState.auto_interval())) + 1, "自动拍受实际自动间隔限制")
	GameState.advance_round(80.0)
	check(GameState.automation_enabled and GameState.practice_runs >= 2, "持续自动采集会结算并接续下一轮")
	GameState.stop_automation(false)
	var actions := GameState.round_slaps
	GameState.advance_round(1.0)
	check(GameState.round_slaps == actions, "停止自动后不再偷偷拍击")
	GameState.retreat()

func _test_last_second() -> void:
	fixture()
	# 只让最薄段在最后一秒完成，其他城牌仍在，不伪造提前完成整城。
	var last := -1
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].stage) == 0:
			last = i
			GameState.battle[i].hp = 0.0
			GameState.battle[i].kill_rewarded = true
	GameState.battle[last].hp = 1.0
	GameState.battle[last].kill_rewarded = false
	GameState.battle[last].burn_remaining = 1.0
	GameState.battle[last].burn_dps = 2.0
	GameState.battle[last].burn_tick = 0.0
	GameState.round_seconds_left = 1.0
	GameState.round_seconds_elapsed = 29.0
	GameState.advance_round(1.0)
	check(not GameState.in_battle and str(GameState.last_outcome.reason) == "time_up", "最后一秒燃烧后正常到期结算")
	check(GameState.run_damage == 1.0 and GameState.round_tables_flipped == 1, "到期前合法持续伤害可翻完一段")
	check(GameState.table_progress(1) == 1 and GameState.gold > 0.0, "最后一秒完成薄段保留收入与永久进度")
	check(GameState.region_status(1) != "cleared", "只完成薄段不误记整城首通")
	var cash := GameState.gold
	GameState.advance_round(10.0)
	GameState._tick_build_effects(10.0)
	check(GameState.gold == cash, "到期后持续伤害不再幽灵产金")

func _test_save() -> void:
	fixture()
	GameState.attack(0)
	GameState.retreat()
	GameState.up["speed"] = 2
	GameState.up["stamina"] = 3
	GameState.up["radius"] = 4
	GameState.gold = 123.456
	var roster := GameState.owned.duplicate(true)
	var outcome := GameState.last_outcome.duplicate(true)
	GameState.save_game()
	GameState.gold = 0.0
	GameState.up.clear()
	check(GameState.load_game(), "新版本存档能重载")
	check(is_equal_approx(GameState.gold, 123.456), "金币保留小数精度")
	check(GameState.up.speed == 2 and GameState.up.stamina == 3 and GameState.up.radius == 4, "拍速时长与范围升级保存")
	var same_stock := GameState.owned.size() == roster.size()
	for id in roster:
		same_stock = same_stock and int(GameState.owned.get(id, -1)) == int(roster[id])
	check(same_stock, "人物替换后旧ID与每张持有数量保持")
	check(is_equal_approx(float(GameState.last_outcome.gold), float(outcome.gold)), "最近轮次金币重载仍精确")
	check(int(GameState.last_outcome.slaps) == int(outcome.slaps), "轮次拍数保存")

func _test_setting() -> void:
	check(GameData.effect_text(GameData.card("E13")).contains("每轮时长 +5%"), "铠甲百分比词条显示实际轮时长")
	check(GameData.effect_text(GameData.card("E35")).contains("每轮时长 +4秒"), "固定体力词条显示换算后的秒数")
	check(GameData.effect_text(GameData.card("G27")).contains("每轮时长 +4秒"), "额外拍击词条显示当前时长效果")
	for c in GameData.cards:
		check(str(c.get("route", "")) != "现实线", "运行时人物与路线为古代 " + str(c.id))
	for pair in [["I01", "新野校尉"], ["G00", "荆州壮士"], ["G56", "荆州游侠"], ["B05", "杂货铺"]]:
		check(GameData.card_name(pair[0]) == pair[1], "设定映射 " + pair[0])
	for id in ["I01", "G00", "G56"]:
		check(Art.texture(id) != null, "替换人物有可用古代肖像 " + id)
	for event in Story.events():
		for page in event.pages:
			var content := str(page)
			for modern in ["小野", "雷飞", "唐棠", "小学生", "操场", "课桌", "零花钱"]:
				check(not content.contains(modern), "剧情不混入现代设定 " + modern)

func all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button:
		result += str(node.text) + "\n"
	for child in node.get_children():
		result += all_text(child)
	return result

func _test_ui() -> void:
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._story_camp_run = GameState.runs
	for i in range(3):
		await get_tree().process_frame
	check(main._lbl_stamina.text.contains("秒"), "牌桌显示倒计时而非耐力")
	check(main._lbl_pace.text.contains("秒"), "牌桌显示拍击冷却")
	check(main._cards.size() == 21, "实际主界面显示全城二十一张牌")
	check(main._slap_cursor != null and main._camera_toolbar != null, "实际主界面有拍卡圆圈和缩放工具")
	var first: Dictionary = main._cards[0]
	var last: Dictionary = main._cards[main._cards.size() - 1]
	var start: Vector2 = main._world_to_screen(first.rest_pos + first.size * 0.5)
	var finish: Vector2 = main._world_to_screen(last.rest_pos + last.size * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	main._on_table_input(press)
	check(GameState.round_slaps == 1 and GameState.run_damage > 0.0, "左键按下立即以圆圈范围拍卡")
	var click_damage := GameState.run_damage
	var click_gold := GameState.gold
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	main._on_table_input(motion)
	check(GameState.round_slaps == 1 and GameState.run_damage == click_damage, "按住移动只移动圆圈，不沿途扫牌")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = finish
	main._on_table_input(release)
	check(GameState.round_slaps == 1 and GameState.gold == click_gold, "松开左键不重复拍卡或改为重拍")
	GameState.advance_round(GameState.slap_interval())
	main._navigate_minimap(last.rest_pos + last.size * 0.5)
	finish = main._world_to_screen(last.rest_pos + last.size * 0.5)
	main._cursor_preview = finish
	press.position = finish
	main._on_table_input(press)
	check(GameState.round_slaps == 2 and GameState.gold > click_gold, "冷却后单击新位置真正命中当前圆圈范围")
	GameState.advance_round(GameState.round_seconds_left)
	await get_tree().process_frame
	check(main._home.visible, "轮次结束真实回营")
	check(main._home._hub_tiles.size() == 4, "保留商店构筑升级基建四区")
	check(main._home._primary_action != null and main._home._primary_action.text.contains("一轮"), "结算提供再来一轮")
	main._home._primary_action.pressed.emit()
	await get_tree().process_frame
	check(GameState.in_battle and not main._home.visible, "再来一轮按钮真正开始轮次")
	main._open_home()
	main._process(0.1)
	check(GameState.narrative_paused, "打开手动整备暂停计时")
	main._close_home()
	main._process(0.1)
	check(not GameState.narrative_paused, "关闭整备恢复计时")
	for word in ["小野", "雷飞", "唐棠", "操场", "课桌", "耐力耗尽"]:
		check(not all_text(main).contains(word), "实际主界面无旧设定文案 " + word)
	main.queue_free()
	await get_tree().process_frame
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	menu._open_rules()
	await get_tree().process_frame
	for word in ["操场", "课桌", "耐力耗尽", "1 点耐力"]:
		check(not all_text(menu).contains(word), "封面与玩法说明已更新 " + word)
	menu.queue_free()
	await get_tree().process_frame
