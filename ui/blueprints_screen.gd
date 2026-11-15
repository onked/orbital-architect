extends Control

const ROW := preload("res://scenes/components/home_row.tscn")

@onready var _header: ScreenHeader = %Header
@onready var _list: VBoxContainer = %List
@onready var _count: Label = %Count


func _ready() -> void:
	_header.back_pressed.connect(func() -> void: EventBus.goto_home.emit())
	_fill()


func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var ids: Array = []
	for mission in GameData.campaign_missions():
		var m: MissionDef = mission
		if not (GameState.designs.get(m.id, []) as Array).is_empty():
			ids.append(m.id)
	if not (GameState.designs.get("sandbox", []) as Array).is_empty():
		ids.append("sandbox")
	for id in GameState.designs.keys():
		if not ids.has(id) and not (GameState.designs.get(id, []) as Array).is_empty():
			ids.append(id)

	var meta := Localization.t("%d saved designs", [ids.size()])
	if ids.size() == 1:
		meta = Localization.t("1 saved design")
	_header.setup(Localization.t("CAREER / BLUEPRINTS"), Localization.t("BLUEPRINT LIBRARY"),
		meta, "", Localization.t("< HOME"))
	_count.text = "%d" % ids.size()
	if ids.is_empty():
		var empty := UiKit.label(Localization.t("No saved blueprints."), 13, UiKit.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		var hint := UiKit.label(Localization.t("Launch a vehicle to store its design here."), 11, UiKit.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(hint)
		return

	for raw in ids:
		var id := str(raw)
		var mission := _mission_for(id)
		var parts: Array = GameState.designs.get(id, [])
		if parts.is_empty():
			continue
		var built: Dictionary = CraftState.build(parts, GameData.parts)
		var craft: CraftState = built["craft"]
		var row: HomeRow = ROW.instantiate()
		_list.add_child(row)
		var title := Localization.t(mission.display_name) if mission != null else _fallback_title(id)
		var tag := _tag_for(id, mission)
		var action := Localization.t("OPEN") if mission != null else Localization.t("SANDBOX")
		var accent := UiKit.GREEN
		if id == "sandbox":
			accent = UiKit.CYAN
		elif mission == null:
			accent = UiKit.VIOLET
		elif mission.playable:
			accent = UiKit.AMBER
		row.setup(">", title.to_upper(),
			Localization.t("%d parts  /  %s  /  %s  /  %.0f m/s", [
				parts.size(), UiKit.money(float(built.get("cost", 0.0))),
				UiKit.kg(craft.wet_mass()), craft.delta_v()]),
			Localization.t(tag), accent, true, true, action)
		row.activated.connect(_on_open.bind(id, mission))


func _mission_for(id: String) -> MissionDef:
	var mission: MissionDef = GameData.mission(id)
	if mission != null:
		return mission
	mission = GameState.custom_mission(id)
	if mission != null:
		return mission
	if id == "sandbox":
		return GameState.sandbox_mission()
	if not GameState.active_contract.is_empty():
		var raw: Dictionary = GameState.active_contract.get("mission", {})
		if str(raw.get("id", "")) == id:
			return MissionDef.from_dict(raw)
	return null


func _fallback_title(id: String) -> String:
	if id.begins_with("contract_"):
		return Localization.t("CONTRACT %s", [id.get_slice("_", 1)])
	return id.replace("_", " ").to_upper()


func _tag_for(id: String, mission: MissionDef) -> String:
	if id == "sandbox":
		return "[SANDBOX]"
	if mission == null:
		return "[CONTRACT]"
	return "[%s]" % mission.code.get_slice(" / ", 0)


func _on_open(id: String, mission: MissionDef) -> void:
	if mission == null:
		GameState.save_design("sandbox", GameState.design_for(id), GameState.layout_for(id),
			GameState.rot_for(id), GameState.hull_for(id))
		EventBus.open_hangar.emit(GameState.sandbox_mission())
		return
	EventBus.open_hangar.emit(mission)


func request_exit() -> void:
	EventBus.goto_home.emit()
