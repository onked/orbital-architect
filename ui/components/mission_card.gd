class_name MissionCard
extends PanelContainer

signal open_requested(mission: MissionDef)

var mission: MissionDef = null
var _accent: Color = UiKit.AMBER

@onready var _accent_bar: ColorRect = %Accent
@onready var _number: Label = %Number
@onready var _name: Label = %Name
@onready var _code: Label = %Code
@onready var _meta: Label = %Meta
@onready var _state: Label = %State
@onready var _open: Button = %Open

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func setup(m: MissionDef, cleared: bool, best_score: float, next_up: bool = false) -> void:
	mission = m
	var target: CelestialBody = GameData.body(m.target_body)
	var target_name: String = Localization.t(target.display_name) if target != null else m.target_body
	_number.text = "%02d" % m.number
	_name.text = Localization.t(m.display_name)
	_code.text = m.code
	_meta.text = Localization.t("TARGET %s   /   %s BUDGET   /   %s CAP", [
		target_name.to_upper(), UiKit.money(m.budget_usd), UiKit.kg(m.mass_cap_kg)])

	if not m.playable:
		_accent = UiKit.MUTED
		_state.text = Localization.t("DATA PENDING")
		_state.add_theme_color_override("font_color", UiKit.MUTED)
		_open.disabled = true
		modulate = Color(1, 1, 1, 0.65)
	elif cleared:
		var medal: String = GameState.mission_medal(m.id)
		if medal == "":
			medal = GameState.medal_for(best_score)
		_accent = _medal_color(medal)
		_state.text = "%s  %d%%" % [Localization.t(medal), roundi(best_score)]
		_state.add_theme_color_override("font_color", _accent)
	elif next_up:
		_accent = UiKit.CYAN
		_state.text = Localization.t("NEXT UP")
		_state.add_theme_color_override("font_color", UiKit.CYAN)
	else:
		_accent = UiKit.AMBER
		_state.text = Localization.t("AVAILABLE")
		_state.add_theme_color_override("font_color", UiKit.AMBER)

	_accent_bar.color = _accent
	add_theme_stylebox_override("panel", UiKit.style_panel(
		Color(0.0705882, 0.0941176, 0.129412, 0.96), UiKit.LINE, 4, 12, 10, 12))
	if m.playable:
		UiKit.attach_hover(self, _accent)

	_open.pressed.connect(_on_open)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Audio.ui_click()
			_on_open()
			accept_event()

func _medal_color(medal: String) -> Color:
	match medal:
		"GOLD":
			return Color("#ffd166")
		"SILVER":
			return Color("#cfd8e3")
		"BRONZE":
			return Color("#c98a5b")
		_:
			return UiKit.GREEN

func _on_open() -> void:
	if mission != null and mission.playable:
		open_requested.emit(mission)
