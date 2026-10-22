class_name PaanMapEvents
extends RefCounted
## 地图事件独立于敌牌；持久数据只使用JSON基本类型，世界坐标在entries中临时转换。

const HUNT_SECONDS := 20.0
const ESCORT_STEP := 80.0
const ESCORT_NEAR := 160.0
const ESCORT_GOAL := 55.0
const CARD_SIZE := Vector2(178, 182)
const ITEM_NAMES := {"supply": "军需"}

static func ensure_region(state: Object, idx: int) -> bool:
	if GameData.region(idx).is_empty(): return false
	var changed := false
	var bounds: Rect2 = state.zone_rect(idx, 0)
	var configs := [
		{"kind": "chest", "point": Vector2(0.15, 0.13), "reward": {"kind": "item", "id": "supply", "amount": 1}},
		{"kind": "hunt", "point": Vector2(0.50, 0.13), "target_card": _hunt_target(idx), "required": 2,
			"reward": {"kind": "xp", "amount": 20 + idx * 5}},
		{"kind": "exchange", "point": Vector2(0.84, 0.13), "card_cost": {"id": "S01", "amount": 1},
			"item_cost": {"id": "supply", "amount": 1},
			"reward": {"kind": "card", "id": "E02" if idx == 1 else ("E03" if idx == 2 else "E04"), "amount": 1}},
	]
	if idx >= 2:
		configs.append({"kind": "escort", "point": Vector2(0.28, 0.81), "target": Vector2(0.67, 0.81),
			"reward": {"kind": "gold", "amount": 30 + idx * 10}})
	for config in configs:
		var id := "%s_%d" % [config["kind"], idx]
		if state.map_events.has(id): continue
		var point: Vector2 = bounds.position + bounds.size * Vector2(config["point"])
		var event := {"id": id, "region": idx, "zone": 0, "kind": config["kind"], "status": "ready",
			"claimed": false, "position": [point.x, point.y], "reward": config["reward"].duplicate(true)}
		for field in ["target_card", "required", "card_cost", "item_cost"]:
			if config.has(field): event[field] = config[field]
		if config.has("target"):
			var target: Vector2 = bounds.position + bounds.size * Vector2(config["target"])
			event["target"] = [target.x, target.y]
		state.map_events[id] = event
		changed = true
	for event in state.map_events.values():
		if int(event.get("region", 0)) != idx or str(event.get("kind", "")) != "hunt": continue
		if str(event.get("status", "ready")) not in ["ready", "failed"]: continue
		if _remaining_targets(state, event) < int(event["required"]):
			event["status"] = "expired"
			changed = true
	return changed

static func entries(state: Object, idx: int) -> Array[Dictionary]:
	ensure_region(state, idx)
	var result: Array[Dictionary] = []
	for event in state.map_events.values():
		if int(event.get("region", 0)) != idx: continue
		var kind := str(event["kind"])
		var status := str(event["status"])
		var point := _point(event["position"])
		var entry := {"id": str(event["id"]), "kind": kind, "status": status, "point": point,
			"rect": Rect2(point - CARD_SIZE * 0.5, CARD_SIZE), "reward_text": _reward_text(event["reward"]),
			"title": "", "hint": "", "progress_text": "", "card_id": "B11"}
		match kind:
			"chest":
				entry["title"] = "军需宝箱"
				entry["hint"] = "拍开得一个奖励" if status != "done" else "已经领过"
				entry["progress_text"] = "未开启" if status != "done" else "已开启"
			"hunt":
				entry["title"] = "限时剿敌"
				entry["card_id"] = str(event["target_card"])
				entry["hint"] = _hunt_hint(status)
				entry["progress_text"] = "%s %d/%d" % [str(event["target_card"]), int(event.get("kills", 0)), int(event["required"])]
				if status == "active": entry["progress_text"] = "%.1f秒 · %s" % [float(event.get("remaining", 0)), entry["progress_text"]]
			"exchange":
				entry["title"] = "军需换兵"
				entry["card_id"] = str(event["reward"]["id"])
				entry["hint"] = "拍下查看并兑换" if status != "done" else "兑换已完成"
				entry["progress_text"] = "%s×%d + 军需×%d" % [GameData.card_name(str(event["card_cost"]["id"])), int(event["card_cost"]["amount"]), int(event["item_cost"]["amount"])]
			"escort":
				entry["title"] = "护送军需官"
				entry["card_id"] = "G00"
				entry["target"] = _point(event["target"])
				entry["near_radius"] = ESCORT_NEAR if status == "active" else 0.0
				entry["hint"] = "拍本体顺箭头走" if status == "active" else ("拍下接取护送" if status == "ready" else "已安全送达")
				entry["progress_text"] = "不受伤 · 不算敌人" if status != "done" else "护送完成"
		result.append(entry)
	return result

static func interact(state: Object, id: String, point: Vector2) -> Dictionary:
	if not state.map_events.has(id): return _result(false, false, false, "")
	var event: Dictionary = state.map_events[id]
	if bool(event.get("claimed", false)): return _result(true, false, false, "此奖励已经领取。")
	var event_point := _point(event["position"])
	var nearby := event_point.distance_to(point) <= ESCORT_NEAR if str(event["kind"]) == "escort" else Rect2(event_point - CARD_SIZE * 0.5, CARD_SIZE).has_point(point)
	if not nearby: return _result(false, false, false, "")
	match str(event["kind"]):
		"chest":
			if not state.consume_event_slap(): return _result(true, false, false, "正在蓄掌，稍后再拍宝箱。")
			return _claim(state, event, "宝箱已打开")
		"hunt":
			if str(event["status"]) == "claimable": return _claim(state, event, "剿敌任务完成")
			if str(event["status"]) == "active": return _result(true, false, false, "20秒内拍翻%s×%d，完成后回来领奖。" % [GameData.card_name(str(event["target_card"])), int(event["required"])])
			if _remaining_targets(state, event) < int(event["required"]):
				event["status"] = "expired"
				return _result(true, true, false, "未征服区域的指定目标已不足，此任务不可再接；不会重新刷敌。")
			if int(state.battle_region) != int(event["region"]) or str(state.battle_mode) != "challenge" or _live_targets(state, str(event["target_card"])) < int(event["required"]):
				return _result(true, false, false, "本轮指定目标不足，出征未征服区域后再接任务。")
			event["status"] = "active"
			event["remaining"] = HUNT_SECONDS
			event["kills"] = 0
			return _result(true, true, false, "已接取：20秒内拍翻%s×%d。" % [GameData.card_name(str(event["target_card"])), int(event["required"])])
		"exchange":
			var card: Dictionary = event["card_cost"]
			var item: Dictionary = event["item_cost"]
			if free_card_count(state, str(card["id"])) < int(card["amount"]) or int(state.items.get(str(item["id"]), 0)) < int(item["amount"]):
				return _result(true, false, false, "需要自由库存%s×%d、%s×%d；不足时不消耗，上阵与附着卡受保护。" % [GameData.card_name(str(card["id"])), int(card["amount"]), _item_name(str(item["id"])), int(item["amount"])])
			state.owned[str(card["id"])] = int(state.owned[str(card["id"])]) - int(card["amount"])
			if int(state.owned[str(card["id"])]) == 0: state.owned.erase(str(card["id"]))
			state.items[str(item["id"])] = int(state.items[str(item["id"])]) - int(item["amount"])
			return _claim(state, event, "兑换完成")
		"escort":
			var current := _point(event["position"])
			if current.distance_to(point) > ESCORT_NEAR: return _result(false, false, false, "")
			if not state.consume_event_slap(): return _result(true, false, false, "正在蓄掌，稍后再推。")
			var target := _point(event["target"])
			var direction := (target - current).normalized() if current.distance_to(point) < 14.0 else (current - point).normalized()
			var next := current + direction * ESCORT_STEP
			var bounds: Rect2 = state.zone_rect(int(event["region"]), int(event["zone"])).grow(-70)
			next = next.clamp(bounds.position, bounds.end)
			event["position"] = [next.x, next.y]
			event["status"] = "active"
			if next.distance_to(target) <= ESCORT_GOAL:
				event["position"] = [target.x, target.y]
				return _claim(state, event, "军需官已安全送达")
			return _result(true, true, false, "护送中：拍本体沿箭头前进，拍侧边把他推向另一侧。")
	return _result(false, false, false, "")

static func on_enemy_killed(state: Object, card_id: String) -> bool:
	if str(state.battle_mode) != "challenge": return false
	var changed := false
	for event in state.map_events.values():
		if str(event.get("kind", "")) != "hunt" or str(event.get("status", "")) != "active": continue
		if int(event["region"]) != int(state.battle_region) or str(event["target_card"]) != card_id: continue
		if float(event.get("remaining", 0)) <= 0.0: continue
		event["kills"] = mini(int(event["required"]), int(event.get("kills", 0)) + 1)
		if int(event["kills"]) >= int(event["required"]): event["status"] = "claimable"
		changed = true
	return changed

static func advance(state: Object, delta: float) -> bool:
	if delta <= 0.0: return false
	var changed := false
	for event in state.map_events.values():
		if str(event.get("kind", "")) != "hunt" or str(event.get("status", "")) != "active": continue
		event["remaining"] = maxf(0.0, float(event.get("remaining", HUNT_SECONDS)) - delta)
		if float(event["remaining"]) <= 0.0: event["status"] = "failed"
		changed = true
	return changed

static func finish_round(state: Object) -> bool:
	var changed := false
	for event in state.map_events.values():
		if str(event.get("kind", "")) == "hunt" and str(event.get("status", "")) == "active":
			event["status"] = "failed"
			event["remaining"] = 0.0
			changed = true
	return changed

static func free_card_count(state: Object, id: String) -> int:
	var reserved := 1 if state.carry.has(id) else 0
	for attachments in [state.hero_equip, state.hero_troops]:
		for cards in attachments.values():
			if (cards as Array).has(id): reserved += 1
	# 已装建筑本就从owned仓库扣出，此处不再重复减一次。
	return maxi(0, int(state.owned.get(id, 0)) - reserved)

static func _claim(state: Object, event: Dictionary, message: String) -> Dictionary:
	if bool(event.get("claimed", false)): return _result(true, false, false, "此奖励已经领取。")
	var reward: Dictionary = event["reward"]
	var amount := int(reward.get("amount", 1))
	event["claimed"] = true
	event["status"] = "done"
	match str(reward["kind"]):
		"gold": state.gold += amount
		"xp": state.gain_player_xp(amount)
		"card": state.owned[str(reward["id"])] = int(state.owned.get(str(reward["id"]), 0)) + amount
		"item": state.items[str(reward["id"])] = int(state.items.get(str(reward["id"]), 0)) + amount
	var result := _result(true, true, true, message + "：" + _reward_text(reward))
	result["reward"] = reward.duplicate(true)
	return result

static func _hunt_target(idx: int) -> String:
	var enemies: Array = GameData.enemies_by_region.get(idx, [])
	for enemy in enemies:
		var id := str(enemy["card_id"])
		if str(GameData.card(id).get("type", "")) == "士兵": return id
	return str(enemies[0]["card_id"]) if not enemies.is_empty() else "S01"

static func _remaining_targets(state: Object, event: Dictionary) -> int:
	var count := 0
	var idx := int(event["region"])
	var enemies: Array = GameData.enemies_by_region.get(idx, [])
	for zone in state.zone_details(idx):
		if bool(zone.get("cleared", false)): continue
		for slot in range(mini(int(zone.get("cards", 0)), enemies.size())):
			if str(enemies[slot]["card_id"]) == str(event["target_card"]): count += 1
	return count

static func _live_targets(state: Object, card_id: String) -> int:
	var count := 0
	for enemy in state.battle:
		if str(enemy["card_id"]) == card_id and float(enemy["hp"]) > 0.0: count += 1
	return count

static func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))

static func _item_name(id: String) -> String:
	return str(ITEM_NAMES.get(id, id))

static func _reward_text(reward: Dictionary) -> String:
	var amount := int(reward.get("amount", 1))
	match str(reward.get("kind", "")):
		"gold": return "金币 +%d" % amount
		"xp": return "玩家经验 +%d" % amount
		"card": return "%s ×%d" % [GameData.card_name(str(reward["id"])), amount]
		"item": return "%s ×%d" % [_item_name(str(reward["id"])), amount]
	return ""

static func _hunt_hint(status: String) -> String:
	match status:
		"ready": return "拍下接取 · 20秒"
		"active": return "先杀指定牌再领奖"
		"claimable": return "已达标 · 拍下领奖"
		"failed": return "失败 · 拍下重试"
		"expired": return "目标已不足 · 不可接"
		"done": return "奖励已领取"
	return ""

static func _result(handled: bool, changed: bool, completed: bool, message: String) -> Dictionary:
	return {"handled": handled, "changed": changed, "completed": completed, "message": message}
