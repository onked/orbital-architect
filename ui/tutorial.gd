class_name FlightSchool
extends PanelContainer

# This script handles stuff for the tutorial (flight school)
const STEPS_PATH := "res://data/tutorial.json"
const MISSIONS := ["lunar_relay", "flight_school_landing"]

var steps: Array = []
var index: int = 0
var active: bool = false

var _screen: Node = null
var _poll: float = 0.0
var _pulse: float = 0.0
var _marker: ReferenceRect = null
var _marker_target: Control = null
var _voiced_id: String = ""

@onready var _kicker: Label = %Kicker
@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _progress: ProgressBar = %Progress
@onready var _next: Button = %Next
@onready var _skip: Button = %Skip

func _ready() -> void:
	steps = _load_steps()
	active = not GameState.tutorial_done
	index = clampi(GameState.tutorial_index, 0, maxi(steps.size() - 1, 0))
	visible = false
	_next.pressed.connect(_advance)
	_skip.pressed.connect(_skip_all)

func _load_steps() -> Array:
	if not FileAccess.file_exists(STEPS_PATH):
		push_warning("Flight School steps missing at %s" % STEPS_PATH)
		return []
	var file := FileAccess.open(STEPS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []

func restart() -> void:
	steps = _load_steps()
	index = 0
	active = true
	GameState.tutorial_done = false
	GameState.tutorial_index = 0
	GameState.save_campaign()
	_clear_marker()
	_refresh()

func set_screen(screen: Node) -> void:
	_screen = screen
	_clear_marker()
	_refresh()

func _process(delta: float) -> void:
	if not active:
		return
	_pulse += delta
	if _marker != null and is_instance_valid(_marker):
		_marker.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_pulse * 4.0))
	_poll += delta
	if _poll < 0.2:
		return
	_poll = 0.0
	_refresh()

func _refresh() -> void:
	if not active:
		visible = false
		_clear_marker()
		_stop_step_voice()
		return
	var mission: Variant = _screen.get("mission") if _screen != null else null
	if mission is MissionDef and not MISSIONS.has((mission as MissionDef).id):
		visible = false
		_clear_marker()
		return
	var guard := 0
	var start_index := index
	while index < steps.size() and _done(steps[index]) and guard < steps.size():
		index += 1
		guard += 1
	if index != start_index:
		GameState.tutorial_index = index
		GameState.save_campaign()
	if index >= steps.size():
		_finish()
		return

	var step: Dictionary = steps[index]
	if _screen == null or str(step.get("screen", "")) != _screen_name():
		visible = false
		_clear_marker()
		_stop_step_voice()
		return
	var step_mission := str(step.get("mission", ""))
	var current_mission := _mission_id()
	if step_mission != "" and current_mission != "" and step_mission != current_mission:
		visible = false
		_clear_marker()
		_stop_step_voice()
		return

	visible = true
	_kicker.text = Localization.t("FLIGHT SCHOOL  /  %d OF %d", [index + 1, steps.size()])
	_title.text = Localization.t(str(step.get("title", "")))
	_body.text = Localization.t(str(step.get("body", "")))
	_progress.max_value = steps.size()
	_progress.value = index + 1
	_highlight(str(step.get("node", "")))
	var cue_title := str(step.get("title", ""))
	var cue_body := str(step.get("body", ""))
	var cue := "%s. %s" % [cue_title, cue_body]
	if str(step.get("id", "")) == "build":
		cue = "Welcome to Orbit Architect. " + cue
	_play_step_voice(str(step.get("id", "")), cue)

func _play_step_voice(id: String, subtitle: String) -> void:
	if id == "" or id == _voiced_id:
		return
	_voiced_id = id
	Audio.play_voice(Localization.voice_path("tutorial_%s" % id), subtitle)

func _stop_step_voice() -> void:
	if _voiced_id == "":
		return
	var expected := Localization.voice_path("tutorial_%s" % _voiced_id)
	_voiced_id = ""
	if Audio.voice_path() == expected:
		Audio.stop_voice()

func _screen_name() -> String:
	if _screen == null:
		return ""
	var n := String(_screen.name).to_lower()
	if n.begins_with("@"):
		return ""
	if n == "flight":
		return "sim"
	return n

func _done(step: Dictionary) -> bool:
	var id := str(step.get("id", ""))
	var screen_now := _screen_name()
	var step_mission := str(step.get("mission", ""))
	if step_mission != "" and _mission_id() != "" and step_mission != _mission_id():
		return false
	match id:
		"build":
			return screen_now == "sim" or screen_now == "debrief"
		"tli":
			var s := _sim()
			return s != null and s.phase != "PLANNING"
		"coast":
			var s := _sim()
			return s != null and s.t > 7200.0
		"approach":
			var s := _sim()
			return s != null and (bool(s.get("_periapsis_flagged")) or s.flags.has("capture")) \
				or screen_now == "debrief"
		"capture":
			return _flag("capture") or screen_now == "debrief"
		"circular":
			return _circular() or _flag("capture") and _eccentric() < 0.2
		"science":
			return _flag("science") or screen_now == "debrief"
		"debrief":
			return screen_now == "debrief"
		"landing_ready":
			return _mission_id() == "flight_school_landing" \
				and _screen_name() in ["hangar", "sim", "debrief"]
		"land_build":
			return screen_now == "sim" or screen_now == "debrief"
		"land_fall":
			return _land_altitude() < 1000.0 or screen_now == "debrief"
		"land_brake":
			return _flag("land") or screen_now == "debrief"
		"land_end":
			return screen_now == "debrief"
	return false

func _mission_id() -> String:
	if _screen == null:
		return ""
	var value: Variant = _screen.get("mission")
	if value is MissionDef:
		return (value as MissionDef).id
	return ""

func _land_altitude() -> float:
	var s := _sim()
	if s == null or s.mission == null:
		return 1.0e12
	var target: CelestialBody = s.target()
	if target == null:
		return 1.0e12
	var rel: Dictionary = s.universe.relative_state_xy(
		target.id, s.craft.px, s.craft.py, s.craft.vx, s.craft.vy, s.t)
	return float(rel["dist"]) - target.radius_m

func _sim() -> Sim:
	if _screen == null:
		return null
	var value: Variant = _screen.get("sim")
	return value as Sim

func _flag(id: String) -> bool:
	var s := _sim()
	return s != null and s.flags.has(id)

func _eccentric() -> float:
	var s := _sim()
	if s == null or s.mission == null:
		return 1.0
	var o: Dictionary = s.orbit_about(s.mission.target_body)
	if o.is_empty() or not bool(o.get("bound", false)):
		return 1.0
	var rp: float = float(o.get("rp", 1.0))
	var ra: float = float(o.get("ra", 1.0))
	return (ra - rp) / maxf(ra + rp, 1.0)

func _circular() -> bool:
	var s := _sim()
	if s == null:
		return false
	var o: Dictionary = s.orbit_about(s.mission.target_body)
	return not o.is_empty() and bool(o.get("bound", false)) and _eccentric() < 0.2

func _highlight(node_name: String) -> void:
	if node_name == "":
		_clear_marker()
		return
	var target := _find(node_name)
	if target == null:
		_clear_marker()
		return
	if _marker != null and is_instance_valid(_marker) and _marker_target == target:
		return
	_clear_marker()
	var marker := ReferenceRect.new()
	marker.border_color = UiKit.AMBER
	marker.border_width = 2.0
	marker.editor_only = false
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.modulate = Color(1, 1, 1, 0.8)
	target.add_child(marker)
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker = marker
	_marker_target = target

func _find(node_name: String) -> Control:
	if _screen == null:
		return null
	var node := _screen.get_node_or_null("%" + node_name)
	return node as Control

func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	_marker_target = null

func _advance() -> void:
	if index >= steps.size() - 1:
		_finish()
		return
	index += 1
	GameState.tutorial_index = index
	GameState.save_campaign()
	_clear_marker()
	_refresh()

func _skip_all() -> void:
	active = false
	visible = false
	_clear_marker()
	_stop_step_voice()
	Audio.play_voice(Localization.voice_path("callout_school"), "Flight School complete. Good flying.")
	GameState.tutorial_done = true
	GameState.tutorial_index = 0
	GameState.save_campaign()

func _finish() -> void:
	active = false
	visible = false
	_clear_marker()
	_stop_step_voice()
	GameState.tutorial_done = true
	GameState.tutorial_index = 0
	GameState.save_campaign()
	GameState.evaluate_achievements(true)
	EventBus.toast.emit(Localization.t("Flight School complete"))
