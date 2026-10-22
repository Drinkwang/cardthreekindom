extends Node
## 从营地实际技能页验证选择、单处消费、真实门槛和两个常用窗口高度。
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 8) -> void:
	for i in count: await get_tree().process_frame

func snapshot(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename)) == OK, "保存 " + filename)

func click(button: Button) -> void:
	if DisplayServer.get_name() == "headless": button.pressed.emit()
	else:
		var point := button.get_global_rect().get_center()
		# 圆图下方含标签，选择真实圆图中心，避免落到节点间的留白。
		if button.has_meta("upgrade_card_id"): point.y = button.global_position.y + float(button.get("diameter")) * 0.5 + 4.0
		var move := InputEventMouseMotion.new()
		move.position = point
		move.global_position = point
		get_viewport().push_input(move, true)
		await frames(2)
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			event.position = point
			event.global_position = point
			get_viewport().push_input(event, true)
			await frames(2)
	await frames()

func _ready() -> void:
	if GameState.save_path() == GameState.SAVE_PATH:
		push_error("CultivationGraphTest 必须使用 --test-profile")
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	GameState.set_process(false)
	GameState.new_game()
	GameState.settle_run("休息")
	GameState.skill_points = 8
	GameState.gold = 137.0
	var home = load("res://scripts/home_view.gd").new()
	add_child(home)
	home.open_section("upgrade")
	await frames()
	var page = home._upgrade_page
	check(page.cards.size() == 9, "完整九项手动技能")
	check(home._title.text == "升级 · 修炼图" and home.find_child("ReturnToMain", true, false) == null, "修炼图只有返回大本营的页头返回入口")
	var purchase_count := 0
	for button in page.find_children("*", "Button", true, false):
		if button.has_meta("skill_purchase"): purchase_count += 1
	check(purchase_count == 1 and page.find_children("*", "Button", true, false).size() == 10, "九个选择节点和唯一升级按钮")
	var before: Dictionary = GameState.up.duplicate()
	for id in page.IDS:
		await click(page.cards[id].art_button)
		check(page.selected_id == id and page._detail_title.text == str(page.COPY[id][0]), "节点选择显示独立详情 " + id)
		check(GameState.up == before and GameState.skill_points == 8 and GameState.gold == 137.0, "选中节点不消费或升级 " + id)
		check(page.cards[id].panel.artwork != null, "圆章插画已载入 " + id)
	await click(page.cards.crit.art_button)
	check(page._buy_button.disabled and page._requirement.text.contains("拍力"), "暴击前置来自实际拍力技能")
	page._buy_button.pressed.emit()
	check(GameState.upgrade_level("crit") == 0 and GameState.skill_points == 8, "强制触发锁定按钮也不能升级")
	await click(page.cards.power.art_button)
	await click(page._buy_button)
	check(GameState.upgrade_level("power") == 1 and GameState.skill_points == 7 and GameState.gold == 137.0, "右按钮只花一技能点，金币不变")
	await click(page.cards.crit.art_button)
	check(not page._buy_button.disabled, "点亮实际前置后暴击解锁")
	await click(page._buy_button)
	check(GameState.upgrade_level("crit") == 1 and GameState.skill_points == 6 and GameState.gold == 137.0, "解锁技能使用同一个右侧按钮升级")
	await click(page.cards.equip.art_button)
	check(page._buy_button.disabled and page._requirement.text.contains("征服新野"), "装备保留征服新野的实际门槛")
	GameState.region_state[1] = "cleared"
	GameState.cleared_zones[1] = [0, 1, 2, 3, 4]
	page.refresh()
	await click(page._buy_button)
	check(GameState.upgrade_level("equip") == 1 and GameState.skill_points == 5, "征服新野后装备可学习")
	await click(page.cards.troops.art_button)
	check(page._buy_button.disabled and page._requirement.text.contains("携带位"), "带兵同时需要携带位和装备")
	await click(page.cards.carry.art_button)
	await click(page._buy_button)
	await click(page.cards.troops.art_button)
	check(not page._buy_button.disabled, "两个真实前置齐全后带兵解锁")
	GameState.skill_points = 0
	GameState.gold = 100000.0
	page.refresh()
	check(page._buy_button.disabled and page._requirement.text == "技能点不足", "金币不能替代技能点")
	GameState.skill_points = 8
	GameState.up.radius = 20
	await click(page.cards.radius.art_button)
	check(page._buy_button.disabled and page._level.text == "Lv.20 → Lv.20", "满级不虚构下一级")
	GameState.bonus.stamina_flat = 3.0
	await click(page.cards.stamina.art_button)
	var duration_preview := GameState.upgrade_preview("stamina")
	check(page._value.text == "%s → %s 秒 / 局" % [page._number(float(duration_preview.current.duration)), page._number(float(duration_preview.next.duration))], "时长详情包含当前队伍的实际时长修饰")
	await click(page._buy_button)
	check(is_equal_approx(GameState.round_duration_value(), float(duration_preview.next.duration)), "含修饰的时长预览与购买后实际轮长一致")
	await click(page.cards.power.art_button)
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		await frames()
		home._fit_to_parent()
		await frames()
		var rect: Rect2 = page._graph.get_global_rect()
		for id in page.IDS:
			var node: Button = page.cards[id].panel
			check(rect.encloses(node.get_global_rect()), "%d高度节点完整可见 %s" % [height, id])
			check(node.get_global_rect().encloses(node._caption.get_global_rect()) and node.get_global_rect().encloses(node._level.get_global_rect()), "%d高度名称和等级完整落在节点内 %s" % [height, id])
			check(node._caption.size.y >= node._caption.get_minimum_size().y, "%d高度标签容纳实际字高 %s" % [height, id])
			check(node._caption.get_global_rect().end.y <= node._level.get_global_rect().position.y, "%d高度名称不压住等级 %s" % [height, id])
			await click(node)
			check(page.selected_id == id, "%d高度实际点击切换 %s" % [height, id])
			check(page.get_global_rect().encloses(page._buy_button.get_global_rect()), "%d高度切换后详情按钮完整可见 %s" % [height, id])
			check(page._picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "详情完整显示单幅插画 " + id)
		check(page.get_global_rect().encloses(page._buy_button.get_global_rect()), "%d高度右按钮完整可见" % height)
		check(page.get_global_rect().encloses(page._receipt.get_global_rect()), "%d高度右侧说明完整可见" % height)
		await click(page.cards.power.art_button)
		home.refresh()
		await snapshot("cultivation-%d.png" % height)
	print("[Cultivation Graph] checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
