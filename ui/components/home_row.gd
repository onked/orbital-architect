class_name HomeRow
extends PanelContainer

signal activated

var _accent: Color = UiKit.AMBER
var _enabled := true

@onready var _accent_bar: ColorRect = %Accent
@onready var _glyph: Label = %Glyph
@onready var _title: Label = %Title
@onready var _sub: Label = %Sub
@onready var _tag: Label = %Tag
@onready var _action: Button = %Action

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_action.pressed.connect(_activate)

func setup(glyph: String, title: String, sub: String, tag: String,
		accent: Color, primary: bool, enabled: bool = true,
		action_text: String = "START") -> void:
	_accent = accent
	_enabled = enabled
	_glyph.text = glyph
	_glyph.add_theme_color_override("font_color", accent)
	_title.text = title
	_sub.text = sub
	_tag.text = tag
	_action.visible = primary
	_action.text = action_text
	_tag.visible = not primary
	_accent_bar.color = accent

	var bg := Color(0.0627451, 0.0862745, 0.121569, 0.94)
	var border := UiKit.LINE
	if primary:
		bg = Color(0.0862745, 0.105882, 0.141176, 0.96)
		border = UiKit.LINE
	add_theme_stylebox_override("panel", UiKit.style_panel(bg, border, 4, 14, 12, 14))

	if enabled:
		UiKit.attach_hover(self, accent)
	else:
		modulate = Color(1, 1, 1, 0.55)

func _activate() -> void:
	if _enabled:
		activated.emit()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_activate()
			accept_event()
