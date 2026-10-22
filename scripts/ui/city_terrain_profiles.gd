extends RefCounted

const PROFILES := [
	{
		"city_index": 1, "name": "新野", "theme": "秋叶石坪", "ground": 0,
		"tint": Color(1.0, 0.99, 0.96), "flip_h": false, "flip_v": false,
	},
	{
		"city_index": 2, "name": "樊城", "theme": "疏草灰石", "ground": 0,
		"tint": Color(0.95, 0.97, 1.0), "flip_h": true, "flip_v": false,
	},
	{
		"city_index": 3, "name": "中庐", "theme": "桑荫土坪", "ground": 1,
		"tint": Color(1.0, 0.97, 0.92), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 4, "name": "宜城", "theme": "柳影青石", "ground": 2,
		"tint": Color(0.96, 0.99, 0.99), "flip_h": true, "flip_v": true,
	},
	{
		"city_index": 5, "name": "宛城", "theme": "松荫平庭", "ground": 0,
		"tint": Color(0.99, 0.98, 0.95), "flip_h": false, "flip_v": false,
	},
	{
		"city_index": 6, "name": "襄阳", "theme": "苔痕石坪", "ground": 0,
		"tint": Color(0.96, 0.98, 0.96), "flip_h": true, "flip_v": false,
	},
	{
		"city_index": 7, "name": "当阳", "theme": "草坡土路", "ground": 1,
		"tint": Color(1.0, 0.98, 0.94), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 8, "name": "夏口", "theme": "芦影青石", "ground": 2,
		"tint": Color(0.94, 0.98, 1.0), "flip_h": true, "flip_v": true,
	},
	{
		"city_index": 9, "name": "夷陵", "theme": "山麓土坪", "ground": 1,
		"tint": Color(0.98, 0.97, 0.94), "flip_h": true, "flip_v": false,
	},
	{
		"city_index": 10, "name": "武昌", "theme": "疏柳石路", "ground": 0,
		"tint": Color(1.0, 0.99, 0.97), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 11, "name": "沅陵", "theme": "竹影土坪", "ground": 1,
		"tint": Color(0.97, 0.99, 0.94), "flip_h": true, "flip_v": true,
	},
	{
		"city_index": 12, "name": "公安", "theme": "草缘空坪", "ground": 1,
		"tint": Color(1.0, 0.96, 0.92), "flip_h": false, "flip_v": false,
	},
	{
		"city_index": 13, "name": "汉寿", "theme": "荷叶青石", "ground": 2,
		"tint": Color(0.96, 1.0, 0.98), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 14, "name": "临沅", "theme": "林荫土路", "ground": 1,
		"tint": Color(0.99, 0.97, 0.93), "flip_h": true, "flip_v": true,
	},
	{
		"city_index": 15, "name": "攸县", "theme": "麦草土坪", "ground": 1,
		"tint": Color(1.0, 0.98, 0.91), "flip_h": true, "flip_v": false,
	},
	{
		"city_index": 16, "name": "临湘", "theme": "桂荫石路", "ground": 0,
		"tint": Color(1.0, 0.97, 0.95), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 17, "name": "耒阳", "theme": "草影青石", "ground": 2,
		"tint": Color(0.97, 0.98, 1.0), "flip_h": true, "flip_v": false,
	},
	{
		"city_index": 18, "name": "郴县", "theme": "樟荫土坪", "ground": 1,
		"tint": Color(0.98, 0.98, 0.94), "flip_h": false, "flip_v": true,
	},
	{
		"city_index": 19, "name": "观阳", "theme": "浅草石坪", "ground": 0,
		"tint": Color(0.98, 0.99, 1.0), "flip_h": true, "flip_v": true,
	},
	{
		"city_index": 20, "name": "泉陵", "theme": "蕨影青石", "ground": 2,
		"tint": Color(0.95, 0.99, 0.98), "flip_h": false, "flip_v": false,
	},
	{
		"city_index": 21, "name": "江陵", "theme": "松影空庭", "ground": 0,
		"tint": Color(0.99, 0.98, 0.96), "flip_h": true, "flip_v": false,
	},
]

static func for_city(city_index: int) -> Dictionary:
	if city_index < 1 or city_index > PROFILES.size():
		city_index = 1
	var profile: Dictionary = PROFILES[city_index - 1]
	return profile.duplicate(true)
