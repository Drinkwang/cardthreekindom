extends Node
## 城池牌堆：真实范围命中、镜头坐标、单掌冷却和永久成长。
## Godot --headless --path . tests/CityPileTest.tscn -- --test-profile
const Story = preload("res://scripts/story_book.gd")
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

func fixture() -> void:
	GameState.set_process(false)
	GameState.new_game()
	GameState.stop_automation(false)
	GameState.narrative_paused = false
	GameState.carry.clear()
	GameState.up["crit"] = 0
	GameState.story_seen.clear()
	for event in Story.events():
		GameState.story_seen.append(str(event.id))

func stage_indices(stage: int) -> Array:
	var indices: Array = []
	for i in range(GameState.battle.size()):
		if int(GameState.battle[i].get("stage", -1)) == stage:
			indices.append(i)
	return indices

func reward_count(id: String) -> int:
	# 建筑首通卡直接装配进城；仓库数量和已装配数量一起才是实际拥有数。
	var total := int(GameState.owned.get(id, 0))
	if id.begins_with("B"):
		for idx in GameState.cities:
			total += GameState.city_buildings(int(idx)).count(id)
	return total

func clear_stage(stage: int) -> void:
	GameState.advance_round(GameState.slap_interval())
	check(GameState.begin_slap_batch(), "同城阶段%d可开始一掌" % stage)
	var targets := stage_indices(stage)
	check(not targets.is_empty(), "同城阶段%d有原始牌" % stage)
	for i in targets:
		if float(GameState.battle[i]["hp"]) > 0.0:
			check(GameState.attack(i), "范围轻拍可击中同掌的阶段%d牌%d" % [stage, i])
	GameState.end_slap_batch()

func clear_pile() -> void:
	GameState.advance_round(GameState.slap_interval())
	var generation := GameState.battle_gen
	var count := GameState.battle.size()
	var before := GameState.round_slaps
	check(GameState.begin_slap_batch(), "整堆范围拍能开始")
	for i in range(count):
		check(GameState.attack(i), "整堆范围轻拍命中原始牌%d" % i)
	check(GameState.battle_gen == generation, "所有目标结算前不补出下一堆")
	check(GameState.round_slaps == before + 1, "二十一张范围拍共用一次出手")
	GameState.end_slap_batch()
	check(GameState.battle_gen == generation + 1, "整堆只补牌一次")

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "城池牌堆测试隔离玩家正式存档")
	_test_radius()
	_test_city_pile()
	_test_checkpoint_restart()
	await _test_camera_and_area()
	print("[City pile v2.2] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_radius() -> void:
	fixture()
	check(GameState.up_def("radius").size() > 0, "范围是实际永久升级项")
	check(is_equal_approx(GameState.slap_radius(), 34.0), "初始世界拍卡圆半径34")
	GameState.gold = 10000.0
	var before: Dictionary = GameState.up.duplicate(true)
	var gold := GameState.gold
	var duration := GameState.round_duration
	var hp := GameState.pile_health()
	var preview := GameState.upgrade_preview("radius")
	check(GameState.up == before and GameState.gold == gold, "范围预览不改等级和金币")
	check(GameState.round_duration == duration and GameState.pile_health() == hp, "范围预览不改当前局和牌堆")
	check(is_equal_approx(float(preview.current.radius), 34.0), "范围预览当前值真实")
	check(is_equal_approx(float(preview.next.radius), 40.0), "范围下一级半径增加6")
	check(GameState.upgrade_cost("radius") == 24, "首次范围升级24金币")
	check(GameState.buy_upgrade("radius"), "范围实际可购买")
	check(is_equal_approx(GameState.gold, gold - 24.0), "范围购买精确扣金币")
	check(is_equal_approx(GameState.slap_radius(), float(preview.next.radius)), "购买后的实际范围等于预览")
	check(GameState.round_duration == duration, "范围升级不重启轮倒计时")
	var saved_up: Dictionary = GameState.up.duplicate(true)
	GameState.save_game()
	GameState.up = {}
	check(GameState.load_game(), "范围升级存档可读回")
	check(GameState.up == saved_up and GameState.upgrade_level("radius") == 1, "范围等级长期保留")
	GameState.up.radius = 20
	gold = GameState.gold
	preview = GameState.upgrade_preview("radius")
	check(GameState.upgrade_maxed("radius") and is_equal_approx(GameState.slap_radius(), 154.0), "范围20级半径154封顶")
	check(preview.current == preview.next, "满级预览不虚构下一档")
	check(not GameState.buy_upgrade("radius") and GameState.gold == gold, "满级不能扣钱")
	GameState.up.erase("radius")
	before = GameState.up.duplicate(true)
	preview = GameState.upgrade_preview("radius")
	check(GameState.up == before and not GameState.up.has("radius"), "老存档缺少范围键时预览仍保持只读")
	check(is_equal_approx(float(preview.current.radius), 34.0), "旧存档范围默认从小圆开始")

func _test_city_pile() -> void:
	fixture()
	check(GameState.battle.size() == 21, "新野五阶段二十一张牌同时铺进一个城池")
	check(GameState.pile_card_count() == 21 and GameState.pile_remaining() == 21, "牌堆总数和存活数准确")
	check(is_equal_approx(GameState.pile_health(), 304.0), "全城总厚度为原五阶段之和304")
	check(is_equal_approx(GameState.pile_max_health(), 304.0), "全城最大厚度准确")
	for stage in range(5):
		check(stage_indices(stage).size() == [3, 3, 4, 5, 6][stage], "阶段%d保留原始牌数量" % stage)
	var generation := GameState.battle_gen
	var gift_counts := {}
	for id in ["G00", "G04", "G05", "B06", "B08"]:
		gift_counts[id] = reward_count(id)
	GameState.up.power = 90
	clear_stage(4)
	check(GameState.table_progress(1) == 0, "先翻末段不跳过前面关卡")
	check(GameState.battle_gen == generation and GameState.battle.size() == 21, "部分牌翻完保持同一堆和数组")
	check(GameState.pile_remaining() == 15, "末段六牌翻完只剩十五张")
	check(int(GameState.owned.get("G05", 0)) == gift_counts.G05, "末段提前翻完不预支唯一奖励")
	check(not GameState.round_first_clears.has(1), "部分牌翻完不提前完成城池")
	var killed_gold := GameState.gold
	var killed_slaps := GameState.round_slaps
	check(not GameState.attack(stage_indices(4)[0]), "已翻牌不能重复击中")
	check(GameState.gold == killed_gold and GameState.round_slaps == killed_slaps, "重复拍死牌不发金币不耗拍数")
	for stage in range(4):
		clear_stage(stage)
		check(GameState.table_progress(1) == (5 if stage == 3 else stage + 1), "连贯阶段%d推进永久进度" % stage)
		if stage < 3:
			check(GameState.battle_gen == generation, "阶段%d完成不切牌堆" % stage)
	check(GameState.region_state[1] == "cleared" and GameState.table_progress(1) == 5, "整城翻完记录首通")
	check(GameState.round_first_clears == [1], "本轮首通只记一次")
	check(GameState.in_battle and GameState.round_active, "首通后本轮倒计时仍继续")
	check(GameState.battle_gen == generation + 1 and GameState.pile_remaining() == 21, "清完整堆后一次补齐新堆")
	check(GameState.round_tables_flipped == 5 and GameState.run_kills == 21, "一次全城保持五阶段和二十一翻牌统计")
	for id in ["G00", "G04", "G05", "B06", "B08"]:
		check(reward_count(id) == int(gift_counts[id]) + 1, "每份首通奖励只领一次 " + id)
	check(GameState.cities.has(1), "全城清完实际获得城建入口")
	var unique_rewards: Dictionary = GameState.owned.duplicate(true)
	var affinity: Dictionary = GameState.affinity.duplicate(true)
	var captures: Array = GameState.captured.duplicate()
	var earned := GameState.run_gold
	clear_pile()
	check(GameState.round_tables_flipped == 10 and GameState.run_kills == 42, "重复堆仍有完整翻牌统计")
	check(GameState.run_gold > earned, "重复同城牌堆继续挣钱")
	for id in ["G00", "G04", "G05", "B06", "B08"]:
		check(int(GameState.owned.get(id, 0)) == int(unique_rewards.get(id, 0)), "重复堆不重发唯一奖励 " + id)
	check(GameState.affinity == affinity and GameState.captured == captures, "重复堆不重复亲和与俘获奖励")
	check(GameState.round_first_clears == [1], "重复堆不重记首通")
	var gold := GameState.gold
	var outcome_income := GameState.run_gold
	GameState.advance_round(GameState.round_seconds_left)
	check(not GameState.round_active and not GameState.in_battle, "倒计时到期结束全城轮")
	check(is_equal_approx(GameState.gold, gold), "到期不会再发即时收益")
	check(is_equal_approx(float(GameState.last_outcome.gold), outcome_income), "全城轮结算保留本轮真实收入")
	GameState.settle_run()
	check(is_equal_approx(GameState.gold, gold), "重复全城结算不重复发钱")

func _test_checkpoint_restart() -> void:
	fixture()
	GameState.up.power = 90
	clear_stage(0)
	clear_stage(1)
	check(GameState.table_progress(1) == 2 and GameState.pile_remaining() == 15, "半城永久进度和剩余牌数准确")
	var gift_count := int(GameState.owned.get("G00", 0))
	GameState.retreat()
	GameState.save_game()
	check(GameState.load_game() and GameState.table_progress(1) == 2, "半城进度存档可读回")
	check(GameState.start_battle(1), "半城回营后继续开城池轮")
	check(GameState.battle.size() == 15 and GameState.pile_remaining() == 15, "新一轮跳过已完成前两阶段")
	check(stage_indices(0).is_empty() and stage_indices(1).is_empty(), "已完成阶段不会混进新牌堆")
	clear_stage(4)
	check(GameState.table_progress(1) == 2, "先拍末段仍保留中间未完成进度")
	GameState.retreat()
	check(GameState.start_battle(1) and GameState.battle.size() == 15, "非连贯阶段重试恢复未完成牌堆")
	clear_stage(4)
	check(int(GameState.owned.get("G05", 0)) == 0, "重复先拍末段不能刷末段将牌")
	clear_stage(2)
	clear_stage(3)
	check(GameState.table_progress(1) == 5 and int(GameState.owned.get("G00", 0)) == gift_count, "继续整城只补领未领取阶段奖励")

func put_card(main, index: int, position: Vector2, card_size: Vector2, rotation: float = 0.0) -> void:
	var card: Dictionary = main._cards[index]
	var shake = card.get("shake_tween")
	if shake != null and shake.is_valid():
		shake.kill()
	card["rest_pos"] = position
	card["size"] = card_size
	card["rot"] = rotation
	card["dead"] = false
	var node: Control = card["node"]
	node.position = position
	node.size = card_size
	node.rotation = rotation
	node.pivot_offset = card_size * 0.5
	node.scale = Vector2.ONE
	node.visible = true
	GameState.battle[index]["hp"] = 10000.0
	GameState.battle[index]["hp_max"] = 10000.0

func click(main, point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	main._on_table_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	main._on_table_input(release)

func _test_camera_and_area() -> void:
	fixture()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await frames()
	check(main._cards.size() == GameState.battle.size(), "实际城池场景显示完整牌堆")
	check(main._table.clip_contents, "镜头世界按牌堆视口裁切")
	check(main._slap_cursor != null and main._slap_cursor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "范围光标不挡单击输入")
	main._reset_camera()
	var anchor: Vector2 = main._table.size * 0.5
	main._cursor_preview = anchor
	var original_world: Vector2 = main._screen_to_world(anchor)
	for zoom in [0.85, 1.4, 1.0]:
		main._set_camera_zoom(zoom, anchor)
		check(is_equal_approx(main._camera_zoom, zoom), "真实镜头倍率可切到%.2f" % zoom)
		check(main._world_to_screen(original_world).distance_to(anchor) < 0.01, "以鼠标为锚缩放保持世界点不跳%.2f" % zoom)
		for point in [original_world, original_world + Vector2(80, -70), original_world + Vector2(-110, 50)]:
			check(main._screen_to_world(main._world_to_screen(point)).distance_to(point) < 0.01, "镜头变换可往返%.2f" % zoom)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = anchor
	wheel.pressed = true
	main._on_table_input(wheel)
	check(main._camera_zoom > 1.0, "鼠标滚轮实际连接镜头放大")
	check(main._world_to_screen(original_world).distance_to(anchor) < 0.01, "滚轮缩放也保持鼠标下世界点")
	main._set_camera_zoom(1.8, anchor)
	# 中键只平移镜头；释放后同样的鼠标运动不再移动世界。
	var pan_slaps := GameState.round_slaps
	var pan_gold := GameState.gold
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.position = anchor
	middle.pressed = true
	main._on_table_input(middle)
	check(main._panning, "中键按下实际开始平移镜头")
	var before_pan: Vector2 = main._world_to_screen(original_world)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.relative = Vector2(37, -24)
	pan_motion.position = anchor + pan_motion.relative
	pan_motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	main._on_table_input(pan_motion)
	check(main._world_to_screen(original_world).distance_to(before_pan + pan_motion.relative) < 0.01, "中键位移量精确移动同一世界点的屏幕位置")
	middle.pressed = false
	middle.position = pan_motion.position
	main._on_table_input(middle)
	check(not main._panning, "释放中键实际结束平移")
	var after_pan: Vector2 = main._world_to_screen(original_world)
	pan_motion.relative = Vector2(11, 9)
	pan_motion.position += pan_motion.relative
	pan_motion.button_mask = 0
	main._on_table_input(pan_motion)
	check(main._world_to_screen(original_world).distance_to(after_pan) < 0.01, "释放后的鼠标运动不再平移世界")
	check(GameState.round_slaps == pan_slaps and GameState.gold == pan_gold, "平移镜头不拍卡不发金币")
	main._set_camera_zoom(100.0, anchor)
	check(is_equal_approx(main._camera_zoom, 4.0), "镜头放大限制在400%")
	main._set_camera_zoom(0.01, anchor)
	check(is_equal_approx(main._camera_zoom, 0.65), "镜头缩小限制在65%")
	for button in main._camera_toolbar.get_child(0).get_children():
		if button is Button and button.text == "全城":
			button.pressed.emit()
	check(is_equal_approx(main._camera_zoom, 1.0) and main._camera_pan.is_zero_approx(), "实际全城按钮恢复100%镜头和零平移")
	check(main._world_to_screen(original_world).distance_to(anchor) < 0.01 and main._screen_to_world(anchor).distance_to(original_world) < 0.01, "归中后城池世界中心和视口中心仍可双向对应")
	# 将一张真牌摆在控制区后面，保证输入阻挡验证不是拍空的偶然结果。
	var toolbar_point: Vector2 = main._camera_toolbar.get_rect().get_center()
	var toolbar_world: Vector2 = main._screen_to_world(toolbar_point)
	put_card(main, 0, toolbar_world - Vector2(20, 30), Vector2(40, 60))
	check(main._area_targets(toolbar_world, GameState.slap_radius()).has(0), "缩放控制区后面确有可被范围命中的牌")
	click(main, toolbar_point)
	check(GameState.round_slaps == pan_slaps and GameState.gold == pan_gold and is_zero_approx(GameState.slap_cooldown_left), "单击缩放控制区不穿透拍牌或占用冷却")
	# 用已知局部矩形检验范围圆与旋转牌边/角的碰撞，避免只测牌心距离。
	for i in range(main._cards.size()):
		put_card(main, i, Vector2(6000 + i * 100, 6000), Vector2(40, 60))
	var card_center := original_world
	put_card(main, 0, card_center - Vector2(20, 30), Vector2(40, 60), PI / 4.0)
	var tangent := card_center + Vector2(28, 0).rotated(PI / 4.0)
	check(main._area_targets(tangent, 8.0).has(0), "范围圆与旋转牌边相切也命中")
	check(not main._area_targets(card_center + Vector2(29, 0).rotated(PI / 4.0), 8.0).has(0), "圆离旋转牌边一像素时不误中")
	var corner := card_center + Vector2(24, 34).rotated(PI / 4.0)
	check(main._area_targets(corner, 6.0).has(0), "旋转牌角距离在圆内时命中")
	check(not main._area_targets(corner, 5.0).has(0), "旋转牌角不在圆内时不命中")
	main._cards[0]["dead"] = true
	check(not main._area_targets(card_center, 100.0).has(0), "已经翻面动画的牌不参与命中")
	main._cards[0]["dead"] = false
	GameState.battle[0]["hp"] = 0.0
	check(not main._area_targets(card_center, 100.0).has(0), "零厚度牌即使仍可见也不参与命中")
	put_card(main, 0, card_center + Vector2(-40, -30), Vector2(40, 60))
	put_card(main, 1, card_center + Vector2(0, -30), Vector2(40, 60))
	put_card(main, 2, card_center + Vector2(38, -30), Vector2(40, 60))
	var world_targets: Array = main._area_targets(card_center, GameState.slap_radius())
	check(world_targets.size() == 2 and world_targets.has(0) and world_targets.has(1), "小圆同一掌覆盖相邻两张牌")
	for zoom in [0.85, 1.4]:
		main._set_camera_zoom(zoom, anchor)
		var screen_point: Vector2 = main._world_to_screen(card_center)
		check(main._area_targets(main._screen_to_world(screen_point), GameState.slap_radius()) == world_targets, "缩放不改变世界范围命中%.2f" % zoom)
		main._cursor_preview = screen_point
		await frames()
		var screen_radius: float = main._world_to_screen(card_center + Vector2(GameState.slap_radius(), 0)).distance_to(screen_point)
		check(is_equal_approx(main._slap_cursor.radius, screen_radius), "圆圈屏幕大小跟随镜头缩放%.2f" % zoom)
	main._set_camera_zoom(1.0, anchor)
	var screen_point: Vector2 = main._world_to_screen(card_center)
	var hp0 := float(GameState.battle[0]["hp"])
	var hp1 := float(GameState.battle[1]["hp"])
	var hp2 := float(GameState.battle[2]["hp"])
	var damage := GameState.click_damage()
	var before_slaps := GameState.round_slaps
	var before_damage := GameState.run_damage
	click(main, screen_point)
	check(GameState.round_slaps == before_slaps + 1, "一次鼠标单击只记一掌")
	check(is_equal_approx(GameState.slap_cooldown_left, GameState.slap_interval()), "范围单击沿用轻拍冷却")
	check(is_equal_approx(float(GameState.battle[0]["hp"]), hp0 - damage), "范围第一张实际承受轻拍伤害")
	check(is_equal_approx(float(GameState.battle[1]["hp"]), hp1 - damage), "范围第二张共用同掌实际承伤")
	check(is_equal_approx(float(GameState.battle[2]["hp"]), hp2), "范围外牌不吃伤害")
	check(is_equal_approx(GameState.run_damage - before_damage, damage * 2.0), "多牌伤害精确计入即时收入")
	var gold := GameState.gold
	click(main, screen_point)
	check(GameState.round_slaps == before_slaps + 1 and GameState.gold == gold, "连点和换目标不能绕过共用冷却")
	GameState.advance_round(GameState.slap_interval())
	before_slaps = GameState.round_slaps
	main._slap_area(main._world_to_screen(card_center + Vector2(-300, 0)))
	check(GameState.round_slaps == before_slaps and is_zero_approx(GameState.slap_cooldown_left), "拍空不占次数和冷却")
	# 打开整备的同一帧也不能穿透去拍牌。
	main._open_home()
	gold = GameState.gold
	main._slap_area(screen_point)
	check(GameState.round_slaps == before_slaps and GameState.gold == gold, "打开覆盖层当帧范围输入不穿透")
	await frames()
	check(GameState.narrative_paused, "看升级时手动轮计时暂停")
	main._home.open_section("upgrade")
	await frames()
	var page = main._home._upgrade_page
	check(page.cards.has("radius"), "实际升级页有范围卡")
	if page.cards.has("radius"):
		check(page.cards.radius.picture.texture != null, "范围卡实际加载生成插画")
		GameState.gold = 1000.0
		page.refresh()
		var preview := GameState.upgrade_preview("radius")
		page.cards.radius.button.pressed.emit()
		check(GameState.upgrade_level("radius") == 1, "范围卡实际按钮买到升级")
		check(is_equal_approx(GameState.slap_radius(), float(preview.next.radius)), "实际购买令光标世界范围变大")
		check(page.cards.radius.value.text.contains("→"), "范围卡显示当前到下一级的增量")
		check(main._area_targets(card_center, GameState.slap_radius()).has(2), "半径升级真实覆盖原先圆外的第三张牌")
		main._close_home()
		main._cursor_preview = screen_point
		await frames()
		var screen_radius: float = main._world_to_screen(card_center + Vector2(GameState.slap_radius(), 0)).distance_to(screen_point)
		check(main._slap_cursor.visible and is_equal_approx(main._slap_cursor.radius, screen_radius), "关闭升级后实际圆圈立即使用增大范围")
		before_slaps = GameState.round_slaps
		main._slap_area(screen_point)
		check(GameState.round_slaps == before_slaps + 1 and float(GameState.battle[2]["hp"]) < hp2, "升级后同掌实际伤到新覆盖的第三牌")
	main.queue_free()
	await frames()
