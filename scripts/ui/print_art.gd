extends RefCounted
## 怀旧印刷统一资源层。插画与动态文案分开，所有界面共享同一份 ID 映射。
const AncientSetting = preload("res://scripts/ancient_setting.gd")

const PAPER := Color("f1e6ca")
const PAPER_LIGHT := Color("f8f0dc")
const INK := Color("2b211a")
const DIM := Color("74654f")
const RED := Color("9d3d2e")
const RULE := Color("b8a078")
const GOLD := Color("927029")
const ROUTES := {
	"魏线": Color("294a80"), "蜀线": Color("a52e24"),
	"吴线": Color("21665b"), "群雄线": Color("8c681c"),
	"起点": Color("76644b"), "通用": Color("76644b"),
}
const RARITY := {
	1: Color("8a8172"), 2: Color("56714f"), 3: Color("416282"),
	4: Color("75566f"), 5: Color("a17c2f"), 6: Color("a63f2c"),
}
const SCENIC_ATLASES := [
	{"path": "res://assets/art_v7/buildings_a.png", "first": 1, "count": 12, "columns": 4, "rows": 3},
	{"path": "res://assets/art_v7/buildings_b.png", "first": 13, "count": 12, "columns": 4, "rows": 3},
	{"path": "res://assets/art_v7/buildings_c.png", "first": 25, "count": 6, "columns": 3, "rows": 2},
]
const SCENIC_HEROES := ["G04", "G05", "G30", "G40", "G20", "G24"]

static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}
static var _portraits: Dictionary = {}
static var _portrait_icons: Dictionary = {}
static var _theme: Theme
static var _font: SystemFont
static var _title_font: SystemFont


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var f := FileAccess.open("res://assets/art_v2/catalog.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_catalog = parsed.get("cards", {})
		_apply_portrait_overrides()
		_apply_scenic_overrides()
		_apply_unified_hero_overrides()
		_apply_ancient_portrait_aliases()
	return _catalog


## 兼容旧存档的卡牌 ID，最终统一使用古代人物插图。
static func _apply_ancient_portrait_aliases() -> void:
	for id in AncientSetting.PORTRAIT_ALIASES:
		var source_id := str(AncientSetting.PORTRAIT_ALIASES[id])
		if not _catalog.has(id) or not _catalog.has(source_id):
			continue
		var source: Dictionary = _catalog[source_id]
		var updated: Dictionary = _catalog[id].duplicate()
		for field in ["atlas", "columns", "rows", "index", "inset", "icon_focus", "icon_scale"]:
			if source.has(field):
				updated[field] = source[field]
		updated["art_version"] = "ancient-setting"
		if AncientSetting.CARD_TEXT.has(id):
			updated["name"] = str(AncientSetting.CARD_TEXT[id].get("name", updated.get("name", "")))
		_catalog[id] = updated


## v3 只替换已存在 ID 的插图，不新增卡、不改变名称或玩法数据。
## 新图尚未完成导入、路径失效或格位重复时，保留 v2 的有效映射。
static func _apply_portrait_overrides() -> void:
	var file := FileAccess.open("res://assets/art_v3/portrait_overrides.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var overrides: Variant = parsed.get("cards", {})
	if not overrides is Dictionary:
		return
	var occupied := {}
	for id in _catalog:
		var base: Dictionary = _catalog[id]
		occupied[str(base.get("atlas", "")) + ":" + str(base.get("index", 0))] = id
	for id in overrides:
		if AncientSetting.PORTRAIT_ALIASES.has(id):
			continue
		if not _catalog.has(id) or not overrides[id] is Dictionary:
			continue
		var entry: Dictionary = overrides[id]
		var path := str(entry.get("atlas", ""))
		var columns := int(entry.get("columns", 1))
		var rows := int(entry.get("rows", 1))
		var index := int(entry.get("index", 0))
		if columns < 1 or rows < 1 or index < 0 or index >= columns * rows:
			continue
		if not ResourceLoader.exists(path):
			continue
		var key := path + ":" + str(index)
		if occupied.has(key) and occupied[key] != id:
			continue
		var source := _textures.get(path) as Texture2D
		if source == null:
			source = load(path) as Texture2D
		if source == null or source.get_width() < columns or source.get_height() < rows:
			continue
		var updated: Dictionary = _catalog[id].duplicate()
		var old_key := str(updated.get("atlas", "")) + ":" + str(updated.get("index", 0))
		occupied.erase(old_key)
		occupied[key] = id
		updated["atlas"] = path
		updated["columns"] = columns
		updated["rows"] = rows
		updated["index"] = index
		_catalog[id] = updated
		_textures[path] = source


## v7 为每座建筑使用完整场景；缺失、未导入或无效图集继续用既有插图。
## 覆盖只改图像坐标和裁边，名称、星级、规则等原有字段均保留。
static func _apply_scenic_overrides() -> void:
	for atlas in SCENIC_ATLASES:
		var path := str(atlas["path"])
		var columns := int(atlas["columns"])
		var rows := int(atlas["rows"])
		var source := _valid_texture(path)
		if source == null or source.get_width() < columns or source.get_height() < rows:
			continue
		for index in int(atlas["count"]):
			var id := "B%02d" % (int(atlas["first"]) + index)
			if not _catalog.has(id):
				continue
			var updated: Dictionary = _catalog[id].duplicate()
			updated["atlas"] = path
			updated["columns"] = columns
			updated["rows"] = rows
			updated["index"] = index
			updated["inset"] = 0.01
			_catalog[id] = updated
	var hero_path := "res://assets/art_v7/heroes.png"
	var portraits := _valid_texture(hero_path)
	if portraits == null or portraits.get_width() < 3 or portraits.get_height() < 2:
		return
	for index in SCENIC_HEROES.size():
		var id: String = SCENIC_HEROES[index]
		if not _catalog.has(id):
			continue
		var updated: Dictionary = _catalog[id].duplicate()
		updated["atlas"] = hero_path
		updated["columns"] = 3
		updated["rows"] = 2
		updated["index"] = index
		updated["inset"] = 0.01
		_catalog[id] = updated


## v8 武将全部按固定 ID 顺序排在同风格图集中。
## 只覆盖通过校验的格位；没有新图的卡仍使用 v7/v3/v2 对应图像。
static func _apply_unified_hero_overrides() -> void:
	var file := FileAccess.open("res://assets/art_v8/heroes_catalog.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var overrides: Variant = parsed.get("cards", {})
	if not overrides is Dictionary:
		return
	var occupied := {}
	for id in overrides:
		if (not str(id).begins_with("G") and id != "I01") or not _catalog.has(id) or not overrides[id] is Dictionary:
			continue
		var entry: Dictionary = overrides[id]
		var path := str(entry.get("atlas", ""))
		var columns := int(entry.get("columns", 0))
		var rows := int(entry.get("rows", 0))
		var index := int(entry.get("index", -1))
		if columns < 1 or rows < 1 or index < 0 or index >= columns * rows:
			continue
		var key := path + ":" + str(index)
		if occupied.has(key):
			continue
		occupied[key] = id
		var source := _valid_texture(path)
		if source == null or source.get_width() < columns or source.get_height() < rows:
			continue
		var updated: Dictionary = _catalog[id].duplicate()
		for field in ["atlas", "columns", "rows", "index", "inset", "icon_focus", "icon_scale"]:
			if entry.has(field):
				updated[field] = entry[field]
		updated["art_version"] = "print-v8-unified-heroes"
		_catalog[id] = updated


static func _valid_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var source := _textures.get(path) as Texture2D
	if source == null:
		source = load(path) as Texture2D
	if source == null or source.get_width() <= 0 or source.get_height() <= 0:
		return null
	_textures[path] = source
	return source


static func texture(card_id: String) -> Texture2D:
	if _portraits.has(card_id):
		return _portraits[card_id] as Texture2D
	var entry: Dictionary = catalog().get(card_id, {})
	if entry.is_empty():
		return null
	var path := str(entry.get("atlas", ""))
	if not _textures.has(path):
		if not ResourceLoader.exists(path):
			return null
		_textures[path] = load(path) as Texture2D
	var source: Texture2D = _textures[path]
	if source == null:
		return null
	var columns := maxi(1, int(entry.get("columns", 1)))
	var rows := maxi(1, int(entry.get("rows", 1)))
	var index := int(entry.get("index", 0))
	var cell := source.get_size() / Vector2(columns, rows)
	var inset := cell * clampf(float(entry.get("inset", 0.055)), 0.0, 0.2)
	var result := AtlasTexture.new()
	result.atlas = source
	result.region = Rect2(Vector2(index % columns, index / columns) * cell + inset,
		cell - inset * 2.0)
	result.filter_clip = true
	_portraits[card_id] = result
	return result


static func image(card_id: String, minimum: Vector2 = Vector2(48, 48)) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture(card_id)
	node.custom_minimum_size = minimum
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.set_meta("print_card_id", card_id)
	return node


## 小头像从原图集读取同一武将的脸和肩胸安全区，不重新缩小整张主卡。
## 使用方形像素裁切，避免不同图集纵横比造成头像尺寸和留白不一致。
static func portrait_icon_texture(card_id: String) -> Texture2D:
	if _portrait_icons.has(card_id):
		return _portrait_icons[card_id] as Texture2D
	var main := texture(card_id)
	if not card_id.begins_with("G") and card_id != "I01":
		return main
	if not main is AtlasTexture:
		return main
	var portrait := main as AtlasTexture
	var entry: Dictionary = catalog().get(card_id, {})
	var focus: Variant = entry.get("icon_focus", [0.5, 0.43])
	var focus_point := Vector2(0.5, 0.43)
	if focus is Array and focus.size() == 2:
		focus_point = Vector2(clampf(float(focus[0]), 0.0, 1.0), clampf(float(focus[1]), 0.0, 1.0))
	var area := portrait.region
	var side := minf(area.size.x, area.size.y) * clampf(float(entry.get("icon_scale", 0.88)), 0.50, 1.0)
	var local := area.size * focus_point - Vector2(side, side) * 0.5
	local.x = clampf(local.x, 0.0, area.size.x - side)
	local.y = clampf(local.y, 0.0, area.size.y - side)
	var result := AtlasTexture.new()
	result.atlas = portrait.atlas
	result.region = Rect2(area.position + local, Vector2(side, side))
	result.filter_clip = true
	_portrait_icons[card_id] = result
	return result


static func portrait_icon(card_id: String, minimum: Vector2 = Vector2(48, 48)) -> TextureRect:
	var node := image(card_id, minimum)
	node.texture = portrait_icon_texture(card_id)
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	node.set_meta("print_portrait_icon", true)
	return node


## 场景大图铺满画框，普通仓库小图继续调用 image() 保持完整轮廓。
static func scenic(card_id: String, minimum: Vector2 = Vector2(200, 110)) -> TextureRect:
	var node := image(card_id, minimum)
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return node


static func paper_background() -> Texture2D:
	var paper := background("paper")
	return paper if paper != null else ui_texture("paper_grain")


static func background(name: String) -> Texture2D:
	if name == "paper" or name == "deck_scene":
		var scenic_path := "res://assets/art_v7/%s.png" % name
		var scenic_texture := _valid_texture(scenic_path)
		if scenic_texture != null:
			return scenic_texture
	var path := "res://assets/art_v2/backgrounds/%s.png" % ("home" if name == "cover" else name)
	if ResourceLoader.exists(path):
		if not _textures.has(path):
			_textures[path] = load(path) as Texture2D
		return _textures[path] as Texture2D
	var original := "res://assets/bg/%s.png" % name
	return load(original) as Texture2D if ResourceLoader.exists(original) else null


static func body_font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	return _font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = SystemFont.new()
		_title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun", "Noto Serif CJK SC", "Songti SC"])
	return _title_font


static func panel(fill: Color = PAPER, padding: float = 9.0,
		border: Color = RULE, width: int = 1) -> PaperStyle:
	var box := PaperStyle.new()
	box.grain = ui_texture("paper_grain")
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(1)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.7
	box.content_margin_bottom = padding * 0.7
	return box


static func card_frame(star: int, boss: bool = false) -> PaperStyle:
	var ink: Color = RARITY.get(clampi(star, 1, 6), RULE)
	var box := panel(PAPER_LIGHT, 6, ink, 2 if boss else 1)
	box.set_meta("paper_card", true)
	box.shadow_color = Color(0.09, 0.06, 0.03, 0.35)
	box.shadow_size = 4
	box.shadow_offset = Vector2(2, 3)
	return box


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 14
	for cls in ["Button", "MenuButton", "OptionButton"]:
		th.set_stylebox("normal", cls, panel(PAPER_LIGHT, 10))
		th.set_stylebox("hover", cls, panel(Color("fff7e3"), 10, RED))
		th.set_stylebox("pressed", cls, panel(Color("e9d6ad"), 10, RED))
		th.set_stylebox("disabled", cls, panel(Color("e3dbc9"), 10, Color("c9bda5")))
		th.set_stylebox("focus", cls, panel(Color(0, 0, 0, 0), 10, RED, 2))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			th.set_color(state, cls, INK)
		th.set_color("font_disabled_color", cls, Color("9b8c76"))
		th.set_constant("icon_max_width", cls, 36)
		th.set_constant("h_separation", cls, 6)
		th.set_constant("outline_size", cls, 0)
	th.set_stylebox("panel", "PanelContainer", panel())
	th.set_stylebox("panel", "Panel", panel())
	th.set_stylebox("panel", "PopupMenu", panel(PAPER_LIGHT, 8))
	th.set_stylebox("hover", "PopupMenu", panel(Color("e9d6ad"), 4, RED))
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", RED)
	th.set_color("font_disabled_color", "PopupMenu", DIM)
	th.set_constant("icon_max_width", "PopupMenu", 28)
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		th.set_stylebox(state, "TabContainer", panel(PAPER_LIGHT if state == "tab_selected" else PAPER, 7))
	for state in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		th.set_color(state, "TabContainer", INK)
	th.set_stylebox("background", "ProgressBar", panel(Color("cbbfa6"), 0, RULE))
	th.set_stylebox("fill", "ProgressBar", panel(RED, 0, RED, 0))
	th.set_stylebox("panel", "TooltipPanel", panel(PAPER_LIGHT, 12, RED))
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_stylebox("normal", "LineEdit", panel(PAPER_LIGHT, 7))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", RED)
	th.set_color("selection_color", "LineEdit", Color(0.66, 0.24, 0.17, 0.18))
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_color("font_color", "CheckBox", INK)
	th.set_color("font_hover_color", "CheckBox", RED)
	th.set_color("font_pressed_color", "CheckBox", RED)
	th.set_stylebox("normal", "CheckBox", panel(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 0))
	th.set_stylebox("scroll", "VScrollBar", panel(Color("ded4bf"), 0, Color("ded4bf"), 0))
	th.set_stylebox("grabber", "VScrollBar", panel(Color("9f8b68"), 0, RULE, 0))
	_theme = th
	return th


static func label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 纸纹与小图标都是独立矢量 UI，不复用或改写卡牌 ID 图集。
static func ui_texture(name: String) -> Texture2D:
	var key := "print_ui:" + name
	if _textures.has(key):
		return _textures[key] as Texture2D
	var path := "res://assets/art_v3/ui/%s.svg" % name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var raster := Image.new()
	if raster.load_svg_from_string(file.get_as_text()) != OK:
		return null
	var tex := ImageTexture.create_from_image(raster)
	_textures[key] = tex
	return tex


static func nav_icon(kind: String) -> Texture2D:
	var known := ["map", "home", "city", "shop", "cards", "gold", "stamina", "gear", "synth"]
	return ui_texture("nav_" + kind) if known.has(kind) else null


## 背景装饰永远不遮挡交互；overlay 可放在已有插画上保留画面。
static func paper_surface(kind: String = "paper") -> Control:
	var surface := PrintSurface.new()
	surface.kind = kind
	surface.grain = ui_texture("paper_grain")
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return surface


static func stamp(text: String, minimum: Vector2 = Vector2(60, 72),
		ink: Color = RED) -> Control:
	var seal := PrintStamp.new()
	seal.ink = ink
	seal.grain = ui_texture("seal_wear")
	seal.custom_minimum_size = minimum
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := label(text, 24, PAPER_LIGHT)
	var vertical := minimum.y > minimum.x * 1.15
	if vertical and text.length() > 1:
		var lines := PackedStringArray()
		for i in text.length():
			lines.append(text.substr(i, 1))
		caption.text = "\n".join(lines)
	var letters := text.length() if not vertical else 1
	var fit := mini(38, int((minimum.x - 14.0) / maxf(1.0, letters)))
	if vertical:
		fit = mini(fit, int((minimum.y - 10.0) / maxf(1.0, text.length())))
	caption.add_theme_font_size_override("font_size", maxi(14, fit))
	caption.add_theme_font_override("font", title_font())
	caption.add_theme_constant_override("line_spacing", -3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 5
	caption.offset_right = -5
	caption.offset_top = 3
	caption.offset_bottom = -3
	seal.add_child(caption)
	return seal


static func divider() -> Control:
	var line := PrintDivider.new()
	line.custom_minimum_size = Vector2(0, 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func city_id(index: int) -> String:
	return "C%02d" % index


static func faction_label(route: String) -> String:
	return {"魏线": "魏", "蜀线": "蜀", "吴线": "吴", "群雄线": "群",
		"起点": "新", "通用": "通"}.get(route, "通")


static func deck_metrics(count: int, area: Vector2, ratio: float = 1.38) -> Dictionary:
	if count <= 0:
		return {"columns": 1, "rows": 1, "card_size": Vector2(106, 146), "gap": 18.0}
	var gap := 18.0 if area.y > 460.0 else 12.0
	var pad := 22.0 if area.y > 460.0 else 10.0
	var best_score := -10000.0
	var result := {}
	for columns in range(1, count + 1):
		var rows := ceili(float(count) / float(columns))
		var width := minf((area.x - pad * 2.0 - gap * (columns - 1)) / columns,
			(area.y - pad * 2.0 - gap * (rows - 1)) / (rows * ratio))
		width = minf(190.0, width)
		var score := width - float(columns * rows - count) * 2.0
		if score > best_score:
			best_score = score
			result = {"columns": columns, "rows": rows,
				"card_size": Vector2(maxf(48.0, width), maxf(48.0, width) * ratio), "gap": gap}
	return result


static func deck_position(index: int, count: int, area: Vector2, metrics: Dictionary) -> Vector2:
	var columns := int(metrics["columns"])
	var rows := int(metrics["rows"])
	var card_size: Vector2 = metrics["card_size"]
	var gap := float(metrics["gap"])
	var row := index / columns
	var column := index % columns
	var row_count := mini(columns, count - row * columns)
	var total_height := rows * card_size.y + (rows - 1) * gap
	var row_width := row_count * card_size.x + (row_count - 1) * gap
	return Vector2((area.x - row_width) * 0.5 + column * (card_size.x + gap),
		(area.y - total_height) * 0.5 + row * (card_size.y + gap))


static func decorate(star: int) -> Control:
	var motif := PrintCorners.new()
	motif.star = clampi(star, 1, 6)
	motif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motif.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return motif


class PrintCorners extends Control:
	var star := 1
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var col: Color = RARITY.get(star, RULE)
		var length := 5.0 + float(star)
		var faded := Color(col, 0.30)
		if size.x > 45.0 and size.y > 55.0:
			draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), faded, false, 1.0)
		for anchor in [Vector2(3, 3), Vector2(size.x - 3, 3),
			Vector2(3, size.y - 3), Vector2(size.x - 3, size.y - 3)]:
			var direction := Vector2(1 if anchor.x < size.x * 0.5 else -1,
				1 if anchor.y < size.y * 0.5 else -1)
			draw_line(anchor, anchor + Vector2(length * direction.x, 0), col, 1)
			draw_line(anchor, anchor + Vector2(0, length * direction.y), col, 1)
			if star >= 4:
				draw_circle(anchor + direction * 4, 1.5, col)
				draw_line(anchor + Vector2(length * direction.x, 3 * direction.y),
					anchor + Vector2(length * direction.x, length * direction.y), faded, 1.0)
				draw_line(anchor + Vector2(3 * direction.x, length * direction.y),
					anchor + Vector2(length * direction.x, length * direction.y), faded, 1.0)


## StyleBoxFlat 原生绘制会绕过脚本 _draw，所以继承 StyleBox 并保留常用 flat API。
## 模板样式先画，再画不遮字的纹理。纹理缓存，全屏 UI 不生成逐像素噪声。
class PaperStyle extends StyleBox:
	var grain: Texture2D
	var bg_color := PAPER
	var border_color := RULE
	var draw_center := true
	var border_blend := false
	var shadow_color := Color(0, 0, 0, 0.6)
	var shadow_size := 0
	var shadow_offset := Vector2.ZERO
	var anti_aliasing := true
	var corner_radius_top_left := 0
	var corner_radius_top_right := 0
	var corner_radius_bottom_left := 0
	var corner_radius_bottom_right := 0
	var border_width_left := 0
	var border_width_top := 0
	var border_width_right := 0
	var border_width_bottom := 0
	var _base := StyleBoxFlat.new()
	func set_corner_radius_all(radius: int) -> void:
		corner_radius_top_left = radius
		corner_radius_top_right = radius
		corner_radius_bottom_left = radius
		corner_radius_bottom_right = radius
		emit_changed()
	func set_border_width_all(width: int) -> void:
		border_width_left = width
		border_width_top = width
		border_width_right = width
		border_width_bottom = width
		emit_changed()
	func set_border_width(side: Side, width: int) -> void:
		match side:
			SIDE_LEFT: border_width_left = width
			SIDE_TOP: border_width_top = width
			SIDE_RIGHT: border_width_right = width
			SIDE_BOTTOM: border_width_bottom = width
		emit_changed()
	func get_border_width(side: Side) -> int:
		match side:
			SIDE_LEFT: return border_width_left
			SIDE_TOP: return border_width_top
			SIDE_RIGHT: return border_width_right
			SIDE_BOTTOM: return border_width_bottom
		return 0
	func _get_minimum_size() -> Vector2:
		return Vector2(border_width_left + border_width_right, border_width_top + border_width_bottom)
	func _get_draw_rect(rect: Rect2) -> Rect2:
		return rect.merge(Rect2(rect.position + shadow_offset, rect.size).grow(shadow_size))
	func _draw(canvas: RID, rect: Rect2) -> void:
		_base.bg_color = bg_color
		_base.border_color = border_color
		_base.draw_center = draw_center
		_base.border_blend = border_blend
		_base.shadow_color = shadow_color
		_base.shadow_size = shadow_size
		_base.shadow_offset = shadow_offset
		_base.anti_aliasing = anti_aliasing
		_base.corner_radius_top_left = corner_radius_top_left
		_base.corner_radius_top_right = corner_radius_top_right
		_base.corner_radius_bottom_left = corner_radius_bottom_left
		_base.corner_radius_bottom_right = corner_radius_bottom_right
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_base.set_border_width(side, get_border_width(side))
		_base.draw(canvas, rect)
		if grain != null and bg_color.a > 0.05 and draw_center:
			var surface := rect.grow(-1.0)
			RenderingServer.canvas_item_add_texture_rect(canvas, surface, grain.get_rid(), true,
				Color(1, 1, 1, bg_color.a * 0.38))
		if border_color.a < 0.01 or get_border_width(SIDE_LEFT) == 0:
			return
		if rect.size.x >= 38.0 and rect.size.y >= 26.0:
			var inset := 4.0 if rect.size.y < 45.0 else 5.0
			var inner := rect.grow(-inset)
			var faint := Color(border_color, border_color.a * 0.30)
			RenderingServer.canvas_item_add_line(canvas, inner.position,
				Vector2(inner.end.x, inner.position.y), faint, 1.0, true)
			RenderingServer.canvas_item_add_line(canvas, Vector2(inner.position.x, inner.end.y),
				inner.end, faint, 1.0, true)
			if rect.size.y > 80.0:
				RenderingServer.canvas_item_add_line(canvas, inner.position,
					Vector2(inner.position.x, inner.end.y), faint, 1.0, true)
				RenderingServer.canvas_item_add_line(canvas, Vector2(inner.end.x, inner.position.y),
					inner.end, faint, 1.0, true)


class PrintSurface extends Control:
	var kind := "paper"
	var grain: Texture2D
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		if kind == "wood":
			draw_rect(Rect2(Vector2.ZERO, size), Color("4a2d1e"))
			for y in range(0, int(size.y), 61):
				draw_line(Vector2(0, y), Vector2(size.x, y + 1), Color(0.08, 0.04, 0.025, 0.5), 2)
				for line in range(3):
					var offset := float(y) + 11.0 + line * 9.0
					draw_line(Vector2(0, offset), Vector2(size.x, offset + 3), Color(0.70, 0.45, 0.28, 0.10), 1)
		elif kind != "overlay":
			draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		if grain != null:
			draw_texture_rect(grain, Rect2(Vector2.ZERO, size), true,
				Color(1, 1, 1, 0.28 if kind == "overlay" else 0.42))
		if kind == "paper" and size.x > 80.0 and size.y > 80.0:
			draw_rect(Rect2(Vector2(9, 9), size - Vector2(18, 18)), Color(RULE, 0.45), false, 1.0)
			draw_line(Vector2(9, 13), Vector2(size.x - 9, 13), Color(RULE, 0.22), 1.0)


class PrintStamp extends Control:
	var ink := RED
	var grain: Texture2D
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_rect(r, ink)
		draw_rect(r.grow(-3), Color(PAPER_LIGHT, 0.70), false, 1.0)
		draw_rect(r.grow(-5), Color(PAPER_LIGHT, 0.33), false, 1.0)
		if grain != null:
			draw_texture_rect(grain, r, true, Color(PAPER_LIGHT, 0.66))
		for edge in range(7):
			var along := size.x * float(edge + 1) / 8.0
			draw_line(Vector2(along, 2), Vector2(along + 3, 2), PAPER, 1.0)
			draw_line(Vector2(along - 2, size.y - 2), Vector2(along + 1, size.y - 2), PAPER, 1.0)


class PrintDivider extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var cy := size.y * 0.5
		var cx := size.x * 0.5
		draw_line(Vector2(0, cy), Vector2(cx - 11, cy), Color(RULE, 0.6), 1.0)
		draw_line(Vector2(cx + 11, cy), Vector2(size.x, cy), Color(RULE, 0.6), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - 3), Vector2(cx + 3, cy),
			Vector2(cx, cy + 3), Vector2(cx - 3, cy)]), Color(GOLD, 0.70))
