extends Node
## 真正从回营页操作：预览与实际购买一致、门禁正确、刷新不跳滚动位置。
const Story = preload("res://scripts/story_book.gd")
const CORE := ["power", "speed", "radius", "stamina"]
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in range(6):
		await get_tree().process_frame

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "升级测试隔离正式存档")
	GameState.set_process(false)
	GameState.new_game()
	GameState.narrative_paused = false
	GameState.stop_automation(false)
	GameState.story_seen = []
	for event in Story.events():
		GameState.story_seen.append(str(event.id))
	GameState.advance_round(GameState.round_seconds_left)
	GameState.gold = 1000.0
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	main._open_home()
	main._home.open_section("upgrade")
	await frames()
	var page = main._home._upgrade_page
	check(page.visible and page.is_visible_in_tree(), "实际升级入口显示练掌堂")
	check(not main._home._section_page.visible, "旧升级树不叠在新页上")
	check(GameState.UPGRADES.size() == 13 and page.cards.size() == 13, "全部13项升级均有实际卡片")
	check(main._home._primary_action != null, "升级时仍保留下一轮入口")
	check(GameState.upgrade_level("radius") == 0 and is_equal_approx(GameState.slap_radius(), 34.0), "初始光标范围半径为34")
	check(GameState.skill_req_met("radius") and not page.cards.radius.button.disabled, "范围升级从初始城池即可购买")
	check(GameState.upgrade_cost("radius") == 24, "范围初始升级费用为24金币")
	check(page._core_grid.get_child_count() == 4 and page._core_grid.columns == 4, "1280宽度首屏并列四项核心")
	var initial_radius := GameState.upgrade_preview("radius")
	check(is_equal_approx(float(initial_radius.current.radius), 34.0) and is_equal_approx(float(initial_radius.next.radius), 40.0), "范围预览使用真实半径34到40")
	check(page.cards.radius.value.text.contains("34 → 40"), "范围卡显示真实半径变化")
	check(page.cards.radius.gain.text.contains("68 → 80") and page.cards.radius.gain.text.contains("38.4%"), "范围卡显示直径与圆形面积增量")
	page.select_upgrade("radius")
	check(page._detail.text.contains("立即生效") and page._detail.text.contains("实际范围不变"), "范围说明即时扩圈且缩放不改变实际命中")
	var node_ids := {}
	for id in page.cards:
		var card: Dictionary = page.cards[id]
		node_ids[id] = card.panel.get_instance_id()
		check(card.button.get_meta("upgrade_id") == id, "购买按钮绑定唯一升级 " + id)
	for id in CORE:
		var card: Dictionary = page.cards[id]
		check(card.picture.texture != null, "核心插画已实际加载 " + id)
		check(card.picture.texture.get_width() >= 1024, "核心插画保留原图精度 " + id)
		var before: Dictionary = GameState.up.duplicate()
		var gold := GameState.gold
		var duration := GameState.round_duration
		var preview := GameState.upgrade_preview(id)
		check(GameState.up == before and GameState.gold == gold, "查看预览不改升级和金币 " + id)
		check(GameState.round_duration == duration, "预览不修改已经开始的轮 " + id)
		var cost := GameState.upgrade_cost(id)
		card.button.pressed.emit()
		if id == "radius":
			check(is_equal_approx(GameState.slap_radius(), float(preview.next.radius)), "范围购买后立即采用预览半径")
		await frames()
		check(GameState.upgrade_level(id) == int(before[id]) + 1, "实际按钮购买成功 " + id)
		check(is_equal_approx(GameState.gold, gold - float(cost)), "实际购买仅扣当前费用 " + id)
		var actual := GameState._upgrade_snapshot()
		for field in ["damage", "interval", "duration", "slaps", "radius"]:
			check(is_equal_approx(float(actual[field]), float(preview.next[field])), "下一级预览与购后实际一致 %s/%s" % [id, field])
		check(page.selected_id == id and page._receipt.text.contains("已升级"), "购买后显示所选项目和回执 " + id)
		check(card.value.text.contains("→"), "购后显示下次可买的提升 " + id)
	check(page.cards.auto.button.disabled and page.cards.auto.gain.text.contains("前2段"), "自动拍显示真实新野牌堆前2段门禁")
	check(page.cards.carry.button.disabled and page.cards.carry.gain.text.contains("前3段"), "同行位显示真实新野牌堆前3段门禁")
	var locked_gold := GameState.gold
	page.cards.auto.button.pressed.emit()
	check(GameState.gold == locked_gold and GameState.upgrade_level("auto") == 0, "锁定升级即使触发信号也不扣钱")
	GameState.region_state[1] = "cleared"
	GameState.gold = 100000.0
	page.refresh()
	for id in ["auto", "auto_next", "auto_power", "carry", "equip", "troops", "crit", "fortune", "idle"]:
		var card: Dictionary = page.cards[id]
		var old_level := GameState.upgrade_level(id)
		var old_gold := GameState.gold
		var cost := GameState.upgrade_cost(id)
		check(not card.button.disabled, "满足实际前置后可购买 " + id)
		card.button.pressed.emit()
		await frames()
		check(GameState.upgrade_level(id) == old_level + 1, "进阶购买走真实后端 " + id)
		check(is_equal_approx(GameState.gold, old_gold - float(cost)), "进阶费用准确 " + id)
	check(page.cards.auto.button.disabled and page.cards.auto.button.text == "已学会", "一次解锁技能购后禁用")
	page.scroll_vertical = 280
	await frames()
	var scroll_before: int = page.scroll_vertical
	page.cards.power.button.pressed.emit()
	await frames()
	check(scroll_before > 0 and page.scroll_vertical == scroll_before, "购买刷新保留滚动位置")
	for id in page.cards:
		check(page.cards[id].panel.get_instance_id() == node_ids[id], "刷新保持卡片节点 " + id)
	GameState.gold = 0.0
	page.refresh()
	check(page.cards.power.button.disabled and page.cards.power.button.text.contains("还差"), "金币不足显示缺口")
	var old_power := GameState.upgrade_level("power")
	page.cards.power.button.pressed.emit()
	check(GameState.gold == 0.0 and GameState.upgrade_level("power") == old_power, "资金不足不能购买")
	check(page.cards.radius.button.disabled and page.cards.radius.button.text.contains("还差"), "范围金币不足显示实际缺口")
	var old_radius := GameState.upgrade_level("radius")
	var radius_before := GameState.slap_radius()
	page.cards.radius.button.pressed.emit()
	check(GameState.gold == 0.0 and GameState.upgrade_level("radius") == old_radius and is_equal_approx(GameState.slap_radius(), radius_before), "范围资金不足不扣钱也不扩大光标")
	GameState.gold = 100000.0
	GameState.up.speed = 40
	GameState.up.radius = 20
	GameState.up.stamina = 60
	page.refresh()
	check(is_equal_approx(GameState.slap_radius(), 154.0), "范围满20级实际半径为154")
	for id in ["speed", "radius", "stamina"]:
		check(page.cards[id].button.disabled and page.cards[id].button.text == "已满级", "满级状态准确 " + id)
		var preview := GameState.upgrade_preview(id)
		check(preview.current == preview.next, "满级不虚构下一档 " + id)
		var old_gold := GameState.gold
		page.cards[id].button.pressed.emit()
		check(GameState.gold == old_gold, "满级按钮不扣钱 " + id)
	GameState.up.stamina = 1
	GameState.bonus.stamina_flat = 3.0
	var modified := GameState.upgrade_preview("stamina")
	check(float(modified.current.duration) >= GameState.upgrade_value("stamina") + 6.0, "预览包含建筑增加时长")
	GameState.owned["G04"] = 1
	GameState.carry.clear()
	check(GameState.carry_add("G04"), "装备预览测试将领实际入阵")
	GameState.up.equip = 2
	var armour := ""
	for card in GameData.cards:
		if str(card.get("type", "")) == "装备" and str(card.get("subtype", "")) == "铠甲" and str(card.get("effect", "")).contains("体力上限"):
			armour = str(card.id)
			break
	GameState.owned[armour] = 1
	check(armour != "" and GameState.equip_to("G04", armour), "预览测试实际装上增加时长的铠甲")
	var equipped_preview := GameState.upgrade_preview("stamina")
	var duration_before := GameState.round_duration_value()
	check(GameState.buy_upgrade("stamina"), "带装备的时长升级成功")
	check(is_equal_approx(GameState.round_duration_value(), float(equipped_preview.next.duration)), "下一档预览包含装备百分比")
	check(GameState.round_duration_value() > duration_before + 2.0, "铠甲时长百分比会放大升级增量")
	page.select_upgrade("stamina")
	check(page._detail.text.contains("下一轮"), "时长明确从下一轮生效")
	var saved_up: Dictionary = GameState.up.duplicate()
	GameState.save_game()
	GameState.up = {}
	check(GameState.load_game() and GameState.up == saved_up, "升级结果可存档并读回")
	page.refresh()
	for height in [800, 720]:
		main.size = Vector2(1280, height)
		main._home._fit_to_parent()
		page.scroll_vertical = 0
		await frames()
		var visible_rect: Rect2 = page.get_global_rect()
		for id in CORE:
			check(visible_rect.grow(1.0).encloses(page.cards[id].button.get_global_rect()), "核心购买首屏可见 %s/%d" % [id, height])
		check(page._content.size.x <= page.size.x + 1.0, "升级内容不水平溢出 %d" % height)
		check(page.get_v_scroll_bar().visible and page.get_v_scroll_bar().size.x >= 8.0, "滚动条可见且有可拖宽度 %d" % height)
		page.scroll_vertical = 10000
		await frames()
		check(page.get_global_rect().grow(1.0).encloses(page.cards.fortune.button.get_global_rect()), "最后升级可滚动到达 %d" % height)
	main.queue_free()
	await frames()
	print("[Upgrade art v2.2] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
