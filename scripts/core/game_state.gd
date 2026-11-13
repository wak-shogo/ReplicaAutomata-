extends Node

# ==============================================================================
# STAR REPLICA: AUTOMA - CORE GAME STATE & CATALOG
# ==============================================================================

signal inventory_changed
signal state_updated
signal blueprint_selected(building_id: String)
signal drone_count_changed(new_count: int)
signal probe_launched(world_pos: Vector2)
signal log_event(message: String, level: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

# Raw & Refined Resources
var fe: int = 0
var cu: int = 0
var si: int = 0
var ti: int = 0
var he3: int = 0

var plate_fe: int = 0
var wire_cu: int = 0
var wafer_si: int = 0
var circuit: int = 0
var alloy: int = 0
var probe_stock: int = 0

# Progression & Fleet
var drones: int = 0
var max_drones: int = 12
var fleet_count: int = 0
var max_fleet: int = 10000
var total_launches: int = 0
var hostiles_defeated: int = 0
var hostiles_active: int = 0
var boss_hp: float = 2500.0
var boss_max_hp: float = 2500.0
var boss_defeated: bool = false

# Energy Grid
var power_gen: float = 15.0  # Base Seed Unit reactor
var power_use: float = 0.0
var power_ratio: float = 1.0

# Macro Replicator & Doctrine
var printer_progress: float = 0.0
var printer_active: bool = false
var current_doctrine: int = Doctrine.HARVEST
var selected_tool: String = "pick"
var build_rotation: int = 0 # 0: Right/Up, 1: Down, 2: Left, 3: Up

# Cumulative mining feedback near player
var recent_ore_type: String = ""
var recent_ore_amount: int = 0
var recent_ore_timer: float = 0.0

# Megastructure unlock tracking
var megastructures: Dictionary = {
	"elevator": false,
	"dyson": false,
	"citadel": false,
	"warpgate": false,
}

# Single source of truth for all tools & facilities
const BUILDINGS: Dictionary = {
	"drill": {
		"name": "Mining Drill",
		"category": "MINE",
		"hotkey": "1",
		"cost": {"fe": 12},
		"power": -12.0,
		"req_drones": 1,
		"size": Vector2i(1, 2),
		"place": "ORE_OR_ROCK",
		"icon": "res://assets/ui/tool_drill.png",
		"sheet": "res://assets/sprites/mining_drill_sheet.png",
		"frames": 4,
		"desc": "Extracts Fe/Cu/Si/Ti veins continuously onto nearby belts or lifts.",
		"usage": "Place on underground ore veins or rock seams."
	},
	"belt": {
		"name": "Conveyor Belt",
		"category": "MINE",
		"hotkey": "2",
		"cost": {"fe": 2},
		"power": 0.0,
		"req_drones": 1,
		"size": Vector2i(1, 1),
		"place": "ANY_CLEAR",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/conveyor_sheet.png",
		"frames": 4,
		"desc": "Transports mined ores & plates horizontally across terrain or tunnels.",
		"usage": "Connect Drills to Smelters, Assemblers & Replicators. Press [R] to flip."
	},
	"lift": {
		"name": "Ore Lift Shaft",
		"category": "MINE",
		"hotkey": "3",
		"cost": {"fe": 3},
		"power": -1.0,
		"req_drones": 1,
		"size": Vector2i(1, 1),
		"place": "ANY_CLEAR",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/lift_shaft_sheet.png",
		"frames": 4,
		"desc": "Vertical elevator tube hoisting underground ores to the surface.",
		"usage": "Stack vertically inside dug shafts to lift items upward."
	},
	"inserter": {
		"name": "Inserter Arm",
		"category": "MINE",
		"hotkey": "4",
		"cost": {"fe": 4, "cu": 2},
		"power": -2.0,
		"req_drones": 1,
		"size": Vector2i(1, 1),
		"place": "ANY_CLEAR",
		"icon": "res://assets/ui/tool_assembler.png",
		"sheet": "res://assets/sprites/inserter_sheet.png",
		"frames": 4,
		"desc": "Robotic transfer arm boosting throughput between belts & machines.",
		"usage": "Place beside Smelters/Assemblers/Drivers."
	},
	"depot": {
		"name": "Container Depot",
		"category": "MINE",
		"hotkey": "5",
		"cost": {"fe": 18, "cu": 5},
		"power": -3.0,
		"req_drones": 1,
		"size": Vector2i(2, 2),
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_depot.png",
		"sheet": "res://assets/sprites/container_depot.png",
		"frames": 1,
		"desc": "Logistics buffer hub. Connects surface storage & feeds machines automatically.",
		"usage": "Place on surface horizon to share items across your colony."
	},
	"smelter": {
		"name": "Blast Smelter",
		"category": "FACTORY",
		"hotkey": "6",
		"cost": {"fe": 20, "cu": 6},
		"power": -18.0,
		"req_drones": 2,
		"size": Vector2i(2, 2),
		"place": "SURFACE_OR_CAVERN",
		"icon": "res://assets/ui/tool_smelter.png",
		"sheet": "res://assets/sprites/smelter_sheet.png",
		"frames": 4,
		"desc": "Refines raw Fe->Plates, Cu->Wire, Si->Wafers for advanced parts.",
		"usage": "Feed raw ores via belt/depot to smelt refined components."
	},
	"assembler": {
		"name": "Auto Assembler",
		"category": "FACTORY",
		"hotkey": "7",
		"cost": {"fe": 25, "cu": 14, "si": 8},
		"power": -24.0,
		"req_drones": 3,
		"size": Vector2i(2, 2),
		"place": "SURFACE_OR_CAVERN",
		"icon": "res://assets/ui/tool_assembler.png",
		"sheet": "res://assets/sprites/assembler_sheet.png",
		"frames": 4,
		"desc": "Fabricates Circuits (Cu Wire + Si Wafer) & Titanium Alloys.",
		"usage": "Supplies high-tech Circuits & Alloys needed for Replica Probes."
	},
	"printer": {
		"name": "Macro Replicator",
		"category": "FACTORY",
		"hotkey": "8",
		"cost": {"fe": 45, "cu": 20, "si": 12},
		"power": -40.0,
		"req_drones": 4,
		"size": Vector2i(3, 2),
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_printer.png",
		"sheet": "res://assets/sprites/factory_hall_sheet.png",
		"frames": 4,
		"desc": "Heavy industrial printer assembling autonomous Replica Swarm Probes.",
		"usage": "Converts Plates, Circuits & Alloys into Orbital Probes automatically."
	},
	"mass_driver": {
		"name": "Mass Driver",
		"category": "FACTORY",
		"hotkey": "9",
		"cost": {"fe": 60, "cu": 30, "si": 15, "ti": 8},
		"power": -45.0,
		"req_drones": 5,
		"size": Vector2i(4, 3),
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_mass_driver.png",
		"sheet": "res://assets/sprites/mass_driver_sheet.png",
		"frames": 4,
		"desc": "Electromagnetic railgun launching finished Replica Probes into orbit!",
		"usage": "Place on clear surface skyline to fire Probes into your Swarm Fleet."
	},
	"solar": {
		"name": "Solar Array",
		"category": "POWER",
		"hotkey": "0",
		"cost": {"fe": 10, "si": 6},
		"power": 30.0,
		"req_drones": 1,
		"size": Vector2i(2, 1),
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_solar.png",
		"sheet": "res://assets/sprites/solar_array.png",
		"frames": 1,
		"desc": "Clean photovoltaic surface array generating +30 kW power.",
		"usage": "Build along surface horizon to power drills & smelters."
	},
	"geothermal": {
		"name": "Geothermal Plant",
		"category": "POWER",
		"hotkey": "-",
		"cost": {"fe": 35, "cu": 15, "ti": 8},
		"power": 110.0,
		"req_drones": 3,
		"size": Vector2i(2, 2),
		"place": "DEEP_ROCK",
		"icon": "res://assets/ui/tool_geothermal.png",
		"sheet": "res://assets/sprites/geothermal_plant.png",
		"frames": 1,
		"desc": "Taps planetary magma vents for massive +110 kW baseload energy.",
		"usage": "Place deep underground near magma crust."
	},
	"turret": {
		"name": "Defense Turret",
		"category": "POWER",
		"hotkey": "=",
		"cost": {"fe": 20, "cu": 12, "ti": 4},
		"power": -10.0,
		"req_drones": 2,
		"size": Vector2i(1, 1),
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_turret.png",
		"sheet": "res://assets/sprites/defense_turret.png",
		"frames": 1,
		"desc": "Automated pulse laser protecting surface factories from raiders.",
		"usage": "Place on surface rooftops to intercept Corrupted ships."
	},
	"elevator": {
		"name": "Space Elevator",
		"category": "SPACE",
		"hotkey": "",
		"cost": {"fe": 140, "cu": 80, "si": 50, "ti": 40},
		"power": -60.0,
		"req_drones": 6,
		"size": Vector2i(3, 5),
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_elevator.png",
		"sheet": "res://assets/sprites/megastructure_elevator.png",
		"frames": 1,
		"desc": "Orbital tether tripling probe replication output and linking orbit.",
		"usage": "Megastructure anchored on surface horizon."
	},
	"dyson": {
		"name": "Dyson Ring",
		"category": "SPACE",
		"hotkey": "",
		"cost": {"fe": 220, "cu": 140, "si": 100, "ti": 70},
		"power": 400.0,
		"req_drones": 7,
		"size": Vector2i(5, 3),
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_dyson.png",
		"sheet": "res://assets/sprites/megastructure_dyson.png",
		"frames": 1,
		"desc": "Stellar collector beaming +400 kW and supercharging orbital swarm.",
		"usage": "Megastructure boosting power & swarm speed."
	},
	"citadel": {
		"name": "Plasma Citadel",
		"category": "SPACE",
		"hotkey": "",
		"cost": {"fe": 200, "cu": 110, "si": 80, "ti": 90},
		"power": -50.0,
		"req_drones": 7,
		"size": Vector2i(4, 4),
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_citadel.png",
		"sheet": "res://assets/sprites/megastructure_citadel.png",
		"frames": 1,
		"desc": "Orbital fortress empowering Assault Doctrine firepower x2.",
		"usage": "Megastructure built for final Corrupted Hub siege."
	},
	"warpgate": {
		"name": "Warp Gate",
		"category": "SPACE",
		"hotkey": "",
		"cost": {"fe": 320, "cu": 200, "si": 160, "ti": 140},
		"power": -120.0,
		"req_drones": 8,
		"size": Vector2i(4, 4),
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_warpgate.png",
		"sheet": "res://assets/sprites/megastructure_warpgate.png",
		"frames": 1,
		"desc": "Interstellar Seed Gate amplifying full Swarm Self-Replication.",
		"usage": "Final Phase 4 Megastructure achieving total swarm transcendence."
	}
}

func reset_state() -> void:
	fe = 0
	cu = 0
	si = 0
	ti = 0
	he3 = 0
	plate_fe = 0
	wire_cu = 0
	wafer_si = 0
	circuit = 0
	alloy = 0
	probe_stock = 0
	drones = 0
	fleet_count = 0
	total_launches = 0
	hostiles_defeated = 0
	hostiles_active = 0
	boss_hp = boss_max_hp
	boss_defeated = false
	power_gen = 15.0
	power_use = 0.0
	power_ratio = 1.0
	printer_progress = 0.0
	printer_active = false
	current_doctrine = Doctrine.HARVEST
	selected_tool = "pick"
	build_rotation = 0
	recent_ore_type = ""
	recent_ore_amount = 0
	recent_ore_timer = 0.0
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

func get_drone_craft_cost() -> Dictionary:
	# Progressive affordable scaling: first drone = 10 Fe!
	if drones == 0:
		return {"fe": 10}
	elif drones == 1:
		return {"fe": 18, "cu": 6}
	elif drones == 2:
		return {"fe": 26, "cu": 12, "si": 6}
	else:
		var scale = drones
		return {
			"fe": 16 + scale * 10,
			"cu": 8 + scale * 6,
			"si": 4 + scale * 4,
		}

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
		"he3": return he3
		"plate_fe": return plate_fe
		"wire_cu": return wire_cu
		"wafer_si": return wafer_si
		"circuit": return circuit
		"alloy": return alloy
		"probe_stock": return probe_stock
	return 0

func add_res(key: String, amount: int, track_mining_popup: bool = false) -> void:
	match key:
		"fe": fe = maxi(0, fe + amount)
		"cu": cu = maxi(0, cu + amount)
		"si": si = maxi(0, si + amount)
		"ti": ti = maxi(0, ti + amount)
		"he3": he3 = maxi(0, he3 + amount)
		"plate_fe": plate_fe = maxi(0, plate_fe + amount)
		"wire_cu": wire_cu = maxi(0, wire_cu + amount)
		"wafer_si": wafer_si = maxi(0, wafer_si + amount)
		"circuit": circuit = maxi(0, circuit + amount)
		"alloy": alloy = maxi(0, alloy + amount)
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
	emit_signal("log_event", "Docked Fabricator Drone #%d! Beams & Tier unlocked." % drones, "good")
	return true

func get_current_phase() -> int:
	if fleet_count >= 500 or megastructures["warpgate"]:
		return 4
	if fleet_count >= 1 or total_launches >= 1:
		return 3
	if drones >= 1:
		return 2
	return 1

func set_tool(tool_id: String) -> void:
	selected_tool = tool_id
	emit_signal("blueprint_selected", tool_id)
	emit_signal("state_updated")

func set_doctrine(doc: int) -> void:
	current_doctrine = doc
	var names = ["HARVEST", "REPLICATE", "DEFEND", "ASSAULT"]
	emit_signal("log_event", "Swarm Doctrine -> %s" % names[clampi(doc, 0, 3)], "info")
	emit_signal("state_updated")

func add_fleet_units(count: int) -> void:
	fleet_count = mini(max_fleet, fleet_count + count)
	emit_signal("state_updated")

func to_dict() -> Dictionary:
	return {
		"fe": fe, "cu": cu, "si": si, "ti": ti, "he3": he3,
		"plate_fe": plate_fe, "wire_cu": wire_cu, "wafer_si": wafer_si,
		"circuit": circuit, "alloy": alloy, "probe_stock": probe_stock,
		"drones": drones, "fleet_count": fleet_count,
		"total_launches": total_launches, "hostiles_defeated": hostiles_defeated,
		"boss_hp": boss_hp, "boss_defeated": boss_defeated,
		"current_doctrine": current_doctrine,
		"megastructures": megastructures.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	fe = int(d.get("fe", 0))
	cu = int(d.get("cu", 0))
	si = int(d.get("si", 0))
	ti = int(d.get("ti", 0))
	he3 = int(d.get("he3", 0))
	plate_fe = int(d.get("plate_fe", 0))
	wire_cu = int(d.get("wire_cu", 0))
	wafer_si = int(d.get("wafer_si", 0))
	circuit = int(d.get("circuit", 0))
	alloy = int(d.get("alloy", 0))
	probe_stock = int(d.get("probe_stock", 0))
	drones = int(d.get("drones", 0))
	fleet_count = int(d.get("fleet_count", 0))
	total_launches = int(d.get("total_launches", 0))
	hostiles_defeated = int(d.get("hostiles_defeated", 0))
	boss_hp = float(d.get("boss_hp", boss_max_hp))
	boss_defeated = bool(d.get("boss_defeated", false))
	current_doctrine = int(d.get("current_doctrine", Doctrine.HARVEST))
	var ms = d.get("megastructures", {})
	if ms is Dictionary:
		for k in megastructures.keys():
			megastructures[k] = bool(ms.get(k, false))
	emit_signal("inventory_changed")
	emit_signal("state_updated")
