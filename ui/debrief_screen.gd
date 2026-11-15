extends Control

# End of mission debrief handler
const OBJECTIVE_ROW := preload("res://scenes/components/objective_row.tscn")

var report: Dictionary = {}
var hub: String = "campaign"

@onready var _title: Label = %Title
@onready var _verdict: Label = %Verdict
@onready var _reward: Label = %Reward
@onready var _failure: Label = %Failure
@onready var _accent: ColorRect = %Accent
@onready var _objectives: VBoxContainer = %Objectives
@onready var _score_objectives: StatRow = %ScoreObjectives
@onready var _score_budget: StatRow = %ScoreBudget
@onready var _score_fuel: StatRow = %ScoreFuel
@onready var _total: Label = %Total
@onready var _total_caption: Label = %TotalCaption
@onready var _time_note: Label = %TimeNote
@onready var _best_run: StatRow = %BestRun
@onready var _medal_gap: StatRow = %MedalGap
@onready var _missed: Label = %Missed
@onready var _telemetry: Label = %Telemetry
@onready var _field_divider: ColorRect = %FieldDivider
@onready var _field_heading: Label = %FieldHeading
@onready var _field_note: Label = %FieldNote
@onready var _redesign: Button = %Redesign
@onready var _fly_again: Button = %FlyAgain
@onready var _next: Button = %Next
@onready var _control: Button = %Control

func _ready() -> void:
	_redesign.pressed.connect(_on_redesign)
	_fly_again.pressed.connect(_on_fly_again)
	_next.pressed.connect(_on_next)
	_control.pressed.connect(func() -> void:
		Audio.stop_voice()
		EventBus.go_back.emit())
	_fill()

func _fill() -> void:
	var success: bool = bool(report.get("success", false))
	_title.text = Localization.t(str(report.get("mission_name", "MISSION"))).to_upper()
	_verdict.text = Localization.t("OBJECTIVES COMPLETE" if success else "MISSION INCOMPLETE")
	_verdict.add_theme_color_override("font_color", UiKit.GREEN if success else UiKit.CRIMSON)

	var medal := str(report.get("medal", ""))
	var award := int(report.get("credits_awarded", 0))
	if report.has("contract_name"):
		if success:
			_reward.text = Localization.t("CONTRACT PAID  /  +%s  /  REP %d", [
				UiKit.money(float(report.get("contract_reward", 0))),
				int(report.get("reputation", 0))])
			_reward.add_theme_color_override("font_color", Color("#ffd166"))
		else:
			_reward.text = Localization.t("CONTRACT FAILED  /  NO PAYOUT")
			_reward.add_theme_color_override("font_color", UiKit.CRIMSON)
	elif success:
		if medal == "":
			medal = GameState.medal_for(float(report.get("total", 0.0)))
		if award > 0:
			_reward.text = Localization.t("%s MEDAL  /  +%s CREDITS", [
				Localization.t(medal), UiKit.money(float(award))])
		else:
			_reward.text = Localization.t("%s MEDAL  /  NO PAYOUT", [Localization.t(medal)])
		_reward.add_theme_color_override("font_color", _medal_color(medal))
	else:
		_reward.text = Localization.t("NO PAYOUT")
		_reward.add_theme_color_override("font_color", UiKit.MUTED)
	_accent.color = UiKit.GREEN if success else UiKit.CRIMSON

	var failure := str(report.get("failure", ""))
	_failure.visible = failure != ""
	_failure.text = Localization.t("Cause: ") + Localization.translate_any(failure)

	for child in _objectives.get_children():
		child.queue_free()
	for raw in report.get("objectives", []):
		var o: Dictionary = raw
		var done: bool = bool(o.get("done", false))
		var row: ObjectiveRow = OBJECTIVE_ROW.instantiate()
		_objectives.add_child(row)
		row.setup(str(o.get("label", "")), str(o.get("detail", "")), int(o.get("points", 0.0)), done)

	_score_objectives.setup(Localization.t("Objectives"), Localization.t("%d pts", [int(report.get("objective_points", 0.0))]), UiKit.CYAN)
	_score_budget.setup(Localization.t("Budget surplus"), Localization.t("%.1f pts", [float(report.get("budget_points", 0.0))]), UiKit.CYAN)
	_score_fuel.setup(Localization.t("Propellant reserve"), Localization.t("%.1f pts", [float(report.get("fuel_points", 0.0))]), UiKit.CYAN)

	_total.text = "%d / 100" % roundi(float(report.get("total", 0.0)))
	_total.add_theme_color_override("font_color", UiKit.GREEN if success else UiKit.AMBER)

	_total_caption.text = Localization.t("Cost %s / %s budget", [
		UiKit.money(float(report.get("cost", 0.0))),
		UiKit.money(float(report.get("budget", 0.0)))])
	_time_note.text = Localization.t("Flight %s / fuel %s", [
		Sim.format_met(float(report.get("met", 0.0))),
		UiKit.kg(float(report.get("fuel_left", 0.0)))])
	Audio.play_voice(Localization.voice_path("verdict_%s" % ("success" if success else "failure")),
		"Objectives complete. Contract filed." if success else "Mission incomplete. Debrief follows.")
	var hints := float(report.get("hint_penalty", 0.0))
	if hints > 0.0:
		_time_note.text += "  /  " + Localization.t("hints -%d pts", [int(hints)])
	_fill_analysis(success)


func _fill_analysis(success: bool) -> void:
	var mid := str(report.get("mission_id", ""))
	var score := float(report.get("total", 0.0))
	var best := GameState.best_score(mid)
	var best_text := "%d" % roundi(best) if best > 0.0 else "--"
	if bool(report.get("new_best", false)):
		best_text += "  " + Localization.t("NEW BEST")
	_best_run.setup(Localization.t("Personal best"), best_text,
		UiKit.GREEN if bool(report.get("new_best", false)) else _medal_color(GameState.medal_for(best)))

	var next_rank := ""
	var threshold := 0.0
	if score < 60.0:
		next_rank = "BRONZE"
		threshold = 60.0
	elif score < 75.0:
		next_rank = "SILVER"
		threshold = 75.0
	elif score < 90.0:
		next_rank = "GOLD"
		threshold = 90.0
	if next_rank == "":
		_medal_gap.setup(Localization.t("Top medal"), Localization.t("GOLD"), Color("#ffd166"))
	else:
		_medal_gap.setup(Localization.t("Next medal"),
			"%s  +%d" % [Localization.t(next_rank), int(ceil(threshold - score))],
			_medal_color(next_rank))

	var missed := ""
	for raw in report.get("objectives", []):
		var o: Dictionary = raw
		if not bool(o.get("done", false)):
			missed = Localization.translate_any(str(o.get("label", "")))
			break
	if missed != "":
		_missed.text = Localization.t("Missed: %s", [missed])
		_missed.add_theme_color_override("font_color", UiKit.CRIMSON)
	else:
		_missed.text = Localization.t("All objectives logged.")
		_missed.add_theme_color_override("font_color", UiKit.GREEN)

	var telemetry := Localization.t("%d burns  /  %s propellant used", [
		int(report.get("burns", 0)), UiKit.kg(float(report.get("fuel_used", 0.0)))])
	var closest := float(report.get("closest_target", 0.0))
	if is_finite(closest) and closest > 0.0:
		telemetry += "  /  " + Localization.t("%s closest", [UiKit.dist(closest)])
	_telemetry.text = telemetry

	var mission := _mission()
	var note := Localization.translate_any(mission.science_note) if mission != null else ""
	_field_divider.visible = note != ""
	_field_heading.visible = note != ""
	_field_note.visible = note != ""
	_field_note.text = note

	_fill_next(success)


func _fill_next(success: bool) -> void:
	var mid := str(report.get("mission_id", ""))
	var mission: MissionDef = GameData.mission(mid)
	_next.visible = success and mission != null and not mission.hidden
	if not _next.visible:
		return
	var upcoming: MissionDef = null
	for raw in GameData.campaign_missions():
		var m: MissionDef = raw
		if not m.playable or GameState.mission_cleared(m.id):
			continue
		upcoming = m
		break
	_next.disabled = upcoming == null
	if upcoming == null:
		_next.text = Localization.t("CAMPAIGN COMPLETE")
		_next.add_theme_color_override("font_color", UiKit.GREEN)
	else:
		_next.text = Localization.t("NEXT CONTRACT  >")
		_next.add_theme_color_override("font_color", UiKit.CYAN)


func _on_next() -> void:
	for raw in GameData.campaign_missions():
		var m: MissionDef = raw
		if not m.playable or GameState.mission_cleared(m.id):
			continue
		EventBus.open_briefing.emit(m)
		return

func _medal_color(medal: String) -> Color:
	match medal:
		"GOLD":
			return Color("#ffd166")
		"SILVER":
			return Color("#cfd8e3")
		"BRONZE":
			return Color("#c98a5b")
		_:
			return UiKit.MUTED

func _mission() -> MissionDef:
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

func _on_redesign() -> void:
	var mission := _mission()
	if mission != null:
		EventBus.open_hangar.emit(mission)

func _on_fly_again() -> void:
	var mission := _mission()
	if mission == null:
		return
	var design: Array = GameState.design_for(mission.id)
	if design.is_empty():
		design = mission.recommended_design.duplicate()
	var built: Dictionary = CraftState.build(design, GameData.parts)
	EventBus.start_flight.emit(mission, design, float(built.get("cost", 0.0)), GameState.layout_for(mission.id), GameState.rot_for(mission.id), GameState.hull_for(mission.id))

func request_exit() -> void:
	EventBus.go_back.emit()
