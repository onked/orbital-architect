extends Node

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.bak.json"
const SAVE_VERSION := 2

var designs: Dictionary = {}
var layouts: Dictionary = {}
var custom_missions: Array = []
var custom_serial: int = 0
var completed: Dictionary = {}
var credits: int = 0
var tutorial_done: bool = false
var tutorial_index: int = 0
var board: Array = []
var active_contract: Dictionary = {}
var reputation: int = 0
var contract_serial: int = 0
var campaign_day: float = 0.0
var flights: int = 0
var failures: int = 0
var hints_used: int = 0
var rewinds_used: int = 0
var achievement_defs: Array = []
var unlocked_achievements: Array = []
var economy_seeded: bool = false
var settings: Dictionary = {
	"animated": true, "scanlines": true, "motion": true,
	"fullscreen": false, "subtitles": false, "sandbox_target": "moon", "warp": 1,
	"vol_master": 0.8, "vol_sfx": 0.8, "vol_ambience": 0.35, "vol_music": 0.5,
	"vol_voice": 1.0, "locale": "en",
}
signal achievement_unlocked(id: String, title: String, detail: String)

var flight: Dictionary = {}
var pending_resume: bool = false
var save_warning: String = ""

func _ready() -> void:
	_load_achievements()
	load_campaign()
	ensure_board()
	ensure_free_build_bodies()
	ensure_saved_target_bodies()
	evaluate_achievements(false)

func design_for(mission_id: String) -> Array:
	return (designs.get(mission_id, []) as Array).duplicate()

func save_design(mission_id: String, part_ids: Array, layout: Array = [], rots: Array = [], hull: Array = []) -> void:
	designs[mission_id] = part_ids.duplicate()
	if not layout.is_empty() or not hull.is_empty():
		layouts[mission_id] = pack_bay(layout, rots, hull)
	save_campaign()

func pack_bay(layout: Array, rots: Array, hull: Array) -> Dictionary:
	var packed: Array = []
	for i in range(layout.size()):
		var v: Vector2i = layout[i]
		var r: int = int(rots[i]) % 4 if i < rots.size() else 0
		packed.append([v.x, v.y, r])
	var hull_rows: Array = []
	for c in hull:
		var h: Vector2i = c
		hull_rows.append([h.x, h.y])
	return {"cells": packed, "hull": hull_rows}

func _layout_data(mission_id: String) -> Dictionary:
	var raw: Variant = layouts.get(mission_id, [])
	if raw is Dictionary:
		return raw
	var rows: Array = []
	if raw is Array:
		rows = raw
	return {"cells": rows, "hull": []}

func rot_for(mission_id: String) -> Array:
	var out: Array = []
	for raw in (_layout_data(mission_id).get("cells", []) as Array):
		if raw is Array and (raw as Array).size() >= 3:
			out.append(int(raw[2]) % 4)
		else:
			out.append(0)
	return out

func layout_for(mission_id: String) -> Array:
	var out: Array = []
	for raw in (_layout_data(mission_id).get("cells", []) as Array):
		if raw is Array and (raw as Array).size() >= 2:
			out.append(Vector2i(int(raw[0]), int(raw[1])))
	return out

func hull_for(mission_id: String) -> Array:
	var out: Array = []
	for raw in (_layout_data(mission_id).get("hull", []) as Array):
		if raw is Array and (raw as Array).size() >= 2:
			out.append(Vector2i(int(raw[0]), int(raw[1])))
	return out

func record_report(report: Dictionary) -> void:
	var mid := str(report.get("mission_id", ""))
	flights += 1
	if not bool(report.get("success", false)):
		failures += 1
	hints_used += int(report.get("hint_penalty", 0.0))
	campaign_day += float(report.get("met", 0.0)) / 86400.0
	var score := float(report.get("total", 0.0))
	var previous := float((completed.get(mid, {}) as Dictionary).get("score", 0.0))
	report["previous_best"] = previous
	report["new_best"] = bool(report.get("success", false)) and score > previous + 0.001
	var medal := medal_for(score)
	var payout := 0
	if bool(report.get("success", false)):
		var best := maxf(previous, score)
		var c_tier := 0
		var c_template := ""
		if not active_contract.is_empty():
			c_tier = int(active_contract.get("tier", 0))
			c_template = str(active_contract.get("template", ""))
		completed[mid] = {"score": best, "clear": true, "medal": medal_for(best),
			"hints": int(report.get("hint_penalty", 0.0)),
			"tier": c_tier, "template": c_template}
		if GameData.mission(mid) != null:
			var campaign_mission: MissionDef = GameData.mission(mid)
			if not campaign_mission.hidden:
				payout = int(round(maxf(score - previous, 0.0) * 100000.0))
				credits += payout
		medal = medal_for(best)
	else:
		medal = ""
	report["medal"] = medal
	report["credits_awarded"] = payout

	var cid := ""
	if not active_contract.is_empty():
		cid = str((active_contract.get("mission", {}) as Dictionary).get("id", ""))
	if cid == mid:
		var reward := int(active_contract.get("reward", 0))
		report["contract_name"] = str((active_contract.get("mission", {}) as Dictionary).get("name", ""))
		if bool(report.get("success", false)):
			var quality := clampf(score / 100.0, 0.0, 1.0)
			var paid: int = int(round(float(reward) * (0.5 + 0.5 * quality)))
			credits += paid
			reputation += 1
			report["contract_reward"] = paid
		else:
			reputation = maxi(0, reputation - 1)
			report["contract_reward"] = 0
		report["reputation"] = reputation
		active_contract = {}
		_prune_board()

	flight = {}
	save_campaign()
	evaluate_achievements(true)

func medal_for(score: float) -> String:
	if score >= 90.0:
		return "GOLD"
	if score >= 75.0:
		return "SILVER"
	if score >= 60.0:
		return "BRONZE"
	return "CLEARED"

func mission_medal(mission_id: String) -> String:
	return str((completed.get(mission_id, {}) as Dictionary).get("medal", ""))

func contracts_done() -> int:
	var n := 0
	for id in completed.keys():
		if str(id).begins_with("contract_"):
			n += 1
	return n

func has_medal(rank: String) -> bool:
	for id in completed.keys():
		if str((completed[id] as Dictionary).get("medal", "")) == rank:
			return true
	return false

func clean_clear() -> bool:
	for id in completed.keys():
		var entry: Dictionary = completed[id]
		if int(entry.get("hints", 0)) == 0:
			return true
	return false

func medal_count() -> int:
	var n := 0
	for m in GameData.campaign_missions():
		if str((completed.get((m as MissionDef).id, {}) as Dictionary).get("medal", "")) != "":
			n += 1
	return n

func all_cleared() -> bool:
	for m in GameData.campaign_missions():
		if not completed.has((m as MissionDef).id):
			return false
	return true

func mission_cleared(mission_id: String) -> bool:
	return completed.has(mission_id)

func best_score(mission_id: String) -> float:
	return float((completed.get(mission_id, {}) as Dictionary).get("score", 0.0))

func setting(key: String, fallback: bool = true) -> bool:
	return bool(settings.get(key, fallback))

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_campaign()

func has_flight_save() -> bool:
	return not flight.is_empty() and str(flight.get("mission_id", "")) != ""

func save_flight(data: Dictionary) -> void:
	flight = data.duplicate(true)
	flight["saved_at"] = Time.get_datetime_string_from_system()
	save_campaign()

func clear_flight() -> void:
	if flight.is_empty():
		return
	flight = {}
	save_campaign()

func flight_mission() -> MissionDef:
	var mid := str(flight.get("mission_id", ""))
	if mid == "sandbox":
		return sandbox_mission(str(flight.get("target_body", "")))
	var mission: MissionDef = GameData.mission(mid)
	if mission == null:
		mission = custom_mission(mid)
	return mission

func add_custom_mission(data: Dictionary) -> MissionDef:
	custom_serial += 1
	var entry: Dictionary = data.duplicate(true)
	entry["id"] = "custom_%d" % custom_serial
	entry["playable"] = true
	custom_missions.append(entry)
	save_campaign()
	return MissionDef.from_dict(entry)

func custom_mission(id: String) -> MissionDef:
	for raw in custom_missions:
		var entry: Dictionary = raw
		if str(entry.get("id", "")) == id:
			return MissionDef.from_dict(entry)
	return null

func delete_custom_mission(id: String) -> void:
	for i in range(custom_missions.size() - 1, -1, -1):
		if str((custom_missions[i] as Dictionary).get("id", "")) == id:
			custom_missions.remove_at(i)
	designs.erase(id)
	layouts.erase(id)
	completed.erase(id)
	if str(flight.get("mission_id", "")) == id:
		clear_flight()
	save_campaign()

func sandbox_mission(target_override: String = "") -> MissionDef:
	var target_id := target_override if target_override != "" else str(settings.get("sandbox_target", "moon"))
	var target: CelestialBody = GameData.body(target_id)
	if target == null:
		target_id = "moon"
		target = GameData.body(target_id)
	var m := MissionDef.new()
	m.id = "sandbox"
	m.number = 0
	m.display_name = "Sandbox Sim"
	m.code = "LAB / FREE BUILD"
	m.playable = true
	m.target_body = target_id
	m.start_body = "earth"
	m.start_altitude_m = 200000.0
	m.budget_usd = maxf(float(credits), 1000000.0)
	m.mass_cap_kg = 1.0e6
	m.recommended_design = ["core_bus", "tank_small", "engine_chem", "solar_wing"]
	m.science_range_m = 1.0e9
	m.duration_days = _sandbox_duration(target)
	m.objectives = [
		{
			"id": "depart",
			"label": "Test flight",
			"detail": "Reach 1,000 km from Earth.",
			"points": 25,
			"kind": "distance",
			"body": "earth",
			"value": 1000,
		},
		{
			"id": "target",
			"label": "Reach target SOI",
			"detail": "Enter the target's sphere of influence.",
			"points": 50,
			"kind": "soi",
			"body": target_id,
		},
	]
	return m

func _sandbox_duration(target: CelestialBody) -> float:
	if target == null:
		return 180.0
	if target.parent_id == "earth":
		return 180.0
	var au := 0.0
	var body: CelestialBody = target
	var guard := 0
	while body != null and body.parent_id != "" and guard < 8:
		au += body.a_m / Ephemeris.AU_M
		body = GameData.body(body.parent_id)
		guard += 1
	return clampf(180.0 + au * 420.0, 180.0, 6000.0)

func set_sandbox_target(id: String) -> void:
	if GameData.body(id) == null:
		return
	settings["sandbox_target"] = id
	save_campaign()

func sandbox_duration_for(id: String) -> float:
	return _sandbox_duration(GameData.body(id))

func ensure_free_build_bodies() -> void:
	for serial in [90001, 90002, 90003, 90004]:
		var id := "proc_%d" % int(serial)
		if GameData.body(id) != null:
			continue
		var offer := ContractGen.make_offer(int(serial), GameData.bodies)
		if not offer.is_empty():
			_add_offer_body(offer)

func ensure_saved_target_bodies() -> void:
	var ids: Array = [str(settings.get("sandbox_target", ""))]
	for raw in custom_missions:
		ids.append(str((raw as Dictionary).get("target_body", "")))
	for raw in ids:
		var id := str(raw)
		if not id.begins_with("proc_") or GameData.body(id) != null:
			continue
		var serial := int(id.substr(5))
		var offer := ContractGen.make_offer(serial, GameData.bodies)
		if not offer.is_empty():
			_add_offer_body(offer)

func relocalize_board() -> void:
	for raw in board:
		_relocalize_offer(raw)
	if not active_contract.is_empty():
		_relocalize_offer(active_contract)


func _relocalize_offer(offer: Dictionary) -> void:
	var serial := int(offer.get("serial", 0))
	if serial <= 0:
		return
	var fresh := ContractGen.make_offer(serial, GameData.bodies)
	if fresh.is_empty():
		return
	offer["mission"] = fresh.get("mission", offer.get("mission", {}))
	offer["template"] = fresh.get("template", offer.get("template", "orbit"))
	var body: Dictionary = offer.get("body", {})
	body["name"] = str((fresh.get("body", {}) as Dictionary).get("name", body.get("name", "")))
	offer["body"] = body


func ensure_board() -> void:
	if board.is_empty() and active_contract.is_empty():
		refresh_board()
	else:
		var migrated := false
		for raw in board:
			if _ensure_offer(raw):
				migrated = true
		if not active_contract.is_empty():
			if _ensure_offer(active_contract):
				migrated = true
		_prune_board()
		_register_contract_bodies()
		if migrated:
			save_campaign()

func refresh_board() -> void:
	board.clear()
	for i in range(3):
		board.append(_new_offer())
	save_campaign()

func accept_contract(index: int) -> MissionDef:
	ensure_board()
	if not active_contract.is_empty():
		return null
	if index < 0 or index >= board.size():
		return null
	active_contract = board[index]
	board.remove_at(index)
	credits += int(active_contract.get("advance", 0))
	_add_offer_body(active_contract)
	save_campaign()
	evaluate_achievements(true)
	return MissionDef.from_dict(active_contract["mission"] as Dictionary)

func active_mission() -> MissionDef:
	if active_contract.is_empty():
		return null
	_add_offer_body(active_contract)
	return MissionDef.from_dict(active_contract["mission"] as Dictionary)

func _new_offer() -> Dictionary:
	contract_serial += 1
	var offer := ContractGen.make_offer(contract_serial, GameData.bodies)
	var tier := float(offer.get("tier", 1))
	offer["expires_day"] = campaign_day + 60.0 + 60.0 * tier
	_add_offer_body(offer)
	return offer

func _prune_board() -> void:
	var changed := false
	for i in range(board.size() - 1, -1, -1):
		var offer: Dictionary = board[i]
		if float(offer.get("expires_day", 1.0e30)) <= campaign_day:
			board.remove_at(i)
			changed = true
	while board.size() < 3:
		board.append(_new_offer())
		changed = true
	if changed:
		save_campaign()

func _register_contract_bodies() -> void:
	for raw in board:
		_ensure_offer(raw)
	if not active_contract.is_empty():
		_ensure_offer(active_contract)

func _ensure_offer(offer: Dictionary) -> bool:
	var changed := false
	if not offer.has("expires_day"):
		offer["expires_day"] = campaign_day + 120.0 + 60.0 * float(offer.get("tier", 1))
		changed = true
	var body: Dictionary = offer.get("body", {})
	var key := str(body.get("id", ""))
	if key != "" and (str(body.get("art", "")) == "" or not Art.has(key)):
		changed = true
	_add_offer_body(offer)
	return changed

func _add_offer_body(offer: Dictionary) -> void:
	var body: Dictionary = offer.get("body", {})
	var id := str(body.get("id", ""))
	if id == "":
		return
	var key := id
	if not Art.has(key):
		Art.register_texture(key, _make_body_texture(body))
	body["art"] = key
	GameData.add_body_def(body)

func _make_body_texture(body: Dictionary) -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := Color(str(body.get("color", "#9aa8c9")))
	var planet: bool = str(body.get("parent", "")) == "sun" \
		or float(body.get("atmosphere_top_m", 0.0)) > 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = str(body.get("id", "")).hash()
	var craters: Array = []
	for i in range(6):
		craters.append(Vector3(rng.randf_range(-15.0, 15.0),
			rng.randf_range(-15.0, 15.0), rng.randf_range(1.5, 4.5)))
	var radius := float(n) * 0.5 - 1.0
	var half := (float(n) - 1.0) * 0.5
	for y in range(n):
		for x in range(n):
			var dx := float(x) - half
			var dy := float(y) - half
			var d := sqrt(dx * dx + dy * dy)
			if d > radius:
				continue
			var shade := 1.0 - 0.30 * (dx + dy) / float(n)
			if planet:
				shade *= 1.0 + 0.10 * sin(float(y) * 0.55 + float(rng.seed % 17))
			else:
				for c in craters:
					var dv := Vector2(dx - (c as Vector3).x, dy - (c as Vector3).y)
					if dv.length() < (c as Vector3).z:
						shade *= 0.78 if dv.x + dv.y < 0.0 else 1.12
			if d > radius - 1.5:
				shade *= 0.72
			img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	return ImageTexture.create_from_image(img)

func _load_achievements() -> void:
	achievement_defs = []
	if not FileAccess.file_exists("res://data/achievements.json"):
		return
	var file := FileAccess.open("res://data/achievements.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		achievement_defs = parsed

func evaluate_achievements(announce: bool) -> Array:
	var fresh: Array = []
	for raw in achievement_defs:
		var a: Dictionary = raw
		var id := str(a.get("id", ""))
		if id == "" or unlocked_achievements.has(id):
			continue
		if not _achievement_met(a):
			continue
		unlocked_achievements.append(id)
		fresh.append(a)
		if announce:
			achievement_unlocked.emit(id, str(a.get("name", id)), str(a.get("desc", "")))
	if not fresh.is_empty():
		save_campaign()
	return fresh

func _achievement_met(a: Dictionary) -> bool:
	var value: Variant = a.get("value", 0)
	match str(a.get("kind", "")):
		"flights":
			return flights >= int(value)
		"failures":
			return failures >= int(value)
		"contracts":
			return contracts_done() >= int(value)
		"mission":
			return mission_cleared(str(value))
		"medal":
			return has_medal(str(value))
		"gold_count":
			return _medal_total("GOLD") >= int(value)
		"credits":
			return credits >= int(value)
		"no_hints":
			return clean_clear()
		"all_missions":
			return all_cleared()
		"perfect":
			return _best_score() >= 99.5
		"tier":
			return _max_contract_tier() >= int(value)
		"landings":
			return _landing_count() >= int(value)
		"tutorial":
			return tutorial_done
		"designs":
			return designs.size() >= int(value)
		"rewinds":
			return rewinds_used >= int(value)
	return false

func _medal_total(rank: String) -> int:
	var n := 0
	for id in completed.keys():
		if str((completed[id] as Dictionary).get("medal", "")) == rank:
			n += 1
	return n

func _best_score() -> float:
	var best := 0.0
	for id in completed.keys():
		best = maxf(best, float((completed[id] as Dictionary).get("score", 0.0)))
	return best

func _max_contract_tier() -> int:
	var tier := 0
	for id in completed.keys():
		tier = maxi(tier, int((completed[id] as Dictionary).get("tier", 0)))
	return tier

func _landing_count() -> int:
	var n := 0
	for id in completed.keys():
		if str((completed[id] as Dictionary).get("template", "")) == "land":
			n += 1
	return n
	
func save_campaign() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"designs": designs,
		"layouts": layouts,
		"custom_missions": custom_missions,
		"custom_serial": custom_serial,
		"completed": completed,
		"credits": credits,
		"tutorial_done": tutorial_done,
		"tutorial_index": tutorial_index,
		"board": board,
		"active_contract": active_contract,
		"reputation": reputation,
		"contract_serial": contract_serial,
		"campaign_day": campaign_day,
		"flights": flights,
		"failures": failures,
		"hints_used": hints_used,
		"rewinds_used": rewinds_used,
		"unlocked_achievements": unlocked_achievements,
		"economy_seeded": economy_seeded,
		"settings": settings,
		"flight": flight,
	}
	return _write_atomic(SAVE_PATH, payload)

func _write_atomic(path: String, payload: Dictionary) -> bool:
	var text := JSON.stringify(payload, "\t")
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		if old != null:
			var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if backup != null:
				backup.store_string(old.get_as_text())
				backup.close()
			old.close()
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		save_warning = "Could not open save file for writing"
		return false
	f.store_string(text)
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		save_warning = "Could not open user directory"
		return false
	var name := path.get_file()
	if FileAccess.file_exists(path):
		dir.remove(name)
	var err := dir.rename(tmp_path.get_file(), name)
	if err != OK:
		save_warning = "Could not replace save file (%d)" % err
		return false
	save_warning = ""
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

func load_campaign() -> void:
	var data := _read_json(SAVE_PATH)
	if data.is_empty():
		data = _read_json(BACKUP_PATH)
		if not data.is_empty():
			save_warning = "Save recovered from backup"
	if data.is_empty():
		return
	designs = data.get("designs", {})
	layouts = data.get("layouts", {})
	custom_missions = data.get("custom_missions", [])
	custom_serial = int(data.get("custom_serial", custom_missions.size()))
	completed = data.get("completed", {})
	credits = int(data.get("credits", 0))
	tutorial_done = bool(data.get("tutorial_done", false))
	tutorial_index = int(data.get("tutorial_index", 0))
	var migrated := false
	for id in completed.keys():
		var entry: Dictionary = completed[id]
		if not entry.has("medal"):
			entry["medal"] = medal_for(float(entry.get("score", 0.0)))
			migrated = true
	if credits <= 0 and not completed.is_empty():
		var back_pay := 0
		for id in completed.keys():
			back_pay += int(round(float((completed[id] as Dictionary).get("score", 0.0)) * 100000.0))
		credits = back_pay
		migrated = true
	var stored: Variant = data.get("settings", {})
	if stored is Dictionary:
		for key in settings.keys():
			if not (stored as Dictionary).has(key):
				continue
			var value: Variant = (stored as Dictionary)[key]
			if key == "warp":
				settings[key] = int(value)
			elif typeof(settings[key]) == TYPE_STRING:
				settings[key] = str(value)
			elif typeof(settings[key]) == TYPE_FLOAT:
				settings[key] = clampf(float(value), 0.0, 1.0)
			else:
				settings[key] = bool(value)
	flight = data.get("flight", {})
	board = data.get("board", [])
	active_contract = data.get("active_contract", {})
	reputation = maxi(0, int(data.get("reputation", 0)))
	contract_serial = int(data.get("contract_serial", 0))
	campaign_day = float(data.get("campaign_day", 0.0))
	flights = int(data.get("flights", 0))
	failures = int(data.get("failures", 0))
	hints_used = int(data.get("hints_used", 0))
	rewinds_used = int(data.get("rewinds_used", 0))
	unlocked_achievements = data.get("unlocked_achievements", [])
	economy_seeded = bool(data.get("economy_seeded", false))
	if flights == 0 and not completed.is_empty():
		flights = completed.size()
		migrated = true
	if not economy_seeded:
		economy_seeded = true
		if credits < 25000000:
			credits = 25000000
		migrated = true
	_register_contract_bodies()
	if migrated:
		save_campaign()
