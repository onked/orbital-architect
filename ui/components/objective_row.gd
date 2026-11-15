class_name ObjectiveRow
extends VBoxContainer

@onready var _check: Label = %Check
@onready var _title: Label = %Title
@onready var _points: Label = %Points
@onready var _detail: Label = %Detail

func setup(label_text: String, detail_text: String, points: int, done: bool) -> void:
	_check.text = "[x]" if done else "[ ]"
	_check.add_theme_color_override("font_color", UiKit.GREEN if done else UiKit.MUTED)
	_title.text = Localization.translate_any(label_text)
	_title.add_theme_color_override("font_color", UiKit.GREEN if done else UiKit.TEXT)
	_points.text = Localization.t("%d pts", [points])
	_points.add_theme_color_override("font_color", UiKit.GREEN if done else UiKit.MUTED)
	_detail.text = Localization.translate_any(detail_text)
