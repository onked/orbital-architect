extends Control

const HOME_SCENE := preload("res://scenes/home.tscn")
const CONTRACTS_SCENE := preload("res://scenes/contracts.tscn")
const ACHIEVEMENTS_SCENE := preload("res://scenes/achievements.tscn")
const BLUEPRINTS_SCENE := preload("res://scenes/blueprints.tscn")
const BUILDER_SCENE := preload("res://scenes/mission_builder.tscn")
const CREDITS_SCENE := preload("res://scenes/credits.tscn")
const MENU_SCENE := preload("res://scenes/menu.tscn")
const BRIEFING_SCENE := preload("res://scenes/briefing.tscn")
const HANGAR_SCENE := preload("res://scenes/hangar.tscn")
const SIM_SCENE := preload("res://scenes/sim.tscn")
const DEBRIEF_SCENE := preload("res://scenes/debrief.tscn")

var current_screen: Node = null

@onready var _host: Control = %ScreenHost
@onready var _toast: Label = %Toast
@onready var _tutorial: FlightSchool = $Tutorial
@onready var _achievement_popup: Node = %AchievementPopup

var _toast_tween: Tween = null


func _ready() -> void:
	EventBus.open_contracts.connect(show_contracts)
	EventBus.open_achievements.connect(show_achievements)
	EventBus.open_blueprints.connect(show_blueprints)
	EventBus.open_builder.connect(show_builder)
	EventBus.open_credits.connect(show_credits)
	EventBus.goto_home.connect(show_home)
	EventBus.goto_menu.connect(show_menu)
	EventBus.go_back.connect(_on_go_back)
	EventBus.open_briefing.connect(show_briefing)
	EventBus.open_hangar.connect(show_hangar)
	EventBus.start_flight.connect(show_sim)
	EventBus.end_flight.connect(show_debrief)
	EventBus.start_tutorial.connect(_on_start_tutorial)
	EventBus.toast.connect(_on_toast)
	GameState.achievement_unlocked.connect(_on_achievement_unlocked)
	var crt := get_tree().get_first_node_in_group("crt_overlay")
	if crt != null:
		(crt as CanvasItem).visible = GameState.setting("scanlines")
	show_home()


func _swap(screen: Node) -> void:
	Audio.stop_voice()
	if current_screen != null:
		_host.remove_child(current_screen)
		current_screen.queue_free()
	current_screen = screen
	_host.add_child(screen)

	var bg := screen.get_node_or_null("Bg")
	if bg is CanvasItem:
		(bg as CanvasItem).visible = false
	_tutorial.set_screen(screen)
	Localization.apply_tree.call_deferred(screen)
	var flying := String(screen.name).to_lower() == "flight"
	Audio.play_music("flight" if flying else "menu")
	Audio.set_ambience(flying)
	_decorate.call_deferred(screen)


func _decorate(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		if child is Button and not (child as Control).has_meta("ui_hover"):
			UiKit.attach_hover(child as Button)
		_decorate(child)


func show_home() -> void:
	_swap(HOME_SCENE.instantiate())


func show_contracts() -> void:
	_swap(CONTRACTS_SCENE.instantiate())


func show_achievements() -> void:
	_swap(ACHIEVEMENTS_SCENE.instantiate())


func show_blueprints() -> void:
	_swap(BLUEPRINTS_SCENE.instantiate())


func show_builder() -> void:
	_swap(BUILDER_SCENE.instantiate())


func show_credits() -> void:
	_swap(CREDITS_SCENE.instantiate())


func show_menu() -> void:
	_swap(MENU_SCENE.instantiate())


func show_briefing(mission: MissionDef) -> void:
	var screen: Control = BRIEFING_SCENE.instantiate()
	screen.set("mission", mission)
	screen.set("hub", _hub_from_current(mission))
	_swap(screen)


func show_hangar(mission: MissionDef) -> void:
	var screen: Control = HANGAR_SCENE.instantiate()
	screen.set("mission", mission)
	screen.set("hub", _hub_from_current(mission))
	var back := "briefing"
	if current_screen != null and current_screen.name == "Blueprints":
		back = "blueprints"
	screen.set("back_route", back)
	_swap(screen)


func show_sim(mission: MissionDef, design: Array, cost: float, layout: Array, rots: Array, hull: Array) -> void:
	var screen: Control = SIM_SCENE.instantiate()
	screen.set("mission", mission)
	screen.set("design", design)
	screen.set("cost", cost)
	screen.set("layout", layout)
	screen.set("rots", rots)
	screen.set("hull", hull)
	screen.set("hub", _hub_from_current(mission))
	if GameState.pending_resume and GameState.has_flight_save() \
			and str(GameState.flight.get("mission_id", "")) == mission.id:
		screen.set("resume", GameState.flight)
	GameState.pending_resume = false
	_swap(screen)


func show_debrief(report: Dictionary) -> void:
	var screen: Control = DEBRIEF_SCENE.instantiate()
	screen.set("report", report)
	screen.set("hub", _hub_from_current(_report_mission(report)))
	_swap(screen)


func _report_mission(report: Dictionary) -> MissionDef:
	var mid := str(report.get("mission_id", ""))
	var mission: MissionDef = GameData.mission(mid)
	if mission != null:
		return mission
	mission = GameState.custom_mission(mid)
	if mission != null:
		return mission
	if mid == "sandbox":
		return GameState.sandbox_mission(str(report.get("target_body", "")))
	return null


func _screen_hub(screen: Node) -> String:
	if screen == null:
		return ""
	var value: Variant = screen.get("hub")
	return str(value) if value != null else ""


func _hub_for_mission(mission: MissionDef) -> String:
	if mission == null:
		return "campaign"
	if mission.id == "sandbox" or mission.id.begins_with("contract_"):
		return "contracts"
	if mission.id.begins_with("custom_"):
		return "builder"
	return "campaign"


func _hub_from_current(mission: MissionDef) -> String:
	if current_screen != null:
		match current_screen.name:
			"Contracts":
				return "contracts"
			"MissionBuilder":
				return "builder"
			"MainMenu":
				return "campaign"
			"Blueprints":
				return "blueprints"
			"Debrief":
				return _hub_for_mission(mission)
		var inherited := _screen_hub(current_screen)
		if inherited != "":
			return inherited
	return _hub_for_mission(mission)


func _on_go_back() -> void:
	if current_screen == null:
		show_home()
		return
	var back := ""
	var value: Variant = current_screen.get("back_route")
	if value != null:
		back = str(value)
	if back == "blueprints":
		show_blueprints()
		return
	if back == "briefing":
		var mission: Variant = current_screen.get("mission")
		if mission is MissionDef:
			show_briefing(mission)
			return
	var hub := _screen_hub(current_screen)
	if hub == "":
		hub = "campaign"
	match hub:
		"home":
			show_home()
		"contracts":
			show_contracts()
		"builder":
			show_builder()
		"blueprints":
			show_blueprints()
		_:
			show_menu()


func _on_start_tutorial(mission: MissionDef) -> void:
	_tutorial.restart()
	show_briefing(mission)


func _on_achievement_unlocked(_id: String, title: String, detail: String) -> void:
	Audio.achievement()
	_achievement_popup.call("enqueue", title, detail)


func _on_toast(text: String) -> void:
	if text.is_empty():
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	var lift: float = -318.0 if _tutorial.visible else -72.0
	_toast.offset_top = lift
	_toast.offset_bottom = lift + 32.0
	_toast.text = Localization.translate_any(text)
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if current_screen != null and current_screen.has_method("save_now"):
			current_screen.call("save_now")
		GameState.save_campaign()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if current_screen == null:
		return
	if current_screen.has_method("request_exit"):
		current_screen.call("request_exit")
	else:
		show_menu()
	get_viewport().set_input_as_handled()
