extends Control

# CRT overlay cuz why not
var _t: float = 0.0
var _scroll: float = 0.0

func _ready() -> void:
	add_to_group("crt_overlay")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_t += delta
	_scroll = fmod(_scroll + delta * 9.0, 3.0)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 2.0 or h < 2.0:
		return

	var offset: int = int(_scroll)
	for y in range(-3 + offset, int(h) + 3, 3):
		var alpha: float = 0.20 + 0.05 * sin(float(y) * 0.04 + _t * 5.0)
		draw_rect(Rect2(0.0, float(y), w, 1.0), Color(0.0, 0.0, 0.0, alpha), true)

	var band_y: float = fmod(_t * 120.0, h + 180.0) - 90.0
	for i in range(14):
		var d: float = absf(float(i) - 6.5) / 6.5
		var a: float = 0.045 * (1.0 - d)
		draw_rect(Rect2(0.0, band_y + float(i) * 2.0, w, 2.0),
			Color(0.65, 0.92, 1.0, a), true)
