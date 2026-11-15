class_name WorldView
extends Control

# The entire 2D solar sysem. Uses art if it exists or procedural shapes if not

var sim: Sim = null
var focus_id: String = "earth"
var follow_craft: bool = false
var pan := Vector2.ZERO
var zoom: float = 1.5e-6
var min_zoom: float = 2.0e-12
var max_zoom: float = 1.5e-4

var path_baseline := PackedVector2Array()
var path_planned := PackedVector2Array()
var encounter_marks: Array = []
var show_orbits: bool = true
var show_trail: bool = true

var _dragging := false
var _last_touch := Vector2.ZERO
var _stars: Array = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261024
	for _i in range(240):
		_stars.append({
			"p": Vector2(rng.randf(), rng.randf()),
			"a": rng.randf_range(0.15, 0.75),
			"s": rng.randf_range(1.0, 2.0),
		})


func _process(_delta: float) -> void:
	queue_redraw()


func world_center() -> Vector2:
	if sim == null:
		return Vector2.ZERO
	if follow_craft:
		return sim.craft.pos + pan
	return sim.universe.pos_at(focus_id, sim.t) + pan


func to_screen(world: Vector2) -> Vector2:
	return (world - world_center()) * zoom + size * 0.5


func focus(body_id: String) -> void:
	focus_id = body_id
	follow_craft = false
	pan = Vector2.ZERO


func follow() -> void:
	follow_craft = true
	pan = Vector2.ZERO


func zoom_by(factor: float, anchor: Vector2 = Vector2.ZERO) -> void:
	var pivot := anchor
	if pivot == Vector2.ZERO:
		pivot = size * 0.5
	var before: Vector2 = (pivot - size * 0.5) / zoom
	zoom = clampf(zoom * factor, min_zoom, max_zoom)
	var after: Vector2 = (pivot - size * 0.5) / zoom
	pan += before - after


func fit_radius(radius_m: float) -> void:
	zoom = clampf(size.y * 0.4 / maxf(radius_m, 1.0), min_zoom, max_zoom)
	pan = Vector2.ZERO

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG_DEEP)
	_draw_stars()
	if sim == null:
		return

	if show_orbits:
		_draw_orbits()

	_draw_soi()
	_draw_paths()
	_draw_trail()
	_draw_bodies()
	_draw_craft()
	_draw_body_labels()


func _draw_stars() -> void:
	for s in _stars:
		var p: Vector2 = (s["p"] as Vector2) * size
		var a: float = s["a"]
		var dim: float = 0.45 + 0.55 * sin(Time.get_ticks_msec() * 0.0004 + p.x * 0.01)
		draw_rect(Rect2(p, Vector2(s["s"], s["s"])), Color(0.75, 0.85, 1.0, a * dim))


func _draw_orbits() -> void:
	for id in sim.universe.order:
		var body: CelestialBody = sim.universe.bodies[id]
		if not body.has_elements:
			continue
		var parent_id := body.parent_id
		if parent_id.is_empty():
			continue
		var parent_pos: Vector2 = sim.universe.pos_at(parent_id, sim.t)
		var radius_px: float = body.a_m * zoom
		if radius_px < 6.0 or radius_px > 9000.0:
			continue
		var path: PackedVector2Array = sim.universe.orbit_path(id, 128)
		var offset: Vector2 = parent_pos - sim.universe.pos_at(parent_id, 0.0)
		var pts := PackedVector2Array()
		for p in path:
			pts.append(to_screen(p + offset))
		var alpha: float = 0.30 if id == sim.mission.target_body else 0.14
		draw_polyline(pts, Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, alpha), 1.0, true)


func _draw_soi() -> void:
	var target_body: CelestialBody = sim.target()
	if target_body != null and target_body.soi_m > 0.0:
		var r: float = target_body.soi_m * zoom
		if r > 8.0 and r < 20000.0:
			draw_arc(to_screen(sim.universe.pos_at(target_body.id, sim.t)), r, 0.0, TAU, 96,
				Color(UiKit.AMBER.r, UiKit.AMBER.g, UiKit.AMBER.b, 0.16), 1.0, true)


func _draw_paths() -> void:
	if path_baseline.size() > 1:
		_draw_dotted(_clip_path(path_baseline), Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, 0.55))
	if path_planned.size() > 1:
		_draw_dotted(_clip_path(path_planned), Color(UiKit.AMBER.r, UiKit.AMBER.g, UiKit.AMBER.b, 0.95))


func _clip_path(points: PackedVector2Array) -> PackedVector2Array:
	var target: CelestialBody = sim.target() if sim != null else null
	if target == null:
		return points
	var center: Vector2 = sim.universe.pos_at(target.id, sim.t)
	var limit: float = target.radius_m * 1.01
	var out := PackedVector2Array()
	for p in points:
		if p.distance_to(center) > limit:
			out.append(p)
	return out


func _draw_dotted(points: PackedVector2Array, color: Color) -> void:
	var dash: int = 0
	for i in range(points.size() - 1):
		var a: Vector2 = to_screen(points[i])
		var b: Vector2 = to_screen(points[i + 1])
		if not _segment_visible(a, b):
			continue
		dash += 1
		if dash % 2 == 0:
			draw_line(a, b, color, 1.5, true)


func _segment_visible(a: Vector2, b: Vector2) -> bool:
	var margin := 240.0
	var rect := Rect2(-Vector2(margin, margin), size + Vector2(margin * 2.0, margin * 2.0))
	if rect.has_point(a) or rect.has_point(b):
		return true
	return false


func _draw_trail() -> void:
	if not show_trail or sim.trail.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in sim.trail:
		pts.append(to_screen(p))
	draw_polyline(pts, Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, 0.25), 1.0, true)


func _draw_bodies() -> void:
	for id in sim.universe.order:
		var body: CelestialBody = sim.universe.bodies[id]
		var sp: Vector2 = to_screen(sim.universe.pos_at(id, sim.t))
		if sp.x < -160.0 or sp.y < -160.0 or sp.x > size.x + 160.0 or sp.y > size.y + 160.0:
			continue
		var px: float = clampf(body.radius_m * 2.0 * zoom, body.symbol_px, 64.0)
		if id == "sun":
			px = maxf(px, body.symbol_px)
		var tex: Texture2D = Art.tex(body.art_key)
		if tex != null:
			var rect := Rect2(sp - Vector2(px, px) * 0.5, Vector2(px, px))
			var frames: int = Art.frame_count(body.art_key)
			if frames > 1:
				var fw: float = float(tex.get_width()) / float(frames)
				var idx: int = int(Time.get_ticks_msec() / 1000.0 * Art.frame_fps(body.art_key)) % frames
				draw_texture_rect_region(tex, rect, Rect2(Vector2(idx * fw, 0.0), Vector2(fw, tex.get_height())))
			else:
				draw_texture_rect(tex, rect, false)
		if id == sim.mission.target_body:
			_draw_reticle(sp, px * 0.5 + 8.0)
	_draw_encounter_marks()


func _draw_encounter_marks() -> void:
	if encounter_marks.is_empty():
		return
	var font: Font = get_theme_default_font()
	for raw in encounter_marks:
		var mark: Dictionary = raw
		var id := str(mark.get("id", ""))
		var body: CelestialBody = sim.universe.body(id)
		if body == null:
			continue
		var at_t := float(mark.get("t", 0.0))
		if at_t <= sim.t:
			continue
		var now_sp := to_screen(sim.universe.pos_at(id, sim.t))
		var sp := to_screen(sim.universe.pos_at(id, at_t))
		if sp.x < -160.0 or sp.y < -160.0 or sp.x > size.x + 160.0 or sp.y > size.y + 160.0:
			continue
		var c := Color(UiKit.AMBER.r, UiKit.AMBER.g, UiKit.AMBER.b, 0.85)
		draw_dashed_line(now_sp, sp, Color(c.r, c.g, c.b, 0.18), 1.0, 4.0)
		draw_arc(sp, 8.0, 0.0, TAU, 24, c, 1.0, true)
		draw_line(sp + Vector2(-12, 0), sp + Vector2(-4, 0), c, 1.0, true)
		draw_line(sp + Vector2(4, 0), sp + Vector2(12, 0), c, 1.0, true)
		var label := "%s  T+%dd" % [Localization.t(body.display_name), roundi(at_t / 86400.0)]
		draw_string(font, sp + Vector2(13, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(UiKit.AMBER.r, UiKit.AMBER.g, UiKit.AMBER.b, 0.85))

func _draw_body_labels() -> void:
	var font: Font = get_theme_default_font()
	var color := Color(UiKit.TEXT.r, UiKit.TEXT.g, UiKit.TEXT.b, 0.65)
	for id in sim.universe.order:
		var body: CelestialBody = sim.universe.bodies[id]
		var sp: Vector2 = to_screen(sim.universe.pos_at(id, sim.t))
		if sp.x < -160.0 or sp.y < -160.0 or sp.x > size.x + 160.0 or sp.y > size.y + 160.0:
			continue
		var px: float = clampf(body.radius_m * 2.0 * zoom, body.symbol_px, 64.0)
		if id == "sun":
			px = maxf(px, body.symbol_px)
		var label := Localization.t(body.display_name)
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var at := sp + Vector2(-w * 0.5, -px * 0.5 - 8.0)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_reticle(center: Vector2, radius: float) -> void:
	var c := Color(UiKit.AMBER.r, UiKit.AMBER.g, UiKit.AMBER.b, 0.85)
	draw_arc(center, radius, 0.0, TAU, 48, c, 1.0, true)
	for k in range(4):
		var ang: float = TAU * float(k) / 4.0 + PI * 0.25
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(center + dir * (radius + 2.0), center + dir * (radius + 8.0), c, 1.0, true)


func _draw_craft() -> void:
	var sp: Vector2 = to_screen(sim.craft.pos)
	if sp.x < -60.0 or sp.y < -60.0 or sp.x > size.x + 60.0 or sp.y > size.y + 60.0:
		return
	var drawn := false
	if not sim.cells.is_empty() and sim.cells.size() == sim.design.size():
		var maxc := Vector2i(0, 0)
		for c in (sim.cells + sim.hull):
			if typeof(c) != TYPE_VECTOR2I:
				continue
			var v: Vector2i = c
			maxc.x = maxi(maxc.x, v.x + 1)
			maxc.y = maxi(maxc.y, v.y + 1)
		var span: Vector2i = Vector2i(maxi(maxc.x, 1), maxi(maxc.y, 1))
		var unit: float = clampf(60.0 / float(maxi(span.x, span.y)), 3.0, 8.0)
		var half: Vector2 = Vector2(span) * unit * 0.5
		var base_rot: float = sim.craft.vel.angle() + PI * 0.5
		var to_world := Transform2D(base_rot, sp)
		var hull_art: Array[Texture2D] = [Art.tex("icon_hull_a"), Art.tex("icon_hull_b"), Art.tex("icon_hull_c")]
		for hc in sim.hull:
			if typeof(hc) != TYPE_VECTOR2I:
				continue
			var hv: Vector2i = hc
			var local_h: Vector2 = (Vector2(hv) + Vector2(0.5, 0.5)) * unit - half
			var tex_h: Texture2D = hull_art[absi(hv.x * 7 + hv.y * 13) % hull_art.size()]
			if tex_h == null:
				continue
			draw_set_transform(to_world * local_h, base_rot, Vector2.ONE)
			draw_texture_rect_region(tex_h, Rect2(Vector2(-unit, -unit) * 0.5, Vector2(unit, unit)), Rect2(Vector2.ZERO, Vector2(16, 16)))
		for i in range(sim.design.size()):
			var part: PartDef = GameData.part(str(sim.design[i]))
			if part == null:
				continue
			var tex: Texture2D = Art.part_icon(part)
			if tex == null:
				continue
			var cell: Vector2i = sim.cells[i]
			var local: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * unit - half
			var r: int = int(sim.rots[i]) % 4 if i < sim.rots.size() else 0
			draw_set_transform(to_world * local, base_rot + float(r) * PI * 0.5, Vector2.ONE)
			draw_texture_rect_region(tex, Rect2(Vector2(-unit, -unit) * 0.5, Vector2(unit, unit)), ShipBaker.trimmed(tex))
			drawn = true
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not drawn:
		var dir: Vector2 = sim.craft.vel.normalized()
		if dir.length() < 0.5:
			dir = Vector2.RIGHT
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([
			sp + dir * 10.0,
			sp - dir * 6.0 + side * 6.0,
			sp - dir * 3.0,
			sp - dir * 6.0 - side * 6.0,
		])
		draw_colored_polygon(pts, UiKit.CYAN)
	draw_arc(sp, 13.0, 0.0, TAU, 24, Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, 0.35), 1.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.18, mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.18, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		pan -= mm.relative / zoom
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_last_touch = st.position
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		pan -= sd.relative / zoom
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_by(mg.factor, mg.position)
		accept_event()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		pan -= pg.delta / zoom * 12.0
		accept_event()
