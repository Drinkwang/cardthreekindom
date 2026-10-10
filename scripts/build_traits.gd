class_name PaanBuildTraits
extends RefCounted
## 构筑说明与实战共用同一批六将。尚未实现的主将、自动拍不在此显示。

const TRAITS := {
	"G04": {"name": "朱灵", "title": "三拍引雷", "tag": "雷印", "role": "附印", "color": Color("416777"),
		"description": "每3次基础拍击，为存活最厚牌附1层雷印，最多3层。"},
	"G05": {"name": "文聘", "title": "重掌引爆", "tag": "雷印", "role": "引爆", "color": Color("416777"),
		"description": "重拍消耗目标最多2层雷印，每层追加1.5倍轻拍伤害；冷却6秒。"},
	"G30": {"name": "韩玄", "title": "重拍点火", "tag": "烈火", "role": "点燃", "color": Color("a33d29"),
		"description": "重拍使存活目标燃烧6秒，每秒造成0.3倍轻拍伤害；点火冷却4秒。"},
	"G40": {"name": "程普", "title": "四拍借风", "tag": "烈火", "role": "扩散", "color": Color("a33d29"),
		"description": "每4次基础拍击，将已有燃烧复制到另一张未燃烧的牌，保留伤害和剩余时长。"},
	"G20": {"name": "周仓", "title": "三轻追印", "tag": "追击", "role": "标记", "color": Color("487164"),
		"description": "每3次轻拍，标记存活最厚牌6秒；基础拍击对标记牌增伤20%。"},
	"G24": {"name": "马良", "title": "白羽追击", "tag": "追击", "role": "收割", "color": Color("487164"),
		"description": "标记牌翻倒时，追击另一张最低生命普通牌，造成1倍轻拍伤害；冷却6秒。"},
}


static func describe(id: String) -> Dictionary:
	if not TRAITS.has(id):
		return {}
	var info: Dictionary = TRAITS[id].duplicate(true)
	info["summary"] = info["description"]
	return info


static func team_summary(carry: Array) -> Dictionary:
	var steps: Array = []
	var missing: Array = []
	var tags: Array = []
	var chains: Array = []
	var complete_tags: Array = []
	for pair in [["G04", "G05", "雷印", "朱灵附雷 → 文聘重拍引爆"],
		["G30", "G40", "烈火", "韩玄点火 → 程普借风扩散"],
		["G20", "G24", "追击", "周仓标记 → 马良追击残牌"]]:
		var has_source := carry.has(pair[0])
		var has_finish := carry.has(pair[1])
		if has_source or has_finish:
			tags.append(pair[2])
		if has_source and has_finish:
			chains.append(pair[3])
			complete_tags.append(pair[2])
		elif has_source:
			missing.append("%s：可搭配%s（%s）" % [pair[2], TRAITS[pair[1]]["name"], TRAITS[pair[1]]["role"]])
		elif has_finish:
			missing.append("%s：缺少%s（%s）" % [pair[2], TRAITS[pair[0]]["name"], TRAITS[pair[0]]["role"]])
	for id in carry:
		var info := describe(str(id))
		if not info.is_empty():
			steps.append("%s · %s" % [info["name"], info["title"]])
	var title := "组合初成"
	var description := "选两位互相接招的武将，形成自动联动。"
	if chains.size() > 1:
		title = "混搭连锁"
	elif chains.size() == 1:
		title = "%s联动" % complete_tags[0]
	elif not tags.is_empty():
		title = "%s起手" % "、".join(tags)
	if not chains.is_empty():
		description = "；".join(chains)
	elif not steps.is_empty():
		description = "核心武将已上阵，补齐搭档可延长连锁。"
	return {"title": title, "description": description, "steps": steps,
		"missing": missing, "tags": tags}
