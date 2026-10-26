extends RefCounted
## UI 皮肤：宣纸底、墨金双线与朱砂主按钮。尺寸由调用者的布局决定。
const Art = preload("res://scripts/ui/print_art.gd")
const PaperChrome = preload("res://scripts/ui/paper_chrome.gd")
const LACQUER := Color("201b18")
const LACQUER_RAISED := Color("2d241d")
const LACQUER_GOLD := Color("c59c58")
const LACQUER_TEXT := Color("f4e7c8")
const LACQUER_MUTED := Color("c6b18d")
const LACQUER_RED := Color("e49a7e")
const LACQUER_RULE := Color("765735")


static func panel(fill: Color = Art.PAPER_LIGHT, padding: float = 10.0,
		accent: Color = Art.RULE, border: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = accent
	box.set_border_width_all(maxi(0, border))
	box.set_corner_radius_all(1)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.7
	box.content_margin_bottom = padding * 0.7
	box.shadow_color = Color(Art.INK, 0.18)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 2)
	return box


static func lacquer_panel(padding: float = 10.0, border: int = 1) -> StyleBoxFlat:
	var box := panel(LACQUER, padding, LACQUER_RULE, border)
	box.shadow_color = Color(0, 0, 0, 0.35)
	return box


static func button(control: Button, primary: bool = false, compact: bool = false) -> void:
	var padding: float = 6.0 if compact else 11.0
	var ink: Color = Art.PAPER_LIGHT if primary else Art.INK
	var normal: StyleBoxFlat = panel(Art.RED if primary else Color("f7edcf"), padding,
		Color("6e2e24") if primary else Color("96764b"))
	var hover: StyleBoxFlat = panel(Color("b14b32") if primary else Color("fff6df"), padding,
		Color("d6b377") if primary else Art.RED)
	var pressed: StyleBoxFlat = panel(Color("813223") if primary else Color("e4cba2"), padding,
		Color("e0c18f") if primary else Color("765432"))
	pressed.shadow_size = 0
	var disabled: StyleBoxFlat = panel(Color("e0d4bd"), padding, Color("b9ab91"))
	disabled.shadow_size = 0
	var focus: StyleBoxFlat = panel(Color.TRANSPARENT, padding, Art.GOLD, 2)
	focus.draw_center = false
	focus.shadow_size = 0
	_apply_button_styles(control, normal, hover, pressed, disabled, focus,
		ink, Color("827462"), primary, compact)
	_decorate_button(control, "primary_button" if primary else "button")


static func lacquer_button(control: Button, primary: bool = false, compact: bool = false) -> void:
	var padding: float = 6.0 if compact else 11.0
	var normal := lacquer_panel(padding)
	normal.bg_color = Color("552316") if primary else LACQUER_RAISED
	normal.border_color = LACQUER_GOLD
	var hover := lacquer_panel(padding)
	hover.bg_color = Color("74321f") if primary else Color("443323")
	hover.border_color = Color("efd09a")
	var pressed := lacquer_panel(padding)
	pressed.bg_color = Color("48241c") if primary else Color("191511")
	pressed.border_color = Color("a97d43")
	pressed.shadow_size = 0
	var disabled := lacquer_panel(padding)
	disabled.bg_color = Color("27231f")
	disabled.border_color = Color("554a3b")
	disabled.shadow_size = 0
	var focus := lacquer_panel(padding, 2)
	focus.border_color = Color("f3d6a0")
	focus.draw_center = false
	focus.shadow_size = 0
	_apply_button_styles(control, normal, hover, pressed, disabled, focus,
		LACQUER_TEXT, Color("817361"), primary, compact)
	_decorate_button(control, "lacquer_primary_button" if primary else "lacquer_button")


static func _apply_button_styles(control: Button, normal: StyleBoxFlat, hover: StyleBoxFlat,
		pressed: StyleBoxFlat, disabled: StyleBoxFlat, focus: StyleBoxFlat,
		ink: Color, disabled_ink: Color, primary: bool, compact: bool) -> void:
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("hover", hover)
	control.add_theme_stylebox_override("pressed", pressed)
	control.add_theme_stylebox_override("disabled", disabled)
	control.add_theme_stylebox_override("focus", focus)
	if not control.has_theme_font_override("font"):
		control.add_theme_font_override("font", Art.title_font() if primary else Art.body_font())
	if not control.has_theme_font_size_override("font_size"):
		control.add_theme_font_size_override("font_size", 13 if compact else 16)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, ink)
	control.add_theme_color_override("font_disabled_color", disabled_ink)
	control.add_theme_constant_override("outline_size", 0)
	control.add_theme_constant_override("h_separation", 6)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func _decorate_button(control: Button, variant: String) -> void:
	var decoration: Control = control.get_node_or_null("ButtonPaperChrome") as Control
	if decoration == null:
		decoration = chrome(control, variant)
		decoration.name = "ButtonPaperChrome"
	else:
		decoration.set("variant", variant)
		decoration.queue_redraw()


static func chrome(parent: Control, variant: String = "paper") -> Control:
	var layer: Control = PaperChrome.new()
	layer.set("variant", variant)
	layer.name = "PaperChrome"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.focus_mode = Control.FOCUS_NONE
	layer.custom_minimum_size = Vector2.ZERO
	parent.add_child(layer)
	parent.move_child(layer, 0)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer


static func emblem(kind: String, minimum: Vector2 = Vector2(34, 34), lacquer: bool = false) -> Control:
	var icon: Control = PaperChrome.new()
	icon.set("variant", "emblem")
	icon.set("emblem_kind", kind)
	icon.set("lacquer_emblem", lacquer)
	icon.name = kind.capitalize() + "Emblem"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	icon.custom_minimum_size = minimum
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


static func lacquer_stamp(text: String, minimum: Vector2) -> Control:
	var seal := PaperChrome.new()
	seal.variant = "lacquer_seal"
	seal.custom_minimum_size = minimum
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.focus_mode = Control.FOCUS_NONE
	var caption := Art.label("\n".join(text.split("")), 24, LACQUER_TEXT)
	caption.add_theme_font_override("font", Art.title_font())
	caption.add_theme_font_size_override("font_size", maxi(14, mini(int(minimum.x - 12), int((minimum.y - 10) / text.length()))))
	caption.add_theme_constant_override("line_spacing", -3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 5
	caption.offset_right = -5
	caption.offset_top = 3
	caption.offset_bottom = -3
	return seal

