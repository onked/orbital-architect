extends Node

var bodies: Dictionary = {}
var body_list: Array = []
var parts: Dictionary = {}
var part_list: Array = []
var mission_list: Array = []
var mission_by_id: Dictionary = {}

var epoch_days: float = 9800.0
var mission_start_t: float = 0.0
var load_errors: Array = []

func _ready() -> void:
	_load_bodies()
	_load_parts()
	_load_missions()
	for err in load_errors:
		push_warning("[OrbitArchitect] " + str(err))

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("Missing data file: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("Cannot open: %s" % path)
		return null
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		load_errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _load_bodies() -> void:
	var raw: Variant = _read_json("res://data/bodies.json")
	if raw is not Dictionary:
		return
	var root: Dictionary = raw
	var epoch: Dictionary = root.get("epoch", {})
	epoch_days = float(epoch.get("mission_start_days_since_j2000", 9800.0))
	mission_start_t = epoch_days * 86400.0
	for entry in root.get("bodies", []):
		var b_def := CelestialBody.from_dict(entry)
		if b_def.id.is_empty():
			continue
		bodies[b_def.id] = b_def
		body_list.append(b_def)
	for b in body_list:
		var child: CelestialBody = b
		var parent: CelestialBody = bodies.get(child.parent_id, null)
		if parent != null:
			child.parent_mu = parent.mu

func _load_parts() -> void:
	var raw: Variant = _read_json("res://data/parts.json")
	if raw is not Dictionary:
		return
	for entry in (raw as Dictionary).get("parts", []):
		var p_def := PartDef.from_dict(entry)
		if p_def.id.is_empty():
			continue
		parts[p_def.id] = p_def
		part_list.append(p_def)

func _load_missions() -> void:
	var raw: Variant = _read_json("res://data/missions.json")
	if raw is not Dictionary:
		return
	for entry in (raw as Dictionary).get("missions", []):
		var m_def := MissionDef.from_dict(entry)
		if m_def.id.is_empty():
			continue
		mission_list.append(m_def)
		mission_by_id[m_def.id] = m_def

func add_body_def(entry: Dictionary) -> CelestialBody:
	var id := str(entry.get("id", ""))
	if id == "" or bodies.has(id):
		return bodies.get(id, null)
	var b := CelestialBody.from_dict(entry)
	var parent: CelestialBody = bodies.get(b.parent_id, null)
	if parent != null:
		b.parent_mu = parent.mu
	bodies[id] = b
	body_list.append(b)
	return b

func bodies_for_mission(mission: MissionDef) -> Dictionary:
	var out: Dictionary = {}
	for id in bodies.keys():
		if not str(id).begins_with("proc_"):
			out[id] = bodies[id]
	var target := str(mission.target_body) if mission != null else ""
	if bodies.has(target):
		out[target] = bodies[target]
	return out

func body(id: String) -> CelestialBody:
	return bodies.get(id, null)

func part(id: String) -> PartDef:
	return parts.get(id, null)

func mission(id: String) -> MissionDef:
	return mission_by_id.get(id, null)

func campaign_missions() -> Array:
	var out: Array = []
	for raw in mission_list:
		if not (raw as MissionDef).hidden:
			out.append(raw)
	return out
