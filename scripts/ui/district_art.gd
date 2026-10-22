extends RefCounted

const Profiles = preload("res://scripts/ui/city_terrain_profiles.gd")
const STONE_WIDE = preload("res://assets/art_v21/open_stone_wide.png")
const STONE_SQUARE = preload("res://assets/art_v21/open_stone_square.png")
const EARTH_WIDE = preload("res://assets/art_v21/open_earth_wide.png")
const EARTH_SQUARE = preload("res://assets/art_v21/open_earth_square.png")
const GROUND := Color("ded6c4")

static func background_for(extent: Vector2, city_index: int = 1) -> Texture2D:
	var profile := Profiles.for_city(city_index)
	var wide := extent.x / extent.y >= 1.4
	if int(profile["ground"]) == 1:
		return EARTH_WIDE if wide else EARTH_SQUARE
	return STONE_WIDE if wide else STONE_SQUARE

static func source_rect(texture_size: Vector2, extent: Vector2) -> Rect2:
	var cover_scale := maxf(extent.x / texture_size.x, extent.y / texture_size.y)
	var source_size := extent / cover_scale
	return Rect2((texture_size - source_size) * 0.5, source_size)

static func draw_background(canvas: CanvasItem, area: Rect2, extent: Vector2, _zones: Array, city_index: int = 1) -> void:
	var profile := Profiles.for_city(city_index)
	var texture := background_for(extent, city_index)
	var flip := Vector2(-1 if bool(profile["flip_h"]) else 1, -1 if bool(profile["flip_v"]) else 1)
	var origin := area.position + Vector2(area.size.x if flip.x < 0 else 0, area.size.y if flip.y < 0 else 0)
	canvas.draw_set_transform(origin, 0, flip)
	canvas.draw_texture_rect_region(texture, Rect2(Vector2.ZERO, area.size), source_rect(texture.get_size(), extent), profile["tint"])
	canvas.draw_set_transform(Vector2.ZERO)
