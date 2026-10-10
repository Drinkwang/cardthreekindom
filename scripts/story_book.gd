extends RefCounted
class_name PaanStoryBook
## 古代荆州练拍营的一次性短故事。判定只读取快照，不发奖、不改战斗。
## context 接口见 next_event；已读及跳过状态由 GameState 持久保存。

const CAMP_SCENE := "res://assets/art_v2/backgrounds/home.png"
const TABLE_SCENE := "res://assets/art_v10/city_courtyard.png"


static func events() -> Array:
	return [
		{
			"id": "opening_robbery", "chapter": "序章", "title": "新野起家", "requires": [],
			"pages": [
				{"speaker": "关平", "portrait": "G23", "scene": CAMP_SCENE,
				 "text": "汉末，荆州。你奉命驻守新野，营中军资不足，集市上却有一门拍牌赚铜钱的手艺。\n\n关平把将牌分开摆在城内街巷：『瞄准掌风圈落掌，圈里翻得越多，收成便越多。』",
				 "caption": "你是古代新野的校尉，故事从军营与集市开始。"},
				{"speaker": "周仓", "portrait": "G20", "scene": TABLE_SCENE,
				 "text": "周仓摊开城内小图：『循图去街巷找牌。练稳这一掌，再添几分力气，手下翻起的牌自然越来越多。』\n\n你沿着街道巡城，决定先攒下营中第一笔军资。",
				 "caption": "滚轮缩放，鼠标靠边巡城；右上角小地图点选位置，按M收起或展开。"},
			],
		},
		{
			"id": "first_setback", "chapter": "第一章", "title": "先翻一张", "requires": ["opening_robbery"],
			"pages": [
				{"speaker": "马良", "portrait": "G24", "scene": TABLE_SCENE,
				 "text": "案上还有几张厚牌，钱囊里却已经多了铜钱。\n\n马良看过账册：『先看每秒能挣多少。手艺长一分，同样的工夫就能多攒一分军资。』\n\n你把这笔收入留作练掌的本钱。",
				 "caption": "已赚的铜钱与成长会保留。提升效率，再继续练拍。"},
			],
		},
		{
			"id": "early_practice", "chapter": "第一章", "title": "清一段，也算一步", "requires": ["opening_robbery"],
			"pages": [
				{"speaker": "周仓", "portrait": "G20", "scene": TABLE_SCENE,
				 "text": "薄牌接连翻起，铜钱在案边叮当落下。\n\n周仓：『练熟的牌也能继续赚钱。先把手头的生意做顺，再去试厚牌。』\n\n你在账册记下新野的第一笔收成。",
				 "caption": "已熟悉的牌继续提供收入；更厚的牌带来更高收益。"},
			],
		},
		{
			"id": "first_growth", "chapter": "第一章", "title": "下一掌不一样", "requires": ["opening_robbery"],
			"pages": [
				{"speaker": "关平", "portrait": "G23", "scene": TABLE_SCENE,
				 "text": "你用新赚的铜钱修习掌法，再把同样的牌放上木案。\n\n掌风落下，这一回翻得更快，案边的钱囊也鼓得更快。\n\n关平笑道：『每一笔投入，都要看得见长进。』",
				 "caption": "拍力决定一掌的收成，拍速决定同样时间能拍多少掌。"},
			],
		},
		{
			"id": "first_breakthrough", "chapter": "第一章", "title": "新野站稳", "requires": ["opening_robbery"],
			"pages": [
				{"speaker": "周仓", "portrait": "G20", "scene": CAMP_SCENE,
				 "text": "新野的拍牌生意终于站稳了。周仓把余下的牌重新理齐，商旅还在案前等着。\n\n『这份营生留着。军资越足，去下一座城便越有底气。』\n\n你收起账册，望向荆州舆图。",
				 "caption": "城池提供新的牌与经营机会，旧城仍能继续积攒军资。"},
			],
		},
		{
			"id": "camp_unlock", "chapter": "第一章", "title": "把收成接起来", "requires": ["first_breakthrough"],
			"pages": [
				{"speaker": "马良", "portrait": "G24", "scene": CAMP_SCENE,
				 "text": "营外开出第一块田，杂货铺也挂上了招牌。马良把产出逐项写进账册。\n\n『拍牌的钱拿来经营，营地的收成再用来练掌。两头接起来，军资就能越积越快。』",
				 "caption": "建筑持续产钱，组合与拍牌一起提升整体收入。"},
			],
		},
		{
			"id": "practice_partner", "chapter": "第二章", "title": "轮到我帮你练", "requires": ["first_breakthrough"],
			"pages": [
				{"speaker": "周仓", "portrait": "G20", "scene": TABLE_SCENE,
				 "text": "周仓召来营中壮士，按你的节奏轮流练拍。\n\n『你去安排营地，案前有我们守着。回来把新收成投进去，手艺还能再长一截。』\n\n木案上的掌声没有停，钱囊也慢慢充实起来。",
				 "caption": "自动练拍接续赚钱；提升拍速，让单位时间的收入继续增长。"},
			],
		},
		{
			"id": "north_spectator", "chapter": "第二章", "title": "北地商旅", "requires": ["first_breakthrough"],
			"pages": [
				{"speaker": "关平", "portrait": "G23", "scene": CAMP_SCENE,
				 "text": "北来的商旅带着厚牌经过新野。关平见你连拍数掌，便翻开另一页账册。\n\n『薄牌周转快，厚牌收成高。算准手里的拍力与拍速，便知道眼下哪门生意更合算。』",
				 "caption": "新牌带来新收益；用每秒收入判断当前效率。"},
			],
		},
		{
			"id": "give_back", "chapter": "第四章", "title": "军资有了着落", "requires": ["north_spectator"],
			"pages": [
				{"speaker": "马良", "portrait": "G24", "scene": CAMP_SCENE,
				 "text": "六座城的货路接了起来。马良把足额的粮饷交给军需官，再将余钱送回练拍营。\n\n『营中有粮，将士有饷。接下来赚的，便是下一次扩张的本钱。』",
				 "caption": "增长带来新的投入空间；持续升级，继续增加每秒收成。"},
			],
		},
		{
			"id": "name_the_slap", "chapter": "第五章", "title": "掌法成势", "requires": ["give_back"],
			"pages": [
				{"speaker": "周仓", "portrait": "G20", "scene": TABLE_SCENE,
				 "text": "你把将牌摆在掌法册旁，逐一记下相互接应的效果。\n\n周仓一掌落下，数张纸牌齐翻：『将牌配得好，掌风也有了阵势！』\n\n连拍、重掌与财路各有所长。你决定让整套组合的收成再提高一截。",
				 "caption": "将牌组合放大拍击与收入，拍力与拍速继续决定增长效率。"},
			],
		},
		{
			"id": "fair_match", "chapter": "第六章", "title": "江陵来信", "requires": ["give_back", "name_the_slap"],
			"pages": [
				{"speaker": "关羽", "portrait": "G28", "scene": CAMP_SCENE,
				 "text": "江陵送来军书，关羽邀你在全荆州铺开练拍营。\n\n『有进有退，稳住军资便好。先把眼下的掌法练熟，再去试更厚的牌。』\n\n你将军书夹入账册，继续经营手中的城池。",
				 "caption": "按自己的效率推进；升级、组合与经营都能增加收成。"},
			],
		},
		{
			"id": "finale", "chapter": "终章", "title": "掌声遍荆州", "requires": ["fair_match"],
			"pages": [
				{"speaker": "马良", "portrait": "G24", "scene": CAMP_SCENE,
				 "text": "二十一座城的收成汇进账册。荆州商路畅通，营中的铜钱与粮食都有了着落。\n\n马良合上这一册，取出一本新册：『第一叠薄牌的生意，竟做到了今日。往后的收成，还要接着记。』",
				 "caption": "荆州纪事告一段落，增长、经营与收藏继续。"},
				{"speaker": "周仓", "portrait": "G20", "scene": TABLE_SCENE,
				 "text": "木案上的掌声依旧。周仓把下一叠牌摆齐，问你还练不练。\n\n你翻开掌法册，看了看如今的每秒收成：『再快一点，再多翻几张。』\n\n新的铜钱落进钱囊，下一笔升级也有了本钱。",
				 "caption": "拍击赚钱，再用铜钱提升效率。下一掌总能更有收成。"},
			],
		},
	]


static func event_by_id(id: String) -> Dictionary:
	for event in events():
		if str(event.get("id", "")) == id:
			return event.duplicate(true)
	return {}


## context: runs:int, in_battle:bool, last_result:String, power_level:int,
## stamina_level:int(练拍时长), speed_level:int, auto_unlocked:bool, cleared_count:int(不含新野),
## cleared_regions:Array[int], table_wins:int, total_tables:int, practice_runs:int。
## 也接受 first_clear:bool 方便调用者生成快照。
## 序章是唯一可覆盖第一桌的事件；之后每次整备最多请求一个事件。
static func next_event(context: Dictionary, seen_ids: Array) -> Dictionary:
	for event in events():
		var id := str(event.get("id", ""))
		if id in seen_ids:
			continue
		var prerequisites: Array = event.get("requires", [])
		var ready := true
		for required in prerequisites:
			if required not in seen_ids:
				ready = false
				break
		if not ready:
			continue
		if bool(context.get("in_battle", false)) and id != "opening_robbery":
			continue
		if _condition_met(id, context):
			return event.duplicate(true)
	return {}


static func _condition_met(id: String, context: Dictionary) -> bool:
	var regions: Array = context.get("cleared_regions", [])
	var cleared := int(context.get("cleared_count", 0))
	var first_clear := bool(context.get("first_clear", false)) or 1 in regions
	match id:
		"opening_robbery":
			return int(context.get("runs", 0)) == 0 and not first_clear
		"first_setback":
			return str(context.get("last_result", "")) in ["settled", "failed", "retreat"] and not first_clear
		"early_practice":
			return int(context.get("table_wins", 0)) > 0 and not first_clear
		"first_growth":
			return int(context.get("power_level", 0)) > 0 or int(context.get("stamina_level", 0)) > 0 or int(context.get("speed_level", 0)) > 0
		"first_breakthrough":
			return first_clear
		"camp_unlock":
			return first_clear
		"practice_partner":
			return bool(context.get("auto_unlocked", false))
		"north_spectator":
			return cleared >= 2
		"give_back":
			return cleared >= 6
		"name_the_slap":
			return cleared >= 9
		"fair_match":
			return cleared >= 12
		"finale":
			return 21 in regions or bool(context.get("field_clear", false))
	return false


## 已读、跳过都能回看；只显示确实到达的段落，不预先透露后续纪事。
static func journal_entries(seen_ids: Array) -> Array:
	var entries: Array = []
	for event in events():
		if str(event.get("id", "")) in seen_ids:
			entries.append(event.duplicate(true))
	return entries
