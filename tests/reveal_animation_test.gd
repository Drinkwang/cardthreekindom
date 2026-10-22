extends Node
## 翻牌顺序、动画中全部翻开、关闭与重复打开的运行时回归。

var checks := 0
var failures := 0
var finished_count := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)


func front_count(rv: PaanReveal) -> int:
	var count := 0
	for slot in rv._slots:
		if (slot["front"] as Control).visible:
			count += 1
	return count


func _ready() -> void:
	GameState.set_process(false)
	var rv := PaanReveal.new()
	add_child(rv)
	rv.finished.connect(func(): finished_count += 1)
	rv.open("逐张翻牌", ["S01", "S02", "S03"])
	rv.set_process(false)
	await get_tree().process_frame
	check(front_count(rv) == 0, "初始全部为卡背")
	rv._advance()
	check(rv._next == 1 and rv._flipping and front_count(rv) == 0,
		"一次点击仅开始第一张翻牌，不会立刻亮完整包")
	rv._advance()
	check(rv._next == 1, "翻动期间连点不会并发翻其他卡")
	var flip: Tween = rv._flip_tween
	flip.pause()
	flip.custom_step(0.18)
	check((rv._slots[0]["wrap"] as Control).scale.x < 0.95 and front_count(rv) == 0,
		"卡背先收窄，正面尚未出现")
	flip.custom_step(0.10)
	check(front_count(rv) == 1 and rv._flipping, "第一张切换正面，其余仍为卡背")
	flip.custom_step(0.40)
	check(not rv._flipping and (rv._slots[0]["wrap"] as Control).scale.is_equal_approx(Vector2.ONE),
		"第一张翻转完成后恢复完整宽度")
	rv._advance()
	check(rv._next == 2 and front_count(rv) == 1, "下一次点击仅开始第二张")
	flip = rv._flip_tween
	flip.pause()
	flip.custom_step(0.18)
	rv._reveal_all()
	check(not flip.is_valid() and not rv._flipping and front_count(rv) == 3,
		"翻动中全部翻开会终止旧动画并亮出全部卡牌")
	for slot in rv._slots:
		check((slot["wrap"] as Control).scale.is_equal_approx(Vector2.ONE), "全部翻开的卡牌宽度正常")
	check(rv._showcase_done and not rv._showcasing, "低星卡全部翻开后直接等待收牌")

	rv.open("自动逐张", ["S01", "S02"])
	await get_tree().create_timer(1.40).timeout
	check(front_count(rv) == 1 and rv._next == 1, "不点击时也按顺序自动翻开第一张")
	await get_tree().create_timer(1.0).timeout
	check(front_count(rv) == 2 and rv._showcase_done, "自动逐张完成整包")

	rv.open("高星特写", ["S01", "E12"])
	rv.set_process(false)
	rv._advance()
	rv._flip_tween.pause()
	rv._flip_tween.custom_step(1.0)
	check(not rv._showcase_done, "尚有卡背时不会提前特写高星牌")
	rv._advance()
	rv._flip_tween.pause()
	rv._flip_tween.custom_step(1.0)
	var ring := rv.get_child(rv.get_child_count() - 1) as Panel
	var high_card := rv._slots[1]["wrap"] as Control
	check(ring != null and (ring.global_position + ring.size * 0.5).distance_to(
		high_card.get_global_transform() * (high_card.size * 0.5)) < 0.1,
		"翻牌光环以卡牌中心定位，不随收窄偏移")
	rv._after_all_revealed()
	check(front_count(rv) == 2 and rv._showcasing, "逐张完成后仍触发最高星特写")
	var showcase: Tween = rv._showcase_tween
	rv._advance()
	check(not showcase.is_valid() and not rv._showcasing and rv.visible,
		"点击可以跳过特写而保留卡牌")

	rv.open("旧特写", ["E12"])
	rv._reveal_all()
	showcase = rv._showcase_tween
	rv.open("新卡包", ["S01", "S02"])
	rv.set_process(false)
	check(not showcase.is_valid() and front_count(rv) == 0 and not rv._showcasing,
		"重复打开会终止旧特写并恢复新卡包的卡背")
	rv._advance()
	flip = rv._flip_tween
	rv._close()
	check(not flip.is_valid(), "关闭会终止未完成的翻牌")
	rv.open("淡出中重开", ["S03"])
	rv.set_process(false)
	await get_tree().create_timer(0.25).timeout
	check(rv.visible and finished_count == 0 and front_count(rv) == 0,
		"淡出期间重开不会被旧关闭回调隐藏或误发结束信号")
	rv._advance()
	rv._close()
	rv._close()
	await get_tree().create_timer(0.25).timeout
	check(not rv.visible and finished_count == 1, "动画中可直接收牌，关闭信号只发一次")
	rv.queue_free()
	print("[RevealAnimation] 检查 %d 项，失败 %d 项" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
