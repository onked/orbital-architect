class_name ShipBaker
extends RefCounted

static var _trimmed: Dictionary = {}

static func span(cells: Array) -> Vector2i:
	var cols: int = 0
	var rows: int = 0
	for c in cells:
		if typeof(c) != TYPE_VECTOR2I:
			continue
		var v: Vector2i = c
		cols = maxi(cols, v.x + 1)
		rows = maxi(rows, v.y + 1)
	return Vector2i(maxi(cols, 1), maxi(rows, 1))

static func trimmed(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var key: int = tex.get_instance_id()
	if _trimmed.has(key):
		return _trimmed[key]
	var rect := Rect2(Vector2.ZERO, Vector2(tex.get_size()))
	var img: Image = tex.get_image()
	if img != null:
		var used: Rect2i = img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = Rect2(Vector2(used.position), Vector2(used.size))
	_trimmed[key] = rect
	return rect
