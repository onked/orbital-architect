extends PanelContainer

# Achievement toast notification
var _queue: Array = []
var _busy := false

@onready var _title: Label = %AchTitle
@onready var _detail: Label = %AchDetail
@onready var _kicker: Label = $Row/Info/Kicker

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker.text = Localization.t("ACHIEVEMENT UNLOCKED")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.070, 0.105, 0.98)
	sb.border_color = Color("#ffd166")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)
	pivot_offset = Vector2(181, 50)

func enqueue(title: String, detail: String) -> void:
	_queue.append({"title": title, "detail": detail})
	if not _busy:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	_title.text = Localization.t(str(item.get("title", "")))
	_detail.text = Localization.t(str(item.get("detail", "")))
	visible = true
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.92, 0.92)
	var open := create_tween().set_parallel(true)
	open.tween_property(self, "modulate:a", 1.0, 0.22)
	open.tween_property(self, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(3.6).timeout
	var close := create_tween().set_parallel(true)
	close.tween_property(self, "modulate:a", 0.0, 0.35)
	close.tween_property(self, "scale", Vector2(0.96, 0.96), 0.35)
	await close.finished
	visible = false
	_show_next()
