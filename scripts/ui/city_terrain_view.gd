extends Control

const DistrictArt = preload("res://scripts/ui/district_art.gd")
const Profiles = preload("res://scripts/ui/city_terrain_profiles.gd")
const TerrainShader = preload("res://scripts/ui/city_terrain.gdshader")

var world_size := Vector2.ONE
var city_index := -1
var background_texture: Texture2D
var detail_texture: Texture2D
var _terrain_material: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TerrainShader
	material = _terrain_material
	resized.connect(_sync_canvas)


func set_terrain(extent: Vector2, value: int) -> void:
	var next_extent := extent.max(Vector2.ONE)
	var profile := Profiles.for_city(value)
	var next_city := int(profile["city_index"])
	if world_size == next_extent and city_index == next_city: return
	world_size = next_extent
	city_index = next_city
	background_texture = DistrictArt.background_for(world_size, city_index)
	detail_texture = DistrictArt.detail_for(city_index)
	_terrain_material.set_shader_parameter("background_texture", background_texture)
	_terrain_material.set_shader_parameter("detail_texture", detail_texture)
	_terrain_material.set_shader_parameter("world_size", world_size)
	_terrain_material.set_shader_parameter("tint", profile["tint"])
	var texture_size := background_texture.get_size()
	var source := DistrictArt.source_rect(texture_size, world_size)
	_terrain_material.set_shader_parameter("background_uv_rect", Vector4(
		source.position.x / texture_size.x, source.position.y / texture_size.y,
		source.size.x / texture_size.x, source.size.y / texture_size.y))
	_sync_canvas()


func _sync_canvas() -> void:
	_terrain_material.set_shader_parameter("canvas_size", size.max(Vector2.ONE))
	queue_redraw()


func _draw() -> void:
	if background_texture == null or detail_texture == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
