extends Control
class_name PaanShop
const Art = preload("res://scripts/ui/print_art.gd")

signal closed()

var _stats: Label
var content: PanelContainer

func _ready() -> void:
	theme = Art.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.texture = Art.background("table")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	add_child(margin)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", Art.panel(Art.PAPER, 18, Art.RULE, 0))
	margin.add_child(paper)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	paper.add_child(page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(Art.stamp("铺", Vector2(54, 58)))
	var title := Art.label("商店", 38)
	title.add_theme_font_override("font", Art.title_font())
	head.add_child(title)
	_stats = Art.label("", 17, Art.DIM)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_stats)
	var back := Button.new()
	back.name = "ReturnToCamp"
	back.text = "← 返回大本营"
	back.custom_minimum_size = Vector2(176, 48)
	back.add_theme_font_override("font", Art.title_font())
	back.add_theme_font_size_override("font_size", 23)
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	page.add_child(head)
	page.add_child(Art.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	var shopfront := VBoxContainer.new()
	shopfront.custom_minimum_size.x = 340
	shopfront.add_theme_constant_override("separation", 14)
	row.add_child(shopfront)
	var grandma := Art.label("奶奶的卡铺", 30, Art.RED)
	grandma.add_theme_font_override("font", Art.title_font())
	shopfront.add_child(grandma)
	var picture := TextureRect.new()
	var atlas_path := "res://assets/art_v4/camp_atlas.png"
	if ResourceLoader.exists(atlas_path):
		var atlas := load(atlas_path) as Texture2D
		var tex := AtlasTexture.new()
		tex.atlas = atlas
		var cell := atlas.get_size() * 0.5
		tex.region = Rect2(Vector2(cell.x * 0.4, 0), Vector2(cell.x * 0.6, cell.y))
		picture.texture = tex
	else:
		picture.texture = Art.background("home")
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(340, 230)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shopfront.add_child(picture)
	var tip := Art.label("买一包新牌，接着去拍。\n卡包随征服区域解锁。", 19)
	tip.add_theme_font_override("font", Art.title_font())
	shopfront.add_child(tip)
	var hint := Art.label("新牌可在构筑中上阵。\n同星牌可合成，俘获的武将可招降。", 14, Art.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shopfront.add_child(hint)
	content = PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 10, Art.RULE, 0))
	row.add_child(content)
	refresh()

func open_shop() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	refresh()

func refresh() -> void:
	if _stats != null:
		_stats.text = "金币 %s" % GameState.fmt(GameState.gold)
