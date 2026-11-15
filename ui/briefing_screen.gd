extends Control

# Contract handler
const OBJECTIVE_ROW := preload("res://scenes/components/objective_row.tscn")

var mission: MissionDef = null
var hub: String = "campaign"

@onready var _header: ScreenHeader = %Header
@onready var _brief: Label = %Brief
@onready var _hints: Label = %Hints
@onready var _funding: StatRow = %Funding
@onready var _mass_cap: StatRow = %MassCap
@onready var _target: StatRow = %Target
@onready var _payload: Label = %Payload
@onready var _objectives: VBoxContainer = %List
@onready var _field_divider: ColorRect = %FieldDivider
@onready var _field_heading: Label = %FieldHeading
@onready var _field_note: Label = %FieldNote
@onready var _proceed: Button = %Proceed

func _ready() -> void:
	_header.back_pressed.connect(_on_back)
	_proceed.pressed.connect(func() -> void:
		Audio.stop_voice()
		EventBus.open_hangar.emit(mission))
	if mission == null:
		return
	_fill()

func _fill() -> void:
	var target: CelestialBody = GameData.body(mission.target_body)
	var target_name: String = target.display_name if target != null else mission.target_body

	var back := "< MISSION CONTROL"
	match hub:
		"contracts":
			back = "< CONTRACT BOARD"
		"builder":
			back = "< MISSION BUILDER"
		"blueprints":
			back = "< BLUEPRINTS"
	_header.setup(mission.code, Localization.t(mission.display_name).to_upper(),
		Localization.t("TARGET  %s   /   START ALTITUDE %d KM   /   %s BUDGET" if mission.start_mode == "descent" else "TARGET  %s   /   PARKING ORBIT %d KM   /   %s BUDGET", [
			Localization.t(target_name).to_upper(), int(mission.start_altitude_m / 1000.0),
			UiKit.money(mission.budget_usd)]),
		"", back)

	var paragraphs: Array = []
	for p in mission.briefing:
		paragraphs.append(Localization.translate_any(str(p)))
	_brief.text = "\n\n".join(paragraphs)

	var notes: Array = []
	for h in mission.hints:
		notes.append(">  " + Localization.translate_any(str(h)))
	_hints.text = "\n".join(notes) if not notes.is_empty() else Localization.t("No notes.")

	_funding.setup("Funding", UiKit.money(mission.budget_usd))
	_mass_cap.setup("Mass cap", UiKit.kg(mission.mass_cap_kg))
	_target.setup("Target", Localization.t(target_name))

	var payload_names: Array = []
	for pid in mission.required_parts:
		var part: PartDef = GameData.part(str(pid))
		payload_names.append(Localization.t(part.display_name) if part != null else str(pid))
	_payload.text = "\n".join(payload_names) if not payload_names.is_empty() else Localization.t("None")
	var note := Localization.translate_any(mission.science_note)
	_field_divider.visible = note != ""
	_field_heading.visible = note != ""
	_field_note.visible = note != ""
	_field_note.text = note
	var voice_path := Localization.voice_path("briefing_%s" % mission.id)
	if ResourceLoader.exists(voice_path):
		var spoken := mission.display_name + "."
		for p in mission.briefing:
			spoken += " " + str(p)
		Audio.play_voice(voice_path, spoken)
	else:
		Audio.stop_voice()

	for child in _objectives.get_children():
		child.queue_free()
	for raw in mission.objectives:
		var o: Dictionary = raw
		var row: ObjectiveRow = OBJECTIVE_ROW.instantiate()
		_objectives.add_child(row)
		row.setup(str(o.get("label", "")), str(o.get("detail", "")), int(o.get("points", 0)), false)

func _on_back() -> void:
	Audio.stop_voice()
	EventBus.go_back.emit()

func request_exit() -> void:
	_on_back()
