class_name OrbitEmblem
extends Control

# cool emblem yippie
const SHEET := "logo_mark_anim"

var _t: float = 0.0

@onready var _sheet: Texture2D = Art.tex(SHEET)
@onready var _frames: int = maxi(Art.frame_count(SHEET), 1)
@onready var _fps: float = Art.frame_fps(SHEET)


func _ready() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b101b"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#253347"), false, 1.0)
	var fw: float = float(_sheet.get_width()) / float(_frames)
	var idx: int = int(_t * _fps) % _frames
	var inner := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	draw_texture_rect_region(_sheet, inner,
		Rect2(float(idx) * fw, 0.0, fw, float(_sheet.get_height())))
