extends Node

const Art = preload("res://scripts/ui/district_art.gd")
const Layout = preload("res://scripts/city_layout.gd")
const Profiles = preload("res://scripts/ui/city_terrain_profiles.gd")
const PROFILE_KEYS := ["city_index", "name", "theme", "ground", "tint", "background", "detail"]
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
	check(GameData.regions.size() == 21, "开放平地覆盖全部21城")
	var source_hashes := {}
	for region in GameData.regions:
		var city_index := int(region["idx"])
		var profile: Dictionary = Profiles.for_city(city_index)
		check(profile.size() == PROFILE_KEYS.size() and PROFILE_KEYS.all(func(key: String) -> bool: return profile.has(key)), "%s仅保留开放平地配置字段" % region["name"])
		check(int(profile["city_index"]) == city_index and str(profile["name"]) == str(region["name"]), "%s地形配置对应实际城池编号与名称" % region["name"])
		check(not str(profile["theme"]).is_empty() and profile == Profiles.for_city(city_index), "%s地形主题可重复读取且确定" % region["name"])
		var tint: Color = profile["tint"]
		check(is_equal_approx(tint.a, 1.0) and tint.r > 0.8 and tint.g > 0.8 and tint.b > 0.8, "%s地形不透明且调色不过度压暗牌面" % region["name"])
		var background_path := "res://assets/art_v26/city_%02d.png" % city_index
		var detail_path := "res://assets/art_v26/ground_%02d.png" % city_index
		check(str(profile["background"]) == background_path and str(profile["detail"]) == detail_path, "%s独立整城与地表原图路径对应编号" % region["name"])
		test_texture(Art.background_for(Vector2(1800, 1000), city_index), background_path, source_hashes)
		test_texture(Art.detail_for(city_index), detail_path, source_hashes)
		print("[City terrain identity] " + JSON.stringify({"city_index": city_index, "name": str(region["name"]), "background": background_path, "detail": detail_path}))
		for count in [5, 12]:
			test_world(city_index, count)
		test_world(city_index, GameState.zone_count(city_index))
		profile["theme"] = "测试副本"
		check(Profiles.for_city(city_index)["theme"] != "测试副本", "%s配置副本不修改生产配置" % region["name"])
	check(source_hashes.size() == 42, "21城使用42张内容不同的原图，不以调色、翻转或同图别名代替")
	if DisplayServer.get_name() != "headless":
		await test_rendered_seams()
		if not output.is_empty(): await capture_terrain()
	print("[District art] checks=%d failures=%d actual_gui=%s" % [checks, failures, str(DisplayServer.get_name() != "headless")])
	get_tree().quit(1 if failures > 0 else 0)

func test_texture(texture: Texture2D, expected_path: String, source_hashes: Dictionary) -> void:
	check(FileAccess.file_exists(expected_path), expected_path.get_file() + "独立原文件存在")
	var digest := FileAccess.get_sha256(expected_path)
	check(not digest.is_empty() and not source_hashes.has(digest), expected_path.get_file() + "原文件SHA256不重复")
	if not digest.is_empty(): source_hashes[digest] = expected_path
	check(texture != null and texture.resource_path == expected_path, expected_path.get_file() + "实际加载该城独立原图")
	if texture == null: return
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
	var label := "%s%d区" % [Profiles.for_city(city_index)["name"], count]
	check(texture != null and texture.resource_path == "res://assets/art_v26/city_%02d.png" % city_index and texture == Art.background_for(extent, city_index), label + "按实际城池选独立整城图且主小图确定一致")
	if texture == null: return
	var size := Vector2(texture.get_size())
	var source := Art.source_rect(size, extent)
	check(source.has_area() and Rect2(Vector2.ZERO, size).grow(0.01).encloses(source), label + "cover源区完整位于实际原图内")
	check(is_equal_approx(source.size.x / source.size.y, extent.x / extent.y), label + "等比裁切，不横向或纵向拉伸")
	check(source.get_center().distance_to(size * 0.5) < 0.01 and (is_equal_approx(source.size.x, size.x) or is_equal_approx(source.size.y, size.y)), label + "使用居中cover，不放大裁掉多余场地")
	check(zones == Layout.zone_rects(count) and extent == Layout.zone_world_size(count) and positions == before, label + "地形选择与裁切不修改分区、世界尺寸和敌牌位置")

func test_scene_terrain(main, city_index: int, height: int) -> void:
	var label := "%d高度城池%d" % [height, city_index]
	var terrain = main._pile_layer.get_node_or_null("CityCourtyardArt")
	var minimap = main._minimap
	var miniature = minimap.get_node_or_null("TerrainArt")
	var markers = minimap.get_node_or_null("Markers")
	check(terrain != null and miniature != null and markers != null, label + "主图与小地图均有独立地形层及小地图标记层")
	if terrain == null or miniature == null or markers == null: return
	check(terrain.material is ShaderMaterial and miniature.material is ShaderMaterial and terrain.material != miniature.material, label + "主小图各持独立ShaderMaterial，不串改画布尺寸")
	check(main._zone_layer.material == null and minimap.material == null and markers.material == null and not markers.use_parent_material, label + "分区纸签、小地图纸框和红点不受地形Shader污染")
	check(terrain.get_index() < main._zone_layer.get_index() and markers.z_index > miniature.z_index, label + "分区与红点绘制在地形上层")
	check(terrain.mouse_filter == Control.MOUSE_FILTER_IGNORE and miniature.mouse_filter == Control.MOUSE_FILTER_IGNORE and markers.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + "地形与标记层不抢占鼠标")
	check(terrain.world_size == main._world_size and miniature.world_size == main._world_size and minimap.world_size == main._world_size, label + "主小图共用未改变的实际世界尺寸")
	check(terrain.city_index == city_index and miniature.city_index == city_index and minimap.city_index == city_index, label + "主小图对应当前实际城池")
	check(terrain.background_texture == miniature.background_texture and terrain.detail_texture == miniature.detail_texture, label + "主小图共用该城相同整城与高清地表纹理")
	check(terrain.size.is_equal_approx(main._world_size) and miniature.position.is_equal_approx(minimap.map_area.position) and miniature.size.is_equal_approx(minimap.map_area.size), label + "主图覆盖世界且缩略地形严格贴合地图坐标区")
	check(markers.position == Vector2.ZERO and markers.size.is_equal_approx(minimap.size), label + "红点和视野保持原小地图本地坐标")
	var count := GameState.zone_count(city_index)
	check(main._world_size == Layout.zone_world_size(count) and minimap.zones.size() == count, label + "地形接入不改变实际分区数量和几何")
	var bounds := Layout.zone_rects(count)
	for zone in minimap.zones:
		check(zone["rect"] == bounds[int(zone["zone"])], label + "分区%d保留原始边界" % int(zone["zone"]))
	for view in [terrain, miniature]:
		var terrain_material: ShaderMaterial = view.material
		if terrain_material == null: continue
		check(terrain_material.get_shader_parameter("background_texture") == view.background_texture and terrain_material.get_shader_parameter("detail_texture") == view.detail_texture, label + "Shader绑定真实城池的两张纹理")
		check(terrain_material.get_shader_parameter("world_size") == main._world_size and terrain_material.get_shader_parameter("canvas_size") == view.size.max(Vector2.ONE), label + "Shader分别使用相同世界尺度与各自画布尺寸")
		var source := Art.source_rect(view.background_texture.get_size(), main._world_size)
		var texture_size: Vector2 = view.background_texture.get_size()
		var expected_uv := Vector4(source.position.x / texture_size.x, source.position.y / texture_size.y, source.size.x / texture_size.x, source.size.y / texture_size.y)
		var actual_uv: Vector4 = terrain_material.get_shader_parameter("background_uv_rect")
		check(actual_uv.is_equal_approx(expected_uv) and terrain_material.get_shader_parameter("tint") == Profiles.for_city(city_index)["tint"], label + "Shader背景等比cover与城池色彩参数正确")
		check(terrain_material.shader.code.contains("world_uv * world_size / 640.0") and terrain_material.shader.code.contains("mix(background, detail, center_weight)"), label + "中心使用640世界单位高清地表，外围保留整城构图")
		check(terrain_material.shader.code.contains("1.0 - abs(mod(detail_uv, vec2(2.0)) - vec2(1.0))") and terrain_material.shader.code.contains("detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable"), label + "地表镜像衔接且边缘不串采对侧像素")
	print("[City terrain runtime] " + JSON.stringify({"city_index": city_index, "height": height, "background": terrain.background_texture.resource_path, "detail": terrain.detail_texture.resource_path}))

func test_rendered_seams() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	add_child(viewport)
	var terrain = load("res://scripts/ui/city_terrain_view.gd").new()
	terrain.size = Vector2(512, 512)
	viewport.add_child(terrain)
	for city_index in range(1, 22):
		terrain.set_terrain(Vector2(1280, 1280), city_index)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await frames(2)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var horizontal_error := 0.0
		var vertical_error := 0.0
		for sample in range(96, 417, 16):
			horizontal_error = maxf(horizontal_error, color_difference(image.get_pixel(255, sample), image.get_pixel(256, sample)))
			vertical_error = maxf(vertical_error, color_difference(image.get_pixel(sample, 255), image.get_pixel(sample, 256)))
		check(horizontal_error <= 0.015, "城池%d实际GPU横向镜像边界连续，误差%.4f" % [city_index, horizontal_error])
		check(vertical_error <= 0.015, "城池%d实际GPU纵向镜像边界连续，误差%.4f" % [city_index, vertical_error])
	viewport.queue_free()
	await frames()

func color_difference(first: Color, second: Color) -> float:
	return maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))

func test_sampling_density(main, city_index: int, height: int, zoom: float) -> void:
	var detail: Texture2D = main._pile_layer.get_node("CityCourtyardArt").detail_texture
	var enlargement: float = 640.0 / minf(detail.get_width(), detail.get_height()) * main._camera_scale
	check(is_equal_approx(main._camera_zoom, zoom), "%d高度城池%d测量实际%.1f倍镜头" % [height, city_index, zoom])
	check(enlargement <= 1.3, "%d高度城池%d镜头%.1f倍地表每源像素屏幕放大率%.3f不超过1.3" % [height, city_index, zoom, enlargement])
	print("[Terrain pixel density] " + JSON.stringify({"city_index": city_index, "height": height, "zoom": zoom, "camera_scale": main._camera_scale, "source_size": str(detail.get_size()), "screen_pixels_per_source_pixel": enlargement}))

func snapshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(output.path_join(filename)) == OK, "保存原生地形 " + filename)

func capture_terrain() -> void:
	for height in [720, 800]:
		get_window().content_scale_size = Vector2i(1280, height)
		get_window().size = Vector2i(1280, height)
		var cities := [1, 11, 21] if height == 720 else range(1, 22)
		for city_index in cities:
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
			test_scene_terrain(main, city_index, height)
			test_sampling_density(main, city_index, height, main.DEFAULT_ZOOM)
			if height == 800: await snapshot(prefix + "identity.png")
			if city_index in [1, 11, 21]:
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
			main._set_camera_zoom(main.ZOOM_MAX, main._table.size * 0.5)
			await frames()
			test_sampling_density(main, city_index, height, main.ZOOM_MAX)
			main.queue_free()
			await frames()
