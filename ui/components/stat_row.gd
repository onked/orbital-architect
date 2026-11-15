class_name StatRow
extends HBoxContainer

@export var name_text: String = "Label"
@export var value_text: String = "--"
@export var value_color: Color = Color("#d7e3f4")

@onready var _name: Label = %Name
@onready var _value: Label = %Value

func _ready() -> void:
	_apply()

func setup(label_text: String, value: String, color: Color = Color("#d7e3f4")) -> void:
	name_text = label_text
	value_text = value
	value_color = color
	if is_node_ready():
		_apply()

func set_value(value: String, color: Color = Color("#d7e3f4")) -> void:
	value_text = value
	value_color = color
	if is_node_ready():
		_apply()

func _apply() -> void:
	if _name == null or _value == null:
		return
	_name.text = name_text
	_value.text = value_text
	_value.add_theme_color_override("font_color", value_color)
