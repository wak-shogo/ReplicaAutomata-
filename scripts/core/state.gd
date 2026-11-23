extends Node

# STAR REPLICA: AUTOMA - 状態管理・惑星別資源・アイテムツリー・研究ポイント勝利・汚染度＆防衛

signal resource_changed(id: String, amt: int)
signal tech_unlocked(id: String)
signal drone_docked(count: int)
signal propulsion_upgraded(tier: int)
signal craft_completed(kind: String, id: String)
signal stock_changed(id: String, amt: int)
signal log_added(msg: String, kind: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

const SWARM_MAX: int = 10000
const RESEARCH_POINT_GOAL: int = 1000
const MAX_DRONES: int = 8
const DRONE_COST: Dictionary = {"fe": 10, "cu": 6}
const DRONE_CRAFT_TIME: float = 3.5

const RES_NAMES: Dictionary = {
	"fe": "鉄",
	"cu": "銅",
	"si": "ケイ素",
	"ti": "チタン",
	"ignis_ore": "紅蓮鉱",
	"ice": "永久氷晶",
	"astra_shard": "アストラ結晶",
	"plate_fe": "鉄板",
	"wire_cu": "銅線",
	"wafer_si": "基板",
	"alloy": "チタン合金",
	"circuit": "回路",
	"plasma_cell": "プラズマセル",
	"cryo_rod": "超伝導ロッド",
	"quantum_core": "量子コア",
	"antimatter": "反物質コア",
	"dyson_panel": "ダイソン板",
	"sci_pack": "研究ポイント",
	"probe_stock": "プローブ",
}

const RES_PLANET_ORIGIN: Dictionary = {
	"fe": "テラ-I (初期惑星)",
	"cu": "テラ-I (初期惑星)",
	"si": "テラ-I (初期惑星)",
	"ti": "衛星ルナ (月面・洞窟)",
	"ignis_ore": "イグニス-I (内周灼熱惑星)",
	"ice": "クライオ-IV (外周氷結惑星)",
	"astra_shard": "アストラ-V (最外周・敵中枢惑星)",
}

# 各施設のレシピ定義（自動搬送の必要量計算＆アイテムツリー図解の単一ソース）
const SMELTER_RECIPES: Dictionary = {
	"plate_fe": {"in": {"fe": 2}, "out": "plate_fe", "qty": 1, "time": 1.8},
	"wire_cu":  {"in": {"cu": 2}, "out": "wire_cu",  "qty": 1, "time": 1.8},
	"wafer_si": {"in": {"si": 2}, "out": "wafer_si", "qty": 1, "time": 1.8},
}

const ASSEMBLER_RECIPES: Dictionary = {
	"circuit":     {"in": {"plate_fe": 1, "wire_cu": 1},   "out": "circuit",     "qty": 1,  "time": 2.0},
	"alloy":       {"in": {"plate_fe": 2, "ti": 1},        "out": "alloy",       "qty": 1,  "time": 2.1},
	"plasma_cell": {"in": {"ignis_ore": 2, "alloy": 1},    "out": "plasma_cell", "qty": 1,  "time": 2.2},
	"cryo_rod":    {"in": {"ice": 2, "wafer_si": 1},       "out": "cryo_rod",    "qty": 1,  "time": 2.2},
	"sci_pack":    {"in": {"plate_fe": 1, "circuit": 1},   "out": "sci_pack",    "qty": 20, "time": 2.1},
}

const PRINTER_RECIPE: Dictionary = {
	"in": {"plate_fe": 2, "circuit": 1}, "out": "probe_stock", "qty": 1, "time": 2.4
}

const ORB_STATION_RECIPES: Dictionary = {
	"quantum_core": {"in": {"si": 2, "cu": 2},             "out": "quantum_core", "qty": 1,  "time": 2.8},
	"dyson_panel":  {"in": {"fe": 2, "si": 2},             "out": "dyson_panel",  "qty": 1,  "time": 3.0},
	"antimatter":   {"in": {"quantum_core": 1, "fe": 2},   "out": "antimatter",   "qty": 1,  "time": 3.2},
	"probe_stock":  {"in": {"fe": 2, "quantum_core": 1},   "out": "probe_stock",  "qty": 6,  "time": 3.0},
	"sci_pack":     {"in": {"quantum_core": 1, "ti": 1},   "out": "sci_pack",     "qty": 60, "time": 2.8},
}

const DOCTRINE_NAMES: Array[String] = ["収穫", "複製", "防衛", "強襲"]
const DOCTRINE_DESCS: Array[String] = [
	"軌道上の小惑星から自動で鉱石を回収します。",
	"艦隊が自己複製し、時間経過で機体数を増やします。",
	"各惑星の汚染やマップ外から襲来する敵機を自動迎撃します。",
	"最外周の敵拠点惑星アストラ-Vおよび軌道要塞を制圧攻撃します。",
]

var res: Dictionary = {}
var bld_stock: Dictionary = {}
var craft_queue: Array[Dictionary] = []

var unlocked_techs: Array[String] = ["seed_core"]
var attached_drones: int = 0
var propulsion_tier: int = 0

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
var astra_liberated: bool = false
var astra_bastions_left: int = 6
var game_won: bool = false

# 惑星ごとの環境汚染度（初期惑星 terra は常に 0、他惑星で工場稼働すると上昇→敵襲撃を誘発！）
var planet_pollution: Dictionary = {
	"terra": 0.0, "luna": 0.0, "ignis": 0.0, "cryo": 0.0, "astra": 0.0
}

# 電力網テレメトリ
var pwr_prod: float = 0.0
var pwr_use: float = 0.0
var pwr_stored: float = 0.0
var pwr_cap: float = 0.0
var orb_power_bonus_w: float = 0.0
var wire_count: int = 0
var active_teslas: int = 0
var active_printers: int = 0
var total_printers: int = 0

# 操作状態
var selected_tool: String = "mine"
var build_dir: int = 1
var orbit_view: bool = false
var megastructures: Dictionary = {"elevator": false, "dyson": false, "citadel": false, "warpgate": false}
var logs: Array[Dictionary] = []

# インタラクティブ・チュートリアル状態
var tut_enabled: bool = true
var tut_step: int = 0
var tut_placed: Dictionary = {}
var tut_opened_depot: bool = false
var tut_opened_orbit: bool = false

const PROPULSION_TIERS: Dictionary = {
	0: {
		"name": "シード・イオン浮遊", "thrust": 0.0, "ion": 440.0, "max_spd": 210.0,
		"fuel": 120.0, "req": "seed_core", "cost": {}, "craft_time": 0.0,
		"desc": "初期装備。自動充電イオンで地表や洞窟内を自由に移動できます。",
	},
	1: {
		"name": "軌道ブースター", "thrust": 460.0, "ion": 460.0, "max_spd": 360.0,
		"fuel": 220.0, "req": "smelting_booster", "cost": {"fe": 16, "cu": 8, "plate_fe": 4}, "craft_time": 4.5,
		"desc": "テラ-Iの資源のみで製造可能！宇宙軌道と衛星ルナへ進出しチタンを採掘しよう。",
	},
	2: {
		"name": "深宇宙クライオ推進", "thrust": 760.0, "ion": 500.0, "max_spd": 600.0,
		"fuel": 340.0, "req": "deep_space", "cost": {"plate_fe": 8, "wire_cu": 6, "circuit": 4, "ti": 6}, "craft_time": 5.5,
		"desc": "衛星ルナのチタンを使用！惑星イグニス-Iやクライオ-IVへ高速惑星間航行。",
	},
	3: {
		"name": "スウォーム旗艦ドライブ", "thrust": 1250.0, "ion": 560.0, "max_spd": 940.0,
		"fuel": 520.0, "req": "macro_swarm", "cost": {"alloy": 6, "circuit": 8, "plasma_cell": 2}, "craft_time": 6.5,
		"desc": "イグニス-Iのプラズマセルを搭載した最高出力ドライブ。",
	},
}

const TECH_ORDER: Array[String] = [
	"seed_core", "power_grid", "cave_logistics", "smelting_booster",
	"circuits_geo", "deep_space", "macro_swarm", "megastructures",
]

const TECHS: Dictionary = {
	"seed_core": {
		"name": "シード・コア", "col": 0, "row": 1, "req": [], "cost": {},
		"icon": "seed_core",
		"unlocks": ["採掘レーザー", "ドローン増設"],
		"unlock_keys": ["seed_core", "fab_drone"],
		"flow_keys": ["ore_fe", "seed_core", "fab_drone"],
		"summary": "ドローン製造で採掘＆製造を高速化",
		"flow": "採掘 → ドローン製造 → 自動合体",
	},
	"power_grid": {
		"name": "電力とテスラ", "col": 1, "row": 0, "req": ["seed_core"],
		"cost": {"fe": 12, "cu": 6},
		"icon": "tesla",
		"unlocks": ["ソーラー", "テスラ", "蓄電池", "電線"],
		"unlock_keys": ["solar", "tesla", "battery"],
		"flow_keys": ["solar", "battery", "tesla"],
		"summary": "発電機と蓄電池を電線でテスラへ接続（夜間対策）",
		"flow": "ソーラー＋蓄電池 → 電線 → テスラ",
	},
	"cave_logistics": {
		"name": "洞窟物流ライン", "col": 1, "row": 2, "req": ["power_grid"],
		"cost": {"fe": 16, "cu": 8},
		"icon": "drill",
		"unlocks": ["採掘ドリル", "自動配線コンベア", "倉庫"],
		"unlock_keys": ["drill", "depot"],
		"flow_keys": ["drill", "depot"],
		"summary": "硬質鉱床にドリル設置＆他ラインと交差しない自動配線で搬送",
		"flow": "硬質鉱床ドリル → 自動配線コンベア → 倉庫",
	},
	"smelting_booster": {
		"name": "精錬と軌道進出", "col": 2, "row": 1, "req": ["cave_logistics"],
		"cost": {"fe": 22, "cu": 12},
		"icon": "orbital_booster",
		"unlocks": ["溶鉱炉", "軌道ブースター", "軌道発電衛星", "軌道採掘レーザー"],
		"unlock_keys": ["smelter", "orbital_booster", "orb_power", "orb_laser"],
		"flow_keys": ["smelter", "orbital_booster", "moon_luna", "orb_laser"],
		"summary": "ブースターで衛星ルナへ飛びチタンを採掘！軌道施設を建造可能に",
		"flow": "溶鉱炉 → ブースター → 衛星ルナでチタン採掘 → 軌道施設",
	},
	"circuits_geo": {
		"name": "電子回路と防衛", "col": 3, "row": 0, "req": ["smelting_booster"],
		"cost": {"plate_fe": 6, "wire_cu": 4, "si": 8},
		"icon": "assembler",
		"unlocks": ["自動組立機", "地熱発電所", "レーザー砲台"],
		"unlock_keys": ["assembler", "geothermal", "turret"],
		"flow_keys": ["smelter", "assembler", "turret"],
		"summary": "組立機で回路・合金・研究ポイント生産！他惑星の汚染襲撃を砲台で防衛",
		"flow": "溶鉱炉 → 組立機(回路/研究ポイント) ＋ レーザー砲台",
	},
	"deep_space": {
		"name": "惑星開拓と軌道工場", "col": 3, "row": 2, "req": ["circuits_geo"],
		"cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "circuit": 4},
		"icon": "orb_station",
		"unlocks": ["クライオ推進", "軌道回収モジュール", "軌道クラフト局"],
		"unlock_keys": ["orb_collector", "orb_station", "quantum_core", "plasma_cell"],
		"flow_keys": ["orb_laser", "orb_collector", "orb_station", "quantum_core"],
		"summary": "イグニス-Iの紅蓮鉱・クライオ-IVの永久氷晶を開拓し軌道工場で量子コア製造",
		"flow": "軌道採掘 → 軌道回収 → 軌道クラフト局 → 量子コア/研究ポイント",
	},
	"macro_swarm": {
		"name": "マクロ艦隊量産", "col": 4, "row": 1, "req": ["deep_space"],
		"cost": {"plate_fe": 12, "circuit": 8, "ti": 8},
		"icon": "mass_driver",
		"unlocks": ["3Dプリンタ", "マスドライバー", "旗艦ドライブ"],
		"unlock_keys": ["gantry_printer", "mass_driver", "probe_stock"],
		"flow_keys": ["gantry_printer", "mass_driver", "probe_stock"],
		"summary": "艦隊を連続射出し、最外周の敵拠点惑星アストラ-Vを強襲制圧！",
		"flow": "3Dプリンタ → 射出機 → 艦隊強襲でアストラ-V解放",
	},
	"megastructures": {
		"name": "巨大構造物", "col": 5, "row": 1, "req": ["macro_swarm"],
		"cost": {"alloy": 6, "circuit": 10, "ti": 12},
		"icon": "dyson_panel",
		"unlocks": ["軌道エレベーター", "ダイソンリング", "軌道要塞", "ワープゲート"],
		"unlock_keys": ["dyson_panel", "antimatter", "sci_pack"],
		"flow_keys": ["orb_station", "antimatter", "sci_pack"],
		"summary": "研究ポイント1,000pt達成、またはワープゲート建造で完全クリア！",
		"flow": "研究ポイント 1,000 / 1,000 達成 → 完全勝利",
	},
}

const CRAFT_TABS: Array[Dictionary] = [
	{"id": "unit",    "label": "機体・増設"},
	{"id": "power",   "label": "電力・防衛", "items": ["solar", "tesla", "battery", "geothermal", "turret"]},
	{"id": "logi",    "label": "採掘・物流", "items": ["drill", "depot"]},
	{"id": "fact",    "label": "加工・艦隊", "items": ["smelter", "assembler", "gantry_printer", "mass_driver"]},
	{"id": "orbital", "label": "軌道施設",   "items": ["orb_power", "orb_laser", "orb_collector", "orb_station"]},
]

# 軌道モジュールは衛星ルナ等で手に入るチタン(ti)またはチタン合金(alloy)を要求 → 宇宙進出の明確なモチベーション！
const BLD: Dictionary = {
	"solar": {
		"name": "ソーラーパネル", "short": "ソーラー", "tex": "solar", "req": "power_grid",
		"cost": {"fe": 10, "cu": 6}, "craft_time": 2.5, "gen": 44.0, "use": 0.0, "w": 74, "h": 54, "hp": 110.0,
		"desc": "昼間に太陽光発電(44W)。電線でテスラリレーへ接続。",
	},
	"tesla": {
		"name": "テスラリレー", "short": "テスラ", "tex": "tesla", "req": "power_grid",
		"cost": {"fe": 10, "cu": 8}, "craft_time": 3.0, "gen": 0.0, "use": 0.0, "w": 54, "h": 78, "hp": 140.0,
		"desc": "電線で受けた電力を周囲ドーム内の機械へ無線配電＆施設自動修復。",
	},
	"battery": {
		"name": "夜間バッテリー", "short": "蓄電池", "tex": "battery", "req": "power_grid",
		"cost": {"fe": 12, "cu": 8, "si": 4}, "craft_time": 3.5, "gen": 0.0, "use": 0.0, "w": 58, "h": 56, "hp": 150.0,
		"desc": "余剰電力を蓄電し、夜間も工場を止めずに稼働。",
	},
	"geothermal": {
		"name": "地熱発電所", "short": "地熱", "tex": "geothermal", "req": "circuits_geo",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 6}, "craft_time": 4.5, "gen": 135.0, "use": 0.0, "w": 78, "h": 74, "hp": 180.0,
		"desc": "昼夜を問わず135Wを安定発電する大型発電機。",
	},
	"turret": {
		"name": "レーザー砲台", "short": "砲台", "tex": "turret", "req": "circuits_geo",
		"cost": {"plate_fe": 6, "wire_cu": 6}, "craft_time": 3.0, "gen": 0.0, "use": 12.0, "w": 58, "h": 58, "hp": 260.0,
		"desc": "汚染で引き寄せられた敵機やマップ外襲撃機を自動迎撃(12W)。",
	},
	"drill": {
		"name": "採掘ドリル", "short": "ドリル", "tex": "drill", "req": "cave_logistics",
		"cost": {"fe": 12, "cu": 6}, "craft_time": 3.0, "gen": 0.0, "use": 12.0, "w": 58, "h": 78, "hp": 140.0,
		"desc": "各惑星の【硬質鉱床】専用(12W)。固有鉱石を自動採掘。",
	},
	"belt": {
		"name": "コンベアベルト", "short": "ベルト", "tex": "belt", "req": "cave_logistics",
		"cost": {"fe": 2}, "craft_time": 1.2, "gen": 0.0, "use": 1.0, "w": 48, "h": 18, "hp": 60.0,
		"desc": "自動配線コンベアに統合。",
	},
	"lift": {
		"name": "縦リフト", "short": "リフト", "tex": "lift", "req": "cave_logistics",
		"cost": {"fe": 3}, "craft_time": 1.5, "gen": 0.0, "use": 1.0, "w": 24, "h": 54, "hp": 60.0,
		"desc": "自動配線コンベアに統合。",
	},
	"depot": {
		"name": "カーゴデポ", "short": "倉庫", "tex": "depot", "req": "cave_logistics",
		"cost": {"fe": 16, "cu": 6}, "craft_time": 3.5, "gen": 0.0, "use": 0.0, "w": 100, "h": 60, "hp": 200.0,
		"desc": "資源240個保管。接続先のレシピに応じて必要材料だけを賢く自動供給！",
	},
	"smelter": {
		"name": "溶鉱炉", "short": "溶鉱炉", "tex": "smelter", "req": "smelting_booster",
		"cost": {"fe": 18, "cu": 10}, "craft_time": 4.0, "gen": 0.0, "use": 18.0, "w": 88, "h": 88, "hp": 170.0,
		"desc": "鉄→鉄板、銅→銅線、ケイ素→基板へ精錬(18W)。",
	},
	"assembler": {
		"name": "自動組立機", "short": "組立機", "tex": "assembler", "req": "circuits_geo",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 4}, "craft_time": 4.5, "gen": 0.0, "use": 22.0, "w": 84, "h": 68, "hp": 170.0,
		"desc": "回路・チタン合金・プラズマセル・超伝導ロッド・研究ポイントを自動生産(22W)。",
	},
	"gantry_printer": {
		"name": "マクロ3Dプリンタ", "short": "3D印刷", "tex": "gantry_printer", "req": "macro_swarm",
		"cost": {"plate_fe": 14, "circuit": 6, "ti": 6}, "craft_time": 5.0, "gen": 0.0, "use": 34.0, "w": 134, "h": 96, "hp": 220.0,
		"desc": "鉄板×2＋回路×1からプローブを連続造形(34W)。",
	},
	"mass_driver": {
		"name": "マスドライバー", "short": "射出機", "tex": "mass_driver", "req": "macro_swarm",
		"cost": {"plate_fe": 16, "wire_cu": 10, "circuit": 6, "ti": 6}, "craft_time": 5.5, "gen": 0.0, "use": 30.0, "w": 134, "h": 112, "hp": 240.0,
		"desc": "プローブを宇宙へ射出し10,000機艦隊を編成(30W)。",
	},
	"orb_power": {
		"name": "軌道発電衛星", "short": "軌道送電", "tex": "orb_power", "req": "smelting_booster",
		"orbital": true,
		"cost": {"plate_fe": 6, "wire_cu": 6, "wafer_si": 4, "ti": 4}, "craft_time": 4.5, "gen": 120.0, "use": 0.0, "w": 76, "h": 56, "hp": 150.0,
		"desc": "【要チタン(衛星ルナ)】軌道上で+120W発電し地上・軌道施設へ無線送電。",
	},
	"orb_laser": {
		"name": "軌道採掘レーザー", "short": "軌道採掘", "tex": "orb_laser", "req": "smelting_booster",
		"orbital": true,
		"cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "ti": 6}, "craft_time": 5.0, "gen": 0.0, "use": 40.0, "w": 64, "h": 68, "hp": 160.0,
		"desc": "【要チタン(衛星ルナ)】惑星の鉱物を軌道から自動採掘し宇宙へ打ち上げ。",
	},
	"orb_collector": {
		"name": "軌道回収モジュール", "short": "軌道回収", "tex": "orb_collector", "req": "deep_space",
		"orbital": true,
		"cost": {"plate_fe": 8, "circuit": 4, "ti": 6}, "craft_time": 4.5, "gen": 0.0, "use": 25.0, "w": 68, "h": 64, "hp": 160.0,
		"desc": "重力落下する前の採掘パケットを磁気回収し軌道クラフト局へ転送。",
	},
	"orb_station": {
		"name": "軌道クラフト局", "short": "軌道工場", "tex": "orb_station", "req": "deep_space",
		"orbital": true,
		"cost": {"plate_fe": 12, "circuit": 6, "alloy": 4}, "craft_time": 5.5, "gen": 0.0, "use": 45.0, "w": 92, "h": 76, "hp": 220.0,
		"desc": "【要チタン合金】軌道上で量子コア・反物質コア・ダイソン板・研究ポイント製造。",
	},
}

const MEGAS: Dictionary = {
	"elevator": {"name": "軌道エレベーター", "cost": {"plate_fe": 16, "wire_cu": 12, "alloy": 4}, "fleet": 400, "sci": 150, "desc": "艦隊+400機 ＆ 研究ポイント+150"},
	"dyson":    {"name": "ダイソンリング",   "cost": {"wafer_si": 12, "circuit": 8, "dyson_panel": 2}, "fleet": 0, "sci": 250, "desc": "常時+240W送電 ＆ 研究ポイント+250"},
	"citadel":  {"name": "軌道要塞シタデル", "cost": {"alloy": 8, "circuit": 10, "plasma_cell": 2}, "fleet": 800, "sci": 250, "desc": "艦隊+800機 ＆ 研究ポイント+250"},
	"warpgate": {"name": "スターワープゲート", "cost": {"alloy": 10, "quantum_core": 2, "antimatter": 1}, "fleet": 0, "sci": 400, "desc": "研究ポイント+400 ＆ 星系完全解放！"},
}

# ------------------------------------------------------------------------------
# 完全網羅アイテム＆施設レシピツリー（全資源19種＋全施設・装備を1つのDAGに集約！）
# 左(Col 0: 原石) → (Col 1: 採掘/精錬器) → (Col 2: 基礎素材) → (Col 3: 組立機/基礎設備)
# → (Col 4: 回路/高度素材) → (Col 5: 高度施設/軌道局) → (Col 6: 最終品/研究ポイント)
# ------------------------------------------------------------------------------
const ITEM_TREE_NODES: Array[Dictionary] = [
	# Col 0: 各惑星の原石 (7種)
	{"id": "fe",          "kind": "res", "col": 0, "row": 0, "name": "鉄",          "icon": "fe",          "cost": {}, "sub": "惑星テラ-Iで採掘",       "recipe": "テラ-I 地表・洞窟・ドリル鉱床で採掘"},
	{"id": "cu",          "kind": "res", "col": 0, "row": 1, "name": "銅",          "icon": "cu",          "cost": {}, "sub": "惑星テラ-Iで採掘",       "recipe": "テラ-I 地表・洞窟・ドリル鉱床で採掘"},
	{"id": "si",          "kind": "res", "col": 0, "row": 2, "name": "ケイ素",      "icon": "si",          "cost": {}, "sub": "惑星テラ-Iで採掘",       "recipe": "テラ-I 洞窟の青い結晶・鉱床で採掘"},
	{"id": "ti",          "kind": "res", "col": 0, "row": 3, "name": "チタン",      "icon": "ti",          "cost": {}, "sub": "衛星ルナで採掘",         "recipe": "【宇宙進出】衛星ルナの地表・洞窟で採掘"},
	{"id": "ignis_ore",   "kind": "res", "col": 0, "row": 4, "name": "紅蓮鉱",      "icon": "ignis_ore",   "cost": {}, "sub": "惑星イグニス-Iで採掘",   "recipe": "【内周惑星】イグニス-Iの灼熱地層で採掘"},
	{"id": "ice",         "kind": "res", "col": 0, "row": 5, "name": "永久氷晶",    "icon": "ice",         "cost": {}, "sub": "惑星クライオ-IVで採掘",  "recipe": "【外周惑星】クライオ-IVの氷結洞窟で採掘"},
	{"id": "astra_shard", "kind": "res", "col": 0, "row": 6, "name": "アストラ結晶","icon": "astra_shard", "cost": {}, "sub": "惑星アストラ-Vで採掘",   "recipe": "【敵中枢惑星】艦隊で制圧後に採掘可能"},

	# Col 1: 一次精錬（溶鉱炉を鉄・銅・ケイ素の真横に配置！）＋採掘・物流・初期設備 (7種)
	{"id": "drill",       "kind": "fac", "col": 1, "row": 0, "name": "採掘ドリル",  "icon": "drill",       "cost": {"fe": 12, "cu": 6},  "sub": "鉄×12 銅×6",   "recipe": "硬質鉱床から原石を自動採掘(消費電力12W)"},
	{"id": "smelter",     "kind": "fac", "col": 1, "row": 1, "name": "溶鉱炉",      "icon": "smelter",     "cost": {"fe": 18, "cu": 10}, "sub": "鉄×18 銅×10",  "recipe": "鉄×2→鉄板 / 銅×2→銅線 / ケイ素×2→基板"},
	{"id": "depot",       "kind": "fac", "col": 1, "row": 2, "name": "倉庫(デポ)",  "icon": "depot",       "cost": {"fe": 16, "cu": 6},  "sub": "鉄×16 銅×6",   "recipe": "接続先施設のレシピ必要量だけを自動供給"},
	{"id": "seed_core",   "kind": "fac", "col": 1, "row": 3, "name": "シード自機",  "icon": "seed_core",   "cost": {},                    "sub": "初期プレイヤー機", "recipe": "採掘ビームで全惑星の原石を直接採掘"},
	{"id": "fab_drone",   "kind": "fac", "col": 1, "row": 4, "name": "ドローン",    "icon": "fab_drone",   "cost": {"fe": 10, "cu": 6},  "sub": "鉄×10 銅×6",   "recipe": "採掘＆クラフト速度を+18%強化"},
	{"id": "solar",       "kind": "fac", "col": 1, "row": 5, "name": "ソーラーパネル","icon": "solar",     "cost": {"fe": 10, "cu": 6},  "sub": "鉄×10 銅×6",   "recipe": "昼間に44W発電 → 電線でテスラリレーへ接続"},
	{"id": "tesla",       "kind": "fac", "col": 1, "row": 6, "name": "テスラリレー","icon": "tesla",       "cost": {"fe": 10, "cu": 8},  "sub": "鉄×10 銅×8",   "recipe": "周囲へ無線配電＆施設耐久HPを自動修復"},

	# Col 2: 一次精錬素材 + 基礎電力・宇宙推進 (5種)
	{"id": "plate_fe",        "kind": "res", "col": 2, "row": 0, "name": "鉄板",          "icon": "plate_fe",        "cost": {"fe": 2},                        "sub": "鉄×2",                 "recipe": "溶鉱炉で精錬（鉄×2 → 鉄板×1）"},
	{"id": "wire_cu",         "kind": "res", "col": 2, "row": 1, "name": "銅線",          "icon": "wire_cu",         "cost": {"cu": 2},                        "sub": "銅×2",                 "recipe": "溶鉱炉で精錬（銅×2 → 銅線×1）"},
	{"id": "wafer_si",        "kind": "res", "col": 2, "row": 2, "name": "基板",          "icon": "wafer_si",        "cost": {"si": 2},                        "sub": "ケイ素×2",             "recipe": "溶鉱炉で精錬（ケイ素×2 → 基板×1）"},
	{"id": "battery",         "kind": "fac", "col": 2, "row": 4, "name": "夜間バッテリー","icon": "battery",         "cost": {"fe": 12, "cu": 8, "si": 4},     "sub": "鉄×12 銅×8 ケイ素×4", "recipe": "昼の余剰電力を蓄電し夜間も工場を稼働"},
	{"id": "orbital_booster", "kind": "fac", "col": 2, "row": 6, "name": "軌道ブースター","icon": "orbital_booster", "cost": {"fe": 16, "cu": 8, "plate_fe": 4},"sub": "鉄×16 銅×8 鉄板×4",   "recipe": "テラ-Iから宇宙空間＆衛星ルナへ飛び立つ推進機"},

	# Col 3: 自動組立機・地上中級施設・初期軌道施設 (5種)
	{"id": "assembler",  "kind": "fac", "col": 3, "row": 1, "name": "自動組立機",    "icon": "assembler",  "cost": {"plate_fe": 8, "wire_cu": 6, "si": 4},                 "sub": "鉄板×8 銅線×6 ケイ素×4",         "recipe": "回路・チタン合金・プラズマセル・超伝導ロッド・研究ポイント製造"},
	{"id": "geothermal", "kind": "fac", "col": 3, "row": 3, "name": "地熱発電所",    "icon": "geothermal", "cost": {"plate_fe": 8, "wire_cu": 6, "si": 6},                 "sub": "鉄板×8 銅線×6 ケイ素×6",         "recipe": "昼夜を問わず常時135Wを安定発電"},
	{"id": "turret",     "kind": "fac", "col": 3, "row": 4, "name": "レーザー砲台",  "icon": "turret",     "cost": {"plate_fe": 6, "wire_cu": 6},                          "sub": "鉄板×6 銅線×6",                   "recipe": "月面や他惑星の汚染襲撃機・マップ外敵機を自動迎撃"},
	{"id": "orb_power",  "kind": "fac", "col": 3, "row": 5, "name": "軌道発電衛星",  "icon": "orb_power",  "cost": {"plate_fe": 6, "wire_cu": 6, "wafer_si": 4, "ti": 4},  "sub": "鉄板×6 銅線×6 基板×4 チタン×4", "recipe": "同一軌道上で+120W発電し地上・軌道へ無線送電"},
	{"id": "orb_laser",  "kind": "fac", "col": 3, "row": 6, "name": "軌道採掘レーザー","icon": "orb_laser","cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "ti": 6},  "sub": "鉄板×8 銅線×6 基板×4 チタン×6", "recipe": "軌道から地上鉱脈を自動採掘し宇宙へ打ち上げ"},

	# Col 4: 組立完成素材・惑星固有加工品 (4種)
	{"id": "circuit",     "kind": "res", "col": 4, "row": 0, "name": "回路",          "icon": "circuit",     "cost": {"plate_fe": 1, "wire_cu": 1},   "sub": "鉄板×1 銅線×1",       "recipe": "自動組立機で製造（鉄板×1 + 銅線×1 → 回路×1）"},
	{"id": "alloy",       "kind": "res", "col": 4, "row": 2, "name": "チタン合金",    "icon": "alloy",       "cost": {"plate_fe": 2, "ti": 1},        "sub": "鉄板×2 チタン×1",     "recipe": "自動組立機で製造（鉄板×2 + チタン×1 → チタン合金×1）"},
	{"id": "plasma_cell", "kind": "res", "col": 4, "row": 4, "name": "プラズマセル",  "icon": "plasma_cell", "cost": {"ignis_ore": 2, "alloy": 1},    "sub": "紅蓮鉱×2 チタン合金×1","recipe": "自動組立機で製造（紅蓮鉱×2 + チタン合金×1 → プラズマセル×1）"},
	{"id": "cryo_rod",    "kind": "res", "col": 4, "row": 6, "name": "超伝導ロッド",  "icon": "cryo_rod",    "cost": {"ice": 2, "wafer_si": 1},       "sub": "永久氷晶×2 基板×1",   "recipe": "自動組立機で製造（永久氷晶×2 + 基板×1 → 超伝導ロッド×1）"},

	# Col 5: 高度製造施設（軌道回収・軌道クラフト局・3Dプリンタ・マスドライバー）(4種)
	{"id": "gantry_printer", "kind": "fac", "col": 5, "row": 0, "name": "3Dプリンタ",      "icon": "gantry_printer", "cost": {"plate_fe": 14, "circuit": 6, "ti": 6},              "sub": "鉄板×14 回路×6 チタン×6",         "recipe": "鉄板×2 + 回路×1 からプローブを連続造形(34W)"},
	{"id": "mass_driver",    "kind": "fac", "col": 5, "row": 2, "name": "マスドライバー",  "icon": "mass_driver",    "cost": {"plate_fe": 16, "wire_cu": 10, "circuit": 6, "ti": 6},"sub": "鉄板×16 銅線×10 回路×6 チタン×6","recipe": "プローブを宇宙へ射出し艦隊を編成(30W)"},
	{"id": "orb_collector",  "kind": "fac", "col": 5, "row": 4, "name": "軌道回収モジュール","icon": "orb_collector","cost": {"plate_fe": 8, "circuit": 4, "ti": 6},               "sub": "鉄板×8 回路×4 チタン×6",          "recipe": "軌道採掘で浮上した資源パケットを磁気回収し軌道クラフト局へ転送"},
	{"id": "orb_station",    "kind": "fac", "col": 5, "row": 6, "name": "軌道クラフト局",  "icon": "orb_station",    "cost": {"plate_fe": 12, "circuit": 6, "alloy": 4},           "sub": "鉄板×12 回路×6 チタン合金×4",     "recipe": "軌道上で量子コア・ダイソン板・反物質コア・研究ポイントを製造"},

	# Col 6: 最終完成アイテム＆クリア目標「研究ポイント」(5種)
	{"id": "probe_stock",  "kind": "res", "col": 6, "row": 0, "name": "プローブ艦隊",  "icon": "probe_stock",  "cost": {"plate_fe": 2, "circuit": 1},         "sub": "鉄板×2 回路×1",           "recipe": "3Dプリンタまたは軌道クラフト局で製造 → マスドライバーで艦隊射出"},
	{"id": "sci_pack",     "kind": "res", "col": 6, "row": 1, "name": "研究ポイント",  "icon": "sci_pack",     "cost": {"plate_fe": 1, "circuit": 1},         "sub": "1,000pt達成でクリア！",     "recipe": "自動組立機(鉄板×1+回路×1→+20pt) / 軌道クラフト局(量子コア×1+チタン×1→+60pt)"},
	{"id": "quantum_core", "kind": "res", "col": 6, "row": 3, "name": "量子コア",      "icon": "quantum_core", "cost": {"si": 2, "cu": 2},                    "sub": "ケイ素×2 銅×2",           "recipe": "軌道クラフト局で製造（ケイ素×2 + 銅×2 → 量子コア×1）"},
	{"id": "dyson_panel",  "kind": "res", "col": 6, "row": 5, "name": "ダイソン板",    "icon": "dyson_panel",  "cost": {"fe": 2, "si": 2},                    "sub": "鉄×2 ケイ素×2",           "recipe": "軌道クラフト局で製造（鉄×2 + ケイ素×2 → ダイソン板×1）"},
	{"id": "antimatter",   "kind": "res", "col": 6, "row": 6, "name": "反物質コア",    "icon": "antimatter",   "cost": {"quantum_core": 1, "astra_shard": 1}, "sub": "量子コア×1 アストラ結晶×1","recipe": "軌道クラフト局で製造（量子コア×1 + アストラ結晶×1 → 反物質コア×1）"},
]

# 特定アイテムの製造に必要な「直接の原料・施設」マップ（上流ツリー自動展開用！）
const ITEM_UPSTREAM_PARENTS: Dictionary = {
	"plate_fe": ["fe", "smelter"],
	"wire_cu": ["cu", "smelter"],
	"wafer_si": ["si", "smelter"],
	"circuit": ["plate_fe", "wire_cu", "assembler"],
	"alloy": ["plate_fe", "ti", "assembler"],
	"plasma_cell": ["ignis_ore", "alloy", "assembler"],
	"cryo_rod": ["ice", "wafer_si", "assembler"],
	"sci_pack": ["plate_fe", "circuit", "assembler", "quantum_core", "orb_station"],
	"probe_stock": ["plate_fe", "circuit", "gantry_printer", "mass_driver"],
	"quantum_core": ["si", "cu", "cryo_rod", "orb_laser", "orb_collector", "orb_station"],
	"dyson_panel": ["fe", "si", "orb_laser", "orb_collector", "orb_station"],
	"antimatter": ["quantum_core", "astra_shard", "orb_station"],
	"fab_drone": ["fe", "cu"],
	"drill": ["fe", "cu"],
	"depot": ["fe", "cu"],
	"smelter": ["fe", "cu"],
	"solar": ["fe", "cu"],
	"tesla": ["fe", "cu"],
	"battery": ["fe", "cu", "si"],
	"orbital_booster": ["fe", "cu", "plate_fe"],
	"assembler": ["plate_fe", "wire_cu", "si"],
	"geothermal": ["plate_fe", "wire_cu", "si"],
	"turret": ["plate_fe", "wire_cu"],
	"orb_power": ["plate_fe", "wire_cu", "wafer_si", "ti"],
	"orb_laser": ["plate_fe", "wire_cu", "wafer_si", "ti"],
	"orb_collector": ["plate_fe", "circuit", "ti", "orb_laser"],
	"orb_station": ["plate_fe", "circuit", "alloy", "orb_collector"],
	"gantry_printer": ["plate_fe", "circuit", "ti"],
	"mass_driver": ["plate_fe", "wire_cu", "circuit", "gantry_printer"],
}

const ITEM_TREE_EDGES: Array[Array] = [
	# 原石 → 採掘・一次施設・溶鉱炉
	["fe", "smelter"], ["cu", "smelter"], ["si", "smelter"],
	["fe", "fab_drone"], ["cu", "fab_drone"],
	["fe", "drill"], ["fe", "depot"], ["fe", "solar"], ["fe", "tesla"],
	["si", "battery"],
	# 溶鉱炉 → 精錬素材
	["smelter", "plate_fe"], ["smelter", "wire_cu"], ["smelter", "wafer_si"],
	# 精錬素材 → 軌道ブースター・中級施設・自動組立機
	["plate_fe", "orbital_booster"],
	["plate_fe", "assembler"], ["wire_cu", "assembler"], ["wafer_si", "assembler"],
	["plate_fe", "geothermal"], ["wire_cu", "turret"],
	# 衛星ルナ＆他惑星原石 → 軌道施設・自動組立機
	["ti", "orb_power"], ["ti", "orb_laser"], ["ti", "assembler"],
	["ignis_ore", "assembler"], ["ice", "assembler"],
	# 自動組立機 → 回路・合金・惑星加工品・研究ポイント
	["assembler", "circuit"], ["assembler", "alloy"],
	["assembler", "plasma_cell"], ["assembler", "cryo_rod"],
	["assembler", "sci_pack"],
	# 回路・合金 → 高度施設・軌道クラフト局
	["circuit", "gantry_printer"], ["plate_fe", "gantry_printer"],
	["circuit", "mass_driver"], ["circuit", "orb_collector"],
	["alloy", "orb_station"], ["circuit", "orb_station"],
	["alloy", "plasma_cell"], ["wafer_si", "cryo_rod"],
	# 軌道採掘 → 軌道回収 → 軌道クラフト局
	["orb_laser", "orb_collector"], ["orb_collector", "orb_station"],
	["cryo_rod", "orb_station"], ["astra_shard", "orb_station"],
	# 最終生産 → プローブ・研究ポイント・量子コア・ダイソン板・反物質コア
	["gantry_printer", "probe_stock"], ["mass_driver", "probe_stock"],
	["orb_station", "quantum_core"], ["orb_station", "dyson_panel"],
	["orb_station", "antimatter"], ["orb_station", "sci_pack"], ["orb_station", "probe_stock"],
	["quantum_core", "antimatter"], ["quantum_core", "sci_pack"],
]

const GUIDE_TOPICS: Array[Dictionary] = [
	{
		"title": "1. アイテムツリーと回路製造",
		"lines": [
			"・右上の【レシピ図】で全資源・全施設のつながり（鉄→溶鉱炉→鉄板→組立機→回路など）を一目で確認！",
			"・倉庫から組立機や溶鉱炉へコンベアを繋ぐと、レシピに必要な材料だけがバランスよく自動搬入されます。",
		],
	},
	{
		"title": "2. 自動配線コンベア (Autorouter)",
		"lines": [
			"・コンベアは回路基板の自動配線（Autorouter）のように、他施設や既存ラインを避けてグリッド配線されます。",
			"・他のコンベアと交差して解が見つからないルートは赤く表示され設置できません。配置パズルを楽しもう！",
		],
	},
	{
		"title": "3. 5つの輪切り惑星と固有資源",
		"lines": [
			"・初期惑星テラ-Iには宇宙へ出るための必須資源（鉄・銅・ケイ素）だけが存在します。",
			"・軌道ブースターで宇宙へ出て、輪切り内部を持つ【衛星ルナ】でチタン、【イグニス-I】で紅蓮鉱、【クライオ-IV】で永久氷晶を採掘しよう！",
		],
	},
	{
		"title": "4. 汚染・施設耐久値・アストラ-V制圧",
		"lines": [
			"・初期惑星以外で工場を稼働すると【汚染】が広がり、敵機が飛来して施設を攻撃（耐久値HP減少）します！",
			"・レーザー砲台と艦隊の【防衛】で工場を守り、【強襲】で最外周の敵拠点惑星アストラ-Vを制圧しよう！",
		],
	},
	{
		"title": "5. 研究ポイント1,000達成でクリア",
		"lines": [
			"・組立機や軌道クラフト局、巨大構造物で【研究ポイント】を生産できます。",
			"・左上の【研究ポイント: 1,000 / 1,000】がマックスに到達するとゲームクリアです！",
		],
	},
]

func _ready() -> void:
	reset_all()

func _process(delta: float) -> void:
	if craft_queue.is_empty():
		return
	var speed := 1.0 + float(attached_drones) * 0.18
	var front: Dictionary = craft_queue[0]
	front["time_left"] = float(front["time_left"]) - delta * speed
	if float(front["time_left"]) <= 0.0:
		var done: Dictionary = craft_queue.pop_front()
		_finish_craft(done)

func reset_all() -> void:
	res = {}
	for k in RES_NAMES.keys():
		res[String(k)] = 0
	bld_stock.clear()
	craft_queue.clear()
	unlocked_techs = ["seed_core"]
	attached_drones = 0
	propulsion_tier = 0
	max_hp = 100.0; hp = 100.0
	max_fuel = float(PROPULSION_TIERS[0]["fuel"]); fuel = max_fuel
	max_ion_bat = 100.0; ion_bat = 100.0
	swarm_fleet = 0; total_launches = 0; doctrine = Doctrine.HARVEST
	boss_hp = boss_max_hp; boss_dead = false
	astra_liberated = false; astra_bastions_left = 6
	game_won = false
	planet_pollution = {"terra": 0.0, "luna": 0.0, "ignis": 0.0, "cryo": 0.0, "astra": 0.0}
	pwr_prod = 0.0; pwr_use = 0.0; pwr_stored = 0.0; pwr_cap = 0.0; orb_power_bonus_w = 0.0
	wire_count = 0; active_teslas = 0; active_printers = 0; total_printers = 0
	selected_tool = "mine"; build_dir = 1; orbit_view = false
	megastructures = {"elevator": false, "dyson": false, "citadel": false, "warpgate": false}
	tut_enabled = true
	tut_step = 0
	tut_placed.clear()
	tut_opened_depot = false
	tut_opened_orbit = false
	logs.clear()
	add_log("シード降下完了！研究ポイント1,000pt達成を目指そう。【レシピ図】で全工程を確認！", "info")

func res_name(id: String) -> String:
	return String(RES_NAMES.get(id, id))

func format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "無料"
	var parts: Array[String] = []
	for k in cost.keys():
		parts.append("%s:%d" % [res_name(String(k)), int(cost[k])])
	return " ".join(parts)

func get_r(id: String) -> int:
	return int(res.get(id, 0))

func add_r(id: String, delta: int) -> void:
	res[id] = maxi(0, int(res.get(id, 0)) + delta)
	resource_changed.emit(id, int(res[id]))
	if id == "sci_pack" and delta > 0:
		check_victory()
	update_tutorial()

func get_pollution(body_id: String) -> float:
	if body_id == "terra": return 0.0
	return float(planet_pollution.get(body_id, 0.0))

func add_pollution(body_id: String, delta_p: float) -> void:
	if body_id == "terra" or body_id == "sun":
		return
	planet_pollution[body_id] = clampf(float(planet_pollution.get(body_id, 0.0)) + delta_p, 0.0, 100.0)

func get_stock(bid: String) -> int:
	return int(bld_stock.get(bid, 0))

func add_stock(bid: String, delta: int) -> void:
	var nxt := maxi(0, get_stock(bid) + delta)
	if nxt == 0:
		bld_stock.erase(bid)
	else:
		bld_stock[bid] = nxt
	stock_changed.emit(bid, nxt)
	update_tutorial()

func is_orbital_bld(bid: String) -> bool:
	return BLD.has(bid) and bool(BLD[bid].get("orbital", false))

func get_owned_buildings() -> Array[String]:
	var out: Array[String] = []
	for k in BLD.keys():
		if get_stock(String(k)) > 0:
			out.append(String(k))
	return out

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
	add_log("研究完了: %s" % TECHS[tid]["name"], "good")
	tech_unlocked.emit(tid)
	update_tutorial()
	return true

func is_unlocked(tool_id: String) -> bool:
	if tool_id == "mine" or tool_id == "salvage": return true
	if tool_id == "wire": return has_tech("power_grid")
	if tool_id == "conveyor": return has_tech("cave_logistics")
	if not BLD.has(tool_id): return false
	return has_tech(String(BLD[tool_id]["req"]))

func count_queued(kind: String, id: String = "") -> int:
	var c := 0
	for q in craft_queue:
		if String(q["kind"]) == kind and (id == "" or String(q["id"]) == id):
			c += 1
	return c

func can_enqueue_drone() -> bool:
	return (attached_drones + count_queued("drone")) < MAX_DRONES and can_afford(DRONE_COST)

func can_enqueue_propulsion() -> bool:
	if count_queued("propulsion") > 0:
		return false
	var nxt := propulsion_tier + 1
	if not PROPULSION_TIERS.has(nxt): return false
	var info: Dictionary = PROPULSION_TIERS[nxt]
	return has_tech(String(info["req"])) and can_afford(info["cost"])

func can_enqueue_building(bid: String) -> bool:
	if not BLD.has(bid) or not is_unlocked(bid):
		return false
	return can_afford(BLD[bid]["cost"])

func enqueue_craft(kind: String, id: String) -> bool:
	if craft_queue.size() >= 12:
		Sfx.play("error")
		add_log("製造キューがいっぱいです（最大12件）。", "warn")
		return false
	if kind == "drone":
		if not can_enqueue_drone():
			Sfx.play("error")
			add_log("ドローン製造に必要な資源が不足、または上限です。", "warn")
			return false
		spend(DRONE_COST)
		craft_queue.append({
			"kind": "drone", "id": "fab_drone", "name": "ファブリケータードローン",
			"time_left": DRONE_CRAFT_TIME, "total_time": DRONE_CRAFT_TIME, "cost": DRONE_COST.duplicate(),
		})
		Sfx.play("select")
		add_log("製造開始: ファブリケータードローン", "info")
		update_tutorial()
		return true
	elif kind == "propulsion":
		if not can_enqueue_propulsion():
			Sfx.play("error")
			add_log("推進モジュールの条件または資源が不足しています。", "warn")
			return false
		var nxt := propulsion_tier + 1
		var info: Dictionary = PROPULSION_TIERS[nxt]
		spend(info["cost"])
		var ct := float(info["craft_time"])
		craft_queue.append({
			"kind": "propulsion", "id": str(nxt), "name": String(info["name"]),
			"time_left": ct, "total_time": ct, "cost": info["cost"].duplicate(),
		})
		Sfx.play("select")
		add_log("製造開始: %s" % String(info["name"]), "info")
		update_tutorial()
		return true
	elif kind == "building":
		if not can_enqueue_building(id):
			Sfx.play("error")
			if BLD.has(id) and not is_unlocked(id):
				add_log("先に【研究】で「%s」を解放してください。" % TECHS[BLD[id]["req"]]["name"], "warn")
			else:
				add_log("資源が不足しています（【レシピ図】で入手先を確認）。", "warn")
			return false
		var binfo: Dictionary = BLD[id]
		spend(binfo["cost"])
		var ct := float(binfo["craft_time"])
		craft_queue.append({
			"kind": "building", "id": id, "name": String(binfo["name"]),
			"time_left": ct, "total_time": ct, "cost": binfo["cost"].duplicate(),
		})
		Sfx.play("select")
		add_log("製造キュー追加: %s（%.1f秒）" % [String(binfo["name"]), ct], "info")
		update_tutorial()
		return true
	return false

func cancel_craft(idx: int) -> bool:
	if idx < 0 or idx >= craft_queue.size():
		return false
	var item: Dictionary = craft_queue[idx]
	craft_queue.remove_at(idx)
	var cost: Dictionary = item["cost"]
	for k in cost.keys():
		add_r(String(k), int(cost[k]))
	Sfx.play("pop")
	add_log("製造キャンセル: %s（資源を返却）" % String(item["name"]), "info")
	return true

func _finish_craft(item: Dictionary) -> void:
	var kind := String(item["kind"])
	var id := String(item["id"])
	if kind == "drone":
		attached_drones = mini(MAX_DRONES, attached_drones + 1)
		max_hp = 100.0 + float(attached_drones) * 15.0 + float(propulsion_tier) * 40.0
		hp = max_hp
		Sfx.play("dock")
		add_log("ドローン #%d 製造完了＆自動ドッキング！" % attached_drones, "good")
		drone_docked.emit(attached_drones)
	elif kind == "propulsion":
		var nxt := int(id)
		propulsion_tier = maxi(propulsion_tier, nxt)
		var info: Dictionary = PROPULSION_TIERS[propulsion_tier]
		max_fuel = float(info["fuel"]); fuel = max_fuel
		max_hp = 100.0 + float(attached_drones) * 15.0 + float(propulsion_tier) * 40.0
		hp = max_hp
		Sfx.play("dock")
		add_log("推進モジュール装着完了: %s！衛星ルナや他惑星へ飛び立とう！" % String(info["name"]), "good")
		propulsion_upgraded.emit(propulsion_tier)
	elif kind == "building":
		add_stock(id, 1)
		Sfx.play("research")
		add_log("製造完了: %s（下部バーから配置）" % String(item["name"]), "good")
	craft_completed.emit(kind, id)
	update_tutorial()

func build_mega(mid: String) -> bool:
	if not has_tech("megastructures") or bool(megastructures.get(mid, false)):
		Sfx.play("error"); return false
	if not MEGAS.has(mid) or not spend(MEGAS[mid]["cost"]):
		Sfx.play("error"); return false
	megastructures[mid] = true
	var fl := int(MEGAS[mid]["fleet"])
	if fl > 0: swarm_fleet = mini(SWARM_MAX, swarm_fleet + fl)
	var sp := int(MEGAS[mid].get("sci", 0))
	if sp > 0: add_r("sci_pack", sp)
	Sfx.play("research")
	add_log("巨大構造物 完成: %s！（研究ポイント+%d）" % [MEGAS[mid]["name"], sp], "good")
	check_victory()
	return true

func check_victory() -> void:
	if game_won:
		return
	if get_r("sci_pack") >= RESEARCH_POINT_GOAL or (boss_dead and bool(megastructures["warpgate"])):
		game_won = true
		Sfx.play("research")
		add_log("完全勝利！研究ポイントが最大（%dpt）に達し、星系開拓を達成しました！" % RESEARCH_POINT_GOAL, "good")

func note_building_placed(bid: String) -> void:
	tut_placed[bid] = int(tut_placed.get(bid, 0)) + 1
	update_tutorial()

func update_tutorial() -> void:
	var changed := true
	while changed:
		changed = false
		match tut_step:
			0:
				if get_r("fe") >= 10 and get_r("cu") >= 6:
					tut_step = 1; changed = true
			1:
				if attached_drones >= 1:
					tut_step = 2; changed = true
			2:
				if has_tech("power_grid"):
					tut_step = 3; changed = true
			3:
				var has_sol := (get_stock("solar") + int(tut_placed.get("solar", 0))) >= 1
				var has_tes := (get_stock("tesla") + int(tut_placed.get("tesla", 0))) >= 1
				if has_sol and has_tes:
					tut_step = 4; changed = true
			4:
				if int(tut_placed.get("solar", 0)) >= 1 and int(tut_placed.get("tesla", 0)) >= 1:
					tut_step = 5; changed = true
			5:
				if wire_count >= 1 and active_teslas >= 1:
					tut_step = 6; changed = true
			6:
				if int(tut_placed.get("drill", 0)) >= 1 and int(tut_placed.get("depot", 0)) >= 1 and tut_opened_depot:
					tut_step = 7; changed = true
			7:
				if propulsion_tier >= 1:
					tut_step = 8; changed = true
			8:
				if get_r("ti") >= 6:
					tut_step = 9; changed = true
			9:
				if has_tech("circuits_geo"):
					tut_step = 10; changed = true
			10:
				if int(tut_placed.get("assembler", 0)) >= 1 and get_r("circuit") >= 2:
					tut_step = 11; changed = true
			11:
				if get_r("sci_pack") >= 20:
					tut_step = 12; changed = true
			12:
				var orb_cnt := int(tut_placed.get("orb_power", 0)) + int(tut_placed.get("orb_laser", 0)) + int(tut_placed.get("orb_collector", 0)) + int(tut_placed.get("orb_station", 0))
				if has_tech("deep_space") and (int(tut_placed.get("turret", 0)) >= 1 or orb_cnt >= 1):
					tut_step = 13; changed = true
			13:
				if game_won:
					tut_step = 14; changed = true

func get_tutorial_info() -> Dictionary:
	match tut_step:
		0:
			return {
				"step": "1/14", "title": "鉱石を採掘しよう",
				"hint": "右下スティック（PCはSPACE）で狙った方向を掘ろう！",
				"focus": "mine",
			}
		1:
			var qd := count_queued("drone")
			var h := "製造キュー進行中…完成すると自動で自機にドッキング！" if qd > 0 else "右上の【クラフト】を開き『ドローン増設』を製造！"
			return {"step": "2/14", "title": "ドローンをクラフト増設", "hint": h, "focus": "craft_drone"}
		2:
			return {
				"step": "3/14", "title": "電力を研究しよう",
				"hint": "右上の【研究】から『電力とテスラ』カードをタップして研究！",
				"focus": "research_power",
			}
		3:
			var s_ok := (get_stock("solar") + int(tut_placed.get("solar", 0))) >= 1
			var t_ok := (get_stock("tesla") + int(tut_placed.get("tesla", 0))) >= 1
			return {
				"step": "4/14", "title": "発電装置をクラフト",
				"hint": "【クラフト】→『電力・防衛』でソーラー(%s)とテスラ(%s)を製造！" % ["済" if s_ok else "未", "済" if t_ok else "未"],
				"focus": "craft_power",
			}
		4:
			return {
				"step": "5/14", "title": "地表に装置を設置",
				"hint": "下部バーの『ソーラー』と『テスラ』を選び地表をタップして設置！",
				"focus": "place_power",
			}
		5:
			return {
				"step": "6/14", "title": "電線を張って通電",
				"hint": "下部バーの【配線】を選び、ソーラー → テスラの順にタップ！",
				"focus": "wire_power",
			}
		6:
			return {
				"step": "7/14", "title": "鉱床ドリルと自動配線コンベア",
				"hint": "『洞窟物流ライン』研究→硬質鉱床にドリル＆倉庫を置き【搬送】で接続！",
				"focus": "logistics",
			}
		7:
			return {
				"step": "8/14", "title": "溶鉱炉と軌道ブースター製造",
				"hint": "『精錬と軌道進出』を研究→溶鉱炉で鉄板・銅線を作り、軌道ブースターを製造！",
				"focus": "smelt_orbit",
			}
		8:
			return {
				"step": "9/14", "title": "衛星ルナへ飛んでチタンを採掘",
				"hint": "宇宙へ飛び立ち、地球を公転する『衛星ルナ』に着陸してチタンを6個掘ろう！",
				"focus": "mine_luna_ti",
			}
		9:
			return {
				"step": "10/14", "title": "『電子回路と防衛』を研究しよう",
				"hint": "溶鉱炉で鉄板6・銅線4を揃え、右上の【研究】で『電子回路と防衛』を解放！",
				"focus": "research_circuits",
			}
		10:
			return {
				"step": "11/14", "title": "自動組立機で『回路』を生産",
				"hint": "【クラフト】で自動組立機を製造・設置し、倉庫から搬送接続して回路を2個作ろう！",
				"focus": "assemble_circuit",
			}
		11:
			return {
				"step": "12/14", "title": "研究ポイントの生産方法",
				"hint": "自動組立機をタップ→『レシピ: 回路』を押して【研究ポイント】に切替！（1,000ptでクリア）",
				"focus": "produce_sci_pack",
			}
		12:
			return {
				"step": "13/14", "title": "軌道施設と月面・他惑星の防衛",
				"hint": "『惑星開拓と軌道工場』を研究！周回軌道への軌道施設配置や、月面へのレーザー砲台設置を行おう！",
				"focus": "orbital_and_defense",
			}
		_:
			return {
				"step": "14/14", "title": "研究ポイント1,000達成＆アストラ-V制圧",
				"hint": "研究ポイントを1,000pt貯めるか、3Dプリンタ＋射出機で艦隊を量産し敵拠点アストラ-Vを制圧！",
				"focus": "swarm",
			}

func add_log(msg: String, kind: String = "info") -> void:
	logs.append({"msg": msg, "kind": kind})
	if logs.size() > 8: logs.pop_front()
	log_added.emit(msg, kind)
