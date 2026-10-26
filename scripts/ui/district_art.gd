extends RefCounted

const Profiles = preload("res://scripts/ui/city_terrain_profiles.gd")
const GROUND := Color("ded6c4")
static var _cached_city := -1
static var _background: Texture2D
static var _detail: Texture2D

static func _load_city(city_index: int) -> void:
	var profile := Profiles.for_city(city_index)
	if _cached_city == int(profile["city_index"]): return
	_background = load(str(profile["background"])) as Texture2D
	_detail = load(str(profile["detail"])) as Texture2D
	_cached_city = int(profile["city_index"])

static func background_for(_extent: Vector2, city_index: int = 1) -> Texture2D:
	_load_city(city_index)
	return _background

static func detail_for(city_index: int = 1) -> Texture2D:
	_load_city(city_index)
	return _detail

static func source_rect(texture_size: Vector2, extent: Vector2) -> Rect2:
	var cover_scale := maxf(extent.x / texture_size.x, extent.y / texture_size.y)
	var source_size := extent / cover_scale
	return Rect2((texture_size - source_size) * 0.5, source_size)
