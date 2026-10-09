class_name FixtureIndex
extends RefCounted
## A bucket grid over fixture points in XZ (M3.5, 14 §10 errors' budget): the LightPool's
## per-frame queries (Flicker's lit area and attach tests, the observation light query)
## look only at the fixtures in the buckets a query circle touches instead of every fixture
## of the level. Pure data. Fixtures never move, so the index is built once per level and
## again only when the point set changes (a fixture registers, the light anchors move).
## `near` returns candidates in ascending index order, so callers that filter and sort
## them get exactly what a scan over every fixture would give.

## Bucket edge in metres: about one query radius (Flicker's 3 to 4 m, a 7 m fixture light).
const BUCKET := 4.0

## The largest light range of the indexed fixtures (of_anchors): the is_lit query radius.
var reach: float = 0.0

var _buckets: Dictionary = {}
var _count: int = 0


## Indexed by fixture position (Flicker's queries measure from the fixture).
static func of_fixtures(fixtures: Array[Fixture]) -> FixtureIndex:
	var pts := PackedVector3Array()
	for f in fixtures:
		pts.append(f.global_position)
	var idx := FixtureIndex.new()
	idx.build(pts)
	return idx


## Indexed by light anchor (`anchor_of`: where the pooled light hangs), with `reach` the
## largest light range (each fixture's profile range, else `default_range`).
static func of_anchors(fixtures: Array[Fixture], anchor_of: Callable, default_range: float) -> FixtureIndex:
	var pts := PackedVector3Array()
	var idx := FixtureIndex.new()
	for f in fixtures:
		pts.append(anchor_of.call(f))
		idx.reach = maxf(idx.reach, float(f.light_value(&"range", default_range)))
	idx.build(pts)
	return idx


func build(points: PackedVector3Array) -> void:
	_buckets.clear()
	_count = points.size()
	for i in points.size():
		var k := key_of(points[i])
		if not _buckets.has(k):
			_buckets[k] = PackedInt32Array()
		var list: PackedInt32Array = _buckets[k]
		list.append(i)
		_buckets[k] = list  # packed arrays copy on write


func size() -> int:
	return _count


static func key_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


## The fixtures of `fixtures` (the indexed list) that `near` returns, in index order.
func pick(fixtures: Array[Fixture], pos: Vector3, radius: float) -> Array[Fixture]:
	var out: Array[Fixture] = []
	for i in near(pos, radius):
		out.append(fixtures[i])
	return out


## Indices of the points whose bucket meets the XZ square around `pos` of half side
## `radius`, ascending. A superset of the points within `radius` in XZ; callers apply the
## exact test.
func near(pos: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := key_of(pos - Vector3(radius, 0.0, radius))
	var hi := key_of(pos + Vector3(radius, 0.0, radius))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var list: Variant = _buckets.get(Vector2i(x, z))
			if list != null:
				out.append_array(list)
	out.sort()
	return out
