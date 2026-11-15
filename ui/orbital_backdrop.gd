class_name OrbitalBackdrop
extends Control

# This script is for the cool background
var warp_scale: float = 1.0
var _t: float = 0.0
var _transfer_phase: float = 0.0
var _in_transfer: bool = true
var _stars: Array = []

func _ready() -> void:
	add_to_group("orbital_backdrop")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260414
	for i in range(95):
		_stars.append({
			"uv": Vector2(rng.randf(), rng.randf()),
			"size": 2.0 if rng.randf() < 0.22 else 1.0,
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.6, 2.4),
			"tint": [Color("#d7e3f4"), Color("#ffffff"), Color("#35d0e0"), Color("#ffb53d")][rng.randi() % 4],
		})

func _process(delta: float) -> void:
	_t += delta * warp_scale
	if _in_transfer:
		_transfer_phase = fmod(_transfer_phase + delta * 0.22 * warp_scale, 1.0)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 1.0 or h <= 1.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color("#080c14"), true)

	var grid_minor := Color(0.14, 0.20, 0.29, 0.16)
	var grid_major := Color(0.18, 0.26, 0.38, 0.24)
	var step := 64
	var ix := 0
	for x in range(0, int(w) + step, step):
		var col := grid_major if (ix % 4 == 0) else grid_minor
		draw_line(Vector2(x, 0), Vector2(x, h), col, 1.0)
		ix += 1
	var iy := 0
	for y in range(0, int(h) + step, step):
		var col := grid_major if (iy % 4 == 0) else grid_minor
		draw_line(Vector2(0, y), Vector2(w, y), col, 1.0)
		iy += 1

	for s in _stars:
		var d: Dictionary = s
		var uv: Vector2 = d["uv"]
		var sp := Vector2(floorf(uv.x * w), floorf(uv.y * h))
		var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * float(d["speed"]) + float(d["phase"])))
		var c: Color = d["tint"]
		var sz: float = float(d["size"])
		draw_rect(Rect2(sp, Vector2(sz, sz)), Color(c.r, c.g, c.b, pulse), true)

	var k: float = clampf(minf(w, h) / 760.0, 0.58, 1.35)
	var center := Vector2(floorf(w * 0.63), floorf(h * 0.60))
	var r1 := 64.0 * k
	var r2 := 122.0 * k
	var r3 := 188.0 * k
	var r4 := 256.0 * k

	_draw_pixel_circle(center, r1, Color(0.32, 0.38, 0.48, 0.45), 64)
	_draw_pixel_circle(center, r2, Color("#35d0e0"), 120)
	_draw_pixel_circle(center, r3, Color(0.32, 0.38, 0.48, 0.40), 120)
	_draw_pixel_circle(center, r4, Color(0.32, 0.38, 0.48, 0.28), 140)

	_draw_transfer_ellipse(center, r2, r3, _t * 0.12)

	var sun_pulse := 1.0 + 0.08 * sin(_t * 3.2)
	_draw_pixel_disc(center, 22.0 * k * sun_pulse, Color(1.0, 0.48, 0.12, 0.22))
	_body("body_sun", center, 42.0 * k * sun_pulse)

	var a1 := _t * 0.85 + 2.4
	var p1 := center + Vector2(cos(a1), sin(a1)) * r1
	_body("body_venus", p1, 11.0 * k)

	var a2 := _t * 0.42 + 0.25
	var p2 := center + Vector2(cos(a2), sin(a2)) * r2
	_body("body_earth", p2, 19.0 * k)
	var am := _t * 2.6
	var pm := p2 + Vector2(cos(am), sin(am)) * (12.0 * k)
	_body("body_moon", pm, 7.0 * k)

	var a3 := _t * 0.24 - 0.85
	var p3 := center + Vector2(cos(a3), sin(a3)) * r3
	_body("body_mars", p3, 14.0 * k)

	var a4 := _t * 0.11 + 1.9
	var p4 := center + Vector2(cos(a4), sin(a4)) * r4
	_body("body_saturn", p4, 34.0 * k)

	var ship_pos := _transfer_point(center, r2, r3, _t * 0.12, _transfer_phase)
	var ship_px := maxf(8.0, 17.0 * k)
	var ship_tex: Texture2D = Art.tex("craft_ship")
	if ship_tex != null:
		var ahead := _transfer_point(center, r2, r3, _t * 0.12, fmod(_transfer_phase + 0.004, 1.0))
		var angle := (ahead - ship_pos).angle()
		draw_set_transform(ship_pos, angle, Vector2.ONE)
		draw_texture_rect(ship_tex,
			Rect2(-Vector2(ship_px, ship_px) * 0.5, Vector2(ship_px, ship_px)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _body(key: String, center: Vector2, px: float) -> void:
	var tex: Texture2D = Art.tex(key)
	if tex == null:
		return
	var frames: int = maxi(Art.frame_count(key), 1)
	var fw: float = float(tex.get_width()) / float(frames)
	var fh: float = float(tex.get_height())
	var f: int = int(floor(_t * Art.frame_fps(key))) % frames
	draw_texture_rect_region(tex,
		Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px)),
		Rect2(float(f) * fw, 0.0, fw, fh))

func _draw_pixel_circle(center: Vector2, radius: float, col: Color, steps: int) -> void:
	for i in range(steps):
		var ang := TAU * float(i) / float(steps)
		var pt := (center + Vector2(cos(ang), sin(ang)) * radius).floor()
		draw_rect(Rect2(pt, Vector2(2, 2)), col, true)

func _draw_transfer_ellipse(center: Vector2, r1: float, r2: float, rot: float) -> void:
	var a := (r1 + r2) * 0.5
	var c := (r2 - r1) * 0.5
	var b := sqrt(maxf(a * a - c * c, 1.0))
	var steps := 64
	var xform := Transform2D(rot, center)
	for i in range(steps):
		var ang := TAU * float(i) / float(steps)
		var local := Vector2(cos(ang) * a - c, sin(ang) * b)
		var pt := (xform * local).floor()
		var col := Color("#ffb53d") if (i % 2 == 0) else Color(1.0, 0.71, 0.24, 0.35)
		draw_rect(Rect2(pt, Vector2(2, 2)), col, true)

func _transfer_point(center: Vector2, r1: float, r2: float, rot: float, u: float) -> Vector2:
	var a := (r1 + r2) * 0.5
	var c := (r2 - r1) * 0.5
	var b := sqrt(maxf(a * a - c * c, 1.0))
	var ang := u * TAU
	var local := Vector2(cos(ang) * a - c, sin(ang) * b)
	return Transform2D(rot, center) * local

func _draw_pixel_disc(center: Vector2, radius: float, col: Color) -> void:
	var r := int(ceilf(radius))
	var r2 := radius * radius
	var step := 2
	for dy in range(-r, r + 1, step):
		for dx in range(-r, r + 1, step):
			if float(dx * dx + dy * dy) <= r2:
				draw_rect(Rect2(center + Vector2(dx, dy), Vector2(step, step)), col, true)
