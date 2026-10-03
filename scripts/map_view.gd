class_name PaanMapView
extends Control
## 荆州舆图 —— 全屏覆盖层里的策略地图。
##
## 当前是"纯代码几何版"（下一版换 AI 地形底图，只要把 _draw_backdrop() 换掉即可）：
##   ① 底纹：淡淡的经纬网格
##   ② 长江 / 汉水：两条河就是"荆州"两个字
##   ③ 郡域团：同一个郡的节点叠低透明度圆，形成有边缘的领土斑块
##   ④ 相邻连线：已通行的实线、没打通的虚线
##   ⑤ 区域节点：已克服 / 可挑战 / 未解锁 三态，颜色跟着路线走
##   ⑥ 当前这一桌：脉冲高亮圈
##
## 坐标来自 data/regions.json 的 mx / my（由真实经纬度等距折算），
## 布局时跑一次「松弛」把太近的节点推开 —— 樊城和襄阳在真实地理上几乎重合，不推会叠在一起。

signal region_chosen(idx: int)

const NODE_R := 16.0
const MIN_GAP := 46.0
const PAD := 40.0
const RELAX_ITERS := 320

const KM_PER_LAT := 111.0
const KM_PER_LON := 111.0 * 0.872          # 北纬 29° 附近，1° 经度的实际长度

const COL_CLEARED := Color(0.22, 0.50, 0.29)
const COL_AVAILABLE := Color(0.72, 0.46, 0.05)
const COL_LOCKED := Color(0.46, 0.43, 0.39)
const COL_START := Color(0.48, 0.40, 0.28)
const COL_RIVER := Color(0.26, 0.42, 0.56, 0.34)
const COL_GRID := Color(0.32, 0.26, 0.19, 0.10)
# S5：底图换成泛黄旧地图后，字必须由浅转深（原来是白字，落在纸上会看不见）
const COL_TEXT := Color(0.15, 0.12, 0.09)
const COL_TEXT_DIM := Color(0.40, 0.34, 0.27)
# 描边色也跟着反转：原来是深色垫在白字后面，现在是纸色垫在墨字后面
const COL_HALO := Color(0.94, 0.91, 0.82, 0.90)

## S5：老式印刷折页地图底图（没有就退回原来的纯几何版）
const BG_DIR := "res://assets/bg/"
const BACKDROP_ALPHA := 0.60

const ROUTE_COLOR := {
	"魏线": Color(0.42, 0.60, 0.90),
	"蜀线": Color(0.90, 0.44, 0.40),
	"吴线": Color(0.36, 0.78, 0.64),
	"群雄线": Color(0.90, 0.72, 0.36),
	"通用": Color(0.62, 0.62, 0.62),
	"起点": Color(0.62, 0.62, 0.62),
	"现实线": Color(0.72, 0.52, 0.88),
}

# 河流用「经过哪些区域」来表示（几何版权宜做法，换底图后删掉）
const RIVERS := [
	["夷陵", "当阳", "江陵", "公安", "夏口", "武昌"],   # 长江
	["襄阳", "宜城", "夏口"],                            # 汉水
]

var hover_idx := -1
var selected_idx := -1

var _pts: Dictionary = {}          # idx -> Vector2（本控件局部像素坐标）
var _font: Font
var _pulse := 0.0
var _fs_scale := 1.0
var _backdrop: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	var p := BG_DIR + "map.png"
	if ResourceLoader.exists(p):
		_backdrop = load(p) as Texture2D
	resized.connect(_recompute)
	_recompute()
	set_process(true)


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 1.7, TAU)
	queue_redraw()


# =====================================================================
# 布局：真实经纬度 -> 像素，再跑松弛把重叠节点推开
# =====================================================================
func _recompute() -> void:
	_pts.clear()
	if GameData.regions.is_empty() or size.x < 80.0 or size.y < 80.0:
		return

	var lo0 := 1e9
	var lo1 := -1e9
	var la0 := 1e9
	var la1 := -1e9
	for r in GameData.regions:
		var lo := float(r.get("lon", 0.0))
		var la := float(r.get("lat", 0.0))
		lo0 = minf(lo0, lo)
		lo1 = maxf(lo1, lo)
		la0 = minf(la0, la)
		la1 = maxf(la1, la)

	# 先算出"等距平面"的矩形，再等比缩放到控件里 —— 保持荆州真实的南北长、东西窄
	var w_km := (lo1 - lo0) * KM_PER_LON
	var h_km := (la1 - la0) * KM_PER_LAT
	var avail := Vector2(maxf(60.0, size.x - PAD * 2.0), maxf(60.0, size.y - PAD * 2.0))
	var s := minf(avail.x / maxf(1.0, w_km), avail.y / maxf(1.0, h_km))
	var map_size := Vector2(w_km * s, h_km * s)
	var org := (size - map_size) * 0.5

	# 字号跟着地图大小走，窗口小了也不会糊成一团
	_fs_scale = clampf(map_size.y / 620.0, 0.72, 1.25)

	var arr: Array = []
	var idxs: Array = []
	for r in GameData.regions:
		idxs.append(int(r["idx"]))
		arr.append(org + Vector2(float(r.get("mx", 0.5)), float(r.get("my", 0.5))) * map_size)

	_relax(arr, map_size, org)

	for k in range(idxs.size()):
		_pts[int(idxs[k])] = arr[k]


func _relax(arr: Array, map_size: Vector2, org: Vector2) -> void:
	# 简单的斥力松弛：太近的两个节点互相推开，最后夹回图内。
	# 会让节点稍微偏离真实位置，但地图能看清 —— 策略地图都这么做。
	for _it in range(RELAX_ITERS):
		for a in range(arr.size()):
			for b in range(a + 1, arr.size()):
				var pa: Vector2 = arr[a]
				var pb: Vector2 = arr[b]
				var d := pb - pa
				var l := d.length()
				if l < 0.001:
					d = Vector2(1.0, 0.0).rotated(float(a * 37 + b * 71) * 0.017)
					l = 1.0
				if l < MIN_GAP:
					var push := (MIN_GAP - l) * 0.5
					var dir := d / l
					arr[a] = pa - dir * push
					arr[b] = pb + dir * push
		for i in range(arr.size()):
			var p: Vector2 = arr[i]
			arr[i] = Vector2(
				clampf(p.x, org.x, org.x + map_size.x),
				clampf(p.y, org.y, org.y + map_size.y))


func _map_rect() -> Rect2:
	if _pts.is_empty():
		return Rect2(Vector2.ZERO, size)
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for k in _pts.keys():
		mn = mn.min(_pts[k])
		mx = mx.max(_pts[k])
	return Rect2(mn, mx - mn)


# =====================================================================
# 绘制
# =====================================================================
func _draw() -> void:
	_draw_backdrop()
	if _pts.is_empty():
		return
	_draw_grid()
	_draw_county_blobs()
	_draw_rivers()
	_draw_edges()
	_draw_nodes()
	_draw_tooltip()


## S5：老式印刷折页地图底图。语义层（郡域团 / 河流 / 节点）仍画在它上面，
## 底图只负责"这张图是印出来的"。
## ⚠️ 必须按 cover 等比铺满：舆图区是**竖长**的一块（约 590×690），
##    而底图是 1280×800 的横图，直接 draw_texture_rect(Rect2(0,0,size)) 会被横向压扁。
func _draw_backdrop() -> void:
	if _backdrop == null:
		return
	var ts := Vector2(float(_backdrop.get_width()), float(_backdrop.get_height()))
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var s := maxf(size.x / ts.x, size.y / ts.y)
	var d := ts * s
	var r := Rect2((size - d) * 0.5, d)
	draw_texture_rect(_backdrop, r, false, Color(1, 1, 1, BACKDROP_ALPHA))


func _draw_grid() -> void:
	var step := 56.0
	var x := PAD
	while x < size.x - PAD:
		draw_line(Vector2(x, PAD), Vector2(x, size.y - PAD), COL_GRID, 1.0)
		x += step
	var y := PAD
	while y < size.y - PAD:
		draw_line(Vector2(PAD, y), Vector2(size.x - PAD, y), COL_GRID, 1.0)
		y += step


func _draw_county_blobs() -> void:
	# 同郡的节点各画一个低透明度大圆，叠加处更深 —— 自然形成有边缘的领土斑块
	var r := 74.0 * _fs_scale
	for r0 in GameData.regions:
		var idx := int(r0["idx"])
		if not _pts.has(idx):
			continue
		var col: Color = ROUTE_COLOR.get(str(r0.get("route", "通用")), Color.GRAY)
		var c := col
		c.a = 0.055
		draw_circle(_pts[idx], r, c)
	for r0 in GameData.regions:
		var idx := int(r0["idx"])
		if not _pts.has(idx):
			continue
		var col: Color = ROUTE_COLOR.get(str(r0.get("route", "通用")), Color.GRAY)
		var c := col
		c.a = 0.045
		draw_circle(_pts[idx], r * 1.7, c)


func _draw_rivers() -> void:
	for path in RIVERS:
		var pts := PackedVector2Array()
		for nm in path:
			var idx := _idx_of(str(nm))
			if idx > 0 and _pts.has(idx):
				pts.append(_pts[idx])
		if pts.size() < 2:
			continue
		draw_polyline(pts, COL_RIVER, 9.0 * _fs_scale, true)
		var bright := COL_RIVER
		bright.a = 0.30
		draw_polyline(pts, bright, 3.0 * _fs_scale, true)


func _draw_edges() -> void:
	for r0 in GameData.regions:
		var a := int(r0["idx"])
		if not _pts.has(a):
			continue
		for n in r0.get("unlocks", []):
			var b := int(n)
			if not _pts.has(b):
				continue
			var open_a := GameState.region_status(a) != "locked"
			var open_b := GameState.region_status(b) != "locked"
			if open_a and open_b:
				draw_line(_pts[a], _pts[b], Color(0.85, 0.82, 0.62, 0.42), 2.0)
			else:
				_dashed(_pts[a], _pts[b], Color(0.55, 0.55, 0.60, 0.22), 1.0)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var total := a.distance_to(b)
	var seg := 7.0
	var gap := 7.0
	var t := 0.0
	while t < total:
		var t2: float = minf(t + seg, total)
		draw_line(a.lerp(b, t / total), a.lerp(b, t2 / total), col, w)
		t = t2 + gap


func _draw_nodes() -> void:
	var cur := GameState.battle_region if GameState.in_battle else -1
	for r0 in GameData.regions:
		var idx := int(r0["idx"])
		if not _pts.has(idx):
			continue
		var p: Vector2 = _pts[idx]
		var status := GameState.region_status(idx)
		var route := str(r0.get("route", "通用"))
		var accent: Color = ROUTE_COLOR.get(route, Color(0.62, 0.62, 0.62))

		# 当前这一桌：脉冲圈
		if idx == cur:
			var pr := NODE_R + 8.0 + sin(_pulse) * 5.0
			draw_arc(p, pr, 0.0, TAU, 48, Color(1.0, 0.94, 0.62, 0.75), 2.5, true)
			draw_circle(p, pr + 5.0, Color(1.0, 0.92, 0.55, 0.07))

		# 已选中的
		if idx == selected_idx:
			draw_arc(p, NODE_R + 5.0, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.0, true)

		# 悬停变大的外圈
		var rr := NODE_R
		if idx == hover_idx:
			rr = NODE_R + 2.5
			draw_circle(p, rr + 6.0, Color(1, 1, 1, 0.10))

		var fill := COL_LOCKED
		var border := Color(0.42, 0.43, 0.47)
		match status:
			"cleared":
				fill = COL_CLEARED
				border = Color(0.16, 0.42, 0.26)
			"available":
				fill = accent
				border = Color(0.98, 0.95, 0.88, 0.92)
			_:
				fill = COL_LOCKED
				border = Color(0.40, 0.41, 0.45)
		# v1.0：新野不再是"免打的起点"。未克服时按普通区域着色（要能一眼看出它是待打的敌人），
		# 克服之后才换回起点的专属颜色。
		if idx == GameState.START_REGION and status == "cleared":
			fill = COL_START
			border = Color(0.45, 0.36, 0.22)

		draw_circle(p, rr, fill)
		draw_arc(p, rr, 0.0, TAU, 40, border, 2.0, true)

		# 序号
		var num := str(idx)
		var fnum := int(round(13.0 * _fs_scale))
		_text_centered(num, p + Vector2(0, fnum * 0.36), fnum, Color(0.08, 0.09, 0.10))

		# 名字（带描边，压在底纹上也看得清）
		var fname := int(round(11.5 * _fs_scale))
		var npos := p + Vector2(0, rr + fname + 3.0)
		var ncol := COL_TEXT if status != "locked" else COL_TEXT_DIM
		_text_outlined(str(r0.get("name", "?")), npos, fname, ncol)

		# 已克服打勾（v1.0：新野克服后同样打勾）
		if status == "cleared":
			_text_centered("✓", p + Vector2(rr - 4.0, -rr + 6.0), int(round(11.0 * _fs_scale)),
				Color(0.95, 1.0, 0.95))


func _draw_tooltip() -> void:
	var idx := hover_idx if hover_idx > 0 else selected_idx
	if idx <= 0 or not _pts.has(idx):
		return
	var r0 := GameData.region(idx)
	if r0.is_empty():
		return
	var p: Vector2 = _pts[idx]
	var lines := [
		"%s　[%s]" % [r0.get("name", "?"), r0.get("route", "")],
		"%s · %s" % [r0.get("county", ""), r0.get("difficulty", "")],
	]
	var status := GameState.region_status(idx)
	# v1.0：新野已经是真关卡，不再走"起点序章 · 桌上无牌"这条特殊分支，按正常状态显示。
	if status == "cleared":
		lines.append("已克服 · 建筑槽位 %d" % GameState.city_slots(idx))
	elif status == "available":
		lines.append("可挑战 · 守军 %d　总血量 %s" % [
			int(r0.get("enemy_count", 0)), GameState.fmt(float(r0.get("total_hp", 0)))])
	else:
		lines.append("未解锁 · 先打通相邻区域")

	var fs := int(round(12.0 * _fs_scale))
	var w := 0.0
	for l in lines:
		w = maxf(w, _font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var pad := 9.0
	var box := Vector2(w + pad * 2.0, float(lines.size()) * (fs + 6.0) + pad * 2.0)
	var at := p + Vector2(NODE_R + 10.0, -box.y * 0.5)
	at.x = clampf(at.x, PAD, size.x - PAD - box.x)
	at.y = clampf(at.y, PAD, size.y - PAD - box.y)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.95, 0.87, 0.97)
	sb.border_color = Color(0.42, 0.32, 0.18, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	draw_style_box(sb, Rect2(at, box))

	for i in range(lines.size()):
		var col := COL_TEXT if i == 0 else COL_TEXT_DIM
		draw_string(_font, at + Vector2(pad, pad + float(i + 1) * (fs + 6.0) - 5.0),
			str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# =====================================================================
# 文字小工具
# =====================================================================
func _text_centered(t: String, center: Vector2, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, center - Vector2(w * 0.5, 0.0), t,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_outlined(t: String, center: Vector2, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := center - Vector2(w * 0.5, 0.0)
	for ox in [-1.0, 1.0]:
		for oy in [-1.0, 1.0]:
			draw_string(_font, p + Vector2(ox, oy), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_HALO)
	draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _idx_of(nm: String) -> int:
	for r in GameData.regions:
		if str(r.get("name", "")) == nm:
			return int(r["idx"])
	return -1


# =====================================================================
# 交互
# =====================================================================
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var h := _hit(mm.position)
		if h != hover_idx:
			hover_idx = h
			queue_redraw()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var h := _hit(mb.position)
			if h > 0:
				selected_idx = h
				queue_redraw()
				region_chosen.emit(h)
		return


func _hit(p: Vector2) -> int:
	var best := -1
	var bd := NODE_R + 10.0
	for k in _pts.keys():
		var d: float = p.distance_to(_pts[k])
		if d < bd:
			bd = d
			best = int(k)
	return best


func select(idx: int) -> void:
	selected_idx = idx
	queue_redraw()
