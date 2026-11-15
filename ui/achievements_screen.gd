extends Control

# Achievement page
const ROW := preload("res://scenes/components/home_row.tscn")
const DATA_PATH := "res://data/achievements.json"

@onready var _header: ScreenHeader = %Header
@onready var _rows: VBoxContainer = %Rows
@onready var _progress: Label = %Progress

func _ready() -> void:
	_header.back_pressed.connect(func() -> void: EventBus.goto_home.emit())
	_header.setup("CAREER / ACHIEVEMENTS", "ACHIEVEMENTS",
		"Medals and milestones", "", "< HOME")
	_fill()

func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var defs := _load()
	var unlocked := 0
	for raw in defs:
		var a: Dictionary = raw
		var done := _unlocked(a)
		if done:
			unlocked += 1
		var row: HomeRow = ROW.instantiate()
		_rows.add_child(row)
		row.setup("*" if done else "-", Localization.t(str(a.get("name", ""))),
			Localization.t(str(a.get("desc", ""))),
			Localization.t("[DONE]" if done else "[LOCKED]"),
			UiKit.GREEN if done else UiKit.MUTED, false, true)
	_progress.text = Localization.t("%d / %d UNLOCKED", [unlocked, defs.size()])

func _load() -> Array:
	if not FileAccess.file_exists(DATA_PATH):
		return []
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []

func _unlocked(a: Dictionary) -> bool:
	return GameState.unlocked_achievements.has(str(a.get("id", "")))

func request_exit() -> void:
	EventBus.goto_home.emit()
