extends RefCounted
## 同一份安全布局供后端牌位与前端世界尺寸使用。
const BASE_SIZE := Vector2(2400, 1500)
const ROTATED_CARD_BOUNDS := Vector2(130, 164)
const CLEAR_GAP := 30.0
const ZONE_SIZE := Vector2(1440, 1040)
const ZONE_COLUMNS := 3

static func zone_world_size(count: int) -> Vector2:
	var columns := mini(ZONE_COLUMNS, maxi(1, count))
	var rows := maxi(1, ceili(float(count) / ZONE_COLUMNS))
	return Vector2(columns, rows) * ZONE_SIZE + Vector2(500, 500)

static func zone_rects(count: int) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for zone in range(count):
		result.append(Rect2(Vector2(250, 250) + Vector2(zone % ZONE_COLUMNS, floori(float(zone) / ZONE_COLUMNS)) * ZONE_SIZE, ZONE_SIZE))
	return result

static func zone_positions(count: int, region: int, zone: int, zones: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := zone_rects(zones)[zone].grow(-80)
	var grid := grid_size(count)
	# 同区聚成可操作的小阵；相邻牌在聚拢范围内，仍留出初始间隙。
	var cell := Vector2(180, 210).min(bounds.size / Vector2(grid))
	var origin := bounds.get_center() - cell * Vector2(grid) * 0.5
	var jitter := ((cell - ROTATED_CARD_BOUNDS - Vector2.ONE * CLEAR_GAP) * 0.5).max(Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = region * 7919 + zone * 104729
	var area := zone_world_size(zones) - Vector2(500, 500)
	for i in range(count):
		var center := origin + cell * (Vector2(i % grid.x, floori(float(i) / grid.x)) + Vector2.ONE * 0.5)
		center += Vector2(rng.randf_range(-jitter.x, jitter.x), rng.randf_range(-jitter.y, jitter.y)) * 0.65
		result.append({"nx": (center.x - 250.0) / area.x, "ny": (center.y - 250.0) / area.y, "rot": rng.randf_range(-0.12, 0.12)})
	return result

static func grid_size(count: int) -> Vector2i:
	var columns := maxi(1, int(ceil(sqrt(float(count) * 2.05))))
	return Vector2i(columns, maxi(1, int(ceil(float(count) / float(columns)))))

static func world_size(count: int) -> Vector2:
	var grid := grid_size(count)
	return Vector2(maxf(BASE_SIZE.x, grid.x * 230.0 + 500.0), maxf(BASE_SIZE.y, grid.y * 270.0 + 500.0))

static func positions(count: int, region: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var grid := grid_size(count)
	var area := world_size(count) - Vector2(500, 500)
	var cell := area * 0.88 / Vector2(grid)
	# 所有旋转牌仍各自留在安全槽位；稀疏城区可有更明显的自然错位。
	var jitter := ((cell - ROTATED_CARD_BOUNDS - Vector2.ONE * CLEAR_GAP) * 0.5).max(Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = region * 7919 + count * 104729
	for i in range(count):
		var column := i % grid.x
		var row := int(floor(float(i) / float(grid.x)))
		var center := area * 0.06 + cell * (Vector2(column, row) + Vector2.ONE * 0.5)
		center.x += jitter.x * clampf(rng.randf_range(-0.8, 0.8) + sin(row * 1.9 + column * 0.7) * 0.2, -1, 1)
		center.y += jitter.y * clampf(rng.randf_range(-0.8, 0.8) + sin(column * 1.8 + row * 0.8) * 0.2, -1, 1)
		result.append({"nx": center.x / area.x, "ny": center.y / area.y, "rot": rng.randf_range(-0.12, 0.12)})
	return result
