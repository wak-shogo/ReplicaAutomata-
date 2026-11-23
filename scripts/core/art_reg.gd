extends Node

# Central HD-2D sprite, 32x32 icon, & multi-frame animation sheet cache for STAR REPLICA: AUTOMA.
var tex: Dictionary = {}
var icons: Dictionary = {}
var anim_frames: Dictionary = {}
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

const ANIM_SPECS: Dictionary = {
	"gantry_printer": 6,
	"smelter": 6,
	"assembler": 6,
	"mass_driver": 6,
	"drill": 6,
	"tesla": 6,
	"geothermal": 6,
	"battery": 6,
	"solar": 6,
	"turret": 6,
	"orb_power": 6,
	"orb_laser": 6,
	"orb_collector": 6,
	"orb_station": 6,
	"seed_core": 4,
}

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
		"enemy_station", "enemy_probe", "moon_luna", "moon_ignis", "moon_cryo", "planet_astra",
		"ast_fe", "ast_cu", "ast_si", "ast_ti",
		"icon_strip", "glow",
	]
	for n in names:
		var path := "res://assets/sprites/%s.png" % n
		if ResourceLoader.exists(path):
			var t = load(path)
			if t is Texture2D:
				tex[n] = t

	# Load multi-frame horizontal sprite-sheet animations for factories, railguns, & units!
	for key in ANIM_SPECS.keys():
		var cnt: int = int(ANIM_SPECS[key])
		var apath := "res://assets/sprites/%s_anim.png" % key
		if ResourceLoader.exists(apath):
			var sheet = load(apath)
			if sheet is Texture2D and cnt > 0:
				var fw := int(sheet.get_width() / cnt)
				var fh := int(sheet.get_height())
				var arr: Array[Texture2D] = []
				for f in range(cnt):
					var at := AtlasTexture.new()
					at.atlas = sheet
					at.region = Rect2(f * fw, 0, fw, fh)
					arr.append(at)
				anim_frames[key] = arr

	if tex.has("icon_strip"):
		var s: Texture2D = tex["icon_strip"]
		var cell_sz := int(s.get_height())
		if cell_sz <= 0:
			cell_sz = 32
		for i in range(ICON_IDS.size()):
			var at := AtlasTexture.new()
			at.atlas = s
			at.region = Rect2(i * cell_sz, 0, cell_sz, cell_sz)
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

func get_anim(key: String, frame_idx: int) -> Texture2D:
	if anim_frames.has(key):
		var arr: Array = anim_frames[key]
		if arr.size() > 0:
			return arr[posmod(frame_idx, arr.size())]
	return tex.get(key, null)

func get_anim_count(key: String) -> int:
	if anim_frames.has(key):
		return (anim_frames[key] as Array).size()
	return 1

func get_icon(item_id: String) -> Texture2D:
	return icons.get(item_id, null)

func get_font() -> Font:
	return ui_font if ui_font != null else ThemeDB.fallback_font
