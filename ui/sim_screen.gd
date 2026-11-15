extends Control

# Simulator stuff, essentially this script is used for the primary simulator stuff such as burn planner, telemetry & etc

const OBJECTIVE_ROW := preload("res://scenes/components/objective_row.tscn")
const PREDICT_DAYS := 6.0
const WARPS := [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0]
const PREDICT_INTERVAL := 0.12
const HUD_INTERVAL := 0.08
const STEP_BUDGET_MS := 8.0
const PREDICT_REFRESH := 0.5
const CHECKPOINT_INTERVAL := 30.0
const CHECKPOINT_KEEP := 12

var mission: MissionDef = null
var design: Array = []
var layout: Array = []
var rots: Array = []
var hull: Array = []
var cost: float = 0.0

var sim: Sim = null

var hub: String = "campaign"

var resume: Dictionary = {}

var paused: bool = true
var warp: float = 1.0
var _predict_accum: float = 0.0
var _predict_dirty: bool = true
var _log_accum: float = 0.0
var _hud_accum: float = 0.0
var _carry: float = 0.0

var _preview_days: float = 6.0
var _baseline_valid: bool = false
var _planned_key: String = ""

var _pro_mps: float = 0.0
var _rad_mps: float = 0.0
var _save_accum: float = 0.0

var _checkpoints: Array = []
var _checkpoint_accum: float = 0.0
var _done_announced: bool = false
var _impact_warned: bool = false
var _hint_index: int = 0
var _encounter_target: String = ""
var _solving: bool = false

@onready var _view: WorldView = %Map
@onready var _back: Button = %Back
@onready var _title: Label = %Title
@onready var _clock: Label = %Clock
@onready var _warp_state: Label = %WarpState
@onready var _pause: Button = %Pause
@onready var _skip: Button = %Skip
@onready var _end: Button = %End
@onready var _status: Label = %Status
@onready var _mass: StatRow = %Mass
@onready var _fuel: StatRow = %Fuel
@onready var _delta_v: StatRow = %DeltaV
@onready var _range: StatRow = %Range
@onready var _altitude: StatRow = %Altitude
@onready var _rel_speed: StatRow = %RelSpeed
@onready var _power: StatRow = %Power
@onready var _objectives: VBoxContainer = %Objectives
@onready var _prograde: HSlider = %Prograde
@onready var _radial: HSlider = %Radial
@onready var _prograde_edit: LineEdit = %ProgradeEdit
@onready var _radial_edit: LineEdit = %RadialEdit
@onready var _burn_summary: Label = %BurnSummary
@onready var _execute: Button = %Execute
@onready var _science_state: Label = %ScienceState
@onready var _transmit_button: Button = %Transmit
@onready var _log: Label = %Log
@onready var _hint_line: Label = %HintLine
@onready var _next_hint: Button = %NextHint
@onready var _buy_hint: Button = %BuyHint
@onready var _periapsis: StatRow = %Periapsis
@onready var _apoapsis: StatRow = %Apoapsis
@onready var _auto_capture: Button = %AutoCapture
@onready var _rewind: Button = %Rewind
@onready var _encounters: VBoxContainer = %Encounters
@onready var _scan_button: Button = %ScanEncounters
@onready var _solve_burn: Button = %SolveBurn

func _ready() -> void:
	if mission == null:
		return
	if design.is_empty():
		design = GameState.design_for(mission.id)
	var built: Dictionary = CraftState.build(design, GameData.parts)
	sim = Sim.new()
	sim.setup(mission, built["craft"], GameData.bodies_for_mission(mission), GameData.mission_start_t, cost, design, layout, rots, hull)
	sim.objective_done.connect(_on_objective)
	sim.mission_failed.connect(_on_failure)
	sim.approach.connect(_on_approach)
	sim.periapsis_pass.connect(_on_periapsis)
	_auto_capture.pressed.connect(_auto_plan_capture)
	_next_hint.pressed.connect(_cycle_hint)
	_buy_hint.pressed.connect(_buy_hint_pressed)
	_rewind.pressed.connect(_rewind_last)
	_scan_button.pressed.connect(_scan_encounters)
	_scan_button.tooltip_text = "G"
	_solve_burn.pressed.connect(_solve_flyby_burn)
	_solve_burn.tooltip_text = "F"

	if not resume.is_empty():
		sim.restore(resume.get("sim", {}))
		paused = bool(resume.get("paused", true))
		warp = float(resume.get("warp", 1.0))

	if mission.start_mode == "descent":
		_preview_days = 0.002
	elif _land_limit() > 0.0 or mission.start_body != "earth":
		_preview_days = 0.05
	else:
		_preview_days = clampf(mission.duration_days * 0.05, 6.0, 90.0)
	_title.text = Localization.t(mission.display_name).to_upper()
	_view.sim = sim
	_view.show_orbits = mission.start_mode != "descent"
	var start_body: CelestialBody = GameData.body(mission.start_body)
	if mission.start_body != "earth" and start_body != null:
		_view.focus(mission.start_body)
	else:
		_view.focus("earth")

	var span: float = 2.0e7
	var target: CelestialBody = sim.target()
	var target_dist := 0.0
	if target != null:
		var rel: Dictionary = sim.universe.relative_state_xy(target.id, sim.craft.px, sim.craft.py, sim.craft.vx, sim.craft.vy, sim.t)
		target_dist = float(rel["dist"])
		span = maxf(target_dist * 1.25, span)
	if mission.start_body != "earth" and start_body != null:
		span = maxf(target_dist * 1.5, start_body.radius_m * 4.0)
	_view.fit_radius(span)

	_back.pressed.connect(_confirm_exit)
	_pause.pressed.connect(_toggle_pause)
	_skip.pressed.connect(_skip_hour)
	_end.pressed.connect(_end_mission)
	_prograde.value_changed.connect(_on_burn_slider)
	_radial.value_changed.connect(_on_burn_slider)
	_prograde_edit.text_submitted.connect(_commit_burn_text.bind(_prograde_edit, _prograde, true))
	_radial_edit.text_submitted.connect(_commit_burn_text.bind(_radial_edit, _radial, false))
	_prograde_edit.focus_exited.connect(func() -> void: _commit_burn_text(_prograde_edit.text, _prograde_edit, _prograde, true))
	_radial_edit.focus_exited.connect(func() -> void: _commit_burn_text(_radial_edit.text, _radial_edit, _radial, false))
	_execute.pressed.connect(_execute_burn)
	_transmit_button.pressed.connect(_transmit)

	var warp_buttons: Array[Button] = [%Warp1, %Warp10, %Warp100, %Warp1000, %Warp10000, %Warp100000, %Warp1000000, %Warp10000000]
	for i in range(warp_buttons.size()):
		var factor: float = WARPS[i]
		warp_buttons[i].tooltip_text = str(i + 1)
		warp_buttons[i].pressed.connect(func() -> void:
			warp = factor
			paused = false
			_update_warp_state())

	%FocusEarth.pressed.connect(_focus_body.bind("earth", 2.0e7))
	%FocusMoon.pressed.connect(_focus_body.bind("moon", 4.0e7))
	%FocusShip.pressed.connect(_focus_ship)
	%FocusSystem.pressed.connect(_focus_body.bind("sun", 4.0 * 149597870700.0))
	%ZoomIn.pressed.connect(func() -> void: _view.zoom_by(1.5))
	%ZoomOut.pressed.connect(func() -> void: _view.zoom_by(1.0 / 1.5))
	_pause.tooltip_text = "Space"
	_execute.tooltip_text = "Enter"
	_auto_capture.tooltip_text = "A"
	_rewind.tooltip_text = "R"
	_transmit_button.tooltip_text = "T"
	_buy_hint.tooltip_text = "H"
	_next_hint.tooltip_text = "N"

	_rebuild_objectives()
	_update_prediction()
	_update_hud()
	_auto_capture.visible = _land_limit() <= 0.0
	_push_checkpoint(Localization.t("Launch"))
	_scan_encounters.call_deferred()

func _process(delta: float) -> void:
	if sim == null:
		return
	var dt: float = minf(delta, 0.1)
	if not paused and sim.phase != "DONE":
		_carry += warp * dt
		var unspent: float = sim.advance(_carry, STEP_BUDGET_MS)
		_carry = minf(unspent, warp * 0.25)
		if sim.phase == "DONE":
			paused = true
			_update_warp_state()
			if not _done_announced:
				_done_announced = true
				if sim.failure == "":
					EventBus.toast.emit(Localization.t("Objectives complete. END to file."))

	_predict_accum += dt
	if not paused and _predict_accum >= PREDICT_REFRESH:
		_predict_dirty = true
	if _predict_dirty and _predict_accum >= PREDICT_INTERVAL:
		_predict_accum = 0.0
		_predict_dirty = false
		_update_prediction()

	_hud_accum += dt
	if _hud_accum >= HUD_INTERVAL:
		_hud_accum = 0.0
		_update_hud()

	_log_accum += dt
	if _log_accum >= 0.4:
		_log_accum = 0.0
		_refresh_log()

	_save_accum += dt
	if _save_accum >= 8.0:
		_save_accum = 0.0
		save_now()

	_checkpoint_accum += dt
	if not paused and _checkpoint_accum >= CHECKPOINT_INTERVAL:
		_checkpoint_accum = 0.0
		_push_checkpoint("T+ %s" % Sim.format_met(sim.t))

func _select_encounter(body_id: String, radius: float) -> void:
	_encounter_target = body_id
	_solve_burn.disabled = false
	_focus_body(body_id, radius)


func _focus_body(body_id: String, radius: float) -> void:
	_view.focus(body_id)
	_view.fit_radius(radius)

func _focus_ship() -> void:
	_view.follow()
	_view.fit_radius(6.0e6)

func _toggle_pause() -> void:
	paused = not paused
	_baseline_valid = false
	_predict_dirty = true
	_update_warp_state()
	if paused:
		_scan_encounters.call_deferred()


func _set_warp(factor: float) -> void:
	warp = factor
	paused = false
	_update_warp_state()


func _step_warp(direction: int) -> void:
	var index := WARPS.find(warp)
	if index < 0:
		index = 0
	_set_warp(WARPS[clampi(index + direction, 0, WARPS.size() - 1)])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_8:
		_set_warp(WARPS[key.keycode - KEY_1])
	elif key.keycode == KEY_SPACE:
		_toggle_pause()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_execute_burn()
	elif key.keycode == KEY_A:
		_auto_plan_capture()
	elif key.keycode == KEY_R:
		_rewind_last()
	elif key.keycode == KEY_T:
		_transmit()
	elif key.keycode == KEY_H:
		_buy_hint_pressed()
	elif key.keycode == KEY_N:
		_cycle_hint()
	elif key.keycode == KEY_G:
		_scan_encounters()
	elif key.keycode == KEY_F:
		_solve_flyby_burn()
	elif key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
		_step_warp(1)
	elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
		_step_warp(-1)
	else:
		return
	get_viewport().set_input_as_handled()

func _skip_hour() -> void:
	sim.skip(3600.0)
	_baseline_valid = false
	_predict_dirty = true

func _update_warp_state() -> void:
	if _warp_state == null:
		return
	_warp_state.text = Localization.t("PAUSED") if paused else "%dx" % int(warp)

func _update_prediction() -> void:
	if not paused or not _baseline_valid:
		_view.path_baseline = sim.predict_preview(_preview_days)
		_baseline_valid = true
	var burn: Vector2 = _burn_vector()
	var key := "%d|%d|%d" % [int(burn.x), int(burn.y), int(sim.t / 60.0)]
	if key == _planned_key:
		return
	_planned_key = key
	if burn.length() > 0.5 and sim.can_afford(burn.length()):
		_view.path_planned = sim.predict_preview(_preview_days, burn)
	else:
		_view.path_planned = PackedVector2Array()

func _update_hud() -> void:
	var craft: CraftState = sim.craft
	_clock.text = "T+ %s  /  %s" % [Sim.format_met(sim.t),
		UiKit.jd_date((GameData.mission_start_t + sim.t) / 86400.0)]
	_mass.set_value(UiKit.kg(craft.wet_mass()))
	_fuel.set_value(UiKit.kg(craft.fuel_mass))
	var dv: float = craft.delta_v()
	_delta_v.set_value("%.0f m/s" % dv, UiKit.AMBER if dv < 500.0 else UiKit.TEXT)

	var target: CelestialBody = sim.target()
	if target != null:
		var rel: Dictionary = sim.universe.relative_state_xy(target.id, craft.px, craft.py, craft.vx, craft.vy, sim.t)
		_range.set_value(UiKit.dist(float(rel["dist"])))
		var altitude: float = float(rel["dist"]) - target.radius_m
		_altitude.set_value(UiKit.dist(altitude), UiKit.AMBER if altitude < 5000.0 else UiKit.TEXT)
		_rel_speed.set_value(UiKit.speed(float(rel["speed"])))
		var energy: float = 0.5 * pow(float(rel["speed"]), 2.0) - target.mu / maxf(float(rel["dist"]), 1.0)
		if sim.phase == "DONE":
			_status.text = Localization.t("MISSION COMPLETE" if sim.failure == "" else "MISSION FAILED")
			_status.add_theme_color_override("font_color", UiKit.GREEN if sim.failure == "" else UiKit.CRIMSON)
		elif sim.flags.has("capture"):
			_status.text = Localization.t("BOUND ORBIT")
			_status.add_theme_color_override("font_color", UiKit.GREEN)
		elif float(rel["dist"]) < target.soi_or_default():
			if _land_limit() > 0.0:
				var surface_alt: float = float(rel["dist"]) - target.radius_m
				_status.text = Localization.t("DESCENT  /  %s", [UiKit.dist(maxf(surface_alt, 0.0))])
				_status.add_theme_color_override("font_color",
					UiKit.CRIMSON if surface_alt < 5000.0 else UiKit.AMBER)
			else:
				_status.text = Localization.t("INSIDE %s SOI  /  %s", [
					Localization.t(target.display_name).to_upper(),
					Localization.t("BOUND" if energy < 0.0 else "HYPERBOLIC")])
				_status.add_theme_color_override("font_color", UiKit.GREEN if energy < 0.0 else UiKit.AMBER)
		elif paused:
			_status.text = Localization.t("PLANNING  /  PAUSED")
			_status.add_theme_color_override("font_color", UiKit.AMBER)
		else:
			_status.text = Localization.t("CRUISE  /  %dx", [int(warp)])
			_status.add_theme_color_override("font_color", UiKit.CYAN)
	else:
		_range.set_value("--")
		_altitude.set_value("--")

	var power: float = craft.power_available(sim.sun_distance())
	_power.set_value("%.0f W" % power, UiKit.CRIMSON if power < 0.0 else UiKit.TEXT)

	var target_orbit: Dictionary = {}
	var target_body: CelestialBody = sim.target()
	if target_body != null:
		var target_rel: Dictionary = sim.universe.relative_state_xy(
			target_body.id, craft.px, craft.py, craft.vx, craft.vy, sim.t)
		if float(target_rel["dist"]) < target_body.soi_or_default() * 3.0:
			target_orbit = sim.orbit_about(target_body.id, _burn_vector())
	if target_orbit.is_empty():
		_periapsis.set_value("--")
		_apoapsis.set_value("--")
	else:
		var alt_p: float = float(target_orbit["alt_rp"])
		_periapsis.set_value(UiKit.dist(alt_p), UiKit.CRIMSON if alt_p < 0.0 else UiKit.TEXT)
		if bool(target_orbit["bound"]):
			var alt_a: float = float(target_orbit["alt_ra"])
			_apoapsis.set_value(UiKit.dist(alt_a), UiKit.CRIMSON if alt_a < 0.0 else UiKit.TEXT)
		else:
			_apoapsis.set_value(Localization.t("escape"), UiKit.AMBER)

	if not target_orbit.is_empty() and sim.phase != "DONE":
		if float(target_orbit["alt_rp"]) < 0.0 and not _impact_warned:
			_impact_warned = true
			if _land_limit() <= 0.0:
				paused = true
				sim.request_halt()
				_update_warp_state()
				EventBus.toast.emit(Localization.t("IMPACT TRAJECTORY. REWIND or raise periapsis."))

	var burn: Vector2 = _burn_vector()
	var affordable: bool = sim.can_afford(burn.length())
	_execute.disabled = burn.length() < 0.5 or not affordable or sim.phase == "DONE"
	if burn.length() < 0.5:
		_burn_summary.text = Localization.t("No burn planned. Set PROGRADE negative to brake.") \
			if _land_limit() > 0.0 else Localization.t("No burn planned. AUTO-PLAN CAPTURE or 100kx.")
		_burn_summary.add_theme_color_override("font_color", UiKit.MUTED)
	else:
		_burn_summary.text = Localization.t("Planned burn: %.0f m/s  /  %.0f m/s left", [burn.length(), dv])
		_burn_summary.add_theme_color_override("font_color",
			UiKit.CRIMSON if not affordable else UiKit.TEXT)

	if target != null:
		var in_range: bool = float(sim.universe.relative_state_xy(target.id, craft.px, craft.py, craft.vx, craft.vy, sim.t)["dist"]) <= mission.science_range_m
		if sim.flags.has("science"):
			_science_state.text = Localization.t("DSN: relay active")
			_transmit_button.disabled = true
		elif in_range and craft.has_science():
			_science_state.text = Localization.t("DSN: in range")
			_transmit_button.disabled = false
		else:
			_science_state.text = Localization.t("DSN: %s", [
				Localization.t("no payload") if not craft.has_science() else Localization.t("out of range")])
			_transmit_button.disabled = true

	_refresh_hint()


func _frame_basis() -> Dictionary:
	var frame_body: String = sim.universe.body_radius_influence_xy(sim.craft.px, sim.craft.py, sim.t)
	if frame_body == "":
		frame_body = "sun"
	var rel: Dictionary = sim.universe.relative_state_xy(frame_body, sim.craft.px, sim.craft.py, sim.craft.vx, sim.craft.vy, sim.t)
	var prograde: Vector2 = (rel["vel"] as Vector2).normalized()
	if prograde.length() < 0.5:
		prograde = Vector2.RIGHT
	var outward: Vector2 = rel["pos"]
	var radial: Vector2 = outward - prograde * outward.dot(prograde)
	if radial.length() < 0.5:
		radial = prograde.orthogonal()
	radial = radial.normalized()
	return {"body": frame_body, "prograde": prograde, "radial": radial}

func _hints() -> Array:
	var out: Array = []
	if mission == null or sim == null:
		return out
	var craft: CraftState = sim.craft
	var target: CelestialBody = sim.target()
	if sim.phase == "DONE":
		out.append("Mission over. Press END to file the report.")
	elif target != null:
		var rel: Dictionary = sim.universe.relative_state_xy(
			target.id, craft.px, craft.py, craft.vx, craft.vy, sim.t)
		var dist: float = float(rel["dist"])
		if dist >= target.soi_or_default():
			out.append("Increase warp. The sim pauses at closest approach.")
		else:
			var orbit: Dictionary = sim.orbit_about(target.id)
			if not orbit.is_empty() and float(orbit["alt_rp"]) < 0.0:
				if _land_limit() > 0.0:
					out.append(Localization.t("Descent. Brake before touchdown."))
				else:
					out.append("Impact path. Press REWIND, or raise PERIAPSIS.")
			elif bool(orbit.get("bound", false)):
				if _land_limit() > 0.0:
					out.append(Localization.t("Descent. Brake before touchdown."))
				elif dist <= mission.science_range_m and craft.has_science() and not sim.flags.has("science"):
					out.append("In range. Press TRANSMIT SCIENCE.")
				else:
					out.append("Bound orbit. Use AUTO-PLAN at an apsis to circularize, or press END.")
			else:
				out.append("Flyby. At closest approach, press AUTO-PLAN to capture.")
	for h in sim.hint_notes:
		out.append(str(h))
	for h in mission.hints:
		out.append(str(h))
	out.append("PROGRADE at periapsis raises APOAPSIS.")
	out.append("RETROGRADE at periapsis lowers APOAPSIS.")
	out.append("PROGRADE at apoapsis raises PERIAPSIS.")
	out.append("RADIAL shifts the aim point. Watch PERIAPSIS and APOAPSIS.")
	out.append("To burn: type a number in PROGRADE, then press EXECUTE BURN.")
	out.append("Negative PROGRADE burns backwards (retrograde).")
	out.append("Experiment freely. REWIND undoes the last burn.")
	return out

func _numeric_hint() -> String:
	if sim == null or mission == null:
		return ""
	var target: CelestialBody = sim.target()
	if target == null:
		return ""
	var craft: CraftState = sim.craft
	var rel: Dictionary = sim.universe.relative_state_xy(
		target.id, craft.px, craft.py, craft.vx, craft.vy, sim.t)
	var dist: float = float(rel["dist"])
	var soi: float = target.soi_or_default()
	var rel_speed: float = float(rel["speed"])

	if dist < soi:
		var limit := _land_limit()
		if limit > 0.0:
			var gained: float = 2.0 * target.mu * (1.0 / target.radius_m - 1.0 / maxf(dist, 1.0))
			if gained > limit * limit:
				var g_surface: float = target.mu / pow(maxf(target.radius_m, 1.0), 2.0)
				var safe_alt: float = limit * limit / maxf(2.0 * g_surface, 0.001)
				return Localization.t("Descend below %.1f km, then brake.", [safe_alt / 1000.0])
			var allowed: float = sqrt(maxf(limit * limit - gained, 0.0))
			var brake: float = maxf(rel_speed - allowed, 0.0)
			if brake > 0.5:
				return _hint_budget(Localization.t("Brake %.0f m/s to reach %.0f m/s at touchdown.", [brake, limit]), brake)
			return Localization.t("Speed is safe for touchdown. Let it fall.")
		var orbit: Dictionary = sim.orbit_about(target.id)
		if not orbit.is_empty() and bool(orbit["bound"]):
			var v_circ: float = sqrt(target.mu / maxf(float(orbit["r"]), 1.0))
			var dv: float = float(orbit["speed"]) - v_circ
			if dv > 0.5:
				return _hint_budget(Localization.t("Circularize: burn %.0f m/s retrograde at periapsis.", [dv]), dv)
			return Localization.t("The orbit is nearly circular. Transmit your science or press END.")
		var v_circ2: float = sqrt(target.mu / maxf(dist, 1.0))
		var dv2: float = rel_speed - v_circ2
		if dv2 > 0.5:
			return _hint_budget(Localization.t("Capture: burn %.0f m/s retrograde at closest approach.", [dv2]), dv2)
		return Localization.t("No capture burn is needed. You are already in a bound orbit.")

	var start_body: CelestialBody = sim.universe.body(mission.start_body)
	var still_home := true
	if start_body != null:
		var home_dist: float = sim.universe.distance_to(
			mission.start_body, craft.px, craft.py, sim.t)
		still_home = home_dist < start_body.soi_or_default()

	if still_home and target.parent_id == mission.start_body and start_body != null \
			and sim.phase == "PLANNING":
		var r1: float = start_body.radius_m + mission.start_altitude_m
		var tp: Vector2 = sim.universe.pos_at(target.id, sim.t)
		var r2: float = sim.universe.distance_to(mission.start_body, tp.x, tp.y, sim.t)
		if r2 > r1:
			var dv: float = sqrt(start_body.mu / r1) * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)
			return _hint_budget(Localization.t("Trans-lunar injection: burn %.0f m/s prograde. Type it in PROGRADE and press EXECUTE BURN.", [dv]), dv)

	if still_home and target.parent_id != mission.start_body:
		var sun: CelestialBody = sim.universe.body("sun")
		var parent: CelestialBody = sim.universe.body(target.parent_id)
		var r2: float = target.a_m if target.parent_id == "sun" else (
			parent.a_m if parent != null else 0.0)
		if sun != null and start_body != null and r2 > 0.0:
			var r1: float = sim.universe.distance_to("sun", craft.px, craft.py, sim.t)
			if r2 > r1 * 0.2 and r2 != r1:
				var dv_h: float = sqrt(sun.mu / r1) * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)
				var r_leo: float = start_body.radius_m + mission.start_altitude_m
				var v_escape: float = sqrt(2.0 * start_body.mu / r_leo)
				var v_circular: float = sqrt(start_body.mu / r_leo)
				var departure: float = sqrt(v_escape * v_escape + dv_h * dv_h) - v_circular
				return _hint_budget(Localization.t(
					"Departure burn: %.0f m/s PROGRADE. Type it in PROGRADE and press EXECUTE BURN. This burn escapes Earth and sends you toward %s.",
					[departure, Localization.t(target.display_name)]), departure)

	if dist > soi * 5.0:
		var closing: float = -((rel["pos"] as Vector2).dot(rel["vel"] as Vector2)) / maxf(dist, 1.0)
		var eta: float = dist / maxf(absf(closing), 1.0) / 86400.0
		return Localization.t("Coast to %s: %.0f km away, about %.1f days. Increase warp and wait.", [
			Localization.t(target.display_name), dist / 1000.0, eta])

	var v_inf: float = sqrt(maxf(rel_speed * rel_speed
		- 2.0 * target.mu / maxf(dist, 1.0), 0.0))
	var rp: float = target.radius_m + maxf(target.radius_m * 0.03, 50000.0)
	var v_peri: float = sqrt(v_inf * v_inf + 2.0 * target.mu / rp)
	var v_c: float = sqrt(target.mu / rp)
	return Localization.t("Arriving at %.2f km/s. At closest approach, burn about %.0f m/s retrograde to capture.", [
		v_inf / 1000.0, maxf(v_peri - v_c, 0.0)])

func _hint_budget(text: String, need: float) -> String:
	var have: float = sim.craft.delta_v()
	if need > have + 0.5:
		return text + "\n\n" + Localization.t(
			"Not enough delta-v: need %.0f m/s, have %.0f m/s. Go back and add propellant or a bigger engine.",
			[need, have])
	return text

func _land_limit() -> float:
	for raw in mission.objectives:
		var d: Dictionary = raw
		if str(d.get("kind", "")) == "land":
			return float(d.get("value", 40.0))
	return 0.0

func _buy_hint_pressed() -> void:
	var text := _numeric_hint()
	if text.is_empty():
		EventBus.toast.emit(Localization.t("No burn hint for this phase."))
		return
	sim.hint_penalty += 5.0
	sim.hint_notes.append(text)
	_hint_line.text = text
	EventBus.toast.emit(Localization.t("Hint purchased: -5 pts."))
	_refresh_hint()

func _refresh_hint() -> void:
	if _hint_line == null:
		return
	var list := _hints()
	if list.is_empty():
		_hint_line.text = "--"
		return
	_hint_index = _hint_index % list.size()
	_hint_line.text = Localization.translate_any(str(list[_hint_index]))

func _cycle_hint() -> void:
	var list := _hints()
	if list.is_empty():
		return
	_hint_index = (_hint_index + 1) % list.size()
	_hint_line.text = Localization.translate_any(str(list[_hint_index]))

func _burn_vector() -> Vector2:
	if absf(_pro_mps) < 0.5 and absf(_rad_mps) < 0.5:
		return Vector2.ZERO
	var basis := _frame_basis()
	return (basis["prograde"] as Vector2) * _pro_mps + (basis["radial"] as Vector2) * _rad_mps

func _on_burn_slider(_value: float) -> void:
	_pro_mps = _prograde.value
	_rad_mps = _radial.value
	_refresh_burn_text()
	_predict_dirty = true

func _commit_burn_text(text: String, _edit: LineEdit, slider: HSlider, is_prograde: bool) -> void:
	var typed: float = text.strip_edges().to_float()
	if typed == 0.0 and not text.strip_edges().is_valid_float():
		_refresh_burn_text()
		return
	typed = clampf(typed, slider.min_value, slider.max_value)
	slider.set_value_no_signal(typed)
	if is_prograde:
		_pro_mps = typed
	else:
		_rad_mps = typed
	_refresh_burn_text()
	_predict_dirty = true
	_edit.release_focus()

func _burn_text(v: float) -> String:
	var rounded: float = roundf(v)
	if absf(v - rounded) < 0.05:
		return "%d" % int(rounded)
	return "%.1f" % v

func _refresh_burn_text() -> void:
	if not _prograde_edit.has_focus():
		_prograde_edit.text = _burn_text(_pro_mps)
	if not _radial_edit.has_focus():
		_radial_edit.text = _burn_text(_rad_mps)

func _execute_burn() -> void:
	var burn: Vector2 = _burn_vector()
	if burn.length() >= 0.5:
		_push_checkpoint(Localization.t("Before burn at T+ %s", [Sim.format_met(sim.t)]))
	var result: Dictionary = sim.execute_burn(burn)
	if bool(result.get("ok", false)):
		sim.phase = "FLIGHT"
		paused = true
		_impact_warned = false
		sim.reset_periapsis_watch()
		_pro_mps = 0.0
		_rad_mps = 0.0
		_prograde.set_value_no_signal(0.0)
		_radial.set_value_no_signal(0.0)
		_refresh_burn_text()
		_predict_dirty = true
		_baseline_valid = false
		_update_warp_state()
		_refresh_log()
		Audio.burn()
		EventBus.toast.emit(Localization.t("Burn %.0f m/s.", [burn.length()]))
		_scan_encounters.call_deferred(burn.length() >= 200.0)
	else:
		Audio.ui_error()
		EventBus.toast.emit(Localization.translate_any(str(result.get("reason", "Burn failed"))))

func _transmit() -> void:
	var result: Dictionary = sim.transmit_science()
	if bool(result.get("ok", false)):
		Audio.transmit()
	else:
		Audio.ui_error()
	_science_state.text = Localization.t("DSN: %s", [Localization.translate_any(str(result.get("reason", "")))])
	_refresh_log()

func _scan_encounters(force: bool = false) -> void:
	if sim == null or _encounters == null:
		return
	for child in _encounters.get_children():
		_encounters.remove_child(child)
		child.queue_free()
	_encounter_target = ""
	_solve_burn.disabled = true
	var horizon: float = maxf(mission.duration_days, 30.0)
	var burn: Vector2 = _burn_vector()
	var here: String = sim.universe.body_radius_influence_xy(sim.craft.px, sim.craft.py, sim.t)
	var found: Array = []
	var parked: bool = not force and burn.length() < 0.5 and here == mission.start_body
	if not parked:
		found = sim.encounters(horizon, burn, 4)
	_view.encounter_marks = found
	if found.is_empty():
		var text := Localization.t("Leave parking orbit to scan for flybys.") if parked else \
			Localization.t("No close approaches in the next %d days.", [int(horizon)])
		var empty := UiKit.label(text, 10, UiKit.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_encounters.add_child(empty)
		return
	for raw in found:
		var e: Dictionary = raw
		var id := str(e.get("id", ""))
		var body: CelestialBody = sim.universe.body(id)
		if body == null:
			continue
		var span: float = maxf(body.soi_or_default() * 4.0, 1.0e8)
		var row := Button.new()
		row.flat = true
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 22)
		row.add_theme_font_size_override("font_size", 10)
		row.add_theme_color_override("font_color", UiKit.TEXT)
		row.add_theme_color_override("font_hover_color", UiKit.AMBER)
		row.text = Localization.t("%s  /  T+%.0f d  /  %s  /  %s", [
			Localization.t(body.display_name).to_upper(), float(e.get("t", 0.0)) / 86400.0,
			UiKit.dist(float(e.get("dist", 0.0))), UiKit.speed(float(e.get("speed", 0.0)))])
		row.tooltip_text = Localization.t("Focus %s", [Localization.t(body.display_name)])
		row.pressed.connect(_select_encounter.bind(id, span))
		UiKit.attach_hover(row, UiKit.AMBER)
		_encounters.add_child(row)

func _score_flyby(body: CelestialBody, horizon: float, pro: float, rad: float,
		target_dist: float) -> Dictionary:
	var basis := _frame_basis()
	var burn: Vector2 = (basis["prograde"] as Vector2) * pro + (basis["radial"] as Vector2) * rad
	var hits: Array = sim.encounters(horizon, burn, 1, body.id)
	if hits.is_empty():
		return {"score": INF, "dist": INF, "pro": pro, "rad": rad}
	var e: Dictionary = hits[0]
	var dist: float = float(e["dist"])
	var gap: float = dist - target_dist
	var score: float = gap if gap >= 0.0 else -gap * 8.0
	return {"score": score + burn.length() * 0.0001,
		"dist": dist, "safe": dist >= target_dist, "speed": float(e["speed"]),
		"t": float(e["t"]), "pro": pro, "rad": rad}

func _solve_flyby_burn() -> void:
	if _solving or sim == null or _encounter_target == "":
		return
	var body: CelestialBody = sim.universe.body(_encounter_target)
	if body == null:
		return
	_solving = true
	paused = true
	_baseline_valid = false
	_predict_dirty = true
	_update_warp_state()
	_solve_burn.disabled = true
	var restore := Localization.t("SOLVE BURN")
	_solve_burn.text = Localization.t("Solving...")
	var horizon: float = maxf(mission.duration_days, 30.0)
	var target_dist: float = maxf(body.radius_m * 1.2, 50000.0)
	var pro: float = clampf(_pro_mps, _prograde.min_value, _prograde.max_value)
	var rad: float = clampf(_rad_mps, _radial.min_value, _radial.max_value)
	await get_tree().process_frame
	var best := _score_flyby(body, horizon, pro, rad, target_dist)
	if is_finite(float(best["score"])):
		horizon = minf(horizon, maxf(float(best["t"]) / 86400.0 * 1.15, 30.0))
		best = _score_flyby(body, horizon, pro, rad, target_dist)
	var speed: float = maxf(float(best.get("speed", 0.0)), 1.0)
	var base_step: float = clampf(absf(float(best["dist"]) - target_dist) / speed, 0.1, 1500.0)
	var scales: Array = [1.0, 0.3, 0.09, 0.03, 0.01]
	var tolerance: float = maxf(5000.0, target_dist * 0.002)
	for scale in scales:
		var step: float = maxf(base_step * float(scale), 0.05)
		for _pass in range(1):
			var improved := false
			var candidates: Array = [
				[pro + step, rad], [pro - step, rad],
				[pro, rad + step * 0.5], [pro, rad - step * 0.5]]
			for cand in candidates:
				var cp: float = clampf(float(cand[0]), _prograde.min_value, _prograde.max_value)
				var cr: float = clampf(float(cand[1]), _radial.min_value, _radial.max_value)
				var score := _score_flyby(body, horizon, cp, cr, target_dist)
				await get_tree().process_frame
				if float(score["score"]) < float(best["score"]) - 1.0:
					best = score
					pro = cp
					rad = cr
					improved = true
			if not improved or float(best["score"]) <= tolerance:
				break
		if float(best["score"]) <= tolerance:
			break
	_pro_mps = float(best["pro"])
	_rad_mps = float(best["rad"])
	_prograde.set_value_no_signal(_pro_mps)
	_radial.set_value_no_signal(_rad_mps)
	_refresh_burn_text()
	_predict_dirty = true
	_baseline_valid = false
	_update_prediction()
	_solve_burn.text = restore
	_scan_encounters(true)
	_solving = false
	if not is_finite(float(best["score"])):
		EventBus.toast.emit(Localization.t("No burn found for this flyby."))
	elif float(best["dist"]) < body.radius_m:
		EventBus.toast.emit(Localization.t("Best burn still hits %s. Try another flyby.",
			[Localization.t(body.display_name)]))
	else:
		EventBus.toast.emit(Localization.t("Solved %s: %+.0f / %+.0f m/s, miss %.0f km.", [
			Localization.t(body.display_name), _pro_mps, _rad_mps, float(best["dist"]) / 1000.0]))

func _rebuild_objectives() -> void:
	for child in _objectives.get_children():
		child.queue_free()
	for raw in mission.objectives:
		var o: Dictionary = raw
		var oid := str(o.get("id", ""))
		var row: ObjectiveRow = OBJECTIVE_ROW.instantiate()
		_objectives.add_child(row)
		row.setup(str(o.get("label", oid)), str(o.get("detail", "")),
			int(o.get("points", 0)), sim.flags.has(oid))

func _on_objective(_id: String) -> void:
	Audio.ui_confirm()
	_rebuild_objectives()
	_refresh_log()

func _on_failure(reason: String) -> void:
	Audio.explosion()
	Audio.play_voice(Localization.voice_path("callout_impact"), "Impact trajectory. Rewind, or raise periapsis.")
	paused = true
	save_now()
	_update_warp_state()
	_status.text = Localization.t("MISSION FAILED")
	_status.add_theme_color_override("font_color", UiKit.CRIMSON)
	_refresh_log()
	EventBus.toast.emit(Localization.t("%s. REWIND available.", [Localization.translate_any(reason)]))

func _refresh_log() -> void:
	if _log == null:
		return
	var lines: Array = sim.log_lines.slice(maxi(sim.log_lines.size() - 6, 0))
	var shown: Array = []
	for line in lines:
		shown.append(Localization.translate_any(str(line)))
	_log.text = "\n".join(shown)

func _end_mission() -> void:
	Audio.ui_confirm()
	var success: bool = sim.failure == "" and sim.objectives_complete()
	var report: Dictionary = sim.report(success)
	GameState.record_report(report)
	EventBus.end_flight.emit(report)

func _on_approach(_body_id: String, _dist: float) -> void:
	_push_checkpoint(Localization.t("SOI entry at T+ %s", [Sim.format_met(sim.t)]))

func _on_periapsis(body_id: String, dist: float) -> void:
	paused = true
	sim.request_halt()
	_carry = 0.0
	_baseline_valid = false
	_predict_dirty = true
	_update_warp_state()
	_push_checkpoint(Localization.t("Closest approach at T+ %s", [Sim.format_met(sim.t)]))
	Audio.play_voice(Localization.voice_path("callout_approach"), "Closest approach. Capture window open.")
	var body: CelestialBody = sim.universe.body(body_id)
	var name: String = body.display_name if body != null else body_id
	_auto_plan_capture(Localization.t("Closest approach %s: %.0f km", [Localization.t(name), dist / 1000.0]))

func _auto_plan_capture(prefix: String = "") -> void:
	var target: CelestialBody = sim.target()
	if target == null:
		return
	var rel: Dictionary = sim.universe.relative_state_xy(
		target.id, sim.craft.px, sim.craft.py, sim.craft.vx, sim.craft.vy, sim.t)
	var dist: float = float(rel["dist"])
	if dist > target.soi_or_default():
		EventBus.toast.emit(Localization.t("Outside %s SOI (%.0f km to entry).", [
			Localization.t(target.display_name), (dist - target.soi_or_default()) / 1000.0]))
		return
	var orbit: Dictionary = sim.orbit_about(target.id)
	if orbit.is_empty():
		return
	var r: float = float(orbit["r"])
	if bool(orbit["bound"]):
		var rp: float = float(orbit["rp"])
		var ra: float = float(orbit["ra"])
		var v_circ: float = sqrt(target.mu / maxf(r, 1.0))
		var speed_now: float = float(orbit["speed"])
		if r >= ra * 0.97 and v_circ > speed_now + 0.5:
			var up_dv: float = v_circ - speed_now
			if _apply_burn_vector((rel["vel"] as Vector2).normalized() * up_dv):
				EventBus.toast.emit(Localization.t("Circularize +%.0f m/s at apoapsis.", [up_dv]))
			return
		if r <= rp * 1.05:
			var circ_dv: float = maxf(speed_now - v_circ, 0.0)
			if circ_dv < 0.5:
				EventBus.toast.emit(Localization.t("Already near-circular."))
				return
			if _apply_burn_vector(-((rel["vel"] as Vector2).normalized()) * circ_dv):
				EventBus.toast.emit(Localization.t("Circularize %.0f m/s at periapsis.", [circ_dv]))
			return
		EventBus.toast.emit(Localization.t("Coast to periapsis (%.0f km). 100kx.", [
			(rp - target.radius_m) / 1000.0]))
		return

	var v_circ: float = sqrt(target.mu / maxf(r, 1.0))
	var pos: Vector2 = rel["pos"]
	var vel: Vector2 = rel["vel"]
	var tangent: Vector2 = Vector2(-pos.y, pos.x).normalized()
	if tangent.dot(vel) < 0.0:
		tangent = -tangent
	var rp_a: float = minf(target.radius_m + _safe_periapsis_altitude(target), r)
	var ra_b: float = maxf(r, minf(target.soi_or_default() * 0.45, r * 4.0))
	var v_a: float = sqrt(target.mu * (2.0 / r - 1.0 / ((r + rp_a) * 0.5)))
	var v_b: float = sqrt(target.mu * (2.0 / r - 1.0 / ((r + ra_b) * 0.5)))
	var dv_a: Vector2 = tangent * v_a - vel
	var dv_b: Vector2 = tangent * v_b - vel
	var dv_vec: Vector2 = dv_a if dv_a.length() <= dv_b.length() else dv_b
	var dv: float = dv_vec.length()
	if dv < 0.5:
		EventBus.toast.emit(Localization.t("No burn needed."))
		return
	var preview: Dictionary = sim.orbit_about(target.id, dv_vec)
	if _apply_burn_vector(dv_vec):
		var msg: String = Localization.t("Capture %.0f m/s. Apo %.0f km / Peri %.0f km.", [
			dv, float(preview.get("alt_ra", 0.0)) / 1000.0,
			float(preview.get("alt_rp", 0.0)) / 1000.0])
		if prefix != "":
			msg = prefix + "  /  " + msg
		EventBus.toast.emit(msg)

func _safe_periapsis_altitude(target: CelestialBody) -> float:
	return maxf(target.radius_m * 0.03, maxf(target.atmosphere_top_m + 20000.0, 20000.0))

func _apply_burn_vector(dv_vec: Vector2) -> bool:
	var magnitude: float = dv_vec.length()
	if not sim.can_afford(magnitude):
		EventBus.toast.emit(Localization.t("Need %.0f m/s, have %.0f.", [
			magnitude, sim.craft.delta_v()]))
		return false
	var basis := _frame_basis()
	var pro: float = dv_vec.dot(basis["prograde"])
	var rad: float = dv_vec.dot(basis["radial"])
	var pro_limit: float = maxf(absf(_prograde.min_value), absf(_prograde.max_value))
	var rad_limit: float = maxf(absf(_radial.min_value), absf(_radial.max_value))
	if absf(pro) > pro_limit or absf(rad) > rad_limit:
		EventBus.toast.emit(Localization.t("Burn beyond slider. Type it."))
		return false
	_pro_mps = pro
	_rad_mps = rad
	_prograde.set_value_no_signal(pro)
	_radial.set_value_no_signal(rad)
	_refresh_burn_text()
	_predict_dirty = true
	return true

func _push_checkpoint(label: String) -> void:
	if sim == null or sim.phase == "DONE":
		return
	_checkpoints.append({"label": label, "sim": sim.snapshot()})
	while _checkpoints.size() > CHECKPOINT_KEEP:
		_checkpoints.pop_front()
	_update_rewind()

func _update_rewind() -> void:
	if _rewind != null:
		_rewind.disabled = _checkpoints.is_empty()

func _rewind_last() -> void:
	if _checkpoints.is_empty():
		return
	GameState.rewinds_used += 1
	GameState.evaluate_achievements(true)
	Audio.stop_voice()
	Audio.rewind()
	var cp: Dictionary = _checkpoints.pop_back()
	sim.restore(cp.get("sim", {}))
	paused = true
	_impact_warned = false
	_carry = 0.0
	_baseline_valid = false
	_predict_dirty = true
	_planned_key = ""
	_save_accum = 0.0
	_done_announced = false
	_rebuild_objectives()
	_refresh_log()
	_update_prediction()
	_update_hud()
	_update_warp_state()
	_update_rewind()
	EventBus.toast.emit(Localization.t("Rewind: %s.", [str(cp.get("label", "checkpoint"))]))
	_scan_encounters.call_deferred()

func _confirm_exit() -> void:
	paused = true
	save_now()
	EventBus.open_hangar.emit(mission)

func save_now() -> void:
	if sim == null or mission == null:
		return
	GameState.save_flight({
		"mission_id": mission.id,
		"mission_name": mission.display_name,
		"target_body": mission.target_body,
		"met": sim.t,
		"phase": sim.phase,
		"paused": paused,
		"warp": warp,
		"sim": sim.snapshot(),
	})
	_save_accum = 0.0

func request_exit() -> void:
	_confirm_exit()
