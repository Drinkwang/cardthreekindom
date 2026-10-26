extends Control
class_name PaanShop
const Art = preload("res://scripts/ui/print_art.gd")
const UISkin = preload("res://scripts/ui/ui_skin.gd")

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
	paper.name = "ShopShellFrame"
	paper.add_theme_stylebox_override("panel", UISkin.lacquer_panel(18))
	margin.add_child(paper)
	UISkin.chrome(paper, "lacquer")
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	paper.add_child(page)
	var header := PanelContainer.new()
	header.name = "ShopShellHeader"
	header.add_theme_stylebox_override("panel", UISkin.lacquer_panel(0, 0))
	page.add_child(header)
	UISkin.chrome(header, "lacquer")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	header.add_child(head)
	head.add_child(UISkin.lacquer_stamp("铺", Vector2(54, 58)))
	var title := Art.label("商店", 38, UISkin.LACQUER_TEXT)
	title.add_theme_font_override("font", Art.title_font())
	head.add_child(title)
	_stats = Art.label("", 17, UISkin.LACQUER_MUTED)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_stats)
	var back := Button.new()
	back.name = "ReturnToCamp"
	back.text = "← 返回大本营"
	back.custom_minimum_size = Vector2(176, 48)
	back.add_theme_font_override("font", Art.title_font())
	back.add_theme_font_size_override("font_size", 23)
	UISkin.lacquer_button(back)
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	page.add_child(Art.divider())
	var body := PanelContainer.new()
	body.name = "ShopPaperContent"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_stylebox_override("panel", Art.panel(Art.PAPER, 0, Art.RULE, 0))
	page.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var shopfront := VBoxContainer.new()
	shopfront.custom_minimum_size.x = 340
	shopfront.add_theme_constant_override("separation", 14)
	row.add_child(shopfront)
	var shop_name := Art.label("军需卡铺", 30, Art.RED)
	shop_name.add_theme_font_override("font", Art.title_font())
	shopfront.add_child(shop_name)
	var picture := TextureRect.new()
	var atlas_path := "res://assets/art_v14/camp_atlas.png"
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
	content = PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel", Art.panel(Art.PAPER_LIGHT, 10, Art.RULE, 0))
	row.add_child(content)
	refresh()

func open_shop() -> void:
	if GameState.in_battle: return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	refresh()

func refresh() -> void:
	if _stats != null:
		_stats.text = "金币 %s" % GameState.fmt(GameState.gold)
