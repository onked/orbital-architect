class_name ContractGen
extends RefCounted

const G := 6.6743e-11
const NAMES := ["VESTA", "THALIA", "KEPLER", "NYX", "CALYPSO", "ORPHEUS",
	"HALCYON", "ATLAS", "ERIS", "TETHYS", "BRONTES", "SELENE"]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const COLORS := ["#c9b79a", "#9fb4c9", "#c98f6b", "#8fb39a", "#b49ac9",
	"#c9c39a", "#9aa8c9", "#c99aa8"]

static func _t(key: String, args: Array = []) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Localization"):
		return tree.root.get_node("Localization").call("t", key, args)
	if args.is_empty():
		return key
	return key % args


static func make_offer(serial: int, bodies: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100003 * serial + 17
	var tier: int = 1 + (serial % 3)

	var parent_id := "earth"
	if tier == 2:
		parent_id = "mars" if rng.randf() < 0.5 else "sun"
	elif tier >= 3:
		parent_id = "jupiter" if rng.randf() < 0.5 else "sun"
	var parent: CelestialBody = bodies.get(parent_id, null)
	if parent == null:
		parent = bodies.get("sun")
		parent_id = "sun"

	var moon: bool = parent_id != "sun"
	var radius_km: float
	var a_m: float
	var density: float
	var e: float
	var inc: float
	if moon:
		radius_km = rng.randf_range(180.0, 900.0)
		var a_min := 30000.0
		var a_max := 150000.0
		if parent_id == "mars":
			a_min = 20000.0
			a_max = 110000.0
		elif parent_id == "jupiter":
			a_min = 300000.0
			a_max = 1500000.0
		a_m = rng.randf_range(a_min, a_max) * 1000.0
		density = rng.randf_range(2500.0, 4200.0)
		e = rng.randf_range(0.0, 0.09)
		inc = rng.randf_range(0.0, 12.0)
	else:
		radius_km = rng.randf_range(2600.0, 7200.0)
		var au := 1.5 if tier == 2 else rng.randf_range(3.0, 5.0)
		if tier == 2:
			au = rng.randf_range(1.5, 2.8)
		a_m = au * Ephemeris.AU_M
		density = rng.randf_range(3400.0, 5600.0)
		e = rng.randf_range(0.0, 0.16)
		inc = rng.randf_range(0.0, 18.0)

	var radius_m := radius_km * 1000.0
	var mu := (4.0 / 3.0) * PI * G * density * pow(radius_m, 3.0)
	var soi := maxf(a_m * pow(mu / maxf(parent.mu, 1.0), 0.4), radius_m * 8.0)
	var period_s := TAU * sqrt(pow(a_m, 3.0) / maxf(parent.mu + mu, 1.0))
	var rate_l := 360.0 / maxf(period_s / 86400.0, 0.001) * 36525.0

	var base := str(NAMES[rng.randi() % NAMES.size()])
	var body_name := "%s %s" % [base, str(ROMAN[rng.randi() % ROMAN.size()])]
	var body_id := "proc_%d" % serial
	var atmo := 0.0
	var scale_h := 0.0
	if not moon and radius_km > 3500.0:
		atmo = 60000.0
		scale_h = 7000.0

	var body := {
		"id": body_id,
		"name": body_name,
		"parent": parent_id,
		"mu": mu,
		"radius_m": radius_m,
		"soi_m": soi,
		"atmosphere_top_m": atmo,
		"scale_height_m": scale_h,
		"color": COLORS[rng.randi() % COLORS.size()],
		"symbol_px": 5.0,
		"art": "",
		"elements": {
			"a_km": a_m / 1000.0,
			"e": e,
			"i_deg": inc,
			"L_deg": rng.randf_range(0.0, 360.0),
			"peri_deg": rng.randf_range(0.0, 360.0),
			"node_deg": rng.randf_range(0.0, 360.0),
			"rates": {"L_deg": rate_l},
		},
	}

	var template: String = "orbit"
	var roll := rng.randf()
	if roll < 0.42:
		template = "orbit"
	elif roll < 0.76:
		template = "survey"
	else:
		template = "land" if moon else "orbit"

	var budget := [90000000.0, 180000000.0, 320000000.0][tier - 1] as float
	var mass_cap := [2200.0, 3500.0, 5500.0][tier - 1] as float
	var duration := 60.0
	if parent_id == "jupiter":
		duration = 1200.0
	elif parent_id == "sun":
		duration = 700.0 + 500.0 * float(tier)
	elif parent_id == "mars":
		duration = 320.0

	var design: Array = ["core_bus", "tank_large", "engine_chem", "solar_wing", "dish_hga", "sci_camera", "structure_ring"]
	if tier >= 2:
		design = ["core_deep", "tank_large", "tank_large", "tank_small", "engine_chem", "rtg_mmr", "dish_hga", "sci_camera", "structure_ring"]
	if tier >= 3:
		design = ["core_deep", "tank_large", "tank_large", "tank_small", "tank_small", "engine_chem", "rtg_mmr", "dish_hga", "sci_camera", "shield_ablative", "structure_ring"]

	var objectives: Array = []
	var required: Array = []
	var verb := "Orbit %s"
	var code := _t("SANDBOX / TIER %d", [tier])
	if template == "orbit":
		objectives = [{
			"id": "capture", "label": _t("Achieve orbit"),
			"detail": _t("Bound orbit inside %s's SOI.", [body_name]),
			"points": 60, "kind": "bound", "body": body_id,
		}]
		verb = "Orbit %s"
	elif template == "survey":
		objectives = [
			{
				"id": "flyby", "label": _t("Survey pass"),
				"detail": _t("Pass within 50,000 km of %s.", [body_name]),
				"points": 35, "kind": "flyby", "body": body_id, "value": 50000,
			},
			{
				"id": "science", "label": _t("Send the data"),
				"detail": _t("Transmit within 50,000 km."),
				"points": 25, "kind": "transmit",
			},
		]
		required = ["sci_camera"]
		verb = "Survey %s"
	elif template == "land":
		objectives = [{
			"id": "land", "label": _t("Touchdown"),
			"detail": _t("Land under 40 m/s relative speed."),
			"points": 70, "kind": "land", "body": body_id,
			"value": 40, "ends": true,
		}]
		verb = "Land on %s"
		code = _t("SANDBOX / LANDING")

	var mission := {
		"id": "contract_%d" % serial,
		"number": 0,
		"name": _t(verb, [body_name]),
		"code": code,
		"playable": true,
		"target_body": body_id,
		"start_body": "earth",
		"start_altitude_m": 200000.0,
		"budget_usd": budget,
		"mass_cap_kg": mass_cap,
		"required_parts": required,
		"recommended_design": design,
		"science_range_m": 50000000.0,
		"duration_days": duration,
		"briefing": [
			_t("Client: %s program.", [_t("JPL") if tier == 1 else _t("Deep Space Consortium")]),
			_t("Target: %s, %s of %s. Radius %.0f km.", [
				body_name, _t("moon") if moon else _t("planet"), _t(parent.display_name), radius_km]),
			_t("Payment on completion, advance on acceptance. Tier %d.", [tier]),
		],
		"hints": [
			_t("AUTO-PLAN works inside the target SOI."),
			_t("Orbit: bound energy at closest approach."),
			_t("Landing: touch down under 40 m/s."),
		],
		"objectives": objectives,
		"scoring": {"objectives": 75, "budget_surplus": 15, "fuel_efficiency": 10},
	}

	var reward := [8000000, 18000000, 40000000][tier - 1] as int
	return {
		"mission": mission,
		"body": body,
		"tier": tier,
		"template": template,
		"reward": reward,
		"advance": int(round(float(reward) * 0.25)),
		"serial": serial,
	}
