extends Control

# Cool vehicle assembly stuff
const PART_CARD := preload("res://scenes/components/part_card.tscn")
const AU := 149597870700.0
const BAY_COLS := 17
const BAY_ROWS := 13
const BAY_CELLS := BAY_COLS * BAY_ROWS

var mission: MissionDef = null
var hub: String = "campaign"
var back_route: String = "briefing"
var design: Array = []
var cells: Array = []
var rots: Array = []
var hull: Array = []
var ghost_rot: int = 0
var selected_part: PartDef = null
var category: String = "all"

var _cost: float = 0.0
var _craft: CraftState = null
var _errors: Array = []
var _rebuild_pending: bool = false
var _canvas: BayCanvas = null

@onready var _header: ScreenHeader = %Header
@onready var _tabs: HBoxContainer = %Tabs
@onready var _part_list: VBoxContainer = %PartList
@onready var _bay_list: GridContainer = %BayList
@onready var _slots: Label = %Slots
@onready var _slot_bar: ProgressBar = %SlotBar
@onready var _suggested: Button = %Suggested
@onready var _clear: Button = %Clear
@onready var _delta_v: Label = %DeltaV
@onready var _dry: StatRow = %DryMass
@onready var _propellant: StatRow = %Propellant
@onready var _wet: StatRow = %WetMass
@onready var _thrust: StatRow = %Thrust
@onready var _twr: StatRow = %Twr
@onready var _cost_row: StatRow = %Cost
@onready var _budget: StatRow = %BudgetLeft
@onready var _power_sun: StatRow = %PowerSun
@onready var _power_target: StatRow = %PowerTarget
@onready var _science: StatRow = %Science
@onready var _comms: StatRow = %Comms
@onready var _status: Label = %Status

func _ready() -> void:
	if mission == null:
		return
	_header.setup(mission.code, Localization.t(mission.display_name).to_upper(),
		Localization.t("Assemble the bus, then paint parts into the bay. Mass, cost, power and delta-v update live."),
		Localization.t("LAUNCH  >"), Localization.t("< BLUEPRINTS") if back_route == "blueprints" else Localization.t("< DOSSIER"))
	design = GameState.design_for(mission.id)
	if design.is_empty():
		design = mission.recommended_design.duplicate()
	cells = GameState.layout_for(mission.id)
	rots = GameState.rot_for(mission.id)
	hull = GameState.hull_for(mission.id)
	_sync_cells()
	_make_canvas()

	_header.back_pressed.connect(func() -> void: EventBus.go_back.emit())
	_header.action_pressed.connect(_launch_flight)
	_suggested.pressed.connect(_use_suggested)
	_clear.pressed.connect(_clear_design)

	var keys := ["all", "structure", "propulsion", "power", "comms", "science"]
	for i in range(mini(keys.size(), _tabs.get_child_count())):
		var button: Button = _tabs.get_child(i)
		var key: String = keys[i]
		button.pressed.connect(func() -> void:
			category = key
			_refresh_tabs()
			_build_catalogue())
	_rebuild()
	_build_catalogue()

func _refresh_tabs() -> void:
	var keys := ["all", "structure", "propulsion", "power", "comms", "science"]
	for i in range(mini(keys.size(), _tabs.get_child_count())):
		var b: Button = _tabs.get_child(i)
		var active: bool = keys[i] == category
		b.add_theme_color_override("font_color", UiKit.CYAN if active else UiKit.MUTED)

func _rebuild() -> void:
	_rebuild_pending = false
	var built: Dictionary = CraftState.build(design, GameData.parts)
	_craft = built["craft"]
	_cost = float(built["cost"])
	_errors = built["errors"] as Array
	_errors = _assembly_errors(design, cells, hull) + _mission_errors() + _errors
	_refresh_tabs()
	_build_bay()
	_refresh_stats()

func _build_catalogue() -> void:
	for child in _part_list.get_children():
		_part_list.remove_child(child)
		child.queue_free()
	for part in GameData.part_list:
		var p: PartDef = part
		if category != "all" and p.category != category:
			continue
		var card: PartCard = PART_CARD.instantiate()
		_part_list.add_child(card)
		var can_add: bool = design.size() < BAY_CELLS
		card.setup(p, can_add)
		card.set_selected(selected_part != null and p.id == selected_part.id)
		card.add_requested.connect(_on_add)
		card.select_requested.connect(_select_part)

func _on_add(part: PartDef) -> void:
	if design.size() >= BAY_CELLS:
		EventBus.toast.emit(Localization.t("Bay is full (%d cells)", [BAY_CELLS]))
		return
	var free := _first_free_adjacent_cell()
	if free.x < 0:
		EventBus.toast.emit(Localization.t("No free cell next to the stack."))
		return
	design.append(part.id)
	cells.append(free)
	_rebuild()

func _first_free_adjacent_cell() -> Vector2i:
	if design.is_empty():
		return Vector2i(int(BAY_COLS / 2), int(BAY_ROWS / 2))
	for y in range(BAY_ROWS):
		for x in range(BAY_COLS):
			var c := Vector2i(x, y)
			if cells.find(c) >= 0:
				continue
			for n in _neighbours(c, cells):
				if n >= 0:
					return c
	return Vector2i(-1, -1)

func _build_bay() -> void:
	if _canvas == null:
		return
	_canvas.configure(design, cells, rots, hull, selected_part, ghost_rot)

func _make_canvas() -> void:
	if _bay_list == null:
		return
	var host: Node = _bay_list.get_parent()
	host.remove_child(_bay_list)
	_bay_list.queue_free()
	_bay_list = null
	_canvas = BayCanvas.new()
	_canvas.cols = BAY_COLS
	_canvas.rows = BAY_ROWS
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_canvas.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_canvas.cell_pressed.connect(_on_canvas_cell)
	_canvas.move_requested.connect(_on_canvas_move)
	host.add_child(_canvas)

func _zero_rots(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(0)
	return out

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_S:
			if mission != null:
				GameState.save_design(mission.id, design, cells, rots, hull)
				EventBus.toast.emit(Localization.t("Design saved."))
				get_viewport().set_input_as_handled()
			return
		if key.pressed and not key.echo and key.keycode == KEY_R:
			ghost_rot = (ghost_rot + 1) % 4
			_build_bay()

func _select_part(part: PartDef) -> void:
	selected_part = null if selected_part == part else part
	for card in _part_list.get_children():
		var p: PartDef = card.get("part")
		if p != null:
			card.call("set_selected", selected_part != null and p.id == selected_part.id)
	_build_bay()

func _on_remove(index: int) -> void:
	if index >= 0 and index < design.size():
		design.remove_at(index)
		cells.remove_at(index)
		rots.remove_at(index)
		_queue_rebuild()

func _on_canvas_cell(cell: Vector2i, secondary: bool) -> void:
	var existing: int = cells.find(cell)
	if secondary:
		if existing >= 0:
			_on_remove(existing)
		elif hull.has(cell):
			hull.erase(cell)
			_queue_rebuild()
		return
	if selected_part == null:
		if existing >= 0:
			_select_part(GameData.part(str(design[existing])))
		return
	if selected_part.id == "hull_panel":
		if not hull.has(cell):
			var next_hull: Array = hull.duplicate()
			next_hull.append(cell)
			_commit(design.duplicate(), cells.duplicate(), rots.duplicate(), next_hull)
		return
	var next_ids: Array = design.duplicate()
	var next_cells: Array = cells.duplicate()
	var next_rots: Array = rots.duplicate()
	if existing >= 0:
		next_ids[existing] = selected_part.id
		next_rots[existing] = ghost_rot
	elif next_ids.size() >= BAY_CELLS:
		EventBus.toast.emit(Localization.t("Bay is full (%d tiles)", [BAY_CELLS]))
		return
	else:
		next_ids.append(selected_part.id)
		next_cells.append(cell)
		next_rots.append(ghost_rot)
	_commit(next_ids, next_cells, next_rots, hull.duplicate())

func _commit(next_ids: Array, next_cells: Array, next_rots: Array, next_hull: Array) -> void:
	design = next_ids
	cells = next_cells
	rots = next_rots
	hull = next_hull
	_queue_rebuild()

func _on_canvas_move(from_index: int, cell: Vector2i) -> void:
	if from_index < 0 or from_index >= cells.size():
		return
	if cells[from_index] == cell:
		return
	var next_cells: Array = cells.duplicate()
	var other: int = next_cells.find(cell)
	if other >= 0:
		next_cells[other] = cells[from_index]
	next_cells[from_index] = cell
	_commit(design.duplicate(), next_cells, rots.duplicate(), hull.duplicate())

func _part_name(part_id: String) -> String:
	var part: PartDef = GameData.part(part_id)
	return Localization.t(part.display_name) if part != null else part_id

func _assembly_errors(ids: Array, layout: Array, hull_cells: Array) -> Array:
	var out: Array = []
	if ids.is_empty() and hull_cells.is_empty():
		return out
	var cores: Array = []
	var engines: Array = []
	var tanks: Array = []
	for i in range(ids.size()):
		var part: PartDef = GameData.part(str(ids[i]))
		if part == null:
			continue
		if part.id.begins_with("core_"):
			cores.append(i)
		if part.isp_s > 0.0:
			engines.append(i)
		if part.fuel_kg > 0.0:
			tanks.append(i)

	if cores.is_empty():
		out.append("No command core: place one from the catalogue (top entry).")
		return out
	if cores.size() > 1:
		out.append("Only one command core per vehicle.")
		return out

	var occupied: Dictionary = {}
	for c in hull_cells:
		occupied[c] = true
	occupied[layout[cores[0]]] = true
	var queue: Array = [layout[cores[0]]]
	var reached: Dictionary = {layout[cores[0]]: true}
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for d in dirs:
			var n: Vector2i = at + d
			if occupied.has(n) and not reached.has(n):
				reached[n] = true
				queue.append(n)

	for i in range(ids.size()):
		if not reached.has(layout[i]):
			out.append("%s is floating free of the core." % _part_name(str(ids[i])))
			return out

	for e in engines:
		var fed := false
		for d in dirs:
			var n: Vector2i = layout[e] + d
			if tanks.has(layout.find(n)):
				fed = true
		if not fed:
			out.append("%s is not attached to a propellant tank." % _part_name(str(ids[e])))
	return out

func _neighbours(at: Vector2i, layout: Array) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var j: int = layout.find(at + d)
		if j >= 0:
			out.append(j)
	return out

func _auto_layout(ids: Array) -> Array:
	var out: Array = []
	var rows: int = int(ceil(float(ids.size()) / float(BAY_COLS)))
	var y0: int = maxi(0, int(floor(float(BAY_ROWS - rows) * 0.5)))
	var x0: int = maxi(0, int(floor(float(BAY_COLS - mini(ids.size(), BAY_COLS)) * 0.5)))
	for i in range(ids.size()):
		var c := Vector2i(x0 + i % BAY_COLS, y0 + int(i / BAY_COLS))
		if c.x >= BAY_COLS or c.y >= BAY_ROWS:
			c = Vector2i(-1, -1)
		out.append(c)
	return out

func _sync_cells() -> void:
	var ok: bool = cells.size() == design.size()
	var seen: Dictionary = {}
	if ok:
		for c in cells:
			if typeof(c) != TYPE_VECTOR2I:
				ok = false
				break
			var v: Vector2i = c
			if v.x < 0 or v.y < 0 or v.x >= BAY_COLS or v.y >= BAY_ROWS or seen.has(v):
				ok = false
				break
			seen[v] = true
	if not ok:
		cells = _auto_layout(design)
	if rots.size() != design.size():
		rots = _zero_rots(design.size())
	if hull.is_empty() and not cells.is_empty():
		hull = cells.duplicate()

func _queue_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()

func _use_suggested() -> void:
	var ship: Dictionary = _suggested_ship()
	hull = ship.get("hull", [])
	cells = ship.get("cells", [])
	rots = ship.get("rots", [])
	design = mission.recommended_design.duplicate()
	_rebuild()

func _suggested_ship() -> Dictionary:
	var off := Vector2i(int((BAY_COLS - 13) / 2), int((BAY_ROWS - 7) / 2))
	var hull_cells: Array = []
	for y in range(3, 6):
		for x in range(2, 12):
			hull_cells.append(off + Vector2i(x, y))
	for x in range(12, 14):
		hull_cells.append(off + Vector2i(x, 4))
	for y in [2, 6]:
		hull_cells.append(off + Vector2i(4, y))
		hull_cells.append(off + Vector2i(5, y))
		hull_cells.append(off + Vector2i(9, y))
	var spots := {
		"core_bus": Vector2i(9, 4),
		"core_deep": Vector2i(9, 4),
		"structure_ring": Vector2i(8, 4),
		"tank_large": Vector2i(7, 4),
		"tank_small": Vector2i(7, 4),
		"engine_chem": Vector2i(6, 4),
		"engine_ion": Vector2i(6, 4),
		"solar_wing": Vector2i(10, 3),
		"dish_hga": Vector2i(11, 4),
		"antenna_lga": Vector2i(11, 4),
		"sci_relay": Vector2i(10, 4),
		"sci_camera": Vector2i(10, 4),
	}
	var out_cells: Array = []
	var out_rots: Array = []
	var used: Dictionary = {}
	var design_ids: Array = mission.recommended_design
	for raw in design_ids:
		var id := str(raw)
		var spot: Vector2i = spots.get(id, Vector2i(-1, -1))
		if spot.x >= 0 and not used.has(off + spot):
			out_cells.append(off + spot)
			used[off + spot] = true
		else:
			var fallback := Vector2i(-1, -1)
			for hc in hull_cells:
				if not used.has(hc):
					fallback = hc
					break
			out_cells.append(fallback)
			used[fallback] = true
		var rot := 1 if id.begins_with("engine_") else 0
		out_rots.append(rot)
	return {"hull": hull_cells, "cells": out_cells, "rots": out_rots}

func _clear_design() -> void:
	design.clear()
	cells.clear()
	rots.clear()
	hull.clear()
	_rebuild()

func _refresh_stats() -> void:
	var dv: float = _craft.delta_v()
	_delta_v.text = "%.0f m/s" % dv
	var dv_color := UiKit.GREEN
	if dv < 3000.0:
		dv_color = UiKit.CRIMSON
	elif dv < 4200.0:
		dv_color = UiKit.AMBER
	_delta_v.add_theme_color_override("font_color", dv_color)

	_dry.setup(Localization.t("Dry mass"), UiKit.kg(_craft.dry_mass))
	_propellant.setup(Localization.t("Propellant"), UiKit.kg(_craft.fuel_mass), UiKit.CYAN)
	_wet.setup(Localization.t("Wet mass"), UiKit.kg(_craft.wet_mass()),
		UiKit.CRIMSON if _craft.wet_mass() > mission.mass_cap_kg else UiKit.TEXT)
	_thrust.setup(Localization.t("Thrust"), "%.0f N" % _craft.thrust_n)
	_twr.setup(Localization.t("TWR (1 g)"), "%.2f" % _craft.twr())
	_cost_row.setup(Localization.t("Cost"), UiKit.money(_cost),
		UiKit.CRIMSON if _cost > mission.budget_usd else UiKit.TEXT)
	_budget.setup(Localization.t("Budget left"), UiKit.money(mission.budget_usd - _cost), UiKit.MUTED)

	var power_sun: float = _craft.power_available(AU)
	var target_body: CelestialBody = GameData.body(mission.target_body)
	var sun_d: float = _sun_distance(mission.target_body) if target_body != null else AU
	var power_target: float = _craft.power_available(sun_d)
	_power_sun.setup(Localization.t("Power @ 1 AU"), "%.0f W" % power_sun,
		UiKit.CRIMSON if power_sun < 0.0 else UiKit.GREEN)
	_power_target.setup(Localization.t("Power at target"), "%.0f W" % power_target,
		UiKit.CRIMSON if power_target < 0.0 else UiKit.GREEN)
	_science.setup(Localization.t("Science payloads"), str(_craft.science_units))
	_comms.setup(Localization.t("Comms level"), str(_craft.comms_level))

	_slots.text = Localization.t("PARTS %d / %d", [design.size(), BAY_CELLS])
	_slots.add_theme_color_override("font_color",
		UiKit.CYAN if design.size() <= BAY_CELLS else UiKit.CRIMSON)
	_slot_bar.value = clampf(float(design.size()) / float(BAY_CELLS), 0.0, 1.0)

	if _errors.is_empty():
		_status.text = Localization.t("ALL CHECKS PASSED")
		_status.add_theme_color_override("font_color", UiKit.GREEN)
	else:
		var lines: Array = []
		for err in _errors:
			lines.append("! " + Localization.translate_any(str(err)))
		_status.text = "\n".join(lines)
		_status.add_theme_color_override("font_color", UiKit.CRIMSON)
	_header.set_action_enabled(_errors.is_empty())

func _mission_errors() -> Array:
	var out: Array = []
	if _cost > mission.budget_usd:
		out.append(Localization.t("Over budget by %s", [UiKit.money(_cost - mission.budget_usd)]))
	if _craft.wet_mass() > mission.mass_cap_kg:
		out.append(Localization.t("Over mass cap by %s", [UiKit.kg(_craft.wet_mass() - mission.mass_cap_kg)]))
	for req in mission.required_parts:
		if not design.has(str(req)):
			var part: PartDef = GameData.part(str(req))
			out.append(Localization.t("Missing required payload: %s", [
				Localization.t(part.display_name) if part != null else str(req)]))
	return out

func _sun_distance(body_id: String) -> float:
	var total := 0.0
	var body: CelestialBody = GameData.body(body_id)
	var guard := 0
	while body != null and not body.parent_id.is_empty() and guard < 8:
		total += body.a_m
		body = GameData.body(body.parent_id)
		guard += 1
	return maxf(total, 1.0)

func _launch_flight() -> void:
	if not _errors.is_empty():
		return
	if mission.id == "sandbox":
		var price: int = int(round(_cost))
		if GameState.credits < price:
			EventBus.toast.emit(Localization.t("Not enough funds (%s).", [UiKit.money(float(price))]))
			return
		GameState.credits -= price
		GameState.save_campaign()
	GameState.save_design(mission.id, design, cells, rots, hull)
	GameState.clear_flight()
	EventBus.start_flight.emit(mission, design, _cost, cells, rots, hull)

func request_exit() -> void:
	EventBus.go_back.emit()
