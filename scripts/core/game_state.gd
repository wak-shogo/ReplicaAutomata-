extends Node

# Central game state, progression DAG, vessel upgrade tiers, building definitions,
# and save/load management for STAR REPLICA: AUTOMA.

signal resource_changed(res_id: String, amount: int)
signal tech_unlocked(tech_id: String)
signal vessel_upgraded(tier: int)
signal log_added(msg: String, kind: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

const SAVE_PATH: String = "user://star_replica_automa_v2.json"

# Resources & Intermediate Components
var resources: Dictionary = {}
var unlocked_techs: Array[String] = ["basic_mining"]

# Player Vessel State (Starts as grounded Cylinder Seed Capsule -> Apollo Lander evolution)
var vessel_tier: int = 0
var drones: int = 0
var hp: float = 100.0
var max_hp: float = 100.0
var fuel: float = 100.0
var max_fuel: float = 100.0
var ion_battery: float = 100.0
var max_ion_battery: float = 100.0

# Swarm Fleet & Campaign Objectives
var swarm_fleet: int = 0
const SWARM_MAX: int = 10000
var total_launches: int = 0
var doctrine: int = Doctrine.HARVEST
var boss_hp: float = 3200.0
var boss_max_hp: float = 3200.0
var boss_defeated: bool = false
var game_won: bool = false

# Local Power Telemetry (aggregated from physical wired Tesla/Battery grids)
var power_prod: float = 0.0
var power_use: float = 0.0
var power_stored: float = 0.0
var power_cap: float = 0.0
var wire_count: int = 0
var active_teslas: int = 0

# Tool & HUD Control State
var selected_tool: String = "pick"
var build_dir: int = 1 # +1 CW, -1 CCW along curved sphere
var orbit_camera: bool = false
var megastructures: Dictionary = {
	"elevator": false,
	"dyson": false,
	"citadel": false,
	"warpgate": false,
}

# Activity log feed (max 6 entries)
var logs: Array[Dictionary] = []

const VESSEL_TIERS: Dictionary = {
	0: {
		"name": "Seed Capsule",
		"short": "CAPSULE",
		"thrust": 0.0,
		"ion_thrust": 435.0,
		"max_spd": 165.0,
		"fuel_cap": 100.0,
		"bat_cap": 100.0,
		"req_tech": "basic_mining",
		"cost": {},
		"desc": "Brushed-steel cylinder with electric ion hoppers for surface traversal.",
	},
	1: {
		"name": "Lander Mk-I",
		"short": "MK-1 LANDER",
		"thrust": 385.0,
		"ion_thrust": 340.0,
		"max_spd": 260.0,
		"fuel_cap": 160.0,
		"bat_cap": 140.0,
		"req_tech": "metallurgy",
		"cost": {"fe": 18, "cu": 10, "plate_fe": 4},
		"desc": "Bolts rocket bell, lander struts, RCS jets & fuel pods for atmospheric ascent.",
	},
	2: {
		"name": "Apollo Mk-II",
		"short": "MK-2 APOLLO",
		"thrust": 690.0,
		"ion_thrust": 380.0,
		"max_spd": 520.0,
		"fuel_cap": 280.0,
		"bat_cap": 200.0,
		"req_tech": "apollo_stage",
		"cost": {"plate_fe": 10, "wire_cu": 8, "wafer_si": 6, "circuit": 4},
		"desc": "Gold-foil descent chassis, twin cryo tanks & dish for orbital moon expeditions.",
	},
	3: {
		"name": "Warp Mk-III",
		"short": "MK-3 WARP",
		"thrust": 1220.0,
		"ion_thrust": 460.0,
		"max_spd": 900.0,
		"fuel_cap": 450.0,
		"bat_cap": 300.0,
		"req_tech": "swarm_automation",
		"cost": {"plate_fe": 16, "circuit": 10, "alloy": 6, "ti": 14},
		"desc": "Deployable solar wings, command cone & dual plasma bells for fleet command.",
	},
}

const DRONE_COST: Dictionary = {"fe": 12, "cu": 6}
const MAX_DRONES: int = 8

const TECH_ORDER: Array[String] = [
	"basic_mining",
	"tesla_grid",
	"belt_logistics",
	"metallurgy",
	"orbital_rocket",
	"apollo_stage",
	"swarm_automation",
	"megastructures",
]

const TECH_TREE: Dictionary = {
	"basic_mining": {
		"name": "Seed Core",
		"tier": 0, "col": 0, "row": 1,
		"req": [],
		"cost": {},
		"unlocks": ["Hand Laser", "Ion Hoppers"],
		"summary": "Capsule electric ion hoppers and hand mining laser. Strip-mine Fe/Cu crust veins.",
		"flow": "Capsule Laser -> Hand Inventory -> Research Tech Tree",
	},
	"tesla_grid": {
		"name": "Tesla Power",
		"tier": 1, "col": 1, "row": 0,
		"req": ["basic_mining"],
		"cost": {"fe": 12, "cu": 6},
		"unlocks": ["solar", "tesla", "battery"],
		"summary": "Solar Arrays harvest sunlight; Battery stores night surplus; wire to Tesla Coil domes.",
		"flow": "Solar + Battery --(Wire)--> Tesla Coil --(Dome)--> Machines",
	},
	"belt_logistics": {
		"name": "Belt Logistics",
		"tier": 1, "col": 1, "row": 2,
		"req": ["tesla_grid"],
		"cost": {"fe": 16, "cu": 8},
		"unlocks": ["drill", "belt", "lift", "depot"],
		"summary": "Drills output into Belts/Lifts -> Ship pickup or Cargo Depot 4-way output routing.",
		"flow": "Drill -> Belt / Lift -> Cargo Depot (4-Way Filter)",
	},
	"metallurgy": {
		"name": "Smelting Mk-I",
		"tier": 2, "col": 2, "row": 1,
		"req": ["belt_logistics"],
		"cost": {"fe": 24, "cu": 12},
		"unlocks": ["smelter", "Lander Mk-I"],
		"summary": "Refines Fe->Plate, Cu->Wire, Si->Wafer. Unlocks Lander Mk-I rocket printer blueprint!",
		"flow": "Depot/Belt (Ore) -> Blast Smelter -> Plates / Wires / Wafers",
	},
	"orbital_rocket": {
		"name": "Circuits & Geo",
		"tier": 3, "col": 3, "row": 0,
		"req": ["metallurgy"],
		"cost": {"plate_fe": 6, "wire_cu": 4, "si": 10},
		"unlocks": ["assembler", "geothermal", "turret"],
		"summary": "Auto Assembler crafts Circuits, Alloys & Sci Packs. Geothermal taps magma 24/7.",
		"flow": "Smelter -> Depot -> Assembler -> Circuits / Alloys",
	},
	"apollo_stage": {
		"name": "Apollo Mk-II",
		"tier": 3, "col": 3, "row": 2,
		"req": ["orbital_rocket"],
		"cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "circuit": 4},
		"unlocks": ["Apollo Mk-II"],
		"summary": "Gold-foil Apollo spacecraft with deep-space cryo propulsion for moon & belt mining.",
		"flow": "Orbital Belt -> Apollo Mk-II -> Outer Moons (LUNA/IGNIS/CRYO)",
	},
	"swarm_automation": {
		"name": "Swarm Printer",
		"tier": 4, "col": 4, "row": 1,
		"req": ["apollo_stage"],
		"cost": {"plate_fe": 12, "circuit": 8, "ti": 12},
		"unlocks": ["printer", "mass_driver", "Warp Mk-III"],
		"summary": "Gantry Printer builds Replica Probes -> Mass Driver railgun launches 10,000 Swarm Fleet!",
		"flow": "Assembler -> Macro Printer -> Belt -> Mass Driver -> Orbital Swarm",
	},
	"megastructures": {
		"name": "Megastructures",
		"tier": 5, "col": 5, "row": 1,
		"req": ["swarm_automation"],
		"cost": {"alloy": 8, "circuit": 12, "ti": 18},
		"unlocks": ["Space Elevator", "Dyson Ring", "Citadel", "Warp Gate"],
		"summary": "Construct planetary megastructures and liberate the sector from the Corrupted Fortress.",
		"flow": "10,000 Swarm Fleet + Megastructures -> Destroy Corrupted Fortress",
	},
}

const BUILD_CATEGORIES: Array[Dictionary] = [
	{"id": "logistics", "label": "LOGISTICS", "items": ["drill", "belt", "lift", "depot", "demolish"]},
	{"id": "industry",  "label": "INDUSTRY",  "items": ["smelter", "assembler", "printer", "mass_driver"]},
	{"id": "power",     "label": "POWER/DEF", "items": ["solar", "tesla", "battery", "geothermal", "turret", "wire"]},
]

const BUILDINGS: Dictionary = {
	"solar": {
		"name": "Solar Array", "cat": "power", "req": "tesla_grid",
		"cost": {"fe": 10, "cu": 6}, "pwr_gen": 42.0, "pwr_use": 0.0, "sec_w": 1,
		"tex": "bld_solar", "desc": "Daytime solar power (+42W). Wire to a Tesla Coil.",
	},
	"tesla": {
		"name": "Tesla Coil", "cat": "power", "req": "tesla_grid",
		"cost": {"fe": 10, "cu": 8}, "pwr_gen": 0.0, "pwr_use": 0.0, "sec_w": 1,
		"tex": "bld_tesla", "desc": "Projects 580px power dome to nearby machines once wired.",
	},
	"battery": {
		"name": "Power Bank", "cat": "power", "req": "tesla_grid",
		"cost": {"fe": 12, "cu": 8, "si": 4}, "pwr_gen": 0.0, "pwr_use": 0.0, "sec_w": 1,
		"tex": "bld_battery", "desc": "Stores 18,000 kJ daytime excess to power factories all night.",
	},
	"geothermal": {
		"name": "Geothermal Plant", "cat": "power", "req": "orbital_rocket",
		"cost": {"plate_fe": 10, "wire_cu": 8, "si": 8}, "pwr_gen": 120.0, "pwr_use": 0.0, "sec_w": 1,
		"tex": "bld_geothermal", "desc": "24/7 planetary magma baseload (+120W). Wire to Tesla.",
	},
	"turret": {
		"name": "Laser Turret", "cat": "power", "req": "orbital_rocket",
		"cost": {"plate_fe": 8, "wire_cu": 6}, "pwr_gen": 0.0, "pwr_use": 14.0, "sec_w": 1,
		"tex": "bld_turret", "desc": "Defends base from hostile orbital raiders.",
	},
	"drill": {
		"name": "Mining Drill", "cat": "logistics", "req": "belt_logistics",
		"cost": {"fe": 12, "cu": 6}, "pwr_gen": 0.0, "pwr_use": 12.0, "sec_w": 1,
		"tex": "bld_drill", "desc": "Extracts vein ore (buf 6). Link to Belt/Lift to keep running.",
	},
	"belt": {
		"name": "Conveyor Belt", "cat": "logistics", "req": "belt_logistics",
		"cost": {"fe": 2}, "pwr_gen": 0.0, "pwr_use": 1.0, "sec_w": 1,
		"tex": "bld_belt", "desc": "Transports physical items along curved surface. Tap to flip.",
	},
	"lift": {
		"name": "Lift Shaft", "cat": "logistics", "req": "belt_logistics",
		"cost": {"fe": 3}, "pwr_gen": 0.0, "pwr_use": 1.0, "sec_w": 1,
		"tex": "bld_lift", "desc": "Elevates ore vertically from subterranean caverns.",
	},
	"depot": {
		"name": "Cargo Depot", "cat": "logistics", "req": "belt_logistics",
		"cost": {"fe": 16, "cu": 6}, "pwr_gen": 0.0, "pwr_use": 0.0, "sec_w": 1,
		"tex": "bld_depot", "desc": "Stacked containers (cap 200). Tap for 4-way belt output filters.",
	},
	"smelter": {
		"name": "Blast Smelter", "cat": "industry", "req": "metallurgy",
		"cost": {"fe": 18, "cu": 10}, "pwr_gen": 0.0, "pwr_use": 18.0, "sec_w": 1,
		"tex": "bld_smelter", "desc": "Refines 2 Fe->Plate, 2 Cu->Wire, 2 Si->Wafer.",
	},
	"assembler": {
		"name": "Auto Assembler", "cat": "industry", "req": "orbital_rocket",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 6}, "pwr_gen": 0.0, "pwr_use": 22.0, "sec_w": 1,
		"tex": "bld_assembler", "desc": "Crafts Circuits, Alloys & Sci Packs. Tap to switch recipe.",
	},
	"printer": {
		"name": "Macro Printer", "cat": "industry", "req": "swarm_automation",
		"cost": {"plate_fe": 16, "circuit": 6, "ti": 8}, "pwr_gen": 0.0, "pwr_use": 34.0, "sec_w": 2,
		"tex": "bld_printer", "desc": "Gantry 3D printer producing autonomous Replica Probes.",
	},
	"mass_driver": {
		"name": "Mass Driver", "cat": "industry", "req": "swarm_automation",
		"cost": {"plate_fe": 18, "wire_cu": 12, "circuit": 8}, "pwr_gen": 0.0, "pwr_use": 30.0, "sec_w": 2,
		"tex": "bld_mass_driver", "desc": "Superconducting railgun launching Probes into the 10k Swarm!",
	},
}

const MEGA_DEFS: Dictionary = {
	"elevator": {"name": "Space Elevator",  "cost": {"plate_fe": 20, "wire_cu": 16, "alloy": 6},  "bonus": "Continuous orbital supply +200 Fleet"},
	"dyson":    {"name": "Dyson Ring",      "cost": {"wafer_si": 16, "circuit": 12, "alloy": 8}, "bonus": "Global +240W beamed solar energy"},
	"citadel":  {"name": "Orbital Citadel", "cost": {"alloy": 12, "circuit": 14, "ti": 20},      "bonus": "Automated heavy fleet fire +600 Fleet"},
	"warpgate": {"name": "Star Warp Gate",  "cost": {"alloy": 14, "circuit": 16, "sci_pack": 6}, "bonus": "Sector victory anchor"},
}

func _ready() -> void:
	reset_state()

func reset_state() -> void:
	resources = {
		"fe": 0, "cu": 0, "si": 0, "ti": 0, "ice": 0,
		"plate_fe": 0, "wire_cu": 0, "wafer_si": 0,
		"circuit": 0, "alloy": 0, "sci_pack": 0, "probe_stock": 0,
	}
	unlocked_techs = ["basic_mining"]
	vessel_tier = 0
	drones = 0
	max_hp = 100.0
	hp = 100.0
	max_fuel = float(VESSEL_TIERS[0]["fuel_cap"])
	fuel = max_fuel
	max_ion_battery = float(VESSEL_TIERS[0]["bat_cap"])
	ion_battery = max_ion_battery
	swarm_fleet = 0
	total_launches = 0
	doctrine = Doctrine.HARVEST
	boss_hp = boss_max_hp
	boss_defeated = false
	game_won = false
	power_prod = 0.0
	power_use = 0.0
	power_stored = 0.0
	power_cap = 0.0
	wire_count = 0
	active_teslas = 0
	selected_tool = "pick"
	build_dir = 1
	orbit_camera = false
	megastructures = {"elevator": false, "dyson": false, "citadel": false, "warpgate": false}
	logs.clear()
	add_log("Seed Capsule landed on Origin-Prime. Hold [A] to mine Fe & Cu.", "info")

func get_res(id: String) -> int:
	return int(resources.get(id, 0))

func add_res(id: String, delta: int) -> void:
	if not resources.has(id):
		resources[id] = 0
	resources[id] = maxi(0, int(resources[id]) + delta)
	resource_changed.emit(id, int(resources[id]))

func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if get_res(String(k)) < int(cost[k]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost.keys():
		add_res(String(k), -int(cost[k]))
	return true

func has_tech(tech_id: String) -> bool:
	return tech_id in unlocked_techs

func can_research(tech_id: String) -> bool:
	if has_tech(tech_id) or not TECH_TREE.has(tech_id):
		return false
	var t = TECH_TREE[tech_id]
	for r in t["req"]:
		if not has_tech(String(r)):
			return false
	return can_afford(t["cost"])

func research_tech(tech_id: String) -> bool:
	if not can_research(tech_id):
		AudioSynth.play_sfx("error")
		return false
	spend(TECH_TREE[tech_id]["cost"])
	unlocked_techs.append(tech_id)
	AudioSynth.play_sfx("research")
	add_log("TECH UNLOCKED: %s" % TECH_TREE[tech_id]["name"], "good")
	tech_unlocked.emit(tech_id)
	return true

func is_building_unlocked(bid: String) -> bool:
	if bid == "wire" or bid == "demolish":
		return has_tech("tesla_grid") if bid == "wire" else true
	if not BUILDINGS.has(bid):
		return false
	return has_tech(String(BUILDINGS[bid]["req"]))

func can_upgrade_vessel() -> bool:
	var nxt = vessel_tier + 1
	if not VESSEL_TIERS.has(nxt):
		return false
	var info = VESSEL_TIERS[nxt]
	return has_tech(String(info["req_tech"])) and can_afford(info["cost"])

func upgrade_vessel() -> bool:
	if not can_upgrade_vessel():
		AudioSynth.play_sfx("error")
		return false
	var nxt = vessel_tier + 1
	var info = VESSEL_TIERS[nxt]
	spend(info["cost"])
	vessel_tier = nxt
	max_fuel = float(info["fuel_cap"])
	fuel = max_fuel
	max_ion_battery = float(info["bat_cap"])
	ion_battery = max_ion_battery
	max_hp = 100.0 + float(nxt) * 50.0
	hp = max_hp
	AudioSynth.play_sfx("craft")
	add_log("VESSEL UPGRADED: %s fabricated!" % info["name"], "good")
	vessel_upgraded.emit(vessel_tier)
	return true

func craft_drone() -> bool:
	if drones >= MAX_DRONES or not can_afford(DRONE_COST):
		AudioSynth.play_sfx("error")
		return false
	spend(DRONE_COST)
	drones += 1
	AudioSynth.play_sfx("craft")
	add_log("Fabricator Drone #%d docked to vessel!" % drones, "good")
	return true

func build_megastructure(mid: String) -> bool:
	if not has_tech("megastructures") or not MEGA_DEFS.has(mid) or bool(megastructures.get(mid, false)):
		AudioSynth.play_sfx("error")
		return false
	if not spend(MEGA_DEFS[mid]["cost"]):
		AudioSynth.play_sfx("error")
		return false
	megastructures[mid] = true
	if mid == "elevator":
		swarm_fleet = mini(SWARM_MAX, swarm_fleet + 200)
	elif mid == "citadel":
		swarm_fleet = mini(SWARM_MAX, swarm_fleet + 600)
	AudioSynth.play_sfx("victory")
	add_log("MEGASTRUCTURE COMPLETE: %s!" % MEGA_DEFS[mid]["name"], "good")
	check_victory()
	return true

func check_victory() -> void:
	if boss_defeated and bool(megastructures.get("warpgate", false)):
		if not game_won:
			game_won = true
			AudioSynth.play_sfx("victory")
			add_log("VICTORY: Sector liberated & Warp Gate online!", "good")

func add_log(msg: String, kind: String = "info") -> void:
	logs.append({"msg": msg, "kind": kind})
	if logs.size() > 6:
		logs.pop_front()
	log_added.emit(msg, kind)

func save_to_disk(extra: Dictionary = {}) -> bool:
	var data := {
		"resources": resources,
		"unlocked_techs": unlocked_techs,
		"vessel_tier": vessel_tier,
		"drones": drones,
		"hp": hp, "fuel": fuel, "ion_battery": ion_battery,
		"swarm_fleet": swarm_fleet, "total_launches": total_launches,
		"doctrine": doctrine, "boss_hp": boss_hp, "boss_defeated": boss_defeated,
		"megastructures": megastructures,
		"extra": extra,
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	add_log("Colony progress saved.", "info")
	return true
