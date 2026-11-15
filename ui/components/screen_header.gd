class_name ScreenHeader
extends VBoxContainer

signal back_pressed
signal action_pressed

@onready var _back: Button = %Back
@onready var _code: Label = %Code
@onready var _title: Label = %Title
@onready var _meta: Label = %Meta
@onready var _action: Button = %Action

func _ready() -> void:
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_action.pressed.connect(func() -> void: action_pressed.emit())

func setup(code: String, title: String, meta: String,
		action_text: String = "", back_text: String = "< BACK") -> void:
	_code.text = code
	_title.text = title
	_meta.text = meta
	_back.text = back_text
	_action.visible = action_text != ""
	_action.text = action_text

func set_action_enabled(on: bool) -> void:
	_action.disabled = not on
	_action.modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.5)
