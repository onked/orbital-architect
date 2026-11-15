extends Node

const MANIFEST_PATH := "res://assets/art/art_manifest.json"

var manifest: Dictionary = {}
var _cache: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_cache.clear()
	manifest = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("[Art] No art manifest at %s -- using procedural placeholders." % MANIFEST_PATH)
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		manifest = parsed
	else:
		push_warning("[Art] Could not parse art manifest.")

func texture_path(key: String) -> String:
	var textures: Dictionary = manifest.get("textures", {})
	var entry: Variant = textures.get(key, "")
	if entry is Dictionary:
		return str((entry as Dictionary).get("sheet", ""))
	return str(entry)

func frame_count(key: String) -> int:
	var textures: Dictionary = manifest.get("textures", {})
	var entry: Variant = textures.get(key, "")
	if entry is Dictionary:
		return maxi(1, int((entry as Dictionary).get("frames", 1)))
	return 1

func frame_fps(key: String) -> float:
	var textures: Dictionary = manifest.get("textures", {})
	var entry: Variant = textures.get(key, "")
	if entry is Dictionary:
		return maxf(1.0, float((entry as Dictionary).get("fps", 8.0)))
	return 1.0

func tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := texture_path(key)
	var result: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			result = res
	_cache[key] = result
	return result

func part_icon(part: PartDef) -> Texture2D:
	if part == null:
		return null
	return tex(part.art_key)

func register_texture(key: String, texture: Texture2D) -> void:
	_cache[key] = texture

func has(key: String) -> bool:
	return tex(key) != null
