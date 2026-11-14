extends Node

# ==============================================================================
# STAR REPLICA: AUTOMA - CORE GAME STATE, TECH TREE DAG & LOGISTICS CATALOG
# Local wired power grid, buffered physical logistics, Factorio-style Tech Tree,
# Kepler orbital fuel + electric ion backup propulsion.
# ==============================================================================

signal inventory_changed
signal state_updated
signal blueprint_selected(building_id: String)
signal drone_count_changed(new_count: int)
signal probe_launched(world_pos: Vector2)
signal tech_unlocked(tech_id: String)
signal log_event(message: String, level: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

# Core Seed Unit Vitals & Dual Propulsion Energy
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var player_shield: float = 50.0
var player_max_shield: float = 50.0
var player_fuel: float = 100.0
var player_max_fuel: float = 100.0
var player_battery: float = 100.0
var player_max_battery: float = 100.0

# Player Pocket / Vessel Inventory
var fe: int = 0
var cu: int = 0
var si: int = 0
var ti: int = 0
var ice: int = 0
var he3: int = 0

var plate_fe: int = 0
var wire_cu: int = 0
var wafer_si: int = 0
var circuit: int = 0
var alloy: int = 0
var sci_pack: int = 0
var probe_stock: int = 0

# Progression, Propulsion & Swarm Fleet
var engine_tier: int = 0 # 0=Grounded Capsule, 1=Lander Mk-I, 2=Apollo Mk-II, 3=Warp Mk-III
var drones: int = 0
var max_drones: int = 12
var fleet_count: int = 0
var max_fleet: int = 10000
var total_launches: int = 0
var hostiles_defeated: int = 0
var hostiles_active: int = 0
var boss_hp: float = 3000.0
var boss_max_hp: float = 3000.0
var boss_defeated: bool = false
var game_won: bool = false

const ENGINE_TIERS: Dictionary = {
	1: {
		"name": "Lander Struts Mk-I",
		"speed": 115.0,
		"thrust": 335.0,
		"req_tech": "metallurgy",
		"cost": {"fe": 20, "cu": 10, "plate_fe": 4},
		"desc": "Bolts Rocket Bell, Fuel Tank, Ion Backup & Lander Legs."
	},
	2: {
		"name": "Apollo Descent Mk-II",
		"speed": 260.0,
		"thrust": 680.0,
		"req_tech": "apollo_stage",
		"cost": {"plate_fe": 12, "wire_cu": 10, "wafer_si": 8, "circuit": 4},
		"desc": "Gold Foil Hull, Cryo Tanks, Dish & Orbital Booster."
	},
	3: {
		"name": "Warp Ascent Mk-III",
		"speed": 580.0,
		"thrust": 1350.0,
		"req_tech": "swarm_automation",
		"cost": {"plate_fe": 20, "circuit": 12, "alloy": 8, "ti": 20},
		"desc": "Command Cone, Twin Ion Bells & Solar Wing Arrays."
	},
}

# Power Telemetry (Aggregated from physical local Tesla grids)
var power_gen: float = 0.0
var power_use: float = 0.0
var power_stored: float = 0.0
var power_cap: float = 0.0
var power_ratio: float = 0.0

# Macro Replicator & Doctrine
var printer_progress: float = 0.0
var printer_active: bool = false
var current_doctrine: int = Doctrine.HARVEST
var selected_tool: String = "pick"
var build_rotation: int = 1 # +1 CW or -1 CCW along planetary sphere

# Cumulative mining feedback next to player
var recent_ore_type: String = ""
var recent_ore_amount: int = 0
var recent_ore_timer: float = 0.0

# Megastructures & Orbital Constructions (Zero at start!)
var megastructures: Dictionary = {
	"elevator": false,
	"dyson": false,
	"citadel": false,
	"warpgate": false,
}

# ==============================================================================
# FACTORIO-STYLE TECH TREE DAG
# ==============================================================================
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
		"name": "Seed Core & Laser",
		"tier": 0,
		"col": 0,
		"row": 1,
		"req": [],
		"cost": {},
		"unlocks_bld": [],
		"summary": "Capsule electric treads & hand laser. Mine Fe/Cu veins along the horizon.",
		"flow": "Player Laser -> Hand Inventory -> Research Tech Tree",
	},
	"tesla_grid": {
		"name": "Solar & Tesla Grid",
		"tier": 1,
		"col": 1,
		"row": 0,
		"req": ["basic_mining"],
		"cost": {"fe": 12, "cu": 6},
		"unlocks_bld": ["solar", "tesla", "battery"],
		"summary": "Solar Arrays generate daytime power; tap Solar -> Tesla Coil to wire domes.",
		"flow": "Solar/Battery --(Wire)--> Tesla Coil --(Dome)--> Powered Machines",
	},
	"belt_logistics": {
		"name": "Drill & Belt Logistics",
		"tier": 1,
		"col": 1,
		"row": 2,
		"req": ["tesla_grid"],
		"cost": {"fe": 16, "cu": 8},
		"unlocks_bld": ["drill", "belt", "lift", "depot"],
		"summary": "Drills buffer 6 ores & halt until linked to Belts -> Ship pickup or Depot router.",
		"flow": "Drill (Out 6) -> Belt/Lift -> Cargo Depot (4-Way Output Filter)",
	},
	"metallurgy": {
		"name": "Blast Smelting & Mk-I",
		"tier": 2,
		"col": 2,
		"row": 1,
		"req": ["belt_logistics"],
		"cost": {"fe": 26, "cu": 14},
		"unlocks_bld": ["smelter"],
		"unlocks_eng": 1,
		"summary": "Refines Fe->Plate, Cu->Wire, Si->Wafer via Depot/Belts. Unlocks Lander Mk-I!",
		"flow": "Depot/Belt (Ore) -> Blast Smelter -> Belt (Plates/Wires/Wafers) -> Printer",
	},
	"orbital_rocket": {
		"name": "Circuits & Geothermal",
		"tier": 3,
		"col": 3,
		"row": 0,
		"req": ["metallurgy"],
		"cost": {"plate_fe": 6, "wire_cu": 4, "si": 10},
		"unlocks_bld": ["assembler", "geothermal", "turret"],
		"summary": "Auto Assembler crafts Circuits, Alloys & Sci Packs. Geo taps core magma heat.",
		"flow": "Smelter -> Depot Filter -> Assembler -> Circuit/Sci Pack + Core Tesla Wire",
	},
	"apollo_stage": {
		"name": "Apollo Descent Mk-II",
		"tier": 3,
		"col": 3,
		"row": 2,
		"req": ["orbital_rocket"],
		"cost": {"plate_fe": 10, "wire_cu": 8, "wafer_si": 6, "circuit": 4},
		"unlocks_bld": [],
		"unlocks_eng": 2,
		"summary": "Deep-space propulsion, cryo tanks & orbital moon/asteroid rendezvous mining.",
		"flow": "Orbital Belt -> Apollo Mk-II -> Outer Moons (LUNA/CRYO/IGNIS) -> Rare Ti/Ice/He3",
	},
	"swarm_automation": {
		"name": "Replicator & Fleet",
		"tier": 4,
		"col": 4,
		"row": 1,
		"req": ["apollo_stage"],
		"cost": {"plate_fe": 14, "circuit": 8, "ti": 14},
		"unlocks_bld": ["printer", "mass_driver", "elevator"],
		"unlocks_eng": 3,
		"summary": "Crafts Orbital Probes & fires them into orbit via Mass Driver. Unlocks Mk-III!",
		"flow": "Assembler -> Depot -> Replicator -> Mass Driver -> Swarm Fleet",
	},
	"megastructures": {
		"name": "Megastructures & Warp",
		"tier": 5,
		"col": 5,
		"row": 1,
		"req": ["swarm_automation"],
		"cost": {"plate_fe": 20, "circuit": 14, "alloy": 6, "ti": 20},
		"unlocks_bld": ["dyson", "citadel", "warpgate"],
		"summary": "Dyson Power Ring, Plasma Siege Citadel, and Interstellar Warp Gate victory anchor.",
		"flow": "Dyson (+450kW) + Citadel (2x Siege) + Warp Gate + Boss Defeat -> Victory",
	},
}

var unlocked_techs: Dictionary = {"basic_mining": true}

# ==============================================================================
# SPHERICAL FACILITY CATALOG
# ==============================================================================
const BUILDINGS: Dictionary = {
	"solar": {
		"name": "Solar Array",
		"branch": "POWER",
		"req_tech": "tesla_grid",
		"cost": {"fe": 10, "cu": 4},
		"power": 36.0,
		"sec_w": 2,
		"h_px": 26.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_solar.png",
		"sheet": "res://assets/sprites/solar_array.png",
		"frames": 1,
		"desc": "Generates +36kW on sunlit hemisphere. Wire to Tesla Coil to distribute."
	},
	"tesla": {
		"name": "Tesla Coil",
		"branch": "POWER",
		"req_tech": "tesla_grid",
		"cost": {"fe": 8, "cu": 4},
		"power": 0.0,
		"sec_w": 1,
		"h_px": 40.0,
		"place": "ANY_SPHERE",
		"icon": "res://assets/ui/tool_turret.png",
		"sheet": "",
		"frames": 1,
		"desc": "Tap Generator->Tesla to stretch power wire. Energizes 360px dome around coil."
	},
	"battery": {
		"name": "Power Bank",
		"branch": "POWER",
		"req_tech": "tesla_grid",
		"cost": {"fe": 12, "cu": 8, "si": 4},
		"power": 0.0,
		"sec_w": 1,
		"h_px": 34.0,
		"place": "ANY_SPHERE",
		"icon": "res://assets/ui/tool_depot.png",
		"sheet": "",
		"frames": 1,
		"desc": "Stores 300kJ grid surplus during day; discharges cleanly through planet night."
	},
	"geothermal": {
		"name": "Geo Plant",
		"branch": "POWER",
		"req_tech": "orbital_rocket",
		"cost": {"fe": 28, "cu": 14, "plate_fe": 4},
		"power": 135.0,
		"sec_w": 2,
		"h_px": 44.0,
		"place": "DEEP_ROCK",
		"icon": "res://assets/ui/tool_geothermal.png",
		"sheet": "res://assets/sprites/geothermal_plant.png",
		"frames": 1,
		"desc": "Constant +135kW core heat. Chain underground Tesla Coils to wire up to surface!"
	},
	"turret": {
		"name": "Laser Turret",
		"branch": "POWER",
		"req_tech": "orbital_rocket",
		"cost": {"plate_fe": 6, "wire_cu": 4, "circuit": 2},
		"power": -12.0,
		"sec_w": 1,
		"h_px": 32.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_turret.png",
		"sheet": "res://assets/sprites/defense_turret.png",
		"frames": 1,
		"desc": "Requires powered Tesla dome. Vaporizes raiders attacking colony sectors."
	},
	"drill": {
		"name": "Mining Drill",
		"branch": "MINE",
		"req_tech": "belt_logistics",
		"cost": {"fe": 10, "cu": 4},
		"power": -10.0,
		"sec_w": 1,
		"h_px": 42.0,
		"place": "UNDERGROUND",
		"icon": "res://assets/ui/tool_drill.png",
		"sheet": "res://assets/sprites/mining_drill_sheet.png",
		"frames": 4,
		"desc": "Needs Tesla power! Stores 6 ores locally then halts until unloaded by Belt or Ship."
	},
	"belt": {
		"name": "Arc Belt",
		"branch": "MINE",
		"req_tech": "belt_logistics",
		"cost": {"fe": 2},
		"power": -1.0,
		"sec_w": 1,
		"h_px": 20.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/conveyor_sheet.png",
		"frames": 4,
		"desc": "Moves physical items along planet rim. Fly over to pick up, or tap belt to flip dir."
	},
	"lift": {
		"name": "Radial Lift",
		"branch": "MINE",
		"req_tech": "belt_logistics",
		"cost": {"fe": 3},
		"power": -2.0,
		"sec_w": 1,
		"h_px": 34.0,
		"place": "UNDERGROUND",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/lift_shaft_sheet.png",
		"frames": 4,
		"desc": "Vertical motorized shaft hoisting ore up from underground drills to surface belts."
	},
	"depot": {
		"name": "Cargo Depot",
		"branch": "MINE",
		"req_tech": "belt_logistics",
		"cost": {"fe": 16, "cu": 6},
		"power": -2.0,
		"sec_w": 2,
		"h_px": 46.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_depot.png",
		"sheet": "res://assets/sprites/container_depot.png",
		"frames": 1,
		"desc": "Real storage warehouse! Tap Depot to inspect inventory & set Left/Right/Up/Down outputs."
	},
	"smelter": {
		"name": "Blast Smelter",
		"branch": "FACTORY",
		"req_tech": "metallurgy",
		"cost": {"fe": 18, "cu": 8},
		"power": -16.0,
		"sec_w": 2,
		"h_px": 50.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_smelter.png",
		"sheet": "res://assets/sprites/smelter_sheet.png",
		"frames": 4,
		"desc": "Takes physical ore via Belt/Depot/Hand; refines Plates, Copper Wire & Si Wafers."
	},
	"assembler": {
		"name": "Auto Assembler",
		"branch": "FACTORY",
		"req_tech": "orbital_rocket",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 6},
		"power": -22.0,
		"sec_w": 2,
		"h_px": 50.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_assembler.png",
		"sheet": "res://assets/sprites/assembler_sheet.png",
		"frames": 4,
		"desc": "Crafts Circuit / Alloy / Sci Pack from physical inputs. Tap machine to switch recipe."
	},
	"printer": {
		"name": "Replicator",
		"branch": "FACTORY",
		"req_tech": "swarm_automation",
		"cost": {"plate_fe": 14, "circuit": 4, "wire_cu": 6},
		"power": -32.0,
		"sec_w": 3,
		"h_px": 62.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_printer.png",
		"sheet": "res://assets/sprites/factory_hall_sheet.png",
		"frames": 4,
		"desc": "Builds Orbital Replica Probes from Plates + Circuits supplied via Belt or Depot."
	},
	"mass_driver": {
		"name": "Mass Driver",
		"branch": "FACTORY",
		"req_tech": "swarm_automation",
		"cost": {"plate_fe": 18, "circuit": 6, "ti": 10},
		"power": -38.0,
		"sec_w": 3,
		"h_px": 74.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_mass_driver.png",
		"sheet": "res://assets/sprites/mass_driver_sheet.png",
		"frames": 4,
		"desc": "Fires physical Orbital Probes loaded from Replicator/Belts into planetary orbit."
	},
	"elevator": {
		"name": "Orbital Anchor",
		"branch": "MEGA",
		"req_tech": "swarm_automation",
		"cost": {"plate_fe": 25, "circuit": 10, "ti": 20},
		"power": -45.0,
		"sec_w": 3,
		"h_px": 135.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_elevator.png",
		"sheet": "res://assets/sprites/megastructure_elevator.png",
		"frames": 1,
		"desc": "Physical space tether linking surface Cargo Depots directly to Orbital Shipyard Dock."
	},
	"dyson": {
		"name": "Dyson Ring",
		"branch": "MEGA",
		"req_tech": "megastructures",
		"cost": {"plate_fe": 35, "circuit": 16, "alloy": 8, "ti": 24},
		"power": 450.0,
		"sec_w": 4,
		"h_px": 95.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_dyson.png",
		"sheet": "res://assets/sprites/megastructure_dyson.png",
		"frames": 1,
		"desc": "Beams +450kW stellar energy into connected Tesla grids & boosts Replicators."
	},
	"citadel": {
		"name": "Plasma Citadel",
		"branch": "MEGA",
		"req_tech": "megastructures",
		"cost": {"plate_fe": 35, "circuit": 16, "alloy": 8, "ti": 28},
		"power": -40.0,
		"sec_w": 3,
		"h_px": 110.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_citadel.png",
		"sheet": "res://assets/sprites/megastructure_citadel.png",
		"frames": 1,
		"desc": "Orbital siege amplifier doubling Swarm fleet assault fire."
	},
	"warpgate": {
		"name": "Warp Gate",
		"branch": "MEGA",
		"req_tech": "megastructures",
		"cost": {"plate_fe": 45, "circuit": 24, "alloy": 12, "ti": 36},
		"power": -90.0,
		"sec_w": 4,
		"h_px": 115.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_warpgate.png",
		"sheet": "res://assets/sprites/megastructure_warpgate.png",
		"frames": 1,
		"desc": "Interstellar Seed Anchor. Complete with Boss Liberation to achieve Colony Victory."
	}
}

const ITEM_LIST: Array[String] = [
	"fe", "cu", "si", "ti", "ice", "he3",
	"plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "sci_pack", "probe_stock"
]

func reset_state() -> void:
	player_hp = 100.0
	player_shield = 50.0
	player_fuel = 100.0
	player_max_fuel = 100.0
	player_battery = 100.0
	player_max_battery = 100.0
	fe = 0
	cu = 0
	si = 0
	ti = 0
	ice = 0
	he3 = 0
	plate_fe = 0
	wire_cu = 0
	wafer_si = 0
	circuit = 0
	alloy = 0
	sci_pack = 0
	probe_stock = 0
	engine_tier = 0
	drones = 0
	fleet_count = 0
	total_launches = 0
	hostiles_defeated = 0
	hostiles_active = 0
	boss_hp = boss_max_hp
	boss_defeated = false
	game_won = false
	power_gen = 0.0
	power_use = 0.0
	power_stored = 0.0
	power_cap = 0.0
	power_ratio = 0.0
	printer_progress = 0.0
	printer_active = false
	current_doctrine = Doctrine.HARVEST
	selected_tool = "pick"
	build_rotation = 1
	recent_ore_type = ""
	recent_ore_amount = 0
	recent_ore_timer = 0.0
	unlocked_techs = {"basic_mining": true}
	for k in megastructures.keys():
		megastructures[k] = false
	emit_signal("inventory_changed")
	emit_signal("state_updated")

func _process(delta: float) -> void:
	if recent_ore_timer > 0.0:
		recent_ore_timer -= delta
		if recent_ore_timer <= 0.0:
			recent_ore_amount = 0
			recent_ore_type = ""
	# Passive shield recharge when battery/power healthy
	if player_shield < player_max_shield and player_battery > 20.0:
		player_shield = minf(player_max_shield, player_shield + 3.5 * delta)

func is_tech_unlocked(tid: String) -> bool:
	return bool(unlocked_techs.get(tid, false))

func are_tech_reqs_met(tid: String) -> bool:
	if not TECH_TREE.has(tid):
		return false
	for req_id in TECH_TREE[tid]["req"]:
		if not is_tech_unlocked(req_id):
			return false
	return true

func try_research_tech(tid: String) -> bool:
	if is_tech_unlocked(tid):
		return true
	if not TECH_TREE.has(tid):
		return false
	if not are_tech_reqs_met(tid):
		emit_signal("log_event", "Prerequisite research required!", "warn")
		return false
	var tnode: Dictionary = TECH_TREE[tid]
	var cost: Dictionary = tnode["cost"]
	if not spend_cost(cost):
		emit_signal("log_event", get_missing_text(cost), "error")
		return false
	unlocked_techs[tid] = true
	emit_signal("tech_unlocked", tid)
	emit_signal("state_updated")
	emit_signal("log_event", "TECH UNLOCKED: %s" % tnode["name"], "good")
	return true

func is_building_unlocked(bid: String) -> bool:
	if not BUILDINGS.has(bid):
		return false
	var req_t = String(BUILDINGS[bid].get("req_tech", "basic_mining"))
	return is_tech_unlocked(req_t)

func is_engine_unlocked(tier: int) -> bool:
	if not ENGINE_TIERS.has(tier):
		return false
	var req_t = String(ENGINE_TIERS[tier].get("req_tech", "basic_mining"))
	return is_tech_unlocked(req_t)

func get_drone_craft_cost() -> Dictionary:
	if drones == 0:
		return {"fe": 10}
	elif drones == 1:
		return {"fe": 14, "cu": 6}
	elif drones == 2:
		return {"fe": 16, "cu": 8, "si": 4}
	else:
		var cost := {"fe": 12 + drones * 4, "cu": 5 + drones * 2}
		if drones >= 4:
			cost["si"] = drones * 2
		return cost

func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if get_res(k) < int(cost[k]):
			return false
	return true

func get_missing_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost.keys():
		var req = int(cost[k])
		var have = get_res(k)
		if have < req:
			parts.append("%s -%d" % [k.to_upper(), req - have])
	return "NEED " + ", ".join(parts)

func spend_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost.keys():
		add_res(k, -int(cost[k]))
	emit_signal("inventory_changed")
	return true

func get_res(key: String) -> int:
	match key:
		"fe": return fe
		"cu": return cu
		"si": return si
		"ti": return ti
		"ice": return ice
		"he3": return he3
		"plate_fe": return plate_fe
		"wire_cu": return wire_cu
		"wafer_si": return wafer_si
		"circuit": return circuit
		"alloy": return alloy
		"sci_pack": return sci_pack
		"probe_stock": return probe_stock
	return 0

func add_res(key: String, amount: int, track_mining_popup: bool = false) -> void:
	match key:
		"fe": fe = maxi(0, fe + amount)
		"cu": cu = maxi(0, cu + amount)
		"si": si = maxi(0, si + amount)
		"ti": ti = maxi(0, ti + amount)
		"ice": ice = maxi(0, ice + amount)
		"he3": he3 = maxi(0, he3 + amount)
		"plate_fe": plate_fe = maxi(0, plate_fe + amount)
		"wire_cu": wire_cu = maxi(0, wire_cu + amount)
		"wafer_si": wafer_si = maxi(0, wafer_si + amount)
		"circuit": circuit = maxi(0, circuit + amount)
		"alloy": alloy = maxi(0, alloy + amount)
		"sci_pack": sci_pack = maxi(0, sci_pack + amount)
		"probe_stock": probe_stock = maxi(0, probe_stock + amount)
	if track_mining_popup and amount > 0:
		if recent_ore_type == key or recent_ore_timer <= 0.0:
			recent_ore_type = key
			recent_ore_amount += amount
		else:
			recent_ore_type = key
			recent_ore_amount = amount
		recent_ore_timer = 1.8
	emit_signal("inventory_changed")

func get_flight_speed() -> float:
	if engine_tier <= 0:
		return 0.0
	return float(ENGINE_TIERS.get(clampi(engine_tier, 1, 3), {}).get("speed", 115.0))

func get_engine_thrust() -> float:
	if engine_tier <= 0:
		return 0.0
	return float(ENGINE_TIERS.get(clampi(engine_tier, 1, 3), {}).get("thrust", 335.0))

func get_next_engine_info() -> Dictionary:
	var nxt = engine_tier + 1
	if not ENGINE_TIERS.has(nxt):
		return {}
	return ENGINE_TIERS[nxt]

func try_print_engine() -> bool:
	var nxt = engine_tier + 1
	if not ENGINE_TIERS.has(nxt):
		emit_signal("log_event", "Propulsion already at MAX Mk-III!", "info")
		return false
	var info: Dictionary = ENGINE_TIERS[nxt]
	var req_t = String(info.get("req_tech", ""))
	if req_t != "" and not is_tech_unlocked(req_t):
		var tname = String(TECH_TREE.get(req_t, {}).get("name", req_t))
		emit_signal("log_event", "RESEARCH FIRST: %s" % tname, "warn")
		return false
	var cost: Dictionary = info["cost"]
	if not spend_cost(cost):
		emit_signal("log_event", get_missing_text(cost), "error")
		return false
	engine_tier = nxt
	player_max_fuel = 100.0 + float(engine_tier) * 60.0
	player_fuel = player_max_fuel
	player_max_battery = 100.0 + float(engine_tier) * 40.0
	player_battery = player_max_battery
	emit_signal("state_updated")
	emit_signal("log_event", "Printed %s! Thruster Online." % info["name"], "good")
	return true

func try_craft_drone() -> bool:
	if drones >= max_drones:
		emit_signal("log_event", "Max fabricator drones docked (%d)" % max_drones, "warn")
		return false
	var cost = get_drone_craft_cost()
	if not spend_cost(cost):
		emit_signal("log_event", get_missing_text(cost), "error")
		return false
	drones += 1
	emit_signal("drone_count_changed", drones)
	emit_signal("state_updated")
	emit_signal("log_event", "Docked Builder Drone #%d (+Pickup & Build Speed)" % drones, "good")
	return true

func set_tool(tool_id: String) -> void:
	selected_tool = tool_id
	emit_signal("blueprint_selected", tool_id)
	emit_signal("state_updated")

func add_log(msg: String, level: String = "info") -> void:
	emit_signal("log_event", msg, level)

func set_doctrine(doc: int) -> void:
	current_doctrine = doc
	var names = ["HARVEST", "REPLICATE", "DEFEND", "ASSAULT"]
	emit_signal("log_event", "Swarm -> %s" % names[clampi(doc, 0, 3)], "info")
	emit_signal("state_updated")

func add_fleet_units(count: int) -> void:
	fleet_count = mini(max_fleet, fleet_count + count)
	emit_signal("state_updated")

func damage_player(dmg: float) -> void:
	if player_shield > 0.0:
		var absorbed = minf(player_shield, dmg)
		player_shield -= absorbed
		dmg -= absorbed
	if dmg > 0.0:
		player_hp = maxf(0.0, player_hp - dmg)
	emit_signal("state_updated")

func to_dict() -> Dictionary:
	return {
		"fe": fe, "cu": cu, "si": si, "ti": ti, "ice": ice, "he3": he3,
		"plate_fe": plate_fe, "wire_cu": wire_cu, "wafer_si": wafer_si,
		"circuit": circuit, "alloy": alloy, "sci_pack": sci_pack, "probe_stock": probe_stock,
		"player_hp": player_hp, "player_shield": player_shield,
		"player_fuel": player_fuel, "player_battery": player_battery,
		"drones": drones, "engine_tier": engine_tier, "fleet_count": fleet_count,
		"total_launches": total_launches, "hostiles_defeated": hostiles_defeated,
		"boss_hp": boss_hp, "boss_defeated": boss_defeated, "game_won": game_won,
		"current_doctrine": current_doctrine,
		"unlocked_techs": unlocked_techs.duplicate(),
		"megastructures": megastructures.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	fe = int(d.get("fe", 0))
	cu = int(d.get("cu", 0))
	si = int(d.get("si", 0))
	ti = int(d.get("ti", 0))
	ice = int(d.get("ice", 0))
	he3 = int(d.get("he3", 0))
	plate_fe = int(d.get("plate_fe", 0))
	wire_cu = int(d.get("wire_cu", 0))
	wafer_si = int(d.get("wafer_si", 0))
	circuit = int(d.get("circuit", 0))
	alloy = int(d.get("alloy", 0))
	sci_pack = int(d.get("sci_pack", 0))
	probe_stock = int(d.get("probe_stock", 0))
	engine_tier = int(d.get("engine_tier", 0))
	player_max_fuel = 100.0 + float(engine_tier) * 60.0
	player_max_battery = 100.0 + float(engine_tier) * 40.0
	player_hp = float(d.get("player_hp", 100.0))
	player_shield = float(d.get("player_shield", 50.0))
	player_fuel = float(d.get("player_fuel", player_max_fuel))
	player_battery = float(d.get("player_battery", player_max_battery))
	drones = int(d.get("drones", 0))
	fleet_count = int(d.get("fleet_count", 0))
	total_launches = int(d.get("total_launches", 0))
	hostiles_defeated = int(d.get("hostiles_defeated", 0))
	boss_hp = float(d.get("boss_hp", boss_max_hp))
	boss_defeated = bool(d.get("boss_defeated", false))
	game_won = bool(d.get("game_won", false))
	current_doctrine = int(d.get("current_doctrine", Doctrine.HARVEST))
	unlocked_techs = {"basic_mining": true}
	var ut = d.get("unlocked_techs", {})
	if ut is Dictionary:
		for tk in ut.keys():
			unlocked_techs[tk] = bool(ut[tk])
	var ms = d.get("megastructures", {})
	if ms is Dictionary:
		for k in megastructures.keys():
			megastructures[k] = bool(ms.get(k, false))
	emit_signal("inventory_changed")
	emit_signal("state_updated")
