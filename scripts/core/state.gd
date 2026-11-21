extends Node

# Ground-up State & Progression for STAR REPLICA: AUTOMA
# Fuses DESIGN_SPECIFICATION.md (Seed Unit + Docking Fabricator Drones + Multi-Layer Factory + 10,000 Swarm)
# with Spherical Gravity/Keplerian Orbit, Wired Power Grid, 4-Way Depot Filter & Factorio Tech Tree.

signal resource_changed(id: String, amt: int)
signal tech_unlocked(id: String)
signal drone_docked(count: int)
signal propulsion_upgraded(tier: int)
signal log_added(msg: String, kind: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

const SWARM_MAX: int = 10000
const MAX_DRONES: int = 8
const DRONE_COST: Dictionary = {"fe": 10, "cu": 6}

var res: Dictionary = {}
var unlocked_techs: Array[String] = ["seed_core"]
var attached_drones: int = 0
var propulsion_tier: int = 0 # 0: Surface Ion, 1: Orbital Booster, 2: Deep Cryo, 3: Swarm Flagship

var hp: float = 100.0
var max_hp: float = 100.0
var fuel: float = 120.0
var max_fuel: float = 120.0
var ion_bat: float = 100.0
var max_ion_bat: float = 100.0

var swarm_fleet: int = 0
var total_launches: int = 0
var doctrine: int = Doctrine.HARVEST
var boss_hp: float = 3500.0
var boss_max_hp: float = 3500.0
var boss_dead: bool = false
var game_won: bool = false

# Wired Local Grid Telemetry
var pwr_prod: float = 0.0
var pwr_use: float = 0.0
var pwr_stored: float = 0.0
var pwr_cap: float = 0.0
var wire_count: int = 0
var active_teslas: int = 0
var active_printers: int = 0
var total_printers: int = 0

# Active tool & controls
var selected_tool: String = "mine"
var build_dir: int = 1
var orbit_view: bool = false
var megastructures: Dictionary = {"elevator": false, "dyson": false, "citadel": false, "warpgate": false}
var logs: Array[Dictionary] = []

const PROPULSION_TIERS: Dictionary = {
	0: {"name": "Seed Ion Hover",   "thrust": 0.0,    "ion": 440.0, "max_spd": 210.0, "fuel": 120.0, "req": "seed_core",       "cost": {}},
	1: {"name": "Orbital Booster",  "thrust": 430.0,  "ion": 450.0, "max_spd": 320.0, "fuel": 190.0, "req": "smelting_booster","cost": {"fe": 16, "cu": 8, "plate_fe": 4}},
	2: {"name": "Deep Cryo Drive",  "thrust": 720.0,  "ion": 480.0, "max_spd": 560.0, "fuel": 320.0, "req": "deep_space",      "cost": {"plate_fe": 10, "wire_cu": 8, "wafer_si": 4, "circuit": 4}},
	3: {"name": "Swarm Flagship",   "thrust": 1200.0, "ion": 540.0, "max_spd": 900.0, "fuel": 480.0, "req": "macro_swarm",     "cost": {"plate_fe": 16, "circuit": 10, "alloy": 6, "ti": 12}},
}

const TECH_ORDER: Array[String] = [
	"seed_core", "power_grid", "cave_logistics", "smelting_booster",
	"circuits_geo", "deep_space", "macro_swarm", "megastructures",
]

const TECHS: Dictionary = {
	"seed_core": {
		"name": "Seed Core", "col": 0, "row": 1, "req": [], "cost": {},
		"unlocks": ["Mining Laser", "Docking Drones"],
		"summary": "Dock Fabricator Drones onto Seed Unit for multi-beam mining.",
		"flow": "Mine Fe/Cu/Si -> Dock Drones -> Power Grid",
	},
	"power_grid": {
		"name": "Power & Tesla", "col": 1, "row": 0, "req": ["seed_core"],
		"cost": {"fe": 12, "cu": 6},
		"unlocks": ["solar", "tesla", "battery", "wire"],
		"summary": "Link Solar & Night Batteries via Power Wires to Tesla Relays.",
		"flow": "Solar + Battery -(Wire)-> Tesla -(Dome)-> Machines",
	},
	"cave_logistics": {
		"name": "Cave Logistics", "col": 1, "row": 2, "req": ["power_grid"],
		"cost": {"fe": 16, "cu": 8},
		"unlocks": ["drill", "belt", "lift", "depot"],
		"summary": "Mine caves with Drills; haul via Belts/Lifts to Cargo Depots.",
		"flow": "Drill -> Belt/Lift -> Cargo Depot (4-Way Filter)",
	},
	"smelting_booster": {
		"name": "Smelting & Orbit", "col": 2, "row": 1, "req": ["cave_logistics"],
		"cost": {"fe": 22, "cu": 12},
		"unlocks": ["smelter", "Orbital Booster"],
		"summary": "Smelters refine Plates, Wires & Wafers; unlocks Orbital Booster!",
		"flow": "Depot -> Smelter -> Plates/Wires -> Orbital Booster",
	},
	"circuits_geo": {
		"name": "Circuits & Geo", "col": 3, "row": 0, "req": ["smelting_booster"],
		"cost": {"plate_fe": 6, "wire_cu": 4, "si": 8},
		"unlocks": ["assembler", "geothermal", "turret"],
		"summary": "Assemblers craft Circuits & Alloys; Geothermal taps core magma.",
		"flow": "Smelter -> Assembler (Circuits) + 24/7 Magma Power",
	},
	"deep_space": {
		"name": "Deep-Space Cryo", "col": 3, "row": 2, "req": ["circuits_geo"],
		"cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "circuit": 4},
		"unlocks": ["Deep Cryo Drive"],
		"summary": "High-ISP orbital drive for moon landings & asteroid harvesting.",
		"flow": "Keplerian Orbit -> LUNA/IGNIS/CRYO Rare Ti & Ice",
	},
	"macro_swarm": {
		"name": "Macro Swarm", "col": 4, "row": 1, "req": ["deep_space"],
		"cost": {"plate_fe": 12, "circuit": 8, "ti": 10},
		"unlocks": ["gantry_printer", "mass_driver", "Flagship"],
		"summary": "Gantry Printers build Probes -> Mass Driver fires 10,000 Swarm!",
		"flow": "Macro Printer -> Belt -> Mass Driver -> 10k Fleet",
	},
	"megastructures": {
		"name": "Megastructures", "col": 5, "row": 1, "req": ["macro_swarm"],
		"cost": {"alloy": 8, "circuit": 12, "ti": 16},
		"unlocks": ["Elevator", "Dyson", "Citadel", "Warp Gate"],
		"summary": "Build orbital megastructures & shatter the Corrupted Fortress.",
		"flow": "10,000 Swarm Assault + Warp Gate -> Victory",
	},
}

const HOTBAR_TABS: Array[Dictionary] = [
	{"id": "logi",  "label": "MINE & LOGI", "items": ["mine", "drill", "belt", "lift", "depot", "salvage"]},
	{"id": "fact",  "label": "FACTORY",     "items": ["mine", "smelter", "assembler", "gantry_printer", "mass_driver", "salvage"]},
	{"id": "power", "label": "POWER & DEF", "items": ["mine", "solar", "tesla", "battery", "geothermal", "turret", "wire"]},
]

const BLD: Dictionary = {
	"solar":          {"name": "Solar Array",      "tex": "solar",          "req": "power_grid",       "cost": {"fe": 10, "cu": 6},                    "gen": 44.0,  "use": 0.0,  "w": 74, "h": 54},
	"tesla":          {"name": "Tesla Relay",      "tex": "tesla",          "req": "power_grid",       "cost": {"fe": 10, "cu": 8},                    "gen": 0.0,   "use": 0.0,  "w": 54, "h": 78},
	"battery":        {"name": "Power Bank",       "tex": "battery",        "req": "power_grid",       "cost": {"fe": 12, "cu": 8, "si": 4},           "gen": 0.0,   "use": 0.0,  "w": 58, "h": 56},
	"geothermal":     {"name": "Geothermal Plant", "tex": "geothermal",     "req": "circuits_geo",     "cost": {"plate_fe": 8, "wire_cu": 6, "si": 6}, "gen": 135.0, "use": 0.0,  "w": 78, "h": 74},
	"turret":         {"name": "Laser Turret",     "tex": "turret",         "req": "circuits_geo",     "cost": {"plate_fe": 8, "wire_cu": 6},          "gen": 0.0,   "use": 14.0, "w": 58, "h": 58},
	"drill":          {"name": "Mining Drill",     "tex": "drill",          "req": "cave_logistics",   "cost": {"fe": 12, "cu": 6},                    "gen": 0.0,   "use": 12.0, "w": 58, "h": 78},
	"belt":           {"name": "Conveyor Belt",    "tex": "belt",           "req": "cave_logistics",   "cost": {"fe": 2},                              "gen": 0.0,   "use": 1.0,  "w": 48, "h": 18},
	"lift":           {"name": "Lift Shaft",       "tex": "lift",           "req": "cave_logistics",   "cost": {"fe": 3},                              "gen": 0.0,   "use": 1.0,  "w": 24, "h": 54},
	"depot":          {"name": "Cargo Depot",      "tex": "depot",          "req": "cave_logistics",   "cost": {"fe": 16, "cu": 6},                    "gen": 0.0,   "use": 0.0,  "w": 100,"h": 60},
	"smelter":        {"name": "Blast Smelter",    "tex": "smelter",        "req": "smelting_booster", "cost": {"fe": 18, "cu": 10},                   "gen": 0.0,   "use": 18.0, "w": 88, "h": 88},
	"assembler":      {"name": "Auto Assembler",   "tex": "assembler",      "req": "circuits_geo",     "cost": {"plate_fe": 8, "wire_cu": 6, "si": 4}, "gen": 0.0,   "use": 22.0, "w": 84, "h": 68},
	"gantry_printer": {"name": "Macro 3D Printer", "tex": "gantry_printer", "req": "macro_swarm",      "cost": {"plate_fe": 16, "circuit": 6, "ti": 8},"gen": 0.0,   "use": 34.0, "w": 134,"h": 96},
	"mass_driver":    {"name": "Mass Driver",      "tex": "mass_driver",    "req": "macro_swarm",      "cost": {"plate_fe": 18, "wire_cu": 10, "circuit": 6}, "gen": 0.0, "use": 30.0, "w": 134,"h": 112},
}

const MEGAS: Dictionary = {
	"elevator": {"name": "Space Elevator",  "cost": {"plate_fe": 18, "wire_cu": 14, "alloy": 6},  "fleet": 300},
	"dyson":    {"name": "Dyson Ring",      "cost": {"wafer_si": 14, "circuit": 10, "alloy": 6},  "fleet": 0},
	"citadel":  {"name": "Orbital Citadel", "cost": {"alloy": 10, "circuit": 12, "ti": 16},       "fleet": 700},
	"warpgate": {"name": "Star Warp Gate",  "cost": {"alloy": 12, "circuit": 14, "sci_pack": 5},  "fleet": 0},
}

func _ready() -> void:
	reset_all()

func reset_all() -> void:
	res = {
		"fe": 0, "cu": 0, "si": 0, "ti": 0, "ice": 0,
		"plate_fe": 0, "wire_cu": 0, "wafer_si": 0,
		"circuit": 0, "alloy": 0, "sci_pack": 0, "probe_stock": 0,
	}
	unlocked_techs = ["seed_core"]
	attached_drones = 0
	propulsion_tier = 0
	max_hp = 100.0; hp = 100.0
	max_fuel = float(PROPULSION_TIERS[0]["fuel"]); fuel = max_fuel
	max_ion_bat = 100.0; ion_bat = 100.0
	swarm_fleet = 0; total_launches = 0; doctrine = Doctrine.HARVEST
	boss_hp = boss_max_hp; boss_dead = false; game_won = false
	pwr_prod = 0.0; pwr_use = 0.0; pwr_stored = 0.0; pwr_cap = 0.0
	wire_count = 0; active_teslas = 0; active_printers = 0; total_printers = 0
	selected_tool = "mine"; build_dir = 1; orbit_view = false
	megastructures = {"elevator": false, "dyson": false, "citadel": false, "warpgate": false}
	logs.clear()
	add_log("SEED DEPLOYED. Mine crust & dock Drones!", "info")

func get_r(id: String) -> int:
	return int(res.get(id, 0))

func add_r(id: String, delta: int) -> void:
	res[id] = maxi(0, int(res.get(id, 0)) + delta)
	resource_changed.emit(id, int(res[id]))

func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if get_r(String(k)) < int(cost[k]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost.keys():
		add_r(String(k), -int(cost[k]))
	return true

func has_tech(tid: String) -> bool:
	return tid in unlocked_techs

func can_research(tid: String) -> bool:
	if has_tech(tid) or not TECHS.has(tid): return false
	for r in TECHS[tid]["req"]:
		if not has_tech(String(r)): return false
	return can_afford(TECHS[tid]["cost"])

func research(tid: String) -> bool:
	if not can_research(tid):
		Sfx.play("error")
		return false
	spend(TECHS[tid]["cost"])
	unlocked_techs.append(tid)
	Sfx.play("research")
	add_log("RESEARCH COMPLETE: %s" % TECHS[tid]["name"], "good")
	tech_unlocked.emit(tid)
	return true

func is_unlocked(tool_id: String) -> bool:
	if tool_id == "mine" or tool_id == "salvage": return true
	if tool_id == "wire": return has_tech("power_grid")
	if not BLD.has(tool_id): return false
	return has_tech(String(BLD[tool_id]["req"]))

func dock_new_drone() -> bool:
	if attached_drones >= MAX_DRONES or not spend(DRONE_COST):
		Sfx.play("error")
		return false
	attached_drones += 1
	max_hp = 100.0 + float(attached_drones) * 15.0 + float(propulsion_tier) * 40.0
	hp = max_hp
	Sfx.play("dock")
	add_log("DRONE #%d DOCKED! +1 Multi-Beam active." % attached_drones, "good")
	drone_docked.emit(attached_drones)
	return true

func can_upgrade_propulsion() -> bool:
	var nxt := propulsion_tier + 1
	if not PROPULSION_TIERS.has(nxt): return false
	var info: Dictionary = PROPULSION_TIERS[nxt]
	return has_tech(String(info["req"])) and can_afford(info["cost"])

func upgrade_propulsion() -> bool:
	if not can_upgrade_propulsion():
		Sfx.play("error")
		return false
	var nxt := propulsion_tier + 1
	var info: Dictionary = PROPULSION_TIERS[nxt]
	spend(info["cost"])
	propulsion_tier = nxt
	max_fuel = float(info["fuel"])
	fuel = max_fuel
	max_ion_bat = 100.0 + float(nxt) * 40.0
	ion_bat = max_ion_bat
	Sfx.play("dock")
	add_log("PROPULSION MOUNTED: %s online!" % info["name"], "good")
	propulsion_upgraded.emit(propulsion_tier)
	return true

func build_mega(mid: String) -> bool:
	if not has_tech("megastructures") or not MEGAS.has(mid) or bool(megastructures[mid]):
		Sfx.play("error")
		return false
	if not spend(MEGAS[mid]["cost"]):
		Sfx.play("error")
		return false
	megastructures[mid] = true
	var bonus_f := int(MEGAS[mid]["fleet"])
	if bonus_f > 0:
		swarm_fleet = mini(SWARM_MAX, swarm_fleet + bonus_f)
	Sfx.play("victory")
	add_log("MEGASTRUCTURE COMPLETE: %s!" % MEGAS[mid]["name"], "good")
	check_victory()
	return true

func check_victory() -> void:
	if boss_dead and bool(megastructures["warpgate"]) and not game_won:
		game_won = true
		Sfx.play("victory")
		add_log("SECTOR LIBERATED! Warp Gate & Swarm Victory!", "good")

func add_log(msg: String, kind: String = "info") -> void:
	logs.append({"msg": msg, "kind": kind})
	if logs.size() > 7:
		logs.pop_front()
	log_added.emit(msg, kind)
