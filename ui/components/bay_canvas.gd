class_name BayCanvas
extends Control

signal cell_pressed(cell: Vector2i, secondary: bool)
signal move_requested(from_index: int, cell: Vector2i)

const CELL := 32
const BG_PATH := "res://assets/art/generated/bay_bg.png"
const HULL_KEYS := ["icon_hull_a", "icon_hull_b", "icon_hull_c"]

var cols: int = 17
var rows: int = 13
var design: Array = []
var cells: Array = []
var rots: Array = []
var hull: Array = []
var ghost: PartDef = null
var ghost_rot: int = 0
var hull_brush: bool = false
var background: Texture2D = null

var _hover := Vector2i(-1, -1)
var _painting := false
var _last_paint := Vector2i(-1, -1)
var _drag_from: int = -1
var _hull_art: Array[Texture2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background = load(BG_PATH)
	for key in HULL_KEYS:
		_hull_art.append(Art.tex(str(key)))
	custom_minimum_size = Vector2(cols * CELL, rows * CELL)
	queue_redraw()

func configure(ids: Array, layout: Array, part_rots: Array, hull_cells: Array, ghost_part: PartDef, ghost_rotation: int) -> void:
	design = ids
	cells = layout
	rots = part_rots
	hull = hull_cells
	ghost = ghost_part
	ghost_rot = ghost_rotation
	hull_brush = ghost_part != null and ghost_part.id == "hull_panel"
	queue_redraw()

func _grid_origin() -> Vector2:
	var span := Vector2(cols * CELL, rows * CELL)
	var origin := ((size - span) * 0.5).floor()
	return Vector2(maxf(origin.x, 0.0), maxf(origin.y, 0.0))

func cell_at(pos: Vector2) -> Vector2i:
	var local := pos - _grid_origin()
	var c := Vector2i(floori(local.x / float(CELL)), floori(local.y / float(CELL)))
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return Vector2i(-1, -1)
	return c

func _hull_variant(c: Vector2i) -> Texture2D:
	if _hull_art.is_empty():
		return null
	var i: int = absi(c.x * 7 + c.y * 13) % _hull_art.size()
	return _hull_art[i]

func _draw() -> void:
	var span := Vector2(cols * CELL, rows * CELL)
	var origin := _grid_origin()
	draw_texture_rect(background, Rect2(origin, span), false)

	for c in hull:
		var v: Vector2i = c
		if v.x < 0 or v.x >= cols or v.y < 0 or v.y >= rows:
			continue
		var tex: Texture2D = _hull_variant(v)
		if tex == null:
			continue
		draw_texture_rect_region(tex, Rect2(origin + Vector2(v) * float(CELL), Vector2(CELL, CELL)), Rect2(Vector2.ZERO, Vector2(16, 16)))

	for i in range(mini(cells.size(), design.size())):
		var c: Vector2i = cells[i]
		if c.x < 0:
			continue
		var part: PartDef = GameData.part(str(design[i]))
		if part == null:
			continue
		var tex: Texture2D = Art.part_icon(part)
		if tex == null:
			continue
		var r: int = int(rots[i]) % 4 if i < rots.size() else 0
		var center := origin + (Vector2(c) + Vector2(0.5, 0.5)) * float(CELL)
		draw_set_transform(center, float(r) * PI * 0.5, Vector2.ONE)
		draw_texture_rect_region(tex, Rect2(Vector2(-CELL, -CELL) * 0.5, Vector2(CELL, CELL)), ShipBaker.trimmed(tex))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _hover.x >= 0:
		var rect := Rect2(origin + Vector2(_hover) * float(CELL), Vector2(CELL, CELL))
		if ghost != null:
			var gtex: Texture2D = Art.part_icon(ghost)
			if gtex != null:
				var gcenter := rect.position + Vector2(CELL, CELL) * 0.5
				draw_set_transform(gcenter, float(ghost_rot) * PI * 0.5, Vector2.ONE)
				draw_texture_rect_region(gtex, Rect2(Vector2(-CELL, -CELL) * 0.5, Vector2(CELL, CELL)), ShipBaker.trimmed(gtex), Color(1, 1, 1, 0.6))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(rect, Color(UiKit.CYAN.r, UiKit.CYAN.g, UiKit.CYAN.b, 0.7), false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var c := cell_at(motion.position)
		if c != _hover:
			_hover = c
			queue_redraw()
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if c.x < 0 or c == _last_paint:
			return
		_last_paint = c
		if _drag_from >= 0:
			move_requested.emit(_drag_from, c)
		elif _painting:
			cell_pressed.emit(c, false)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var c := cell_at(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_last_paint = c
				_drag_from = cells.find(c)
				if _drag_from < 0:
					_painting = true
					if c.x >= 0:
						cell_pressed.emit(c, false)
			else:
				_painting = false
				_drag_from = -1
				_last_paint = Vector2i(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and c.x >= 0:
			cell_pressed.emit(c, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i(-1, -1)
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()
