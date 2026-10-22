extends Node

const Art = preload("res://scripts/ui/district_art.gd")
const Layout = preload("res://scripts/city_layout.gd")
const Profiles = preload("res://scripts/ui/city_terrain_profiles.gd")
const PROFILE_KEYS := ["city_index", "name", "theme", "ground", "tint", "flip_h", "flip_v"]
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 6) -> void:
	for frame in count: await get_tree().process_frame

func _ready() -> void:
	check(GameState.save_path() != GameState.SAVE_PATH, "地形测试使用隔离存档")
	if GameState.save_path() == GameState.SAVE_PATH:
		get_tree().quit(1)
		return
	GameState.set_process(false)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output = argument.substr(10)
	for texture in [Art.STONE_WIDE, Art.STONE_SQUARE, Art.EARTH_WIDE, Art.EARTH_SQUARE]:
		test_texture(texture)
	check(Art.STONE_WIDE.get_width() > Art.STONE_WIDE.get_height() * 1.4 and Art.EARTH_WIDE.get_width() > Art.EARTH_WIDE.get_height() * 1.4, "宽幅地形资源具有实际横向构图")
	check(Art.STONE_SQUARE.get_width() == Art.STONE_SQUARE.get_height() and Art.EARTH_SQUARE.get_width() == Art.EARTH_SQUARE.get_height(), "方幅地形资源保持方形构图")
	check(GameData.regions.size() == 21, "开放平地覆盖全部21城")
	var combinations: Array = []
	for region in GameData.regions:
		var city_index := int(region["idx"])
		var profile: Dictionary = Profiles.for_city(city_index)
		check(profile.size() == PROFILE_KEYS.size() and PROFILE_KEYS.all(func(key: String) -> bool: return profile.has(key)), "%s仅保留开放平地配置字段" % region["name"])
		check(int(profile["city_index"]) == city_index and str(profile["name"]) == str(region["name"]), "%s地形配置对应实际城池编号与名称" % region["name"])
		check(not str(profile["theme"]).is_empty() and profile == Profiles.for_city(city_index), "%s地形主题可重复读取且确定" % region["name"])
		var tint: Color = profile["tint"]
		check(is_equal_approx(tint.a, 1.0) and tint.r > 0.8 and tint.g > 0.8 and tint.b > 0.8, "%s地形不透明且调色不过度压暗牌面" % region["name"])
		var combination := [Art.background_for(Vector2(1800, 1000), city_index).resource_path, tint, bool(profile["flip_h"]), bool(profile["flip_v"])]
		check(not combinations.has(combination), "%s实际地表、调色和翻转组合不同于其他城池" % region["name"])
		combinations.append(combination)
		for count in [5, 12]:
			test_world(city_index, count)
		test_world(city_index, GameState.zone_count(city_index))
		profile["theme"] = "测试副本"
		check(Profiles.for_city(city_index)["theme"] != "测试副本", "%s配置副本不修改生产配置" % region["name"])
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var minimap_source := FileAccess.get_file_as_string("res://scripts/ui/city_minimap.gd")
	var call := RegEx.new()
	call.compile("DistrictArt\\.draw_background\\([^\\n]*GameState\\.battle_region\\)")
	check(call.search(main_source) != null, "主图显式传入实际战斗城池编号")
	call.compile("DistrictArt\\.draw_background\\([^\\n]*city_index\\)")
	check(call.search(minimap_source) != null and main_source.contains("_minimap.set_city_index(GameState.battle_region)"), "小地图使用同一实际城池编号与共用地形绘制")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/ui/district_art.gd")
	check(renderer_source.count("canvas.draw_texture_rect_region(") == 1 and not renderer_source.contains("for zone") and not renderer_source.contains("EDGE_ATLAS") and not renderer_source.contains("scenery("), "整城一次绘制连续平地，不再铺分区建筑或重复地块")
	if not output.is_empty() and DisplayServer.get_name() != "headless": await capture_terrain()
	print("[District art] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(DisplayServer.get_name() != "headless")])
	get_tree().quit(1 if failures > 0 else 0)

func test_texture(texture: Texture2D) -> void:
	var image := texture.get_image()
	var label := texture.resource_path.get_file()
	check(image != null and not image.is_empty() and image.get_width() >= 1000 and image.get_height() >= 800, label + "开放地形原图存在且保留实际清晰度")
	if image == null or image.is_empty(): return
	check(image.detect_alpha() == Image.ALPHA_NONE, label + "整幅地形不透明，不露出下层旧地图")
	check(image.has_mipmaps(), label + "小地图与缩放使用mipmap")
	var colors := {}
	for row in 24:
		for column in 32:
			var point := Vector2i((column + 0.5) / 32.0 * image.get_width(), (row + 0.5) / 24.0 * image.get_height())
			colors[image.get_pixelv(point).to_rgba32()] = true
	check(colors.size() >= 24, label + "保留绘画纹理，不退化为纯色底")

func test_world(city_index: int, count: int) -> void:
	var zones := Layout.zone_rects(count)
	var extent := Layout.zone_world_size(count)
	var positions: Array = []
	for zone in count: positions.append(Layout.zone_positions(25, city_index, zone, count))
	var before := positions.duplicate(true)
	var texture: Texture2D = Art.background_for(extent, city_index)
	var earth := int(Profiles.for_city(city_index)["ground"]) == 1
	var wide := extent.x / extent.y >= 1.4
	var expected: Texture2D = Art.EARTH_WIDE if earth and wide else (Art.EARTH_SQUARE if earth else (Art.STONE_WIDE if wide else Art.STONE_SQUARE))
	var label := "%s%d区" % [Profiles.for_city(city_index)["name"], count]
	check(texture == expected and texture == Art.background_for(extent, city_index), label + "按真实世界宽高比与地表类型选图且主小图确定一致")
	var size := Vector2(texture.get_size())
	var source := Art.source_rect(size, extent)
	check(source.has_area() and Rect2(Vector2.ZERO, size).grow(0.01).encloses(source), label + "cover源区完整位于实际原图内")
	check(is_equal_approx(source.size.x / source.size.y, extent.x / extent.y), label + "等比裁切，不横向或纵向拉伸")
	check(source.get_center().distance_to(size * 0.5) < 0.01 and (is_equal_approx(source.size.x, size.x) or is_equal_approx(source.size.y, size.y)), label + "使用居中cover，不放大裁掉多余场地")
	check(zones == Layout.zone_rects(count) and extent == Layout.zone_world_size(count) and positions == before, label + "地形选择与裁切不修改分区、世界尺寸和敌牌位置")

func snapshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(output.path_join(filename)) == OK, "保存原生地形 " + filename)

func capture_terrain() -> void:
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		for city_index in [1, 11, 21]:
			GameState.new_game()
			if city_index != 1:
				for region in GameData.regions: GameState.region_state[int(region["idx"])] = "cleared" if int(region["idx"]) != city_index else "available"
				check(GameState.start_battle(city_index), "截图夹具开启城池%d" % city_index)
			var main = load("res://scenes/Main.tscn").instantiate()
			add_child(main)
			await frames(8)
			main.set_process(false)
			main._window_focused = false
			main._close_home()
			GameState.narrative_paused = false
			await frames()
			main._reset_camera()
			await frames()
			check(main.size.is_equal_approx(Vector2(1280, height)) and main._bar.get_global_rect().encloses(main._minimap.get_global_rect()), "%d高度城池%d真实内容视口与小地图完整" % [height, city_index])
			var prefix := "city-%02d-%d-" % [city_index, height]
			await snapshot(prefix + "default.png")
			main._set_camera_zoom(1.0, main._table.size * 0.5)
			main._navigate_minimap(main._world_size * 0.5)
			await frames()
			await snapshot(prefix + "overview.png")
			main._set_camera_zoom(main.DEFAULT_ZOOM, main._table.size * 0.5)
			var extent: Vector2 = main._world_size
			for entry in [["center", extent * 0.5], ["north", Vector2(extent.x * 0.5, 0)], ["south", Vector2(extent.x * 0.5, extent.y)], ["west", Vector2(0, extent.y * 0.5)], ["east", Vector2(extent.x, extent.y * 0.5)]]:
				main._navigate_minimap(entry[1])
				await frames()
				await snapshot(prefix + entry[0] + ".png")
			main.queue_free()
			await frames()
