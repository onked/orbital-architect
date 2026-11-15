class_name MissionDef
extends Resource

var id: String = ""
var number: int = 0
var display_name: String = ""
var code: String = ""
var playable: bool = false
var hidden: bool = false
var target_body: String = ""
var start_body: String = "earth"
var start_altitude_m: float = 200000.0
var budget_usd: float = 0.0
var mass_cap_kg: float = 0.0
var required_parts: Array = []
var recommended_design: Array = []
var briefing: Array = []
var hints: Array = []
var objectives: Array = []
var science_range_m: float = 30000000.0
var duration_days: float = 90.0
var science_note: String = ""
var start_mode: String = "orbit"
var score_weights: Dictionary = {}

static func from_dict(d: Dictionary) -> MissionDef:
	var m := MissionDef.new()
	m.id = str(d.get("id", ""))
	m.number = int(d.get("number", 0))
	m.display_name = str(d.get("name", m.id.capitalize()))
	m.code = str(d.get("code", ""))
	m.playable = bool(d.get("playable", false))
	m.hidden = bool(d.get("hidden", false))
	m.target_body = str(d.get("target_body", "moon"))
	m.start_body = str(d.get("start_body", "earth"))
	m.start_altitude_m = float(d.get("start_altitude_m", 200000.0))
	m.budget_usd = float(d.get("budget_usd", 0.0))
	m.mass_cap_kg = float(d.get("mass_cap_kg", 0.0))
	m.required_parts = d.get("required_parts", [])
	m.recommended_design = d.get("recommended_design", [])
	m.briefing = d.get("briefing", [])
	m.hints = d.get("hints", [])
	m.objectives = d.get("objectives", [])
	m.science_range_m = float(d.get("science_range_m", 30000000.0))
	m.duration_days = float(d.get("duration_days", 90.0))
	m.science_note = str(d.get("science_note", ""))
	m.start_mode = str(d.get("start_mode", "orbit"))
	m.score_weights = d.get("scoring", {})
	return m

func objective_points() -> float:
	var total := 0.0
	for o in objectives:
		total += float((o as Dictionary).get("points", 0))
	return total
