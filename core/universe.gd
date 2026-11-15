class_name Universe
extends RefCounted

# Ephemeris & gravity field stuff, bodies are sampled from the analytic Keplerian elements

var bodies: Dictionary = {}
var order: Array[String] = []
var tables: Dictionary = {}
var t0: float = 0.0 

var _idx: Dictionary = {}
var _mus := PackedFloat64Array()
var _tpts: Array[PackedFloat64Array] = []
var _tvels: Array[PackedFloat64Array] = []
var _tdts := PackedFloat64Array()
var _orbit_cache: Dictionary = {}

const ACCEL_EPSILON := 1.0e-9

func setup(body_dict: Dictionary, duration_s: float, start_epoch_s: float = 0.0) -> void:
	bodies = body_dict
	order = _sorted_ids()
	t0 = start_epoch_s
	_idx.clear()
	_mus.clear()
	_tpts.clear()
	_tvels.clear()
	_tdts.clear()
	_orbit_cache.clear()
	for id in order:
		var b: CelestialBody = bodies[id]
		var dt: float = _table_dt(id, b)
		dt = maxf(dt, duration_s / 24000.0)
		var count: int = int(ceil(duration_s / dt)) + 2
		var pts := PackedFloat64Array()
		var vels := PackedFloat64Array()
		pts.resize(count * 2)
		vels.resize(count * 2)
		for k in range(count):
			var t: float = float(k) * dt
			var s: PackedFloat64Array = _absolute_xy(id, t)
			pts[k * 2] = s[0]
			pts[k * 2 + 1] = s[1]
			vels[k * 2] = s[2]
			vels[k * 2 + 1] = s[3]
		tables[id] = {"dt": dt, "pts": pts, "vels": vels}
		_idx[id] = _mus.size()
		_mus.append(maxf(b.mu, 0.0))
		_tpts.append(pts)
		_tvels.append(vels)
		_tdts.append(dt)

func _table_dt(id: String, b: CelestialBody) -> float:
	if id == "moon":
		return 900.0
	if id == "earth":
		return 1800.0
	if b.parent_id.is_empty():
		return 7200.0
	return 3600.0

func _sorted_ids() -> Array[String]:
	var depth := {}
	for id in bodies.keys():
		var d: int = 0
		var cur: String = str(id)
		var guard: int = 0
		while bodies.has(cur) and not (bodies[cur] as CelestialBody).parent_id.is_empty() and guard < 16:
			cur = (bodies[cur] as CelestialBody).parent_id
			d += 1
			guard += 1
		depth[id] = d
	var ids: Array[String] = []
	for id in bodies.keys():
		ids.append(str(id))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(depth[a]) < int(depth[b]))
	return ids

func _absolute_xy(id: String, t: float) -> PackedFloat64Array:
	var b: CelestialBody = bodies[id]
	var rel: PackedFloat64Array = b.relative_state_xy(t + t0)
	if b.parent_id.is_empty():
		return rel
	var p: PackedFloat64Array = _absolute_xy(b.parent_id, t)
	p[0] += rel[0]
	p[1] += rel[1]
	p[2] += rel[2]
	p[3] += rel[3]
	return p

func _sample_xy(i: int, t: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(4)
	var pts: PackedFloat64Array = _tpts[i]
	var vels: PackedFloat64Array = _tvels[i]
	if pts.is_empty():
		return out
	var dt: float = _tdts[i]
	var x: float = t / dt
	var last: int = pts.size() / 2 - 1
	if x <= 0.0:
		out[0] = pts[0]
		out[1] = pts[1]
		out[2] = vels[0]
		out[3] = vels[1]
		return out
	if x >= float(last):
		var b2: int = last * 2
		out[0] = pts[b2]
		out[1] = pts[b2 + 1]
		out[2] = vels[b2]
		out[3] = vels[b2 + 1]
		return out
	var k: int = int(x)
	var s: float = x - float(k)
	var s2: float = s * s
	var s3: float = s2 * s
	var h00: float = 2.0 * s3 - 3.0 * s2 + 1.0
	var h10: float = s3 - 2.0 * s2 + s
	var h01: float = -2.0 * s3 + 3.0 * s2
	var h11: float = s3 - s2
	var d00: float = 6.0 * s2 - 6.0 * s
	var d10: float = 3.0 * s2 - 4.0 * s + 1.0
	var d01: float = -6.0 * s2 + 6.0 * s
	var d11: float = 3.0 * s2 - 2.0 * s
	var k2: int = k * 2
	var x0: float = pts[k2]
	var y0: float = pts[k2 + 1]
	var x1: float = pts[k2 + 2]
	var y1: float = pts[k2 + 3]
	var vx0: float = vels[k2]
	var vy0: float = vels[k2 + 1]
	var vx1: float = vels[k2 + 2]
	var vy1: float = vels[k2 + 3]
	out[0] = x0 * h00 + vx0 * (h10 * dt) + x1 * h01 + vx1 * (h11 * dt)
	out[1] = y0 * h00 + vy0 * (h10 * dt) + y1 * h01 + vy1 * (h11 * dt)
	out[2] = (x0 * d00 + x1 * d01) / dt + vx0 * d10 + vx1 * d11
	out[3] = (y0 * d00 + y1 * d01) / dt + vy0 * d10 + vy1 * d11
	return out

func _offset(i: int, px: float, py: float, t: float) -> Vector2:
	var pts: PackedFloat64Array = _tpts[i]
	if pts.is_empty():
		return Vector2.ZERO
	var dt: float = _tdts[i]
	var x: float = t / dt
	var last: int = pts.size() / 2 - 1
	if x <= 0.0:
		return Vector2(pts[0] - px, pts[1] - py)
	if x >= float(last):
		var b2: int = last * 2
		return Vector2(pts[b2] - px, pts[b2 + 1] - py)
	var k: int = int(x)
	var s: float = x - float(k)
	var s2: float = s * s
	var s3: float = s2 * s
	var h00: float = 2.0 * s3 - 3.0 * s2 + 1.0
	var h10: float = s3 - 2.0 * s2 + s
	var h01: float = -2.0 * s3 + 3.0 * s2
	var h11: float = s3 - s2
	var k2: int = k * 2
	var vels: PackedFloat64Array = _tvels[i]
	var bx: float = pts[k2] * h00 + vels[k2] * (h10 * dt) + pts[k2 + 2] * h01 + vels[k2 + 2] * (h11 * dt)
	var by: float = pts[k2 + 1] * h00 + vels[k2 + 1] * (h10 * dt) + pts[k2 + 3] * h01 + vels[k2 + 3] * (h11 * dt)
	return Vector2(bx - px, by - py)

func pos_at(id: String, t: float) -> Vector2:
	var i: int = _idx.get(id, -1)
	if i < 0:
		return Vector2.ZERO
	var s: PackedFloat64Array = _sample_xy(i, t)
	return Vector2(s[0], s[1])

func vel_at(id: String, t: float) -> Vector2:
	var i: int = _idx.get(id, -1)
	if i < 0:
		return Vector2.ZERO
	var s: PackedFloat64Array = _sample_xy(i, t)
	return Vector2(s[2], s[3])

func body_state(id: String, t: float) -> PackedFloat64Array:
	var i: int = _idx.get(id, -1)
	if i < 0:
		var zero := PackedFloat64Array()
		zero.resize(4)
		return zero
	return _sample_xy(i, t)

func distance_to(id: String, px: float, py: float, t: float) -> float:
	var i: int = _idx.get(id, -1)
	if i < 0:
		return INF
	var d: Vector2 = _offset(i, px, py, t)
	return d.length()

func accel_xy(px: float, py: float, t: float) -> Vector2:
	var ax: float = 0.0
	var ay: float = 0.0
	var count: int = _mus.size()
	for i in range(count):
		var mu: float = _mus[i]
		if mu <= 0.0:
			continue
		var pts: PackedFloat64Array = _tpts[i]
		var n: int = pts.size()
		if n < 4:
			continue
		var vels: PackedFloat64Array = _tvels[i]
		var dt: float = _tdts[i]
		var x: float = t / dt
		var last: int = n / 2 - 1
		var bx: float = 0.0
		var by: float = 0.0
		if x <= 0.0:
			bx = pts[0]
			by = pts[1]
		elif x >= float(last):
			bx = pts[last * 2]
			by = pts[last * 2 + 1]
		else:
			var k: int = int(x)
			var s: float = x - float(k)
			var s2: float = s * s
			var s3: float = s2 * s
			var h00: float = 2.0 * s3 - 3.0 * s2 + 1.0
			var h10: float = s3 - 2.0 * s2 + s
			var h01: float = -2.0 * s3 + 3.0 * s2
			var h11: float = s3 - s2
			var k2: int = k * 2
			bx = pts[k2] * h00 + vels[k2] * (h10 * dt) + pts[k2 + 2] * h01 + vels[k2 + 2] * (h11 * dt)
			by = pts[k2 + 1] * h00 + vels[k2 + 1] * (h10 * dt) + pts[k2 + 3] * h01 + vels[k2 + 3] * (h11 * dt)
		var dx: float = bx - px
		var dy: float = by - py
		var r2: float = dx * dx + dy * dy
		if r2 < 1.0:
			continue
		if mu / r2 < ACCEL_EPSILON:
			continue
		var inv: float = mu / (r2 * sqrt(r2))
		ax += dx * inv
		ay += dy * inv
	return Vector2(ax, ay)

func body(id: String) -> CelestialBody:
	return bodies.get(id, null)

func body_radius_influence_xy(px: float, py: float, t: float) -> String:
	var best: String = ""
	var best_r: float = INF
	for i in range(_mus.size()):
		var b: CelestialBody = bodies[order[i]]
		if b.soi_m <= 0.0:
			continue
		var d: float = _offset(i, px, py, t).length()
		if d < b.soi_m and d < best_r:
			best = b.id
			best_r = d
	return best

func crash_body_xy(px: float, py: float, t: float) -> String:
	for i in range(_mus.size()):
		var b: CelestialBody = bodies[order[i]]
		if _offset(i, px, py, t).length() < b.radius_m:
			return b.id
	return ""

func relative_state_xy(id: String, px: float, py: float, vx: float, vy: float, t: float) -> Dictionary:
	var i: int = _idx.get(id, -1)
	var rx: float = px
	var ry: float = py
	var rvx: float = vx
	var rvy: float = vy
	if i >= 0:
		var s: PackedFloat64Array = _sample_xy(i, t)
		rx -= s[0]
		ry -= s[1]
		rvx -= s[2]
		rvy -= s[3]
	return {
		"pos": Vector2(rx, ry),
		"vel": Vector2(rvx, rvy),
		"dist": sqrt(rx * rx + ry * ry),
		"speed": sqrt(rvx * rvx + rvy * rvy),
		"rx": rx,
		"ry": ry,
		"rvx": rvx,
		"rvy": rvy,
	}

func relative_state(id: String, pos: Vector2, vel: Vector2, t: float) -> Dictionary:
	return relative_state_xy(id, pos.x, pos.y, vel.x, vel.y, t)

func orbit_path(id: String, samples: int = 160) -> PackedVector2Array:
	var key := "%s:%d" % [id, samples]
	var cached: Variant = _orbit_cache.get(key, null)
	if cached != null:
		return cached
	var b: CelestialBody = bodies.get(id, null)
	if b == null or not b.has_elements:
		return PackedVector2Array()
	var center := Vector2.ZERO
	if not b.parent_id.is_empty():
		center = pos_at(b.parent_id, 0.0)
	var pts := PackedVector2Array()
	for k in range(samples + 1):
		var m: float = TAU * float(k) / float(samples)
		var st: Dictionary = Ephemeris.state_from_elements(
			b.a_m, b.e, b.i_deg, rad_to_deg(m) + b.peri_deg,
			b.peri_deg, b.node_deg, b.orbit_mu())
		pts.append(center + (st["pos"] as Vector2))
	_orbit_cache[key] = pts
	return pts
