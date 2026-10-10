from pathlib import Path
import re

p = Path('scripts/autoload/game_state.gd')
s = p.read_text(encoding='utf-8')
def function(name, body):
    global s
    pattern = r'^func ' + re.escape(name) + r'\([^\n]*\n[\s\S]*?(?=^func |\Z)'
    s, count = re.subn(pattern, lambda m: body.strip() + '\n\n\n', s, count=1, flags=re.M)
    assert count == 1, name

s = s.replace('const PACK_PRICE_GROWTH := 2.4', 'const PACK_PRICE_GROWTH := 1.05\nconst Progression = preload("res://scripts/progression_rules.gd")')
s = s.replace('"cost": 12, "growth": 1.15', '"cost": 18, "growth": 1.20')
s = s.replace('"factor": 1.15', '"factor": 1.12')
s = s.replace('"cost": 18, "growth": 1.16', '"cost": 18, "growth": 1.20')
s = s.replace('拍力 ×1.15/级', '拍力 ×1.12/级').replace('每次出战可拍击的次数（6 → 66）', '每级多拍一次；有限耐力内翻更多牌')
s = s.replace('const UPGRADES: Array = [', '''const UPGRADES: Array = [
	{"id": "auto", "name": "自动拍", "unit": "已解锁", "kind": "add", "base": 0, "step": 1, "lv": 1,
	 "cost": 60, "growth": 1.0, "desc": "每2秒自动轻拍，伤害为手拍25%；只练已完成的桌，消耗相同耐力"},
	{"id": "auto_next", "name": "自动下一趟", "unit": "已解锁", "kind": "add", "base": 0, "step": 1, "lv": 1,
	 "cost": 120, "growth": 1.0, "desc": "练习结束休息4秒再开原桌；持续挂机及离线练习，不替你推进主线"},
	{"id": "auto_power", "name": "自动助力", "unit": "%", "kind": "add", "base": 25, "step": 5, "lv": 3,
	 "cost": 180, "growth": 2.0, "desc": "自动拍伤害25%→40%；手拍仍是冲关主力"},''')
s = s.replace('const SKILL_TREE: Array = [', '''const SKILL_TREE: Array = [
	{"id": "auto", "tier": 2, "req": ["power"]},
	{"id": "auto_next", "tier": 3, "req": ["auto"]},
	{"id": "auto_power", "tier": 3, "req": ["auto_next"]},''')
s = s.replace('var hero_lv: Dictionary = {}', 'var hero_refined: Dictionary = {}\nvar hero_lv: Dictionary = {}')
s = s.replace('var offline_report: String = ""', '''# 跨桌保留完成记号与最高伤害，敌牌剩余血量仍每次重置。
var table_wins: Dictionary = {}
var table_best: Dictionary = {}
var first_flip_reward := false
var story_seen: Array = []
var practice_runs := 0
var practice_region := 1
var practice_table := 0
var battle_table := 0
var battle_mode := "challenge"
var automation_enabled := false
var narrative_paused := false
var _auto_clock := 0.0
var _auto_rest := 0.0
var offline_report: String = ""''')
s = s.replace('\t_tick_build_effects(delta)\n\tvar income', '\tif not narrative_paused:\n\t\t_tick_build_effects(delta)\n\t\tadvance_automation(delta)\n\tvar income', 1)
s = s.replace('\thero_lv = {}\n\truns = 0', '''	hero_lv = {}
	hero_refined = {}
	table_wins = {}
	table_best = {}
	first_flip_reward = false
	story_seen = []
	practice_runs = 0
	practice_region = 1
	practice_table = 0
	battle_table = 0
	battle_mode = "challenge"
	automation_enabled = false
	narrative_paused = false
	_auto_clock = 0.0
	_auto_rest = 0.0
	runs = 0''')
function('skill_req_met', '''func skill_req_met(id: String) -> bool:
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: return false
	if id == "auto" and table_progress(1) < 2: return false
	if id in ["auto_next", "auto_power", "idle"] and not _is_cleared(1): return false
	if id == "carry" and table_progress(1) < 3: return false
	if id in ["equip", "troops"] and not _is_cleared(1): return false
	return true''')
function('skill_req_text', '''func skill_req_text(id: String) -> String:
	var miss := []
	for req in skill_reqs(id):
		if upgrade_level(str(req)) < 1: miss.append(str(up_def(str(req)).get("name", req)))
	if id == "auto" and table_progress(1) < 2: miss.append("完成新野第2桌")
	if id in ["auto_next", "auto_power", "idle", "equip", "troops"] and not _is_cleared(1): miss.append("完成新野5桌")
	if id == "carry" and table_progress(1) < 3: miss.append("完成新野第3桌")
	return "需先：" + " · ".join(miss) if not miss.is_empty() else ""''')
function('hero_level', '''func hero_level(_id: String) -> int:
	return 0 # 独立经验等级已退役。旧投资迁移时返还。''')
function('hero_lv_max', '''func hero_lv_max(_id: String) -> int:
	return 0''')
function('hero_lv_cost', '''func hero_lv_cost(_id: String) -> int:
	return 0''')
function('hero_lv_mult', '''func hero_lv_mult(id: String) -> float:
	return [1.0, 1.35, 1.8][hero_quality(id)]''')
function('buy_hero_lv', '''func buy_hero_lv(_id: String) -> bool:
	log_msg("武将不设等级，请用仓库的同名3张合成。")
	return false''')
function('city_unlocked', '''func city_unlocked() -> bool:
	return _is_cleared(START_REGION)''')
function('city_unlock_text', '''func city_unlock_text() -> String:
	return "已解锁" if city_unlocked() else "完成新野5桌开放基建 · %d/5" % table_progress(1)''')
function('start_battle', '''func start_battle(idx: int) -> bool:
	if not is_unlocked(idx) or GameData.region(idx).is_empty(): return false
	if _is_cleared(idx):
		log_msg("该城已完成；可从大本营重新练习。")
		return false
	stop_automation(false)
	battle_mode = "challenge"
	battle_table = table_progress(idx)
	return _start_table(idx)''')
function('_refresh_enemies', '''func _refresh_enemies() -> void:
	battle = []
	var raw: Array = GameData.enemies_by_region.get(battle_region, [])
	var take := raw.size()
	if battle_region == 1 and battle_table == 0: take = mini(3, take)
	var total := 0.0
	for i in range(take): total += float(raw[i]["hp"])
	var hp_total := table_hp(battle_region, battle_table)
	for i in range(take):
		var e: Dictionary = raw[i]
		var hp := hp_total * float(e["hp"]) / maxf(1.0, total)
		if battle_region == 1 and battle_table == 0: hp = [4.0, 8.0, 12.0][i]
		battle.append({"card_id": e["card_id"], "hp": hp, "hp_max": hp,
			"boss": bool(e["boss"]) and battle_table == table_count(battle_region) - 1,
			"nx": 0.5, "ny": 0.5, "rot": 0.0,
			"thunder": 0, "mark_remaining": 0.0,
			"burn_remaining": 0.0, "burn_dps": 0.0, "burn_tick": 0.0,
			"kill_rewarded": false})
	_layout_table()
	battle_gen += 1''')
s = s.replace('func attack(i: int, heavy: bool = false)', 'func attack(i: int, heavy: bool = false, automatic: bool = false)')
s = s.replace('\tvar base := click_damage()\n\tvar dmg := base', '\tvar base := click_damage() * (auto_ratio() if automatic else 1.0)\n\tif not automatic: _auto_clock = 0.0\n\tvar dmg := base', 1)
function('_on_enemy_killed', '''func _on_enemy_killed(i: int) -> void:
	var reward := float(battle[i]["hp_max"]) * Progression.KILL_PAY * fortune_mult()
	gold += reward
	run_gold += reward
	run_kills += 1
	if not first_flip_reward:
		first_flip_reward = true
		gold += 8.0
		run_gold += 8.0
		log_msg("第一张翻牌！一次性收获8金币，下一趟可以买助力。")''')
function('_clear_region', '''func _clear_region() -> void:
	if not in_battle: return
	var idx := battle_region
	var training := battle_mode == "practice"
	var hp := table_hp(idx, battle_table)
	_update_table_best()
	_pay_damage()
	var first_clear := false
	var reward := 0.0
	if not training:
		table_wins[idx] = maxi(table_progress(idx), battle_table + 1)
		reward = hp * Progression.TABLE_BONUS
		if table_progress(idx) >= table_count(idx):
			first_clear = true
			region_state[idx] = "cleared"
			reward += hp * Progression.CITY_BONUS
			_grant_affinity(idx)
			for e in battle:
				var c := GameData.card(str(e["card_id"]))
				if str(c.get("type", "")) == "武将" and bool(c.get("capturable", false)):
					if not captured.has(e["card_id"]): captured.append(e["card_id"])
			_backfill_cities()
		_grant_table_reward(idx, battle_table)
	gold += reward
	run_gold += reward
	runs += 1
	if training: practice_runs += 1
	in_battle = false
	end_reason = "cleared"
	combo = 0
	_reset_build_traits()
	_record_outcome("cleared")
	last_outcome["city_clear"] = first_clear
	last_settle = "%s · 第%d/%d桌%s　收获%s金币。%s" % [GameData.region(idx).get("name", ""), battle_table + 1, table_count(idx),
		"练习完成" if training else "已翻完", fmt(run_gold), "全城完成！进入大地图选下一城。" if first_clear else "完成记号保留，先整备再继续。"]
	last_battle_report = last_settle
	_recompute_bonus()
	_finish_automation_run()
	log_msg(last_settle)
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()''')
function('settle_run', '''func settle_run() -> void:
	if not in_battle: return
	_update_table_best()
	var stipend := _pay_damage()
	if run_damage > 0.0:
		runs += 1
		if battle_mode == "practice": practice_runs += 1
	in_battle = false
	end_reason = "settled"
	_reset_build_traits()
	_record_outcome("settled")
	battle = []
	battle_gen += 1
	combo = 0
	last_settle = "%s · 第%d/%d桌　拍翻%d张 · 有效伤害%s · 收获%s金币。最高完成%.0f%%；先升级，再挑战。" % [
		GameData.region(battle_region).get("name", ""), battle_table + 1, table_count(battle_region), run_kills,
		fmt(run_damage), fmt(run_gold), minf(100.0, 100.0 * table_best_value(battle_region, battle_table) / maxf(1.0, table_hp(battle_region, battle_table)))]
	last_battle_report = last_settle
	_finish_automation_run()
	log_msg(last_settle)
	save_game()
	map_changed.emit()
	shop_changed.emit()
	changed.emit()''')
function('_record_outcome', '''func _record_outcome(result: String) -> void:
	last_outcome = {"region": battle_region, "result": result, "gold": int(run_gold),
		"kills": run_kills, "damage": run_damage, "table": battle_table + 1, "tables": table_count(battle_region),
		"mode": battle_mode, "hp": table_hp(battle_region, battle_table), "best": table_best_value(battle_region, battle_table),
		"city_clear": battle_mode == "challenge" and _is_cleared(battle_region)}''')
function('pack_price', '''func pack_price(i: int) -> int:
	if i < 0 or i >= GameData.packs.size(): return 0
	var p: Dictionary = GameData.packs[i]
	var n := int(pack_bought.get(p.get("name", ""), 0))
	var off := clampf(float(bonus["pack_price_pct"]) + float(active_mods()["pack_pct"]), -50.0, 75.0)
	return maxi(1, int(round(float(p.get("price", 100)) * minf(1.5, 1.0 + 0.05 * n) * (1.0 - off / 100.0))))''')
s = s.replace('if county == "全境":\n\t\treturn true', 'if county == "全境":\n\t\treturn true\n\tif i == 1: return _is_cleared(5)', 1)
s = s.replace('var max_star := int(p.get("max_star", 3))', 'var max_star := mini(int(p.get("max_star", 3)), progression_star_cap())', 1)
s = s.replace('if total_packs % 10 == 0:\n\t\tvar hi := _draw_high_star(i, 4)', 'if (int(pack_bought.get(GameData.packs[i].get("name", ""), 0)) + 1) % 10 == 0:\n\t\tvar hi := _draw_high_star(i, mini(3, progression_star_cap()))', 1)
function('_draw_starter', '''func _draw_starter(count: int) -> Array:
	# 固定三种薄牌，避免抽到重复后开局强度与教程失配。
	var pool := []
	for c in GameData.cards:
		if str(c.get("type", "")) == "士兵" and int(c.get("star", 0)) == 1: pool.append(str(c["id"]))
	var out := []
	for i in range(count): out.append(pool[i % mini(3, pool.size())])
	return out''')
function('_star_candidates', '''func _star_candidates(star: int) -> Array:
	var out := []
	for id in owned.keys():
		var c := GameData.card(str(id))
		if c.get("type", "") not in ["士兵", "装备"] or int(c.get("star", 0)) != star: continue
		var held := 1 if in_carry(str(id)) or in_equipped(str(id)) or in_troops(str(id)) else 0
		for k in range(maxi(0, int(owned[id]) - held)): out.append(id)
	return out''')
s = s.replace('if star >= 6:\n\t\tlog_msg', 'if star >= progression_star_cap():\n\t\tlog_msg("当前进度最高开放★%d；武将请用同名合成。" % progression_star_cap())\n\t\treturn ""\n\tif star >= 6:\n\t\tlog_msg', 1)
s = s.replace('c.get("type", "") in ["士兵", "武将", "装备"]', 'c.get("type", "") in ["士兵", "装备"]', 1)
s = s.replace('"gold": gold, "owned": owned, "captured": captured,', '''"gold": gold, "owned": owned, "captured": captured,
		"progression_version": Progression.VERSION, "table_wins": table_wins, "table_best": table_best,
		"first_flip_reward": first_flip_reward, "story_seen": story_seen,
		"hero_refined": hero_refined, "practice_runs": practice_runs, "practice_region": practice_region,
		"practice_table": practice_table, "automation_enabled": automation_enabled,''', 1)
s = s.replace('\t_load_building_state(d)', '\t_load_progression_state(d)\n\t_load_building_state(d)', 1)
s = s.replace('\t# 局内血量不持久；有效战果', '''	if automation_enabled and upgrade_level("auto_next") > 0 and elapsed > 0.0:
		var trained := minf(elapsed, offline_cap_hours() * 3600.0)
		var gain := practice_rate() / 60.0 * trained * offline_efficiency()
		gold += gain
		practice_runs += int(trained / (stamina_max_value() * Progression.AUTO_INTERVAL + Progression.REST_SECONDS))
		offline_report += "  练习积累%s金币（估算收益，离线效率%.0f%%）" % [fmt(gain), offline_efficiency() * 100.0]
	# 局内血量不持久；有效战果''', 1)
s = s.replace('\t\tensure_table()\n\tsave_game()\n\treturn true', '\t\tif not automation_enabled: ensure_table()\n\t_auto_rest = Progression.REST_SECONDS\n\tsave_game()\n\treturn true', 1)
function('_validated_outcome', '''func _validated_outcome(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var idx := int(_outcome_number(raw, "region"))
	if GameData.region(idx).is_empty() or not is_unlocked(idx): return {}
	var result := str(raw.get("result", ""))
	if result not in ["cleared", "settled"]: return {}
	var step := clampi(int(raw.get("table", 1)), 1, table_count(idx))
	var mode := "practice" if str(raw.get("mode", "challenge")) == "practice" else "challenge"
	if result == "cleared" and mode == "challenge" and not _is_cleared(idx) and table_progress(idx) < step: return {}
	return {"region": idx, "result": result, "gold": int(_outcome_number(raw, "gold")),
		"kills": int(_outcome_number(raw, "kills")), "damage": _outcome_number(raw, "damage"),
		"table": step, "tables": table_count(idx), "mode": mode, "hp": table_hp(idx, step - 1),
		"best": table_best_value(idx, step - 1), "city_clear": bool(raw.get("city_clear", _is_cleared(idx))) and mode == "challenge"}''')
# Ensure only test scene profiles use isolated saves: the existing save_path remains untouched.
p.write_text(s, encoding='utf-8')
print('Applied progression integration')
