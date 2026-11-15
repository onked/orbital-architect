extends Control

@onready var _header: ScreenHeader = %Header
@onready var _name: LineEdit = %NameField
@onready var _target: OptionButton = %Target
@onready var _objective: OptionButton = %Objective
@onready var _budget: LineEdit = %BudgetEdit
@onready var _mass: LineEdit = %MassEdit
@onready var _create: Button = %Create
@onready var _library: VBoxContainer = %Library
@onready var _count: Label = %Count
@onready var _code: LineEdit = %Code
@onready var _copy: Button = %Copy
@onready var _import: Button = %Import
@onready var _left: PanelContainer = $Margin/Root/Body/LeftPanel


func _ready() -> void:
	_header.setup(Localization.t("SANDBOX / MISSIONS"), Localization.t("MISSION BUILDER"),
		Localization.t("Design a mission and share it."), "", Localization.t("< CONTRACTS"))
	_header.back_pressed.connect(func() -> void: EventBus.open_contracts.emit())
	_left.add_theme_stylebox_override("panel",
		UiKit.style_panel(UiKit.PANEL, UiKit.LINE, 3, 14, 14, 14))
	_name.placeholder_text = Localization.t("Mission name")
	_code.placeholder_text = Localization.t("Paste a mission code here.")
	_build_targets()
	_objective.add_item(Localization.t("ORBIT"))
	_objective.set_item_metadata(0, "orbit")
	_objective.add_item(Localization.t("FLYBY"))
	_objective.set_item_metadata(1, "flyby")
	_objective.add_item(Localization.t("LANDING"))
	_objective.set_item_metadata(2, "land")
	_create.pressed.connect(_on_create)
	_copy.pressed.connect(_on_copy)
	_import.pressed.connect(_on_import)
	_refresh()


func _build_targets() -> void:
	_target.clear()
	for raw in GameData.body_list:
		var body: CelestialBody = raw
		if body.id == "sun" or body.id == "earth" or body.soi_or_default() <= 0.0:
			continue
		_target.add_item(Localization.t(body.display_name))
		_target.set_item_metadata(_target.item_count - 1, body.id)
	for i in range(_target.item_count):
		if str(_target.get_item_metadata(i)) == "moon":
			_target.select(i)
			break


func _goal_id(mission: MissionDef) -> String:
	if mission.objectives.is_empty():
		return "orbit"
	var kind := str((mission.objectives[0] as Dictionary).get("kind", "bound"))
	if kind == "flyby":
		return "flyby"
	if kind == "land":
		return "land"
	return "orbit"


func _goal_name(goal: String) -> String:
	match goal:
		"flyby":
			return Localization.t("FLYBY")
		"land":
			return Localization.t("LANDING")
		_:
			return Localization.t("ORBIT")


func _mission_dict(name: String, target_id: String, goal: String, budget: float,
		mass: float) -> Dictionary:
	var body: CelestialBody = GameData.body(target_id)
	var target_name: String = Localization.t(body.display_name) if body != null else target_id
	var objectives: Array = []
	match goal:
		"flyby":
			objectives = [{
				"id": "flyby", "label": Localization.t("Survey pass"),
				"detail": Localization.t("Pass within 50,000 km of %s.", [target_name]),
				"points": 50, "kind": "flyby", "body": target_id, "value": 50000,
			}]
		"land":
			objectives = [{
				"id": "land", "label": Localization.t("Touchdown"),
				"detail": Localization.t("Land under 40 m/s relative speed."),
				"points": 70, "kind": "land", "body": target_id,
				"value": 40, "ends": true,
			}]
		_:
			objectives = [{
				"id": "capture", "label": Localization.t("Achieve orbit"),
				"detail": Localization.t("Bound orbit inside %s's SOI.", [target_name]),
				"points": 60, "kind": "bound", "body": target_id,
			}]
	return {
		"id": "",
		"number": 0,
		"name": name,
		"code": "CUSTOM / %s" % goal.to_upper(),
		"playable": true,
		"target_body": target_id,
		"start_body": "earth",
		"start_altitude_m": 200000.0,
		"budget_usd": budget,
		"mass_cap_kg": mass,
		"required_parts": [],
		"recommended_design": ["core_bus", "tank_large", "engine_chem", "solar_wing",
			"dish_hga", "sci_camera"],
		"briefing": [
			Localization.t("Custom mission to %s.", [target_name]),
			Localization.t("Budget %s. Mass cap %s.", [UiKit.money(budget), UiKit.kg(mass)]),
		],
		"hints": [
			"Auto-plan works inside the target SOI.",
			"Orbit: bound energy at closest approach.",
			"Landing: touch down under 40 m/s.",
		],
		"objectives": objectives,
		"science_range_m": 1.0e9,
		"duration_days": GameState.sandbox_duration_for(target_id),
		"scoring": {"objectives": 75, "budget_surplus": 15, "fuel_efficiency": 10},
	}


func _encode(mission: MissionDef) -> String:
	var payload := {
		"v": 1,
		"name": mission.display_name,
		"target": mission.target_body,
		"objective": _goal_id(mission),
		"budget": mission.budget_usd,
		"mass": mission.mass_cap_kg,
	}
	return "OA1-" + Marshalls.utf8_to_base64(JSON.stringify(payload))


func _on_create() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		name = Localization.t("Untitled Mission")
	var budget := _budget.text.strip_edges().to_float()
	var mass := _mass.text.strip_edges().to_float()
	if budget <= 0.0 or mass <= 0.0:
		EventBus.toast.emit(Localization.t("Enter a positive budget and mass cap."))
		return
	var target_id := str(_target.get_item_metadata(_target.selected))
	var goal := str(_objective.get_item_metadata(_objective.selected))
	var mission := GameState.add_custom_mission(_mission_dict(name, target_id, goal, budget, mass))
	_code.text = _encode(mission)
	_refresh()
	EventBus.toast.emit(Localization.t("Mission created."))


func _on_copy() -> void:
	if _code.text.strip_edges() == "":
		EventBus.toast.emit(Localization.t("No code to copy."))
		return
	DisplayServer.clipboard_set(_code.text.strip_edges())
	EventBus.toast.emit(Localization.t("Code copied."))


func _on_import() -> void:
	var raw := _code.text.strip_edges()
	if raw == "":
		raw = DisplayServer.clipboard_get().strip_edges()
	if raw.begins_with("OA1-"):
		raw = raw.substr(4)
	raw = raw.replace("\n", "").replace("\r", "").replace(" ", "")
	var check := RegEx.new()
	check.compile("^[A-Za-z0-9+/=]+$")
	if raw == "" or check.search(raw) == null or raw.length() % 4 != 0:
		EventBus.toast.emit(Localization.t("Invalid mission code."))
		return
	var decoded := Marshalls.base64_to_utf8(raw)
	var parsed: Variant = JSON.parse_string(decoded) if decoded != "" else null
	if not (parsed is Dictionary):
		EventBus.toast.emit(Localization.t("Invalid mission code."))
		return
	var data: Dictionary = parsed
	var target_id := str(data.get("target", ""))
	var budget := float(data.get("budget", 0.0))
	var mass := float(data.get("mass", 0.0))
	if GameData.body(target_id) == null and target_id.begins_with("proc_"):
		var offer := ContractGen.make_offer(int(target_id.substr(5)), GameData.bodies)
		if not offer.is_empty():
			GameData.add_body_def(offer.get("body", {}))
	if GameData.body(target_id) == null or budget <= 0.0 or mass <= 0.0:
		EventBus.toast.emit(Localization.t("Invalid mission code."))
		return
	var name := str(data.get("name", "Imported Mission")).strip_edges()
	if name == "":
		name = Localization.t("Imported Mission")
	var goal := str(data.get("objective", "orbit"))
	if not goal in ["orbit", "flyby", "land"]:
		goal = "orbit"
	var mission := GameState.add_custom_mission(_mission_dict(name, target_id, goal, budget, mass))
	_code.text = _encode(mission)
	_refresh()
	EventBus.toast.emit(Localization.t("Mission imported."))


func _refresh() -> void:
	for child in _library.get_children():
		_library.remove_child(child)
		child.queue_free()
	_count.text = "%d" % GameState.custom_missions.size()
	if GameState.custom_missions.is_empty():
		_library.add_child(UiKit.label(Localization.t("No saved missions."), 12, UiKit.MUTED))
		return
	for raw in GameState.custom_missions:
		var entry: Dictionary = raw
		_library.add_child(_mission_row(entry))


func _mission_row(entry: Dictionary) -> PanelContainer:
	var mission := MissionDef.from_dict(entry)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.style_panel(Color(0.0627451, 0.0862745, 0.121569, 0.94), UiKit.LINE, 3, 10, 8, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	info.add_child(UiKit.label(mission.display_name, 14, UiKit.TEXT))
	var body: CelestialBody = GameData.body(mission.target_body)
	var target_name: String = Localization.t(body.display_name) if body != null else mission.target_body
	var sub := "%s  /  %s  /  %s  /  %s" % [
		target_name, _goal_name(_goal_id(mission)), UiKit.money(mission.budget_usd),
		UiKit.kg(mission.mass_cap_kg)]
	info.add_child(UiKit.label(sub, 9, UiKit.MUTED))
	var open := Button.new()
	open.text = Localization.t("OPEN")
	open.custom_minimum_size = Vector2(58, 24)
	open.add_theme_font_size_override("font_size", 9)
	open.pressed.connect(_open_mission.bind(entry))
	UiKit.attach_hover(open, UiKit.CYAN)
	row.add_child(open)
	var code := Button.new()
	code.text = Localization.t("CODE")
	code.custom_minimum_size = Vector2(54, 24)
	code.add_theme_font_size_override("font_size", 9)
	code.pressed.connect(_set_code.bind(entry))
	UiKit.attach_hover(code, UiKit.CYAN)
	row.add_child(code)
	var remove := Button.new()
	remove.text = Localization.t("DELETE")
	remove.custom_minimum_size = Vector2(60, 24)
	remove.add_theme_font_size_override("font_size", 9)
	remove.add_theme_color_override("font_color", UiKit.CRIMSON)
	remove.pressed.connect(_delete_mission.bind(str(entry.get("id", ""))))
	UiKit.attach_hover(remove, UiKit.CRIMSON)
	row.add_child(remove)
	return panel


func _open_mission(entry: Dictionary) -> void:
	EventBus.open_briefing.emit(MissionDef.from_dict(entry))


func _set_code(entry: Dictionary) -> void:
	_code.text = _encode(MissionDef.from_dict(entry))
	_code.select_all()


func _delete_mission(id: String) -> void:
	GameState.delete_custom_mission(id)
	_refresh()
	EventBus.toast.emit(Localization.t("Mission deleted."))


func request_exit() -> void:
	EventBus.open_contracts.emit()
