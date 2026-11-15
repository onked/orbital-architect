extends Control

# Main script for home screen
const ROW := preload("res://scenes/components/home_row.tscn")
const WARP_LEVELS := [1, 4, 12]

@onready var _rows: VBoxContainer = %Rows
@onready var _career: Label = %Career
@onready var _settings: Control = %Settings
@onready var _animate: CheckButton = %Animate
@onready var _scanlines: CheckButton = %Scanlines
@onready var _motion: CheckButton = %Motion
@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _subtitles: CheckButton = %Subtitles
@onready var _warp_speed: OptionButton = %WarpSpeed
@onready var _language: OptionButton = %Language
@onready var _reset: Button = %ResetDefaults
@onready var _credits: Button = %Credits
@onready var _master: HSlider = %MasterVolume
@onready var _sfx: HSlider = %SfxVolume
@onready var _amb: HSlider = %AmbienceVolume
@onready var _music: HSlider = %MusicVolume
@onready var _voiceh: HSlider = %VoiceVolume
@onready var _master_val: Label = %MasterValue
@onready var _sfx_val: Label = %SfxValue
@onready var _amb_val: Label = %AmbienceValue
@onready var _music_val: Label = %MusicValue
@onready var _voice_val: Label = %VoiceValue
@onready var _save_status: Label = %SaveStatus
@onready var _save_now: Button = %SaveNow
@onready var _clear_flight: Button = %DeleteSave
@onready var _close: Button = %Close

func _ready() -> void:
	for i in range(WARP_LEVELS.size()):
		_warp_speed.add_item("%dx" % int(WARP_LEVELS[i]), i)
	for lang in Localization.languages():
		var info: Dictionary = lang
		_language.add_item(str(info.get("name", info.get("code", ""))))
		_language.set_item_metadata(_language.item_count - 1, str(info.get("code", "en")))
	_build_rows()
	_apply_settings()
	_close.pressed.connect(func() -> void: _settings.visible = false)
	_animate.toggled.connect(_on_animate)
	_scanlines.toggled.connect(_on_scanlines)
	_motion.toggled.connect(_on_motion)
	_fullscreen.toggled.connect(_on_fullscreen)
	_subtitles.toggled.connect(_on_subtitles)
	_warp_speed.item_selected.connect(_on_warp_speed)
	_language.item_selected.connect(_on_language)
	_reset.pressed.connect(_on_reset)
	_credits.pressed.connect(func() -> void: EventBus.open_credits.emit())
	_master.value_changed.connect(_on_volume.bind("vol_master", _master_val))
	_sfx.value_changed.connect(_on_volume.bind("vol_sfx", _sfx_val))
	_amb.value_changed.connect(_on_volume.bind("vol_ambience", _amb_val))
	_music.value_changed.connect(_on_volume.bind("vol_music", _music_val))
	_voiceh.value_changed.connect(_on_volume.bind("vol_voice", _voice_val))
	_master.drag_ended.connect(func(_changed: bool) -> void: GameState.save_campaign())
	_sfx.drag_ended.connect(func(_changed: bool) -> void: GameState.save_campaign())
	_amb.drag_ended.connect(func(_changed: bool) -> void: GameState.save_campaign())
	_music.drag_ended.connect(func(_changed: bool) -> void: GameState.save_campaign())
	_voiceh.drag_ended.connect(func(_changed: bool) -> void: GameState.save_campaign())
	_save_now.pressed.connect(_on_save_now)
	_clear_flight.pressed.connect(_on_clear_flight)
	_update_save_status()
	_update_career()

func _apply_settings() -> void:
	var bg := _backdrop()
	var animated: bool = GameState.setting("animated")
	if bg != null:
		(bg as CanvasItem).visible = animated
	var crt := get_tree().get_first_node_in_group("crt_overlay")
	if crt != null:
		(crt as CanvasItem).visible = GameState.setting("scanlines")
	UiKit.motion_enabled = GameState.setting("motion")
	_animate.set_pressed_no_signal(animated)
	_scanlines.set_pressed_no_signal(GameState.setting("scanlines"))
	_motion.set_pressed_no_signal(GameState.setting("motion"))
	_fullscreen.set_pressed_no_signal(GameState.setting("fullscreen"))
	_subtitles.set_pressed_no_signal(GameState.setting("subtitles", false))
	_apply_fullscreen(GameState.setting("fullscreen"))
	var warp_value := int(GameState.settings.get("warp", 1))
	var warp_index := WARP_LEVELS.find(warp_value)
	if warp_index < 0:
		warp_index = 0
	_warp_speed.select(warp_index)
	for i in range(_language.item_count):
		if str(_language.get_item_metadata(i)) == str(GameState.settings.get("locale", "en")):
			_language.select(i)
			break
	if bg != null:
		bg.set("warp_scale", float(WARP_LEVELS[warp_index]))
	_master.set_value_no_signal(float(GameState.settings.get("vol_master", 0.8)))
	_sfx.set_value_no_signal(float(GameState.settings.get("vol_sfx", 0.8)))
	_amb.set_value_no_signal(float(GameState.settings.get("vol_ambience", 0.35)))
	_music.set_value_no_signal(float(GameState.settings.get("vol_music", 0.5)))
	_voiceh.set_value_no_signal(float(GameState.settings.get("vol_voice", 1.0)))
	_update_volume_labels()
	Audio.apply_all()

func _build_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	if GameState.has_flight_save():
		var fm: MissionDef = GameState.flight_mission()
		if fm != null:
			var f: Dictionary = GameState.flight
			var resume: HomeRow = ROW.instantiate()
			_rows.add_child(resume)
			resume.setup(">", "RESUME FLIGHT",
				"%s  /  T+ %s" % [fm.display_name.to_upper(), Sim.format_met(float(f.get("met", 0.0)))],
				"[SAVE]", UiKit.GREEN, true, true, "RESUME")
			resume.activated.connect(_on_resume.bind(fm))

	var campaign: HomeRow = ROW.instantiate()
	_rows.add_child(campaign)
	var next_name := ""
	for mission in GameData.campaign_missions():
		var m: MissionDef = mission
		if m.playable and not GameState.mission_cleared(m.id):
			next_name = Localization.t(m.display_name).to_upper()
			break
	var campaign_sub := Localization.t("%d JPL MISSION CONTRACTS", [GameData.campaign_missions().size()])
	if not GameState.tutorial_done and GameState.flights == 0:
		campaign_sub += "  /  " + Localization.t("START WITH FLIGHT SCHOOL")
	elif next_name != "":
		campaign_sub += "  /  " + Localization.t("NEXT: %s", [next_name])
	else:
		campaign_sub += "  /  " + Localization.t("ALL CONTRACTS CLEARED")
	campaign.setup(">", "PLAY CAMPAIGN", campaign_sub, "", UiKit.AMBER, false)
	campaign.activated.connect(func() -> void: EventBus.goto_menu.emit())

	var sandbox: HomeRow = ROW.instantiate()
	_rows.add_child(sandbox)
	sandbox.setup("+", "SANDBOX SIM", "CONTRACT BOARD AND FREE BUILD",
		"[LAB]", UiKit.CYAN, false)
	sandbox.activated.connect(_on_sandbox)

	var blueprints: HomeRow = ROW.instantiate()
	_rows.add_child(blueprints)
	blueprints.setup("#", "BLUEPRINTS", "SAVED VEHICLE DESIGNS",
		"[BAY]", UiKit.GREEN, false)
	blueprints.activated.connect(func() -> void: EventBus.open_blueprints.emit())

	var achievements: HomeRow = ROW.instantiate()
	_rows.add_child(achievements)
	achievements.setup("*", "ACHIEVEMENTS", "MEDALS AND MILESTONES",
		"[LOG]", UiKit.VIOLET, false)
	achievements.activated.connect(func() -> void: EventBus.open_achievements.emit())

	var settings: HomeRow = ROW.instantiate()
	_rows.add_child(settings)
	settings.setup("*", "SETTINGS", "OPTIONS",
		"[CFG]", UiKit.CYAN, false)
	settings.activated.connect(func() -> void: _settings.visible = true)

func _update_save_status() -> void:
	if _save_status == null:
		return
	var lines: Array = [Localization.t("%d designs  /  %d cleared", [
		GameState.designs.size(), GameState.completed.size()])]
	if GameState.has_flight_save():
		var fm: MissionDef = GameState.flight_mission()
		lines.append(Localization.t("%s  /  T+ %s", [
			Localization.t(fm.display_name) if fm != null else str(GameState.flight.get("mission_id", "")),
			Sim.format_met(float(GameState.flight.get("met", 0.0)))]))
	else:
		lines.append(Localization.t("No flight saved."))
	if GameState.save_warning != "":
		lines.append(GameState.save_warning)
	_save_status.text = "\n".join(lines)

func _update_career() -> void:
	if _career == null:
		return
	var cleared := 0
	for mission in GameData.campaign_missions():
		var m: MissionDef = mission
		if m.playable and GameState.mission_cleared(m.id):
			cleared += 1
	var medals := GameState.medal_count()
	_career.text = Localization.t("%s CREDITS  /  %d %s  /  %d/%d CONTRACTS", [
		UiKit.money(float(GameState.credits)), medals,
		Localization.t("MEDAL" if medals == 1 else "MEDALS"),
		cleared, GameData.campaign_missions().size()])

func _backdrop() -> Node:
	return get_tree().get_first_node_in_group("orbital_backdrop")

func _on_resume(mission: MissionDef) -> void:
	GameState.pending_resume = true
	var design: Array = GameState.design_for(mission.id)
	if design.is_empty():
		design = mission.recommended_design.duplicate()
	var built: Dictionary = CraftState.build(design, GameData.parts)
	EventBus.start_flight.emit(mission, design, float(built.get("cost", 0.0)),
		GameState.layout_for(mission.id), GameState.rot_for(mission.id),
		GameState.hull_for(mission.id))

func _on_sandbox() -> void:
	EventBus.open_contracts.emit()

func _on_save_now() -> void:
	GameState.save_campaign()
	_update_save_status()
	EventBus.toast.emit(Localization.t("Saved."))

func _on_clear_flight() -> void:
	GameState.clear_flight()
	_build_rows()
	_update_save_status()
	EventBus.toast.emit(Localization.t("Flight save cleared."))

func _on_animate(on: bool) -> void:
	GameState.set_setting("animated", on)
	var bg := _backdrop()
	if bg != null:
		(bg as CanvasItem).visible = on

func _on_scanlines(on: bool) -> void:
	GameState.set_setting("scanlines", on)
	var crt := get_tree().get_first_node_in_group("crt_overlay")
	if crt != null:
		(crt as CanvasItem).visible = on

func _on_motion(on: bool) -> void:
	GameState.set_setting("motion", on)
	UiKit.motion_enabled = on

func _on_fullscreen(on: bool) -> void:
	GameState.set_setting("fullscreen", on)
	_apply_fullscreen(on)

func _on_subtitles(on: bool) -> void:
	GameState.set_setting("subtitles", on)
	if not on:
		Audio.voice_cue_cleared.emit()

func _update_volume_labels() -> void:
	_master_val.text = "%d%%" % int(round(_master.value * 100.0))
	_sfx_val.text = "%d%%" % int(round(_sfx.value * 100.0))
	_amb_val.text = "%d%%" % int(round(_amb.value * 100.0))
	_music_val.text = "%d%%" % int(round(_music.value * 100.0))
	_voice_val.text = "%d%%" % int(round(_voiceh.value * 100.0))

func _on_volume(value: float, key: String, label: Label) -> void:
	GameState.settings[key] = clampf(value, 0.0, 1.0)
	Audio.set_volume(key, value)
	label.text = "%d%%" % int(round(value * 100.0))

func _on_language(index: int) -> void:
	Localization.set_language(str(_language.get_item_metadata(index)))
	_build_rows()
	_update_career()
	_update_save_status()
	_update_volume_labels()
	Localization.apply_tree(get_tree().root)


func _on_warp_speed(index: int) -> void:
	var value: int = int(WARP_LEVELS[clampi(index, 0, WARP_LEVELS.size() - 1)])
	GameState.settings["warp"] = value
	GameState.save_campaign()
	var bg := _backdrop()
	if bg != null:
		bg.set("warp_scale", float(value))

func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _on_reset() -> void:
	GameState.settings = {
		"animated": true, "scanlines": true, "motion": true,
		"fullscreen": false, "subtitles": false, "sandbox_target": "moon", "warp": 1,
		"vol_master": 0.8, "vol_sfx": 0.8, "vol_ambience": 0.35, "vol_music": 0.5, "vol_voice": 1.0,
		"locale": "en",
	}
	GameState.save_campaign()
	Localization.set_language("en")
	_apply_settings()
	_build_rows()
	_update_career()
	_update_save_status()
	Localization.apply_tree(get_tree().root)
	EventBus.toast.emit(Localization.t("Settings reset."))

func request_exit() -> void:
	if _settings.visible:
		_settings.visible = false
