class_name CelestialBody
extends RefCounted

var id: String = ""
var display_name: String = ""
var parent_id: String = ""
var mu: float = 0.0
var radius_m: float = 0.0
var soi_m: float = 0.0
var atmosphere_top_m: float = 0.0
var scale_height_m: float = 0.0
var color: Color = Color.WHITE
var symbol_px: float = 8.0
var art_key: String = ""
var a_m: float = 0.0
var e: float = 0.0
var i_deg: float = 0.0
var l_deg: float = 0.0
var peri_deg: float = 0.0
var node_deg: float = 0.0
var rate_a: float = 0.0
var rate_e: float = 0.0
var rate_i: float = 0.0
var rate_l: float = 0.0
var rate_peri: float = 0.0
var rate_node: float = 0.0
var has_elements := false
var parent_mu: float = 0.0

static func from_dict(d: Dictionary) -> CelestialBody:
	var b := CelestialBody.new()
	b.id = str(d.get("id", ""))
	b.display_name = str(d.get("name", b.id.capitalize()))
	b.parent_id = str(d.get("parent", ""))
	b.mu = float(d.get("mu", 0.0))
	b.radius_m = float(d.get("radius_m", 1000.0))
	b.soi_m = float(d.get("soi_m", 0.0))
	b.atmosphere_top_m = float(d.get("atmosphere_top_m", 0.0))
	b.scale_height_m = float(d.get("scale_height_m", 0.0))
	b.color = Color(str(d.get("color", "#ffffff")))
	b.symbol_px = float(d.get("symbol_px", 8.0))
	b.art_key = str(d.get("art", ""))

	var el: Variant = d.get("elements", null)
	if el is Dictionary and not (el as Dictionary).is_empty():
		var e_dict: Dictionary = el
		b.has_elements = true
		var rates: Dictionary = e_dict.get("rates", {})
		if e_dict.has("a_au"):
			b.a_m = float(e_dict["a_au"]) * Ephemeris.AU_M
			b.rate_a = float(rates.get("a_au", 0.0)) * Ephemeris.AU_M
		else:
			b.a_m = float(e_dict.get("a_km", 0.0)) * 1000.0
			b.rate_a = float(rates.get("a_km", 0.0)) * 1000.0
		b.e = float(e_dict.get("e", 0.0))
		b.i_deg = float(e_dict.get("i_deg", 0.0))
		b.l_deg = float(e_dict.get("L_deg", 0.0))
		b.peri_deg = float(e_dict.get("peri_deg", 0.0))
		b.node_deg = float(e_dict.get("node_deg", 0.0))
		b.rate_e = float(rates.get("e", 0.0))
		b.rate_i = float(rates.get("i_deg", 0.0))
		b.rate_l = float(rates.get("L_deg", 0.0))
		b.rate_peri = float(rates.get("peri_deg", 0.0))
		b.rate_node = float(rates.get("node_deg", 0.0))
	return b

func orbit_mu() -> float:
	if parent_mu > 0.0:
		return parent_mu
	return 1.32712440018e20

func relative_state_xy(t: float) -> PackedFloat64Array:
	if not has_elements or mu <= 0.0:
		var zero := PackedFloat64Array()
		zero.resize(4)
		return zero
	var centuries: float = t / Ephemeris.CENTURY_S
	var scale: float = Ephemeris.DEG / Ephemeris.CENTURY_S
	var n_eff: float = (rate_l - rate_peri) * scale
	var w_dot: float = (rate_peri - rate_node) * scale
	var node_dot: float = rate_node * scale
	var inc_dot: float = rate_i * scale
	return Ephemeris.state_xy(
		a_m + rate_a * centuries, e + rate_e * centuries,
		i_deg + rate_i * centuries, l_deg + rate_l * centuries,
		peri_deg + rate_peri * centuries, node_deg + rate_node * centuries,
		orbit_mu(), n_eff, w_dot, node_dot, inc_dot)

func relative_state(t: float) -> Dictionary:
	if not has_elements or mu <= 0.0:
		return {"pos": Vector2.ZERO, "vel": Vector2.ZERO}
	var centuries: float = t / Ephemeris.CENTURY_S
	var a: float = a_m + rate_a * centuries
	var e_val: float = e + rate_e * centuries
	var inc: float = i_deg + rate_i * centuries
	var l: float = l_deg + rate_l * centuries
	var peri: float = peri_deg + rate_peri * centuries
	var node: float = node_deg + rate_node * centuries
	return Ephemeris.state_from_elements(a, e_val, inc, l, peri, node, orbit_mu())

func soi_or_default() -> float:
	if soi_m > 0.0:
		return soi_m
	return maxf(radius_m * 100.0, 1.0)
