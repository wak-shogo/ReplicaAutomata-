extends Node

# Central sprite & icon cache for STAR REPLICA: AUTOMA.
var tex: Dictionary = {}
var icons: Dictionary = {}
var belt_frames: Array[Texture2D] = []
var lift_frames: Array[Texture2D] = []
var ui_font: Font = null

const ICON_IDS: Array[String] = [
	"fe", "cu", "si", "ti",
	"plate_fe", "wire_cu", "wafer_si", "circuit",
	"alloy", "sci_pack", "probe_stock", "ice",
	"quantum_core", "antimatter", "dyson_panel",
	"ignis_ore", "plasma_cell", "cryo_rod", "astra_shard",
]

func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/NotoSansJP-Bold.ttf"):
		var f = load("res://assets/fonts/NotoSansJP-Bold.ttf")
		if f is Font:
			ui_font = f
	var names := [
		"seed_core", "fab_drone", "orbital_booster",
		"depot", "gantry_printer", "smelter", "assembler", "mass_driver",
		"drill", "belt", "lift", "solar", "tesla", "battery", "geothermal", "turret",
		"orb_power", "orb_laser", "orb_collector", "orb_station",
		"crystal_si", "ore_fe", "ore_cu", "ore_ti",
		"enemy_station", "moon_luna", "moon_ignis", "moon_cryo", "planet_astra",
		"ast_fe", "ast_cu", "ast_si", "ast_ti",
		"icon_strip", "glow",
	]
	for n in names:
		var path := "res://assets/sprites/%s.png" % n
		if ResourceLoader.exists(path):
			var t = load(path)
			if t is Texture2D:
				tex[n] = t

	if tex.has("icon_strip"):
		var s: Texture2D = tex["icon_strip"]
		for i in range(ICON_IDS.size()):
			var at := AtlasTexture.new()
			at.atlas = s
			at.region = Rect2(i * 16, 0, 16, 16)
			icons[ICON_IDS[i]] = at

	if tex.has("belt"):
		var bs: Texture2D = tex["belt"]
		for f in range(4):
			var at := AtlasTexture.new()
			at.atlas = bs
			at.region = Rect2(f * 32, 0, 32, 14)
			belt_frames.append(at)

	if tex.has("lift"):
		var ls: Texture2D = tex["lift"]
		for f in range(4):
			var at := AtlasTexture.new()
			at.atlas = ls
			at.region = Rect2(f * 18, 0, 18, 32)
			lift_frames.append(at)

func get_t(key: String) -> Texture2D:
	return tex.get(key, null)

func get_icon(item_id: String) -> Texture2D:
	return icons.get(item_id, null)

func get_font() -> Font:
	return ui_font if ui_font != null else ThemeDB.fallback_font
