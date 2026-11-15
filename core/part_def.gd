class_name PartDef
extends Resource

var id: String = ""
var display_name: String = ""
var category: String = ""
var mass_kg: float = 0.0
var cost_usd: float = 0.0
var power_w: float = 0.0
var slots: int = 1
var fuel_kg: float = 0.0
var isp_s: float = 0.0
var thrust_n: float = 0.0
var science: int = 0
var comms: int = 0
var solar: bool = false
var art_key: String = ""
var description: String = ""
var tags: Array = []

static func from_dict(d: Dictionary) -> PartDef:
	var p := PartDef.new()
	p.id = str(d.get("id", ""))
	p.display_name = str(d.get("name", p.id.capitalize()))
	p.category = str(d.get("category", "structure"))
	p.mass_kg = float(d.get("mass_kg", 0.0))
	p.cost_usd = float(d.get("cost_usd", 0.0))
	p.power_w = float(d.get("power_w", 0.0))
	p.slots = int(d.get("slots", 1))
	p.fuel_kg = float(d.get("fuel_kg", 0.0))
	p.isp_s = float(d.get("isp_s", 0.0))
	p.thrust_n = float(d.get("thrust_n", 0.0))
	p.science = int(d.get("science", 0))
	p.comms = int(d.get("comms", 0))
	p.solar = bool(d.get("solar", false))
	p.art_key = str(d.get("art", ""))
	p.description = str(d.get("desc", ""))
	p.tags = d.get("tags", [])
	return p

func power_label() -> String:
	if power_w == 0.0:
		return "--"
	if power_w > 0.0:
		return "+%d W" % int(power_w)
	return "%d W" % int(power_w)
