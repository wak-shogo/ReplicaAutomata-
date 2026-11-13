extends Node

# ==============================================================================
# STAR REPLICA: AUTOMA - CORE GAME STATE, SPHERICAL BUILD CATALOG & 2-CLICK TREE
# Zero starting structures, zero pre-built stations. Pure ABXY 2-Click Tree.
# ==============================================================================

signal inventory_changed
signal state_updated
signal blueprint_selected(building_id: String)
signal drone_count_changed(new_count: int)
signal probe_launched(world_pos: Vector2)
signal log_event(message: String, level: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

# Core Seed Unit Vitals
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var player_shield: float = 50.0
var player_max_shield: float = 50.0

# Raw & Refined Resources (Zero start)
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

# Progression & Swarm Fleet
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

# Energy Grid
var power_gen: float = 15.0
var power_use: float = 0.0
var power_ratio: float = 1.0

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

# Spherical Facility Catalog
# Radial width_sec = sectors wide on sphere surface; place rules:
#   SURFACE, UNDERGROUND, DEEP_ROCK, ANY_SPHERE
const BUILDINGS: Dictionary = {
	"drill": {
		"name": "Mining Drill",
		"branch": "MINE",
		"cost": {"fe": 10},
		"power": -10.0,
		"req_drones": 1,
		"sec_w": 1,
		"h_px": 42.0,
		"place": "UNDERGROUND",
		"icon": "res://assets/ui/tool_drill.png",
		"sheet": "res://assets/sprites/mining_drill_sheet.png",
		"frames": 4,
		"desc": "Automated extractor anchored to underground mineral veins."
	},
	"belt": {
		"name": "Arc Belt",
		"branch": "MINE",
		"cost": {"fe": 2},
		"power": 0.0,
		"req_drones": 1,
		"sec_w": 1,
		"h_px": 20.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/conveyor_sheet.png",
		"frames": 4,
		"desc": "Curved planetary conveyor routing materials around the globe."
	},
	"lift": {
		"name": "Radial Lift",
		"branch": "MINE",
		"cost": {"fe": 3},
		"power": -1.0,
		"req_drones": 1,
		"sec_w": 1,
		"h_px": 34.0,
		"place": "UNDERGROUND",
		"icon": "res://assets/ui/tool_belt.png",
		"sheet": "res://assets/sprites/lift_shaft_sheet.png",
		"frames": 4,
		"desc": "Vertical shaft hoisting core ores outward to the surface."
	},
	"depot": {
		"name": "Cargo Depot",
		"branch": "MINE",
		"cost": {"fe": 16, "cu": 4},
		"power": -3.0,
		"req_drones": 1,
		"sec_w": 2,
		"h_px": 46.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_depot.png",
		"sheet": "res://assets/sprites/container_depot.png",
		"frames": 1,
		"desc": "Planetary logistics hub linking storage across sectors."
	},
	"smelter": {
		"name": "Blast Smelter",
		"branch": "FACTORY",
		"cost": {"fe": 18, "cu": 6},
		"power": -16.0,
		"req_drones": 2,
		"sec_w": 2,
		"h_px": 50.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_smelter.png",
		"sheet": "res://assets/sprites/smelter_sheet.png",
		"frames": 4,
		"desc": "Refines raw Fe/Cu/Si into Plates, Wires & Wafers."
	},
	"assembler": {
		"name": "Auto Assembler",
		"branch": "FACTORY",
		"cost": {"fe": 24, "cu": 12, "si": 6},
		"power": -22.0,
		"req_drones": 3,
		"sec_w": 2,
		"h_px": 50.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_assembler.png",
		"sheet": "res://assets/sprites/assembler_sheet.png",
		"frames": 4,
		"desc": "Assembles Circuits & Titanium Alloys for Swarm Probes."
	},
	"printer": {
		"name": "Replicator",
		"branch": "FACTORY",
		"cost": {"fe": 40, "cu": 18, "si": 10},
		"power": -36.0,
		"req_drones": 4,
		"sec_w": 3,
		"h_px": 62.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_printer.png",
		"sheet": "res://assets/sprites/factory_hall_sheet.png",
		"frames": 4,
		"desc": "Macro printer fabricating autonomous Orbital Replica Probes."
	},
	"mass_driver": {
		"name": "Mass Driver",
		"branch": "FACTORY",
		"cost": {"fe": 55, "cu": 28, "si": 14, "ti": 6},
		"power": -42.0,
		"req_drones": 5,
		"sec_w": 3,
		"h_px": 74.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_mass_driver.png",
		"sheet": "res://assets/sprites/mass_driver_sheet.png",
		"frames": 4,
		"desc": "Orbital railgun launching Replica Probes into deep space!"
	},
	"solar": {
		"name": "Solar Array",
		"branch": "POWER",
		"cost": {"fe": 10, "si": 5},
		"power": 30.0,
		"req_drones": 1,
		"sec_w": 2,
		"h_px": 26.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_solar.png",
		"sheet": "res://assets/sprites/solar_array.png",
		"frames": 1,
		"desc": "Surface photovoltaic panel array generating +30 kW."
	},
	"geothermal": {
		"name": "Geo Plant",
		"branch": "POWER",
		"cost": {"fe": 32, "cu": 14, "ti": 6},
		"power": 115.0,
		"req_drones": 3,
		"sec_w": 2,
		"h_px": 44.0,
		"place": "DEEP_ROCK",
		"icon": "res://assets/ui/tool_geothermal.png",
		"sheet": "res://assets/sprites/geothermal_plant.png",
		"frames": 1,
		"desc": "Taps molten core magma layer for +115 kW constant energy."
	},
	"turret": {
		"name": "Laser Turret",
		"branch": "POWER",
		"cost": {"fe": 18, "cu": 10, "ti": 4},
		"power": -10.0,
		"req_drones": 2,
		"sec_w": 1,
		"h_px": 32.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/tool_turret.png",
		"sheet": "res://assets/sprites/defense_turret.png",
		"frames": 1,
		"desc": "Radial defense turret defending planet sectors from raiders."
	},
	"elevator": {
		"name": "Orbital Anchor",
		"branch": "MEGA",
		"cost": {"fe": 120, "cu": 70, "si": 45, "ti": 35},
		"power": -55.0,
		"req_drones": 6,
		"sec_w": 3,
		"h_px": 135.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_elevator.png",
		"sheet": "res://assets/sprites/megastructure_elevator.png",
		"frames": 1,
		"desc": "Player-built Space Elevator & Orbital Shipyard Hub anchor."
	},
	"dyson": {
		"name": "Dyson Ring",
		"branch": "MEGA",
		"cost": {"fe": 200, "cu": 130, "si": 90, "ti": 60},
		"power": 420.0,
		"req_drones": 7,
		"sec_w": 4,
		"h_px": 95.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_dyson.png",
		"sheet": "res://assets/sprites/megastructure_dyson.png",
		"frames": 1,
		"desc": "Planetary energy ring beaming +420 kW into swarm & grid."
	},
	"citadel": {
		"name": "Plasma Citadel",
		"branch": "MEGA",
		"cost": {"fe": 190, "cu": 100, "si": 75, "ti": 80},
		"power": -45.0,
		"req_drones": 7,
		"sec_w": 3,
		"h_px": 110.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_citadel.png",
		"sheet": "res://assets/sprites/megastructure_citadel.png",
		"frames": 1,
		"desc": "Heavy orbital siege fortress doubling Swarm Assault damage."
	},
	"warpgate": {
		"name": "Warp Gate",
		"branch": "MEGA",
		"cost": {"fe": 300, "cu": 180, "si": 150, "ti": 130},
		"power": -100.0,
		"req_drones": 8,
		"sec_w": 4,
		"h_px": 115.0,
		"place": "SURFACE",
		"icon": "res://assets/ui/icon_warpgate.png",
		"sheet": "res://assets/sprites/megastructure_warpgate.png",
		"frames": 1,
		"desc": "Interstellar Seed Gate amplifying full Swarm self-replication."
	}
}

func reset_state() -> void:
	player_hp = 100.0
	player_shield = 50.0
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
	build_rotation = 1
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
	# Passive shield recharge when grid power is healthy
	if player_shield < player_max_shield and power_ratio >= 0.8:
		player_shield = minf(player_max_shield, player_shield + 4.0 * delta)

func get_drone_craft_cost() -> Dictionary:
	if drones == 0:
		return {"fe": 10}
	elif drones == 1:
		return {"fe": 16, "cu": 6}
	elif drones == 2:
		return {"fe": 24, "cu": 12, "si": 6}
	else:
		return {"fe": 16 + drones * 10, "cu": 8 + drones * 6, "si": 4 + drones * 4}

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
	emit_signal("log_event", "Docked Drone #%d! Tier unlocked." % drones, "good")
	return true

func set_tool(tool_id: String) -> void:
	selected_tool = tool_id
	emit_signal("blueprint_selected", tool_id)
	emit_signal("state_updated")

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
		player_hp = maxf(20.0, player_hp - dmg)
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
