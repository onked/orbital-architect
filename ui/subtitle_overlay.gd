extends PanelContainer

@onready var _label: Label = %SubtitleText
var _fade: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.070, 0.105, 0.94)
	sb.border_color = Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	Audio.voice_cue.connect(_show_cue)
	Audio.voice_cue_cleared.connect(_hide_cue)


func _show_cue(text: String) -> void:
	if not GameState.setting("subtitles", false):
		return
	if text.strip_edges() == "":
		return
	var tutorial := get_parent().get_node_or_null("Tutorial")
	if tutorial != null and (tutorial as CanvasItem).visible:
		return
	_label.text = text
	visible = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.18)


func _hide_cue() -> void:
	if not visible:
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.24)
	_fade.tween_callback(func() -> void: visible = false)
