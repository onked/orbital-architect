class_name Sim
extends RefCounted

signal objective_done(id: String)
signal mission_failed(reason: String)
signal approach(body_id: String, dist: float)
signal periapsis_pass(body_id: String, dist: float)

const AU_M := 149597870700.0
const PREVIEW_BODIES := ["earth", "moon"]

var universe: Universe
var mission: MissionDef
var craft: CraftState

var t: float = 0.0 
var epoch: float = 0.0
var phase: String = "PLANNING"
var flags: Dictionary = {}
var failure: String = ""
var log_lines: Array = []
var closest_target: float = INF
var trail := PackedVector2Array()
var cost: float = 0.0
var design: Array = []

var cells: Array = []
var rots: Array = []
var hull: Array = []
var initial_fuel: float = 1.0
var burns: Array = []

var hint_penalty: float = 0.0
var hint_notes: Array = []
var _approach_flagged: bool = false
var _periapsis_flagged: bool = false
var _prev_radial: float = 0.0
var _prev_dist: float = -1.0
var _prev_prev_dist: float = -1.0
var _halt_requested: bool = false

func setup(m: MissionDef, c: CraftState, bodies: Dictionary, mission_epoch: float, design_cost: float, design_ids: Array, layout: Array = [], part_rots: Array = [], hull_cells: Array = []) -> void:
	mission = m
	craft = c
	epoch = mission_epoch
	cost = design_cost
	design = design_ids.duplicate()
	cells = layout.duplicate()
	rots = part_rots.duplicate()
	hull = hull_cells.duplicate()
	initial_fuel = maxf(c.fuel_mass, 1.0)

	universe = Universe.new()
	universe.setup(bodies, 86400.0 * maxf(m.duration_days, 1.0), mission_epoch)
	_place_in_orbit()
	trail.append(craft.pos)
	_log("Clock started. Parking orbit %s km." % str(m.start_altitude_m / 1000.0))

func _place_in_orbit() -> void:
	var body: CelestialBody = universe.body(mission.start_body)
	if body == null:
		return
	var r: float = body.radius_m + mission.start_altitude_m
	var s: PackedFloat64Array = universe.body_state(body.id, 0.0)
	craft.px = s[0] + r
	craft.py = s[1]
	craft.vx = s[2]
	craft.vy = s[3]
	if mission.start_mode != "descent":
		craft.vy += sqrt(body.mu / r)

func target() -> CelestialBody:
	return universe.body(mission.target_body)

func sun_distance() -> float:
	return sqrt(craft.px * craft.px + craft.py * craft.py)

func _step_dt() -> float:
	var target_body: CelestialBody = target()
	if target_body != null:
		var target_alt: float = universe.distance_to(
			target_body.id, craft.px, craft.py, t) - target_body.radius_m
		if target_alt < 50000.0:
			return clampf(target_alt / 1000.0, 0.2, 10.0)
	if universe.distance_to("moon", craft.px, craft.py, t) < 5.0e7:
		return 10.0
	var d: float = universe.distance_to("earth", craft.px, craft.py, t)
	if d < 5.0e7:
		return 10.0
	if d < 2.5e8:
		return 30.0
	return 60.0

func advance(dt_sim: float, budget_ms: float = 0.0) -> float:
	if phase == "DONE" or dt_sim <= 0.0:
		return 0.0
	var remaining: float = minf(dt_sim, 86400.0 * 30.0)
	_halt_requested = false
	var guard: int = 0
	var deadline: int = 0
	if budget_ms > 0.0:
		deadline = Time.get_ticks_usec() + int(budget_ms * 1000.0)
	while remaining > 0.001 and guard < 8000:
		var dt: float = minf(_step_dt(), remaining)
		Propagator.rk4_step(craft, universe, t, dt)
		t += dt
		remaining -= dt

		if (guard & 3) == 0:
			_check()
		guard += 1
		if _halt_requested:
			_halt_requested = false
			break
		if phase == "DONE":
			break
		if deadline > 0 and (guard & 31) == 0 and Time.get_ticks_usec() >= deadline:
			break
	trail.append(craft.pos)
	while trail.size() > 3000:
		trail.remove_at(0)
	return maxf(remaining, 0.0)

func skip(seconds: float) -> void:
	advance(seconds)

func _check() -> void:
	var crash: String = universe.crash_body_xy(craft.px, craft.py, t)
	if crash != "":
		if _try_landing(crash):
			return
		craft.alive = false
		phase = "DONE"
		failure = "Impacted %s" % universe.body(crash).display_name
		_log("CRITICAL: %s" % failure)
		mission_failed.emit(failure)
		return

	var target_body: CelestialBody = target()
	if target_body != null:
		var approach_rel: Dictionary = universe.relative_state_xy(
			target_body.id, craft.px, craft.py, craft.vx, craft.vy, t)
		var approach_dist: float = float(approach_rel["dist"])
		if not _approach_flagged and approach_dist < target_body.soi_or_default():
			_approach_flagged = true
			_log("SOI: %s." % target_body.display_name)
			approach.emit(target_body.id, approach_dist)
		if _approach_flagged and not _periapsis_flagged and approach_dist < target_body.soi_or_default():
			if _prev_dist >= 0.0 and _prev_prev_dist >= 0.0:
				var closing: bool = _prev_dist < _prev_prev_dist
				var opening: bool = approach_dist >= _prev_dist
				if closing and opening:
					_periapsis_flagged = true
					_log("Periapsis: %.0f km." % (approach_dist / 1000.0))
					periapsis_pass.emit(target_body.id, approach_dist)
			_prev_prev_dist = _prev_dist
			_prev_dist = approach_dist

	for raw in mission.objectives:
		var d: Dictionary = raw
		var id: String = str(d.get("id", ""))
		if id == "" or flags.has(id):
			continue
		var kind: String = str(d.get("kind", ""))
		if kind == "":
			kind = _legacy_kind(id)
		if kind == "transmit":
			continue
		if _objective_met(kind, d):
			_complete(id, str(d.get("detail", "")))
			if bool(d.get("ends", false)):
				phase = "DONE"
				_log("Complete: %s." % mission.display_name)
				return

	if sqrt(craft.px * craft.px + craft.py * craft.py) > 8.0 * AU_M:
		phase = "DONE"
		failure = "Spacecraft lost beyond the outer solar system"
		_log("CRITICAL: %s" % failure)
		mission_failed.emit(failure)

func _legacy_kind(id: String) -> String:
	match id:
		"tli":
			return "distance"
		"capture":
			return "bound"
		"science":
			return "transmit"
		_:
			return "soi"

func _try_landing(body_id: String) -> bool:
	for raw in mission.objectives:
		var d: Dictionary = raw
		if str(d.get("kind", "")) != "land":
			continue
		if str(d.get("body", "")) != body_id:
			continue
		var id: String = str(d.get("id", ""))
		if id == "" or flags.has(id):
			continue
		var rel: Dictionary = universe.relative_state_xy(
			body_id, craft.px, craft.py, craft.vx, craft.vy, t)
		var limit: float = float(d.get("value", 40.0))
		if float(rel["speed"]) > limit:
			continue
		craft.alive = true
		_complete(id, "Touchdown at %.1f m/s." % float(rel["speed"]))
		if bool(d.get("ends", false)):
			phase = "DONE"
			_log("Complete: %s." % mission.display_name)
		return true
	return false

func _objective_met(kind: String, d: Dictionary) -> bool:
	var body_id: String = str(d.get("body", mission.start_body))
	if body_id == "":
		body_id = mission.start_body
	var value: float = float(d.get("value", 0.0))
	match kind:
		"distance":
			return universe.distance_to(body_id, craft.px, craft.py, t) >= value * 1000.0
		"au":
			return sqrt(craft.px * craft.px + craft.py * craft.py) >= value * AU_M
		"escape":
			var body: CelestialBody = universe.body(body_id)
			if body == null:
				return false
			return universe.distance_to(body_id, craft.px, craft.py, t) > body.soi_or_default()
		"soi":
			var body_s: CelestialBody = universe.body(body_id)
			if body_s == null:
				return false
			return universe.distance_to(body_id, craft.px, craft.py, t) < body_s.soi_or_default()
		"bound":
			var body_b: CelestialBody = universe.body(body_id)
			if body_b == null:
				return false
			var rel: Dictionary = universe.relative_state_xy(body_id, craft.px, craft.py, craft.vx, craft.vy, t)
			var dist: float = float(rel["dist"])
			if dist >= body_b.soi_or_default():
				return false
			var energy: float = 0.5 * pow(float(rel["speed"]), 2.0) - body_b.mu / maxf(dist, 1.0)
			return energy < 0.0
		"flyby":
			return universe.distance_to(body_id, craft.px, craft.py, t) <= value * 1000.0
		"atmosphere":
			var body_a: CelestialBody = universe.body(body_id)
			if body_a == null or not craft.has_heatshield:
				return false
			var alt: float = universe.distance_to(body_id, craft.px, craft.py, t) - body_a.radius_m
			return alt <= maxf(body_a.atmosphere_top_m, 1000.0)
		_:
			return false

func _complete(id: String, detail: String = "") -> void:
	if flags.has(id):
		return
	flags[id] = true
	_log("OBJECTIVE: %s%s" % [id, (" -- " + detail) if detail != "" else ""])
	objective_done.emit(id)

func _log(line: String) -> void:
	log_lines.append("[T+%s] %s" % [format_met(t), line])
	if log_lines.size() > 200:
		log_lines.remove_at(0)

func can_afford(dv: float) -> bool:
	return craft.can_burn(dv)

func request_halt() -> void:
	_halt_requested = true

func orbit_about(body_id: String, dv: Vector2 = Vector2.ZERO) -> Dictionary:
	var body: CelestialBody = universe.body(body_id)
	if body == null:
		return {}
	var rel: Dictionary = universe.relative_state_xy(body_id, craft.px, craft.py, craft.vx, craft.vy, t)
	var pos: Vector2 = rel["pos"]
	var r: float = maxf(float(rel["dist"]), 1.0)
	var v: Vector2 = (rel["vel"] as Vector2) + dv
	var speed: float = v.length()
	var energy: float = 0.5 * speed * speed - body.mu / r
	var bound: bool = energy < 0.0
	var h: float = pos.x * v.y - pos.y * v.x
	var e: float = sqrt(maxf(1.0 + 2.0 * energy * h * h / (body.mu * body.mu), 0.0))
	var rp: float = r
	var ra: float = INF
	var period: float = 0.0
	var a: float = INF
	if bound:
		a = -body.mu / (2.0 * energy)
		rp = a * (1.0 - e)
		ra = a * (1.0 + e)
		period = TAU * sqrt(a * a * a / body.mu)
	else:
		var p: float = h * h / body.mu
		rp = p / (1.0 + e)
	var soi: float = body.soi_or_default()
	return {
		"body": body_id,
		"body_name": body.display_name,
		"mu": body.mu,
		"radius": body.radius_m,
		"soi": soi,
		"r": r,
		"speed": speed,
		"energy": energy,
		"bound": bound,
		"a": a,
		"rp": rp,
		"ra": ra,
		"alt_rp": rp - body.radius_m,
		"alt_ra": 0.0 if not bound else ra - body.radius_m,
		"period": period,
	}

func reset_periapsis_watch() -> void:
	_periapsis_flagged = false
	_prev_radial = 0.0
	_prev_dist = -1.0
	_prev_prev_dist = -1.0

func objectives_complete() -> bool:
	if mission == null:
		return false
	for raw in mission.objectives:
		var o: Dictionary = raw
		if not flags.has(str(o.get("id", ""))):
			return false
	return true

func execute_burn(dv: Vector2) -> Dictionary:
	var magnitude: float = dv.length()
	if magnitude <= 0.0:
		return {"ok": false, "reason": "Burn magnitude is zero"}
	if not craft.can_burn(magnitude):
		return {"ok": false, "reason": "Not enough propellant for %.0f m/s" % magnitude}
	var fuel_before: float = craft.fuel_mass
	craft.burn(magnitude)
	craft.vx += dv.x
	craft.vy += dv.y
	burns.append({"t": t, "dv": dv, "met": t, "fuel": fuel_before - craft.fuel_mass})
	_log("Burn %.0f m/s, %.0f kg." % [magnitude, fuel_before - craft.fuel_mass])
	return {"ok": true, "reason": "Burn complete"}

func transmit_science() -> Dictionary:
	if not craft.has_science():
		return {"ok": false, "reason": "No science payload installed"}
	var target_body: CelestialBody = target()
	if target_body == null:
		return {"ok": false, "reason": "No target defined"}
	var rel: Dictionary = universe.relative_state_xy(target_body.id, craft.px, craft.py, craft.vx, craft.vy, t)
	if float(rel["dist"]) > mission.science_range_m:
		return {"ok": false, "reason": "Target out of range (%.0f km)" % (float(rel["dist"]) / 1000.0)}
	if craft.power_available(sun_distance()) < 0.0:
		return {"ok": false, "reason": "Insufficient electrical power"}
	if flags.has("science"):
		return {"ok": true, "reason": "Relay already active"}
	craft.intel_collected += 1
	_complete("science", "Science packet received by the Deep Space Network.")
	return {"ok": true, "reason": "Packet received"}

func _preview_dt_at(px: float, py: float, at_t: float) -> float:
	var dt: float = 1800.0
	for id in PREVIEW_BODIES:
		var b: CelestialBody = universe.body(id)
		if b == null or b.mu <= 0.0:
			continue
		var r: float = universe.distance_to(id, px, py, at_t)
		if r <= 1.0:
			continue
		var scale: float = sqrt(r * r * r / b.mu) * 0.02
		dt = minf(dt, clampf(scale, 20.0, 1800.0))
	return dt

func _bound_period(px: float, py: float, vx: float, vy: float, at_t: float) -> float:
	var primary: String = universe.body_radius_influence_xy(px, py, at_t)
	if primary == "":
		return 0.0
	var b: CelestialBody = universe.body(primary)
	if b == null or b.mu <= 0.0:
		return 0.0
	var st: Dictionary = universe.relative_state_xy(primary, px, py, vx, vy, at_t)
	var r: float = maxf(float(st["dist"]), b.radius_m)
	var speed: float = float(st["speed"])
	var eps: float = 0.5 * speed * speed - b.mu / r
	if eps >= 0.0:
		return 0.0
	var a: float = -b.mu / (2.0 * eps)
	return TAU * sqrt(a * a * a / b.mu)
func predict(days: float, burn: Vector2 = Vector2.ZERO, sample_s: float = 3600.0, coarse: bool = false) -> PackedVector2Array:
	var ghost: CraftState = craft.clone()
	if burn.length() > 0.0:
		if not ghost.burn(burn.length()):
			return PackedVector2Array()
		ghost.vx += burn.x
		ghost.vy += burn.y
	var target_span: float = days * 86400.0
	var sample_step: float = sample_s
	if coarse:
		var period: float = _bound_period(ghost.px, ghost.py, ghost.vx, ghost.vy, t)
		if period > 0.0 and period < target_span:
			target_span = period
			sample_step = period / 160.0
	var pts := PackedVector2Array()
	pts.append(ghost.pos)
	var t2: float = t
	var dt: float = _preview_dt_at(ghost.px, ghost.py, t2) if coarse else _step_dt()
	var elapsed: float = 0.0
	var accumulator: float = 0.0
	var steps: int = 0
	var since_check: int = 0
	while elapsed < target_span and steps < 80000:
		Propagator.rk4_step(ghost, universe, t2, dt)
		t2 += dt
		elapsed += dt
		accumulator += dt
		steps += 1
		since_check += 1
		if coarse and since_check >= 4:
			since_check = 0
			dt = minf(_preview_dt_at(ghost.px, ghost.py, t2), dt * 2.0)
		if accumulator >= sample_step:
			accumulator = 0.0
			pts.append(ghost.pos)
		if (not coarse or (steps & 7) == 0) and universe.crash_body_xy(ghost.px, ghost.py, t2) != "":
			pts.append(ghost.pos)
			break
		if sqrt(ghost.px * ghost.px + ghost.py * ghost.py) > 8.0 * AU_M:
			break
	return pts
func predict_preview(days: float, burn: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return predict(days, burn, 3600.0, true)

func _encounter_dt_at(px: float, py: float, at_t: float) -> float:
	var dt: float = 1800.0
	for id in universe.order:
		var b: CelestialBody = universe.body(id)
		if b == null or b.mu <= 0.0:
			continue
		var r: float = universe.distance_to(id, px, py, at_t)
		if r <= 1.0:
			continue
		var scale: float = sqrt(r * r * r / b.mu) * 0.03
		dt = minf(dt, clampf(scale, 10.0, 43200.0))
	return dt

func encounters(days: float, burn: Vector2 = Vector2.ZERO, max_count: int = 4,
		only_body: String = "") -> Array:
	if craft == null:
		return []
	var ghost: CraftState = craft.clone()
	if burn.length() > 0.0:
		if not ghost.burn(burn.length()):
			return []
		ghost.vx += burn.x
		ghost.vy += burn.y
	var span: float = maxf(days, 1.0) * 86400.0
	var best: Dictionary = {}
	var t2: float = t
	var elapsed: float = 0.0
	var dt: float = _encounter_dt_at(ghost.px, ghost.py, t2)
	var steps: int = 0
	while elapsed < span and steps < 8000:
		Propagator.rk4_step(ghost, universe, t2, dt)
		t2 += dt
		elapsed += dt
		steps += 1
		for id in universe.order:
			if only_body != "" and id != only_body:
				continue
			if id == "sun" or id == mission.start_body:
				continue
			var b: CelestialBody = universe.body(id)
			if b == null or b.mu <= 0.0 or b.soi_m <= 0.0:
				continue
			var dist: float = universe.distance_to(id, ghost.px, ghost.py, t2)
			var rec: Dictionary = best.get(id, {})
			if rec.is_empty() or dist < float(rec["dist"]):
				var st: Dictionary = universe.relative_state_xy(id, ghost.px, ghost.py, ghost.vx, ghost.vy, t2)
				best[id] = {"id": id, "t": t2, "dist": dist, "speed": float(st["speed"]), "soi": b.soi_or_default()}
		if (steps & 7) == 0 and universe.crash_body_xy(ghost.px, ghost.py, t2) != "":
			break
		dt = minf(_encounter_dt_at(ghost.px, ghost.py, t2), dt * 1.5)
	var out: Array = []
	for id in best.keys():
		var e: Dictionary = best[id]
		var limit: float = maxf(float(e["soi"]) * 2.5, 1.0e8)
		if float(e["t"]) > t + 3600.0 and float(e["dist"]) <= limit:
			out.append(e)
	out.sort_custom(func(a, b) -> bool: return float(a["t"]) < float(b["t"]))
	if out.size() > max_count:
		out = out.slice(0, max_count)
	return out

func snapshot() -> Dictionary:
	var trail_rows: Array = []
	for i in range(maxi(trail.size() - 600, 0), trail.size()):
		trail_rows.append([trail[i].x, trail[i].y])
	return {
		"t": t,
		"phase": phase,
		"flags": flags.duplicate(),
		"failure": failure,
		"log": log_lines.slice(maxi(log_lines.size() - 60, 0)),
		"closest": closest_target if is_finite(closest_target) else 0.0,
		"cost": cost,
		"fuel": craft.fuel_mass,
		"fuel_used": craft.fuel_used,
		"intel": craft.intel_collected,
		"alive": craft.alive,
		"px": craft.px,
		"py": craft.py,
		"vx": craft.vx,
		"vy": craft.vy,
		"trail": trail_rows,
		"burns": burns.duplicate(true),
		"hint_penalty": hint_penalty,
		"hint_notes": hint_notes.duplicate(),
		"approach": _approach_flagged,
		"periapsis": _periapsis_flagged,
		"prev_radial": _prev_radial,
		"prev_dist": _prev_dist,
		"prev_prev_dist": _prev_prev_dist,
	}

func restore(d: Dictionary) -> void:
	if d.is_empty() or craft == null:
		return
	t = float(d.get("t", 0.0))
	phase = str(d.get("phase", "PLANNING"))
	var stored_flags: Variant = d.get("flags", {})
	if stored_flags is Dictionary:
		flags = (stored_flags as Dictionary).duplicate()
	failure = str(d.get("failure", ""))
	var stored_log: Variant = d.get("log", [])
	if stored_log is Array:
		log_lines = (stored_log as Array).duplicate()
	closest_target = float(d.get("closest", 0.0))
	if closest_target <= 0.0:
		closest_target = INF
	cost = float(d.get("cost", cost))
	craft.fuel_mass = float(d.get("fuel", craft.fuel_mass))
	craft.fuel_used = float(d.get("fuel_used", 0.0))
	craft.intel_collected = int(d.get("intel", 0))
	craft.alive = bool(d.get("alive", true))
	craft.px = float(d.get("px", craft.px))
	craft.py = float(d.get("py", craft.py))
	craft.vx = float(d.get("vx", craft.vx))
	craft.vy = float(d.get("vy", craft.vy))
	trail.clear()
	var stored_trail: Variant = d.get("trail", [])
	if stored_trail is Array:
		for raw in (stored_trail as Array):
			if raw is Array and (raw as Array).size() >= 2:
				trail.append(Vector2(float(raw[0]), float(raw[1])))
	if trail.is_empty():
		trail.append(craft.pos)
	var stored_burns: Variant = d.get("burns", [])
	if stored_burns is Array:
		burns = (stored_burns as Array).duplicate(true)
	_approach_flagged = bool(d.get("approach", false))
	_periapsis_flagged = bool(d.get("periapsis", false))
	_prev_radial = float(d.get("prev_radial", 0.0))
	hint_penalty = float(d.get("hint_penalty", 0.0))
	var stored_hints: Variant = d.get("hint_notes", [])
	if stored_hints is Array:
		hint_notes = (stored_hints as Array).duplicate()
	_prev_dist = float(d.get("prev_dist", -1.0))
	_prev_prev_dist = float(d.get("prev_prev_dist", -1.0))

func report(success: bool) -> Dictionary:
	var rows: Array = []
	var earned: float = 0.0
	for raw in mission.objectives:
		var o: Dictionary = raw
		var oid := str(o.get("id", ""))
		var done: bool = flags.has(oid)
		var pts := float(o.get("points", 0))
		if done:
			earned += pts
		rows.append({
			"id": oid,
			"label": str(o.get("label", oid)),
			"detail": str(o.get("detail", "")),
			"done": done,
			"points": pts,
		})

	var weights: Dictionary = mission.score_weights
	var budget_weight := float(weights.get("budget_surplus", 15))
	var fuel_weight := float(weights.get("fuel_efficiency", 10))

	var spent_ratio := clampf(cost / maxf(mission.budget_usd, 1.0), 0.0, 1.0)
	var budget_points := (1.0 - spent_ratio) * budget_weight

	var fuel_ratio := clampf(craft.fuel_mass / maxf(initial_fuel, 1.0), 0.0, 1.0)
	var fuel_points := fuel_ratio * fuel_weight

	return {
		"mission_id": mission.id,
		"mission_name": mission.display_name,
		"target_body": mission.target_body,
		"success": success and failure == "",
		"failure": failure,
		"objectives": rows,
		"objective_points": earned,
		"budget_points": budget_points,
		"fuel_points": fuel_points,
		"total": maxf(earned + budget_points + fuel_points - hint_penalty, 0.0),
		"hint_penalty": hint_penalty,
		"cost": cost,
		"budget": mission.budget_usd,
		"fuel_left": craft.fuel_mass,
		"fuel_used": maxf(initial_fuel - craft.fuel_mass, 0.0),
		"fuel_start": initial_fuel,
		"burns": burns.size(),
		"met": t,
		"closest_target": closest_target,
	}

static func format_met(seconds: float) -> String:
	var s: int = int(maxf(seconds, 0.0))
	var d: int = int(float(s) / 86400.0)
	var h: int = int(float(s % 86400) / 3600.0)
	var m: int = int(float(s % 3600) / 60.0)
	if d > 0:
		return "%dd %02dh %02dm" % [d, h, m]
	return "%02dh %02dm" % [h, m]
