extends Node

# Central cache for all HD-2D pixel-art textures and sliced AtlasTextures.
var textures: Dictionary = {}
var item_icons: Dictionary = {}
var belt_frames: Array[Texture2D] = []
var lift_frames: Array[Texture2D] = []

const ITEM_ORDER: Array[String] = [
	"fe", "cu", "si", "ti",
	"plate_fe", "wire_cu", "wafer_si", "circuit",
	"alloy", "sci_pack", "probe_stock", "ice",
]

func _ready() -> void:
	_load_all()

func _load_tex(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			textures[key] = t

func _load_all() -> void:
	var direct := {
		"terrain_regolith": "res://assets/art/terrain_regolith.png",
		"terrain_basalt": "res://assets/art/terrain_basalt.png",
		"terrain_backwall": "res://assets/art/terrain_backwall.png",
		"terrain_magma": "res://assets/art/terrain_magma.png",
		"ore_fe": "res://assets/art/ore_fe.png",
		"ore_cu": "res://assets/art/ore_cu.png",
		"ore_si": "res://assets/art/ore_si.png",
		"ore_ti": "res://assets/art/ore_ti.png",
		"bld_solar": "res://assets/art/bld_solar.png",
		"bld_tesla": "res://assets/art/bld_tesla.png",
		"bld_battery": "res://assets/art/bld_battery.png",
		"bld_geothermal": "res://assets/art/bld_geothermal.png",
		"bld_drill": "res://assets/art/bld_drill.png",
		"bld_belt": "res://assets/art/bld_belt.png",
		"bld_lift": "res://assets/art/bld_lift.png",
		"bld_depot": "res://assets/art/bld_depot.png",
		"bld_smelter": "res://assets/art/bld_smelter.png",
		"bld_assembler": "res://assets/art/bld_assembler.png",
		"bld_printer": "res://assets/art/bld_printer.png",
		"bld_mass_driver": "res://assets/art/bld_mass_driver.png",
		"bld_turret": "res://assets/art/bld_turret.png",
		"luna": "res://assets/art/celestials/luna.png",
		"ignis": "res://assets/art/celestials/ignis.png",
		"cryo": "res://assets/art/celestials/cryo.png",
		"ast_fe": "res://assets/art/celestials/ast_fe.png",
		"ast_cu": "res://assets/art/celestials/ast_cu.png",
		"ast_si": "res://assets/art/celestials/ast_si.png",
		"ast_ti": "res://assets/art/celestials/ast_ti.png",
		"enemy_fortress": "res://assets/art/celestials/enemy_fortress.png",
		"icon_items": "res://assets/art/icon_items.png",
		"glow_soft": "res://assets/art/glow_soft.png",
	}
	for k in direct.keys():
		_load_tex(k, direct[k])

	# Slice 16x16 item icons
	if textures.has("icon_items"):
		var sheet: Texture2D = textures["icon_items"]
		for i in range(ITEM_ORDER.size()):
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * 16, 0, 16, 16)
			item_icons[ITEM_ORDER[i]] = at

	# Slice 4 animated belt frames (32x16 each)
	if textures.has("bld_belt"):
		var bs: Texture2D = textures["bld_belt"]
		for f in range(4):
			var at := AtlasTexture.new()
			at.atlas = bs
			at.region = Rect2(f * 32, 0, 32, 16)
			belt_frames.append(at)

	# Slice 4 animated lift frames (24x32 each)
	if textures.has("bld_lift"):
		var ls: Texture2D = textures["bld_lift"]
		for f in range(4):
			var at := AtlasTexture.new()
			at.atlas = ls
			at.region = Rect2(f * 24, 0, 24, 32)
			lift_frames.append(at)

func get_tex(key: String) -> Texture2D:
	return textures.get(key, null)

func get_item_icon(item_id: String) -> Texture2D:
	return item_icons.get(item_id, null)
