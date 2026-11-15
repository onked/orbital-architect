class_name UiKit
extends RefCounted

# The entirety of themes, so everything becomes easier
const THEME_PATH := "res://ui/theme.tres"

const BG := Color("#0b0f16")
const BG_DEEP := Color("#070a10")
const PANEL := Color("#121821")
const PANEL_ALT := Color("#182131")
const LINE := Color("#243244")
const TEXT := Color("#d7e3f4")
const MUTED := Color("#7e8ea3")
const CYAN := Color("#35d0e0")
const AMBER := Color("#ffb53d")
const CRIMSON := Color("#e5484d")
const GREEN := Color("#54d68a")
const VIOLET := Color("#9a7bff")

static var motion_enabled := true

static func style_panel(bg: Color, border: Color, radius: int = 4,
		margin: int = 12, margin_v: int = -1, margin_h: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	var mv := margin if margin_v < 0 else margin_v
	var mh := margin if margin_h < 0 else margin_h
	sb.content_margin_left = mh
	sb.content_margin_right = mh
	sb.content_margin_top = mv
	sb.content_margin_bottom = mv
	return sb

static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func money(v: float) -> String:
	if absf(v) >= 1.0e9:
		return "$%.2fB" % (v / 1.0e9)
	if absf(v) >= 1.0e6:
		return "$%.1fM" % (v / 1.0e6)
	if absf(v) >= 1.0e3:
		return "$%.0fK" % (v / 1.0e3)
	return "$%.0f" % v

static func kg(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.2f t" % (v / 1000.0)
	return "%.0f kg" % v

static func dist(v: float) -> String:
	var a := absf(v)
	if a >= 0.05 * 149597870700.0:
		return "%.3f AU" % (v / 149597870700.0)
	if a >= 1.0e3:
		return "%.0f km" % (v / 1000.0)
	return "%.0f m" % v

static func speed(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.2f km/s" % (v / 1000.0)
	return "%.0f m/s" % v

static func jd_date(days_since_j2000: float) -> String:
	var jd := 2451545.0 + days_since_j2000
	var z := int(floor(jd + 0.5))
	var frac := jd + 0.5 - float(z)
	var a := z
	if z >= 2299161:
		var alpha := int((float(z) - 1867216.25) / 36524.25)
		a = z + 1 + alpha - int(float(alpha) / 4.0)
	var b := a + 1524
	var c := int((float(b) - 122.1) / 365.25)
	var d := int(365.25 * float(c))
	var e := int((float(b) - float(d)) / 30.6001)
	var day := b - d - int(30.6001 * float(e))
	var month := e - 1 if e < 14 else e - 13
	var year := c - 4716 if month > 2 else c - 4715
	var hours := int(frac * 24.0)
	var minutes := int((frac * 24.0 - float(hours)) * 60.0)
	return "%04d-%02d-%02d %02d:%02d" % [year, month, day, hours, minutes]

static func attach_hover(c: Control, accent: Color = CYAN) -> void:
	if c == null or c.has_meta("ui_hover"):
		return
	c.set_meta("ui_hover", true)
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if c is Button and not c.has_meta("ui_click"):
		c.set_meta("ui_click", true)
		c.pressed.connect(Audio.ui_click)
	c.mouse_entered.connect(_hover_enter.bind(c, accent))
	c.mouse_exited.connect(_hover_exit.bind(c, accent))

static func _hover_tween(c: Control) -> Tween:
	var old: Variant = c.get_meta("ui_hover_tween") if c.has_meta("ui_hover_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := c.create_tween()
	t.set_parallel(true)
	c.set_meta("ui_hover_tween", t)
	return t

static func _hover_style(c: Control, accent: Color) -> StyleBoxFlat:
	if c is Button:
		return null
	var cached: Variant = c.get_meta("ui_hover_style") if c.has_meta("ui_hover_style") else null
	if cached is StyleBoxFlat:
		return cached as StyleBoxFlat
	var base := c.get_theme_stylebox("panel") as StyleBoxFlat
	if base == null:
		return null
	var copy := base.duplicate() as StyleBoxFlat
	c.add_theme_stylebox_override("panel", copy)
	c.set_meta("ui_hover_base", base)
	c.set_meta("ui_hover_style", copy)
	return copy

static func _hover_enter(c: Control, accent: Color) -> void:
	if not is_instance_valid(c):
		return
	Audio.ui_hover()
	if not motion_enabled:
		return
	var grown := 1.015 if c is Button else 1.005
	c.pivot_offset = c.size * 0.5
	var t := _hover_tween(c)
	t.tween_property(c, "scale", Vector2(grown, grown), 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate", Color(1.08, 1.08, 1.08), 0.12)
	var sb := _hover_style(c, accent)
	if sb != null:
		var base: StyleBoxFlat = c.get_meta("ui_hover_base") if c.has_meta("ui_hover_base") else null
		t.tween_property(sb, "border_color", accent, 0.12)
		t.tween_property(sb, "bg_color", base.bg_color.lightened(0.06), 0.12)

static func _hover_exit(c: Control, accent: Color) -> void:
	if not is_instance_valid(c):
		return
	if not motion_enabled:
		c.scale = Vector2.ONE
		c.modulate = Color.WHITE
		return
	var t := _hover_tween(c)
	t.tween_property(c, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate", Color.WHITE, 0.16)
	var cached: Variant = c.get_meta("ui_hover_style") if c.has_meta("ui_hover_style") else null
	if cached is StyleBoxFlat:
		var sb := cached as StyleBoxFlat
		var base: StyleBoxFlat = c.get_meta("ui_hover_base") if c.has_meta("ui_hover_base") else null
		t.tween_property(sb, "border_color", base.border_color, 0.16)
		t.tween_property(sb, "bg_color", base.bg_color, 0.16)
