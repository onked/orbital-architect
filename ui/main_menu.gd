extends Control

const CARD_SCENE := preload("res://scenes/components/mission_card.tscn")

@onready var _mission_list: VBoxContainer = %MissionList
@onready var _cleared: StatRow = %Cleared
@onready var _bodies: StatRow = %Bodies
@onready var _parts: StatRow = %Parts
@onready var _epoch: StatRow = %Epoch
@onready var _credits: StatRow = %Credits
@onready var _medals: StatRow = %Medals
@onready var _next_up: StatRow = %NextUp
@onready var _tutorial: Button = %Tutorial
@onready var _practice: Button = %LandingPractice
@onready var _quit: Button = %Quit
@onready var _home: Button = %Home
@onready var _count: Label = %Count

func _ready() -> void:
	_fill()
	_quit.pressed.connect(func() -> void: get_tree().quit())
	_tutorial.pressed.connect(_on_tutorial)
	_practice.pressed.connect(_on_practice)
	_home.pressed.connect(func() -> void: EventBus.goto_home.emit())
	_count.text = "%02d" % GameData.campaign_missions().size()

func _backdrop() -> Node:
	return get_tree().get_first_node_in_group("orbital_backdrop")

func _fill() -> void:
	for child in _mission_list.get_children():
		child.queue_free()

	if GameState.all_cleared():
		_mission_list.add_child(_completion_banner())

	var cleared_count := 0
	var next_mission: MissionDef = null
	for mission in GameData.campaign_missions():
		var m: MissionDef = mission
		var cleared: bool = GameState.mission_cleared(m.id)
		if cleared:
			cleared_count += 1
		elif next_mission == null and m.playable:
			next_mission = m
		var card: MissionCard = CARD_SCENE.instantiate()
		_mission_list.add_child(card)
		card.setup(m, cleared, GameState.best_score(m.id),
			next_mission != null and next_mission.id == m.id)
		card.open_requested.connect(_on_open)

	_cleared.setup(Localization.t("Contracts cleared"), "%d / %d" % [cleared_count, GameData.campaign_missions().size()], UiKit.CYAN)
	_next_up.setup(Localization.t("Next assignment"),
		Localization.t(next_mission.display_name) if next_mission != null else Localization.t("CAMPAIGN COMPLETE"),
		UiKit.AMBER if next_mission != null else UiKit.GREEN)
	var real_bodies := 0
	for id in GameData.bodies.keys():
		if not str(id).begins_with("proc_"):
			real_bodies += 1
	_bodies.setup(Localization.t("Bodies in field"), str(real_bodies))
	_parts.setup(Localization.t("Parts catalogue"), str(GameData.parts.size()))
	_epoch.setup(Localization.t("Launch epoch"), UiKit.jd_date(GameData.mission_start_t / 86400.0))
	_credits.setup(Localization.t("Career credits"), UiKit.money(float(GameState.credits)), UiKit.AMBER)
	_medals.setup(Localization.t("Medals"), str(GameState.medal_count()), UiKit.AMBER)

func _on_open(mission: MissionDef) -> void:
	EventBus.open_briefing.emit(mission)


func _completion_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.style_panel(Color(0.0509804, 0.105882, 0.0862745, 0.96), UiKit.GREEN, 4, 14, 12, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	info.add_child(UiKit.label(Localization.t("CAMPAIGN COMPLETE"), 18, UiKit.GREEN))
	var sub := UiKit.label(Localization.t("All five contracts cleared. Keep flying sandbox work or read the credits."), 11, UiKit.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub)
	var credits := Button.new()
	credits.text = Localization.t("CREDITS")
	credits.custom_minimum_size = Vector2(96, 34)
	credits.add_theme_font_size_override("font_size", 10)
	credits.pressed.connect(func() -> void: EventBus.open_credits.emit())
	UiKit.attach_hover(credits, UiKit.GREEN)
	row.add_child(credits)
	return panel

func _on_tutorial() -> void:
	var mission: MissionDef = GameData.mission("lunar_relay")
	if mission != null:
		EventBus.start_tutorial.emit(mission)

func _on_practice() -> void:
	var mission: MissionDef = GameData.mission("flight_school_landing")
	if mission != null:
		EventBus.open_briefing.emit(mission)

func request_exit() -> void:
	EventBus.goto_home.emit()
