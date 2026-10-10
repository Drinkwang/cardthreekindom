extends RefCounted
## 同一份安全布局供后端牌位与前端世界尺寸使用。
const BASE_SIZE := Vector2(2400, 1500)
const ROTATED_CARD_BOUNDS := Vector2(130, 164)
const CLEAR_GAP := 30.0

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
