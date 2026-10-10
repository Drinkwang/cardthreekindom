extends Node
## 渲染自检：加载主场景，等画面画完，把窗口内容存成 PNG。
## 用途：无头自检只验证"节点树和数据对不对"，这个脚本验证"画面长什么样"。
## 运行：~/Downloads/Godot.app/Contents/MacOS/Godot --path game tests/Screenshot.tscn -- --out=/tmp/paan.png
## 可选参数：
##   --drag=x1,y1,x2,y2  模拟一次拖拽重拍，用于截"重拍中"的画面
##   --region=N          跳过解锁，直接铺第 N 个区域的桌（看"满桌"）
##   --map               打开全屏荆州舆图覆盖层
##   --demo              伪造一个中期存档（几个郡已克服），舆图/桌面都好看
##   --mid               伪造一个中期"局外成长"存档（升级树 / 上阵 / 装备都有），并打开大本营
##   --home              打开四区大本营（商店 / 构筑 / 升级 / 基建）
##   --section=NAME      从大本营进入 upgrade/deck/shop/base/map
##   --outcome=cleared   显示中期通关后的四区大本营
##   --city              伪造中期存档并打开全屏「城建」覆盖层（城池 / 建筑 / 合成）
##   --drawer=1          展开右侧商店抽屉
##   --pack=N            买第 N 个卡包，截翻牌揭示特效
##   --menu              截「主菜单」而不是桌面
##   --rules             在主菜单上打开「玩法说明」覆盖层（需配合 --menu）
##   --table             伪造中期存档，但**不打开大本营**（看桌面 + 底部上阵条）
##   --pool              展开底部「卡池」条（截上阵栏 + 卡池）
##   --deploy=<卡 id>    用真实鼠标事件把某张牌从卡池**拖**到第 1 个携带位，并截图
##                       （⚠️ 必须非无头：无头视口不派发 GUI 输入，拖不动）

func _ready() -> void:
	var out := "/tmp/paan.png"
	var drag := ""
	var region := 0
	var open_map := false
	var demo := false
	var drawer := false
	var pack := -1
	var full := false
	var dump := false
	var reveal := ""
	var instant := false
	var cleared := false
	var fresh := false
	var mid := false
	var open_home := false
	var open_city := false
	var menu := false
	var open_rules := false
	var pool_open := false
	var deploy_id := ""
	var table := false
	var shop_tab := -1
	var captured_demo := false
	var capture_impact := false
	var max_carry := false
	var section := ""
	var upgrade_scroll := 0
	var camera_zoom := -1.0
	var camera_target := Vector2(-1, -1)
	var minimap_collapsed := false
	var minimap_gui_demo := false
	var aim_card := -1
	var radius_level := -1
	var aim := Vector2(-1, -1)
	var area_click := false
	var outcome := ""
	var build_demo := false
	var building_combo := false
	var fusion_demo := false
	var no_story := false
	for a in OS.get_cmdline_user_args():
		if a == "--minimap-gui-demo":
			minimap_gui_demo = true
		elif a == "--minimap-collapsed":
			minimap_collapsed = true
		elif a.begins_with("--camera-target="):
			var coords := a.substr(16).split(",")
			if coords.size() == 2: camera_target = Vector2(float(coords[0]), float(coords[1]))
		elif a.begins_with("--aim-card="):
			aim_card = int(a.substr(11))
		elif a.begins_with("--zoom="):
			camera_zoom = float(a.substr(7))
		elif a.begins_with("--radius-level="):
			radius_level = int(a.substr(15))
		elif a.begins_with("--aim="):
			var coords := a.substr(6).split(",")
			if coords.size() == 2: aim = Vector2(float(coords[0]), float(coords[1]))
		elif a == "--area-click":
			area_click = true
		elif a.begins_with("--upgrade-scroll="):
			upgrade_scroll = int(a.substr(17))
		elif a == "--no-story":
			no_story = true
		elif a == "--building-combo" or a == "--building-fusion":
			building_combo = true
			fusion_demo = a == "--building-fusion"
			mid = true
			open_city = true
		elif a == "--build-demo":
			build_demo = true
			open_home = true
		elif a.begins_with("--section="):
			section = a.substr(10)
			open_home = true
		elif a.begins_with("--outcome="):
			outcome = a.substr(10)
			open_home = true
		elif a == "--maxcarry":
			max_carry = true
		elif a == "--impact":
			capture_impact = true
		elif a == "--captured-demo":
			captured_demo = true
		elif a.begins_with("--tab="):
			shop_tab = int(a.substr(6))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--drag="):
			drag = a.substr(7)
		elif a.begins_with("--region="):
			region = int(a.substr(9))
		elif a == "--map":
			open_map = true
		elif a == "--home":
			open_home = true
		elif a == "--city":
			open_city = true
		elif a == "--menu":
			menu = true
		elif a == "--rules":
			open_rules = true
		elif a == "--pool":
			pool_open = true
		elif a.begins_with("--deploy="):
			deploy_id = a.substr(9)
		elif a == "--mid":
			mid = true
		elif a == "--table":
			mid = true
			table = true
		elif a == "--demo":
			demo = true
		elif a == "--full":
			full = true
		elif a == "--dump":
			dump = true
		elif a == "--instant":
			instant = true
		elif a == "--clear":
			cleared = true
		elif a == "--fresh":
			fresh = true
		elif a.begins_with("--reveal="):
			reveal = a.substr(9)
		elif a.begins_with("--drawer="):
			drawer = a.substr(9) == "1"
		elif a.begins_with("--pack="):
			pack = int(a.substr(7))

	# 截图要可复现：清掉上一轮遗留的存档
	if fresh or (cleared and not demo):
		GameState.new_game()

	if demo:
		# 新野起点 + 前 5 个区域已克服，后一个可挑战，其余未解锁 —— 舆图三色都能看到
		GameState.region_state.clear()
		for r in GameData.regions:
			var i := int(r["idx"])
			if i == GameState.START_REGION or i <= 6:
				GameState.region_state[i] = "cleared"
			else:
				GameState.region_state[i] = "locked"
		for r in GameData.regions:
			var i := int(r["idx"])
			if GameState.region_state.get(i, "locked") == "cleared":
				for n in r.get("unlocks", []):
					var j := int(n)
					if GameState.region_state.get(j, "locked") == "locked":
						GameState.region_state[j] = "available"
		GameState.gold = 6000.0
		GameState._recompute_bonus()
		GameState.map_changed.emit()

	if region > 0:
		# 跳过解锁流程，直接铺第 N 个区域的桌（用于看"满桌"长什么样）
		# 前置区域全设为已克服，目标区域本身保持未克服（否则 start_battle 会拒绝）
		for r in GameData.regions:
			var i := int(r["idx"])
			GameState.region_state[i] = "locked" if i == region else "cleared"
		GameState.start_battle(region)

	if mid or ((open_home or open_city) and not fresh):
		# 中期存档：前 4 处已克服（城建解锁）、升级树点了一截、上阵 5 张、装备槽 2 格
		GameState.new_game()
		GameState.runs = 37
		GameState.up["stamina"] = 9
		GameState.up["power"] = 4
		GameState.up["carry"] = 3 if max_carry else 2
		GameState.up["crit"] = 3
		GameState.up["fortune"] = 2
		GameState.up["idle"] = 2
		GameState.up["equip"] = 2
		GameState.up["troops"] = 2      # v1.1：让截图里能看到「兵位」
		GameState.region_state.clear()
		for r in GameData.regions:
			GameState.region_state[int(r["idx"])] = "locked"
		for i in [1, 2, 3, 4]:
			GameState.region_state[i] = "cleared"
		GameState.region_state[5] = "available"
		GameState._recompute_bonus()

		# 上阵：优先挑武将（好展示「等级 + 被动 + 升级」），不够再拿士兵凑
		var heroes := []
		var others := []
		for c in GameData.cards:
			if not GameState.is_carryable(str(c["id"])):
				continue
			if str(c.get("type", "")) == "武将":
				heroes.append(c)
			else:
				others.append(c)
		var bypow := func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("power", 0.0)) < float(b.get("power", 0.0))
		heroes.sort_custom(bypow)
		others.sort_custom(bypow)
		var cpool := heroes + others
		GameState.carry.clear()
		var added := 0
		for c in cpool:
			if added >= GameState.carry_max():
				break
			var cid := str(c["id"])
			GameState.owned[cid] = int(GameState.owned.get(cid, 0)) + 1
			if GameState.carry_add(cid):
				added += 1
				if GameState.is_hero(cid):
					GameState.hero_lv[cid] = 3     # 练到 Lv.3，展示等级成长

		# 装备巢（v1.1：**每将独立**）：给每个上阵武将各装一套。
		# ⚠️ 一件装备同时只能挂一个武将 —— 所以必须**按部位分桶、取走就删**，
		#    否则后面的将会把前面将身上的装备抢走，截图里就只剩最后一个将有装备。
		var buckets := {}
		for c in GameData.cards:
			var eid := str(c["id"])
			if not GameState.is_equippable(eid):
				continue
			GameState.owned[eid] = int(GameState.owned.get(eid, 0)) + 1
			var bsub := GameState.equip_slot_of(eid)
			if not buckets.has(bsub):
				buckets[bsub] = []
			(buckets[bsub] as Array).append(eid)
		for who in GameState.carry:
			var hid := str(who)
			if not GameState.is_hero(hid):
				continue          # ⚠️ 士兵没有装备巢（用户明确）
			for sub in GameState.unlocked_slots():
				var b: Array = buckets.get(str(sub), [])
				if b.is_empty():
					continue
				var chosen := str(b[0])
				buckets[str(sub)] = b.slice(1)
				GameState.equip_to(hid, chosen)

		# 兵位（v1.1）：点亮「武将带兵」后，往每个武将麾下塞满士卒
		if GameState.troop_slots() > 0:
			var tpool := []
			for c in GameData.cards:
				if str(c.get("type", "")) == "士兵":
					tpool.append(str(c["id"]))
			for who in GameState.carry:
				var hid2 := str(who)
				if not GameState.is_hero(hid2):
					continue
				for tid in tpool:
					if GameState.hero_troops_of(hid2).size() >= GameState.troop_cap(hid2):
						break
					GameState.owned[tid] = int(GameState.owned.get(tid, 0)) + 1
					GameState.troop_put(hid2, tid)

		# 城建：往已克服的城池上放几个建筑
		for c in GameData.cards:
			if str(c.get("type", "")) == "建筑":
				var bid := str(c["id"])
				GameState.owned[bid] = int(GameState.owned.get(bid, 0)) + 1
		if GameState.city_unlocked():
			for ci in [2, 3, 4]:
				for bid in GameState.owned.keys():
					if GameState.city_buildings(ci).size() >= GameState.city_slots(ci):
						break
					if str(GameData.card(str(bid)).get("type", "")) == "建筑" \
							and int(GameState.owned.get(bid, 0)) > 0:
						GameState.place_building(ci, str(bid))

		GameState.gold = 4820.0
		if building_combo:
			GameState.cities.clear()
			GameState.city_quality.clear()
			GameState.building_refined.clear()
			for building in GameData.buildings:
				GameState.owned[str(building["id"])] = 4
			for id in ["B06", "B08", "B11", "B12"]:
				GameState.place_building(2, id, 0)
		GameState.gold = 4820.0
		GameState.leave_battle()
		GameState.battle_region = 5
		GameState.end_reason = "settled"
		GameState.last_outcome = {"region": 5, "result": "settled", "gold": 555, "kills": 3, "damage": 1101.0}
		GameState.last_settle = "第 37 趟 · 「宛城」　击倒 3 张 · 打出 62 伤害 → 收成 30 金币。回大本营整备。"
		GameState.map_changed.emit()
		if open_city or table:
			pass              # --table：只要中期存档，画面留在桌面（看底部上阵条）
		else:
			open_home = true

	if outcome == "cleared":
		GameState.region_state[5] = "cleared"
		for next_idx in GameData.region(5).get("unlocks", []):
			if GameState.region_status(int(next_idx)) == "locked":
				GameState.region_state[int(next_idx)] = "available"
		GameState.last_outcome = {"region": 5, "result": "cleared", "gold": 1012, "kills": 6, "damage": 1500.0}
		GameState.end_reason = "cleared"
		GameState.map_changed.emit()

	if build_demo:
		GameState.carry.clear()
		for cid in ["G04", "G05", "G30", "G40", "G20", "G24", "G14", "G26", "G27", "G43"]:
			GameState.owned[cid] = maxi(1, int(GameState.owned.get(cid, 0)))
		for cid in ["G04", "G05", "G30", "G40", "G20"]:
			GameState.carry_add(cid)
		GameState.hero_lv["G04"] = 3
	var scene_path := "res://scenes/MainMenu.tscn" if menu else "res://scenes/Main.tscn"
	if captured_demo:
		GameState.captured = ["G28", "G26", "G27", "G13"]
		GameState.gold = 50000
	if table:
		var battle_idx := region if region > 0 else 5
		if region > 0:
			for r in GameData.regions:
				GameState.region_state[int(r["idx"])] = "cleared"
		GameState.region_state[battle_idx] = "available"
		GameState.start_battle(battle_idx)
	if radius_level >= 0: GameState.up["radius"] = clampi(radius_level, 0, 20)
	var inst = load(scene_path).instantiate()
	if no_story:
		GameState.story_seen = []
		for event in preload("res://scripts/story_book.gd").events():
			GameState.story_seen.append(str(event.id))
	add_child(inst)

	for i in range(6):
		await get_tree().process_frame

	if open_rules:
		inst._open_rules()
		for i in range(3):
			await get_tree().process_frame

	if pool_open or deploy_id != "":
		await _do_pool_and_deploy(inst, pool_open, deploy_id, mid)

	if drawer:
		var root0 := inst as Control
		root0._set_drawer(true)
		if shop_tab >= 0:
			root0._tabs.current_tab = clampi(shop_tab, 0, 5)
	for i in range(3):
		await get_tree().process_frame

	if cleared:
		# 完整限时轮：拍击、清桌补牌、时间到后回营。
		GameState.set_process(false)
		GameState.narrative_paused = false
		var guard := 0
		while GameState.in_battle and guard < 1000:
			GameState.advance_round(GameState.slap_interval())
			if not GameState.in_battle:
				break
			var alive := -1
			for i in range(GameState.battle.size()):
				if float(GameState.battle[i]["hp"]) > 0.0:
					alive = i
					break
			if alive < 0:
				break
			var card: Dictionary = inst._cards[alive]
			var center: Vector2 = card.rest_pos + card.size * 0.5
			inst._slap_area(inst._world_to_screen(center))
			guard += 1
		for i in range(4):
			await get_tree().process_frame

	if pack >= 0:
		var root1 := inst as Control
		if GameState.gold < 500.0:
			GameState.gold = 500.0
		root1._do_buy_pack(pack)

	if reveal != "":
		var root3 := inst as Control
		root3._play_reveal("将牌新印", reveal.split(","), "旧纸套色 · 连环画人物")
		if instant:
			root3._reveal._reveal_all()

	if open_map:
		var root2 := inst as Control
		root2._open_map()

	if open_home:
		var root4 := inst as Control
		root4._open_home()
		for i in range(4):
			await get_tree().process_frame

	if open_city:
		var root5 := inst as Control
		root5._open_city()
		if building_combo:
			root5._city._on_slot(2)
			if fusion_demo:
				root5._city._on_tab("合成")
		for i in range(4):
			await get_tree().process_frame

	if section != "":
		if section == "shop":
			inst._open_shop()
		elif section == "base":
			inst._open_city()
		elif section == "map":
			inst._on_home_map()
		else:
			inst._home.open_section(section)
		for i in range(6):
			await get_tree().process_frame

	if pack >= 0:
		# 等一帧让覆盖层结算尺寸，再打印关键节点尺寸
		for i in range(4):
			await get_tree().process_frame
		if dump:
			var rv = (inst as Control)._reveal
			print("[dbg] reveal size=", rv.size, " root_box=", rv._root_box.size,
				" pos=", rv._root_box.position)
			var first = rv._slots[0]
			print("[dbg] slot0 wrap=", first["wrap"].size, " back=", first["back"].size,
				" front=", first["front"].size, " front_min=", first["front"].get_combined_minimum_size())

	if section == "upgrade" and upgrade_scroll > 0:
		inst._home._upgrade_page.scroll_vertical = upgrade_scroll
		for i in range(3):
			await get_tree().process_frame

	if not menu and not open_home and not open_city and not open_map:
		if camera_zoom > 0: inst._set_camera_zoom(camera_zoom, inst._table.size * 0.5)
		if camera_target.x >= 0: inst._navigate_minimap(camera_target)
		if minimap_gui_demo:
			if not await _exercise_minimap_gui(inst):
				get_tree().quit(1)
				return
		if minimap_collapsed: inst._minimap.set_expanded(false)
		if aim_card >= 0 and aim_card < inst._cards.size():
			var card: Dictionary = inst._cards[aim_card]
			aim = card.rest_pos + card.size * 0.5
		if aim.x >= 0:
			inst._cursor_preview = inst._world_to_screen(aim)
			if area_click:
				# 非无头下通过真实GUI输入派发，验证视口坐标转换与单击绑定。
				var screen_point: Vector2 = inst._table.global_position + inst._cursor_preview
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				press.position = screen_point
				press.global_position = screen_point
				get_viewport().push_input(press)
				var release := InputEventMouseButton.new()
				release.button_index = MOUSE_BUTTON_LEFT
				release.position = screen_point
				release.global_position = screen_point
				get_viewport().push_input(release)
				print("[area-input] slaps=%d damage=%s income=%s" % [GameState.round_slaps, GameState.run_damage, GameState.run_gold])

	if dump:
		var rootD := inst as Control
		var tb := _find_table(inst)
		print("[dbg] root=", rootD.size, " table=", (tb.size if tb != null else Vector2.ZERO),
			" table_pos=", (tb.global_position if tb != null else Vector2.ZERO))
		print("[dbg] drawer vis/size=", rootD._drawer.visible, "/", rootD._drawer.size,
			"  map vis/size=", rootD._map_layer.visible, "/", rootD._map_layer.size,
			"  home vis/size=", rootD._home.visible, "/", rootD._home.size,
			"  city vis/size=", rootD._city.visible, "/", rootD._city.size,
			"  reveal vis/size=", rootD._reveal.visible, "/", rootD._reveal.size)

	if drag != "":
		var parts := drag.split(",")
		if parts.size() == 4:
			var p0 := Vector2(float(parts[0]), float(parts[1]))
			var p1 := Vector2(float(parts[2]), float(parts[3]))
			# 输入方法挂在主场景根节点（main.gd）上，不在桌面层节点上
			var root := inst as Control
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = p0
			root._on_table_input(down)
			var steps := 14
			for s in range(1, steps + 1):
				var mm := InputEventMouseMotion.new()
				mm.position = p0.lerp(p1, float(s) / float(steps))
				root._on_table_input(mm)
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			up.position = p1
			root._on_table_input(up)

	# 拖拽/开包后多等一会儿，让动画跑完（否则截到的是动画中途）
	var wait := 6
	if capture_impact and GameState.in_battle:
		# 测试档把连击置于触发前，走真实拍击管线捕捉新墨痕。
		var target := -1
		var highest_hp := 0.0
		for i in range(GameState.battle.size()):
			if float(GameState.battle[i]["hp"]) > highest_hp:
				highest_hp = float(GameState.battle[i]["hp"])
				target = i
		if target >= 0:
			GameState.combo = maxi(0, GameState.combo_threshold() - GameState.combo_gain() * 2)
			var card: Dictionary = inst._cards[target]
			var center: Vector2 = card["node"].position + card["size"] * 0.5
			inst._slap(target, true, center)
			print("[impact] ", GameState.last_slap)
			await get_tree().create_timer(0.10).timeout
		wait = 1
	elif drag != "":
		wait = 45
	elif cleared:
		wait = 24
	elif pack >= 0 or reveal != "":
		wait = 260 if full else 105
	for i in range(wait):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	print("[screenshot] %s -> %s (%dx%d)" % [
		"OK" if err == OK else "FAIL(%d)" % err, out, img.get_width(), img.get_height()])
	get_tree().quit()

func _gui_click(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	get_viewport().push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	get_viewport().push_input(release)

func _exercise_minimap_gui(main) -> bool:
	var mini = main._minimap
	var slaps: int = GameState.round_slaps
	var gold: float = GameState.gold
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	var collapsed: bool = not mini.expanded
	key.pressed = false
	get_viewport().push_input(key)
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	var expanded: bool = mini.expanded
	key.pressed = false
	get_viewport().push_input(key)
	_gui_click(mini.global_position + Vector2(38, 18))
	await get_tree().process_frame
	var title_works: bool = not mini.expanded
	_gui_click(mini.toggle_button.get_global_rect().get_center())
	await get_tree().process_frame
	var button_works: bool = mini.expanded
	var destination: Vector2 = main._world_size * 0.5 + Vector2(80, 70)
	var point: Vector2 = mini.global_position + mini.world_to_minimap(destination)
	_gui_click(point)
	await get_tree().process_frame
	var navigation: bool = main._screen_to_world(main._table.size * 0.5).distance_to(destination) < 0.1
	var before_zoom: float = main._camera_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = point
	wheel.global_position = point
	get_viewport().push_input(wheel)
	await get_tree().process_frame
	var guarded: bool = GameState.round_slaps == slaps and GameState.gold == gold and is_equal_approx(main._camera_zoom, before_zoom)
	print("[minimap-gui] M-collapse=%s M-expand=%s title=%s button=%s navigate=%s no-slap-or-zoom=%s" % [collapsed, expanded, title_works, button_works, navigation, guarded])
	var ok := collapsed and expanded and title_works and button_works and navigation and guarded
	if not ok: push_error("小地图真实GUI交互验证未通过")
	return ok


## 底部上阵条 / 卡池：用**真实鼠标事件**驱动 Godot 的 GUI 拖放。
##
## ⚠️ 为什么必须跑非无头：无头模式下视口**根本不派发 GUI 输入事件**（实测连 _gui_input
##    都收不到），所以 push_input() / Input.parse_input_event() 都推不动拖拽。
##    这个验证和截图一样，只能非无头跑。
## ⚠️ 也顺便证明了 set_drag_preview() 的守卫是对的：真实拖拽时 get_viewport().gui_is_dragging()
##    确实是 true（已单独探针验证），所以「先问再设预览」不会让拖拽预览消失，
##    但能让无头自检里直接调 _get_drag_data() 时不冒出引擎 ERROR。
## ⚠️ keep_state=true（中期存档 / --table）时**不能**清空上阵名单 ——
##    v1.0 起这个函数为了"确定性卡池"会 `carry.clear()`，会把中期存档的
##    上阵 5 将 + 各自的装备/兵位全部抹掉（截图里就只剩主角一个）。
func _do_pool_and_deploy(inst: Node, pool_open: bool, deploy_id: String,
		keep_state: bool = false) -> void:
	# 造一个确定的卡池：4 张 ★6 将 + 1 张 ★1 士兵
	for cid in ["G13", "G16", "G26", "G27", "S01"]:
		GameState.owned[cid] = int(GameState.owned.get(cid, 0)) + 1
	if not keep_state:
		GameState.up["carry"] = 0
		GameState.carry.clear()
		GameState.carry_add("S01")
	GameState.changed.emit()
	for i in range(4):
		await get_tree().process_frame

	inst._set_pool(true)
	for i in range(6):
		await get_tree().process_frame

	print("[pool] 卡池展开=%s  内容=%s" % [
		str(inst._pool.visible), str(_pool_ids(inst))])
	if deploy_id == "":
		return

	var src = null
	for c in inst._pool_box.get_children():
		if c is PanelContainer and str(c.card_id) == deploy_id:
			src = c
			break
	var slots = inst._slot_row.get_children()
	var dst = slots[2] if slots.size() > 2 else null
	if src == null or dst == null:
		print("[deploy] 找不到源牌或落点 src=%s dst=%s" % [str(src), str(dst)])
		return

	var from: Vector2 = (src as Control).get_global_rect().get_center()
	var to: Vector2 = (dst as Control).get_global_rect().get_center()
	print("[deploy] 拖 %s  %s → %s" % [deploy_id, str(from), str(to)])
	print("[deploy] 拖前 carry=%s" % str(GameState.carry))

	var vp := get_viewport()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	vp.push_input(down)

	for s in range(1, 13):
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, float(s) / 12.0)
		mm.global_position = mm.position
		mm.relative = (to - from) / 12.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm)

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	vp.push_input(up)

	for i in range(6):
		await get_tree().process_frame
	print("[deploy] 拖后 carry=%s" % str(GameState.carry))
	print("[deploy] 拖拽落点结果：%s" % ("成功上阵 ✓" if GameState.in_carry(deploy_id) else "失败 ✗"))


func _pool_ids(inst) -> Array:
	var out := []
	for c in inst._pool_box.get_children():
		if c is PanelContainer:
			out.append(str(c.card_id))
	return out


func _find_table(n: Node) -> Control:
	if n.has_meta("paan_table"):
		return n as Control
	for ch in n.get_children():
		var r := _find_table(ch)
		if r != null:
			return r
	return null
