class_name CraftState
extends RefCounted

const G0 := 9.80665
const AU_M := 149597870700.0

var px: float = 0.0
var py: float = 0.0
var vx: float = 0.0
var vy: float = 0.0

var pos: Vector2:
	get:
		return Vector2(px, py)
	set(value):
		px = value.x
		py = value.y

var vel: Vector2:
	get:
		return Vector2(vx, vy)
	set(value):
		vx = value.x
		vy = value.y

var dry_mass: float = 0.0
var fuel_mass: float = 0.0
var isp_s: float = 0.0
var thrust_n: float = 0.0
var solar_w: float = 0.0
var constant_w: float = 0.0
var draw_w: float = 0.0
var science_units: int = 0
var comms_level: int = 0
var has_heatshield: bool = false
var slots_used: int = 0
var slots_capacity: int = 0

var parts: Array = []
var fuel_used: float = 0.0
var intel_collected: int = 0
var alive: bool = true

func wet_mass() -> float:
	return dry_mass + fuel_mass

func mass() -> float:
	return wet_mass()

func delta_v() -> float:
	if isp_s <= 0.0 or fuel_mass <= 0.0:
		return 0.0
	return isp_s * G0 * log(wet_mass() / maxf(dry_mass, 1.0))

func twr() -> float:
	if thrust_n <= 0.0:
		return 0.0
	return thrust_n / maxf(wet_mass() * G0, 1.0)

func burn(dv: float) -> bool:
	if dv <= 0.0:
		return true
	if isp_s <= 0.0:
		return false
	var needed: float = fuel_for_dv(dv)
	if needed > fuel_mass + 1.0e-6:
		return false
	fuel_mass = maxf(0.0, fuel_mass - needed)
	fuel_used += needed
	return true

func fuel_for_dv(dv: float) -> float:
	if isp_s <= 0.0:
		return INF
	var m0: float = wet_mass()
	var m1: float = m0 / exp(dv / (isp_s * G0))
	return m0 - m1

func can_burn(dv: float) -> bool:
	return dv <= 0.0 or fuel_for_dv(dv) <= fuel_mass + 1.0e-6

func power_available(sun_distance_m: float) -> float:
	var solar_scale: float = 1.0
	if sun_distance_m > 1.0:
		var ratio: float = AU_M / sun_distance_m
		solar_scale = ratio * ratio
	return solar_w * solar_scale + constant_w - draw_w

func has_science() -> bool:
	return science_units > 0

func clone() -> CraftState:
	var c := CraftState.new()
	c.px = px
	c.py = py
	c.vx = vx
	c.vy = vy
	c.dry_mass = dry_mass
	c.fuel_mass = fuel_mass
	c.isp_s = isp_s
	c.thrust_n = thrust_n
	c.solar_w = solar_w
	c.constant_w = constant_w
	c.draw_w = draw_w
	c.science_units = science_units
	c.comms_level = comms_level
	c.has_heatshield = has_heatshield
	c.slots_used = slots_used
	c.slots_capacity = slots_capacity
	c.parts = parts.duplicate()
	c.fuel_used = fuel_used
	c.intel_collected = intel_collected
	c.alive = alive
	return c

static func build(design: Array, db: Dictionary) -> Dictionary:
	var craft := CraftState.new()
	var errors: Array = []
	var cost := 0.0
	var capacity := 0

	for raw_id in design:
		var pid := str(raw_id)
		var part: PartDef = db.get(pid, null)
		if part == null:
			errors.append("Unknown part: %s" % pid)
			continue
		craft.parts.append(pid)
		craft.dry_mass += part.mass_kg
		craft.fuel_mass += part.fuel_kg
		cost += part.cost_usd
		capacity += part.slots
		if part.isp_s > craft.isp_s:
			craft.isp_s = part.isp_s
		craft.thrust_n += part.thrust_n
		if part.solar:
			craft.solar_w += part.power_w
		elif part.power_w > 0.0:
			craft.constant_w += part.power_w
		elif part.power_w < 0.0:
			craft.draw_w += -part.power_w
		craft.science_units += part.science
		craft.comms_level = maxi(craft.comms_level, part.comms)
		if "heatshield" in part.tags:
			craft.has_heatshield = true

	craft.slots_used = design.size()
	craft.slots_capacity = capacity
	craft.parts = design.duplicate()

	if craft.slots_used > capacity:
		errors.append("Over slot capacity: %d / %d" % [craft.slots_used, capacity])
	if craft.isp_s <= 0.0:
		errors.append("No engine installed")
	if craft.fuel_mass <= 0.0:
		errors.append("No propellant tank installed")
	if craft.thrust_n <= 0.0:
		errors.append("Engine produces no thrust")

	return {"craft": craft, "errors": errors, "cost": cost}
