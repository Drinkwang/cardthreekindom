extends RefCounted

const PROFILES := [
	{"city_index": 1, "name": "新野", "theme": "秋叶暖石", "ground": 0},
	{"city_index": 2, "name": "樊城", "theme": "疏草灰石", "ground": 0},
	{"city_index": 3, "name": "中庐", "theme": "桑荫黄土", "ground": 1},
	{"city_index": 4, "name": "宜城", "theme": "柳影青石", "ground": 2},
	{"city_index": 5, "name": "宛城", "theme": "松荫汉庭", "ground": 0},
	{"city_index": 6, "name": "襄阳", "theme": "苔痕灰石", "ground": 0},
	{"city_index": 7, "name": "当阳", "theme": "草坡土路", "ground": 1},
	{"city_index": 8, "name": "夏口", "theme": "芦影青石", "ground": 2},
	{"city_index": 9, "name": "夷陵", "theme": "山麓土坪", "ground": 1},
	{"city_index": 10, "name": "武昌", "theme": "疏柳石路", "ground": 0},
	{"city_index": 11, "name": "沅陵", "theme": "青石竹庭", "ground": 2},
	{"city_index": 12, "name": "公安", "theme": "草缘空坪", "ground": 1},
	{"city_index": 13, "name": "汉寿", "theme": "荷叶青石", "ground": 2},
	{"city_index": 14, "name": "临沅", "theme": "林荫土路", "ground": 1},
	{"city_index": 15, "name": "攸县", "theme": "麦草土坪", "ground": 1},
	{"city_index": 16, "name": "临湘", "theme": "桂荫暖石", "ground": 0},
	{"city_index": 17, "name": "耒阳", "theme": "草影青板岩", "ground": 2},
	{"city_index": 18, "name": "郴县", "theme": "樟荫赤土", "ground": 1},
	{"city_index": 19, "name": "观阳", "theme": "浅草白石", "ground": 0},
	{"city_index": 20, "name": "泉陵", "theme": "蕨影青石", "ground": 2},
	{"city_index": 21, "name": "江陵", "theme": "灰石汉庭", "ground": 0},
]

static func for_city(city_index: int) -> Dictionary:
	if city_index < 1 or city_index > PROFILES.size():
		city_index = 1
	var profile: Dictionary = PROFILES[city_index - 1].duplicate(true)
	profile["tint"] = Color.WHITE
	profile["background"] = "res://assets/art_v26/city_%02d.png" % city_index
	profile["detail"] = "res://assets/art_v26/ground_%02d.png" % city_index
	return profile
