extends RefCounted
## UI 皮肤：宣纸底、墨金双线与朱砂主按钮。尺寸由调用者的布局决定。
const Art = preload("res://scripts/ui/print_art.gd")
const PaperChrome = preload("res://scripts/ui/paper_chrome.gd")


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
	control.add_theme_color_override("font_disabled_color", Color("827462"))
	control.add_theme_constant_override("outline_size", 0)
	control.add_theme_constant_override("h_separation", 6)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var decoration: Control = control.get_node_or_null("ButtonPaperChrome") as Control
	if decoration == null:
		decoration = chrome(control, "primary_button" if primary else "button")
		decoration.name = "ButtonPaperChrome"
	else:
		decoration.set("variant", "primary_button" if primary else "button")
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


static func emblem(kind: String, minimum: Vector2 = Vector2(34, 34)) -> Control:
	var icon: Control = PaperChrome.new()
	icon.set("variant", "emblem")
	icon.set("emblem_kind", kind)
	icon.name = kind.capitalize() + "Emblem"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	icon.custom_minimum_size = minimum
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

