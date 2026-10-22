extends Node
const Art = preload("res://scripts/ui/print_art.gd")
const Setting = preload("res://scripts/ancient_setting.gd")
const FEMALE_HEROES := ["G57", "G58", "G59", "G60", "G61", "G62", "G63", "G64"]
var failures := 0
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "验证场景必须使用独立档")
	var catalog := Art.catalog()
	check(GameData.cards.size() == 177 and catalog.size() == 177, "177张卡的数据与卡图目录完整对应")
	var used := {}
	var unified_heroes := 0
	var all_heroes_unified := true
	var female_heroes := 0
	var all_female_art := true
	var female_regions := {}
	var unique_hero_regions := true
	var safe_hero_icons := true
	var hero_regions := {}
	for c in GameData.cards:
		var id := str(c["id"])
		check(catalog.has(id), "缺少卡图 " + id)
		var art := Art.texture(id) as AtlasTexture
		check(art != null, "卡图无法加载 " + id)
		if art == null:
			continue
		check(Rect2(Vector2.ZERO, art.atlas.get_size()).encloses(art.region), "裁切超出图集 " + id)
		var key := str(catalog[id]["atlas"]) + ":" + str(catalog[id]["index"])
		var portrait_id := str(Setting.PORTRAIT_ALIASES.get(id, id))
		check(not used.has(key) or used[key] == portrait_id, "仅设定替换卡允许复用已标明的古代肖像 " + id)
		used[key] = portrait_id
		if id.begins_with("G") or id == "I01":
			if FEMALE_HEROES.has(id):
				female_heroes += 1
				all_female_art = all_female_art and str(catalog[id]["atlas"]) == "res://assets/art_v14/female_heroes.png"
				all_female_art = all_female_art and int(catalog[id]["columns"]) == 4 and int(catalog[id]["rows"]) == 2
				all_female_art = all_female_art and int(catalog[id]["index"]) == FEMALE_HEROES.find(id)
				check(not female_regions.has(key), "女将使用独立肖像格位 " + id)
				female_regions[key] = id
			else:
				unified_heroes += 1
				all_heroes_unified = all_heroes_unified and str(catalog[id]["atlas"]).begins_with("res://assets/art_v8/")
			var region_key := art.atlas.resource_path + ":" + str(art.region)
			unique_hero_regions = unique_hero_regions and (not hero_regions.has(region_key) or hero_regions[region_key] == portrait_id)
			hero_regions[region_key] = portrait_id
			var icon := Art.portrait_icon_texture(id) as AtlasTexture
			safe_hero_icons = safe_hero_icons and icon != null
			if icon != null:
				safe_hero_icons = safe_hero_icons and icon.atlas == art.atlas and art.region.grow(0.01).encloses(icon.region)
				safe_hero_icons = safe_hero_icons and is_equal_approx(icon.region.size.x, icon.region.size.y)
		var image := Art.image(id)
		check(image.mouse_filter == Control.MOUSE_FILTER_IGNORE, "卡图不能拦截拖拽 " + id)
		image.free()
	check(unified_heroes == 58 and all_heroes_unified, "原58名武将与初始主角继续读取v8统一肖像")
	check(female_heroes == 8 and all_female_art and female_regions.size() == 8, "8名新女将按固定顺序读取v14独立肖像")
	check(unified_heroes + female_heroes == 66, "共65名武将与1名初始主角")
	check(unique_hero_regions and hero_regions.size() == 66 - Setting.PORTRAIT_ALIASES.size(), "古代设定替换肖像之外，每名武将使用独立图集区域")
	check(safe_hero_icons, "小头像与主卡同源，方形裁切不跨出对应武将格位")
	# 验证实际 21 个区域牌数，在卡铺与卡池同时展开时也没有相交。
	for r in GameData.regions:
		var n := int(r["enemy_count"])
		for area in [Vector2(1280, 610), Vector2(864, 440), Vector2(864, 360), Vector2(1920, 870)]:
			var metrics := Art.deck_metrics(n, area)
			var boxes: Array[Rect2] = []
			for i in range(n):
				var box := Rect2(Art.deck_position(i, n, area, metrics), metrics["card_size"])
				check(Rect2(Vector2.ZERO, area).encloses(box), "卡牌越界 %s/%d" % [r["name"], i])
				for earlier in boxes:
					check(not earlier.intersects(box.grow(3)), "卡牌重叠 %s/%d" % [r["name"], i])
				boxes.append(box)
	GameState.new_game()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(4):
		await get_tree().process_frame
	check(main._cards.size() == GameState.battle.size(), "桌面牌数一致")
	for card in main._cards:
		check(card["portrait"].texture != null, "实战卡图已接入")
	main._collection_search = "关羽"
	main._fill_collection()
	var box = main._shop_boxes["收藏"]
	var rows = box.get_child(box.get_child_count() - 1)
	check(rows.get_child_count() == 1, "图鉴名称搜索")
	main._collection_search = ""
	main._collection_type = "装备"
	main._fill_collection()
	rows = box.get_child(box.get_child_count() - 1)
	check(rows.get_child_count() == 36, "图鉴装备分类 36 张")
	main._collection_owned = true
	main._fill_collection()
	rows = box.get_child(box.get_child_count() - 1)
	check(rows.get_child_count() == 1 and rows.get_child(0) is Label, "持有过滤空状态")
	main.queue_free()
	await get_tree().process_frame
	GameState.save_game()
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/Main.tscn", "当前启动入口不再使用旧主菜单")
	print("[Print v1.2] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
