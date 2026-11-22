extends Node

# STAR REPLICA: AUTOMA - 状態管理・製造キュー・所持インベントリ・研究ツリー・インタラクティブチュートリアル

signal resource_changed(id: String, amt: int)
signal tech_unlocked(id: String)
signal drone_docked(count: int)
signal propulsion_upgraded(tier: int)
signal craft_completed(kind: String, id: String)
signal stock_changed(id: String, amt: int)
signal log_added(msg: String, kind: String)

enum Doctrine { HARVEST, REPLICATE, DEFEND, ASSAULT }

const SWARM_MAX: int = 10000
const MAX_DRONES: int = 8
const DRONE_COST: Dictionary = {"fe": 10, "cu": 6}
const DRONE_CRAFT_TIME: float = 3.5

const RES_NAMES: Dictionary = {
	"fe": "鉄",
	"cu": "銅",
	"si": "ケイ素",
	"ti": "チタン",
	"ice": "氷",
	"plate_fe": "鉄板",
	"wire_cu": "銅線",
	"wafer_si": "基板",
	"circuit": "回路",
	"alloy": "合金",
	"sci_pack": "研究パック",
	"probe_stock": "プローブ",
}

const DOCTRINE_NAMES: Array[String] = ["収穫", "複製", "防衛", "強襲"]
const DOCTRINE_DESCS: Array[String] = [
	"軌道上の小惑星から自動で鉱石を回収します。",
	"艦隊が自己複製し、時間経過で機体数を増やします。",
	"襲来する敵襲撃機を自動迎撃します。",
	"上空の汚染軌道要塞へ一斉攻撃を行います。",
]

var res: Dictionary = {}
var bld_stock: Dictionary = {} # クラフト完了して所持している設置用装置の数
var craft_queue: Array[Dictionary] = [] # {"kind": "building"|"drone"|"propulsion", "id": String, "name": String, "time_left": float, "total_time": float, "cost": Dictionary}

var unlocked_techs: Array[String] = ["seed_core"]
var attached_drones: int = 0
var propulsion_tier: int = 0 # 0: シード・イオン, 1: 軌道ブースター, 2: 深宇宙クライオ, 3: スウォーム旗艦

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

# 電力網テレメトリ
var pwr_prod: float = 0.0
var pwr_use: float = 0.0
var pwr_stored: float = 0.0
var pwr_cap: float = 0.0
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
var tut_placed: Dictionary = {} # bid -> count
var tut_opened_depot: bool = false
var tut_opened_orbit: bool = false

const PROPULSION_TIERS: Dictionary = {
	0: {
		"name": "シード・イオン浮遊", "thrust": 0.0, "ion": 440.0, "max_spd": 210.0,
		"fuel": 120.0, "req": "seed_core", "cost": {}, "craft_time": 0.0,
		"desc": "初期装備。自動充電イオンで地表や洞窟内を自由に移動できます。",
	},
	1: {
		"name": "軌道ブースター", "thrust": 430.0, "ion": 450.0, "max_spd": 320.0,
		"fuel": 190.0, "req": "smelting_booster", "cost": {"fe": 16, "cu": 8, "plate_fe": 4}, "craft_time": 5.0,
		"desc": "大気圏を突破して宇宙軌道へ進入できる化学推進ブースター。",
	},
	2: {
		"name": "深宇宙クライオ推進", "thrust": 720.0, "ion": 480.0, "max_spd": 560.0,
		"fuel": 320.0, "req": "deep_space", "cost": {"plate_fe": 10, "wire_cu": 8, "wafer_si": 4, "circuit": 4}, "craft_time": 6.5,
		"desc": "衛星や小惑星帯へ高速航行できる高効率クライオ推進機関。",
	},
	3: {
		"name": "スウォーム旗艦ドライブ", "thrust": 1200.0, "ion": 540.0, "max_spd": 900.0,
		"fuel": 480.0, "req": "macro_swarm", "cost": {"plate_fe": 16, "circuit": 10, "alloy": 6, "ti": 12}, "craft_time": 8.0,
		"desc": "最終決戦用の超高出力ドライブ。星系全域を自在に制圧できます。",
	},
}

const TECH_ORDER: Array[String] = [
	"seed_core", "power_grid", "cave_logistics", "smelting_booster",
	"circuits_geo", "deep_space", "macro_swarm", "megastructures",
]

const TECHS: Dictionary = {
	"seed_core": {
		"name": "シード・コア", "col": 0, "row": 1, "req": [], "cost": {},
		"unlocks": ["採掘レーザー", "ドローン増設"],
		"summary": "クラフト画面でファブリケータードローンを製造し、同時採掘と製造速度を強化します。",
		"flow": "鉱石採掘 → クラフトでドローン製造 → 自動ドッキング",
	},
	"power_grid": {
		"name": "電力とテスラ", "col": 1, "row": 0, "req": ["seed_core"],
		"cost": {"fe": 12, "cu": 6},
		"unlocks": ["ソーラーパネル", "テスラリレー", "夜間バッテリー", "電線"],
		"summary": "発電機と夜間バッテリーをクラフトし、電線でテスラリレーへ繋いで周囲へ給電します。",
		"flow": "ソーラー＋バッテリー ─(電線)→ テスラリレー ─(電力ドーム)→ 各機械",
	},
	"cave_logistics": {
		"name": "洞窟物流ライン", "col": 1, "row": 2, "req": ["power_grid"],
		"cost": {"fe": 16, "cu": 8},
		"unlocks": ["採掘ドリル", "コンベアベルト", "縦リフト", "カーゴデポ"],
		"summary": "採掘ドリルで自動採掘し、ベルトやリフトで4方向フィルタ付きカーゴデポへ運びます。",
		"flow": "採掘ドリル → ベルト/リフト → カーゴデポ(4方向出力設定)",
	},
	"smelting_booster": {
		"name": "精錬と軌道進出", "col": 2, "row": 1, "req": ["cave_logistics"],
		"cost": {"fe": 22, "cu": 12},
		"unlocks": ["溶鉱炉", "軌道ブースター"],
		"summary": "溶鉱炉で鉄板・銅線・基板を精錬し、軌道ブースターを製造して宇宙へ飛び立ちます。",
		"flow": "カーゴデポ → 溶鉱炉 → 鉄板/銅線/基板 → 軌道ブースター",
	},
	"circuits_geo": {
		"name": "電子回路と地熱", "col": 3, "row": 0, "req": ["smelting_booster"],
		"cost": {"plate_fe": 6, "wire_cu": 4, "si": 8},
		"unlocks": ["自動組立機", "地熱発電所", "レーザー砲台"],
		"summary": "自動組立機で回路・合金を量産。地熱発電所で昼夜問わず安定した大電力を確保します。",
		"flow": "溶鉱炉 → 自動組立機(回路/合金) ＋ 地熱発電",
	},
	"deep_space": {
		"name": "深宇宙クライオ", "col": 3, "row": 2, "req": ["circuits_geo"],
		"cost": {"plate_fe": 8, "wire_cu": 6, "wafer_si": 4, "circuit": 4},
		"unlocks": ["深宇宙クライオ推進"],
		"summary": "無抵抗の宇宙空間をケプラー軌道で周回し、衛星や小惑星からチタンと氷を採取します。",
		"flow": "軌道飛行 → 衛星ルナ/イグニス/クライオで希少資源採取",
	},
	"macro_swarm": {
		"name": "マクロ艦隊量産", "col": 4, "row": 1, "req": ["deep_space"],
		"cost": {"plate_fe": 12, "circuit": 8, "ti": 10},
		"unlocks": ["マクロ3Dプリンタ", "マスドライバー", "旗艦ドライブ"],
		"summary": "マクロ3Dプリンタでレプリカ機体を量産し、マスドライバーで10,000機艦隊を射出！",
		"flow": "マクロ3Dプリンタ → ベルト → マスドライバー → 10,000機艦隊",
	},
	"megastructures": {
		"name": "巨大構造物", "col": 5, "row": 1, "req": ["macro_swarm"],
		"cost": {"alloy": 8, "circuit": 12, "ti": 16},
		"unlocks": ["軌道エレベーター", "ダイソンリング", "軌道要塞", "ワープゲート"],
		"summary": "軌道メガストラクチャーを建造し、汚染軌道要塞を撃破して星系を解放します。",
		"flow": "10,000機艦隊で強襲 ＋ ワープゲート建造 → 完全勝利",
	},
}

const CRAFT_TABS: Array[Dictionary] = [
	{"id": "unit",  "label": "機体・増設"},
	{"id": "power", "label": "電力・防衛", "items": ["solar", "tesla", "battery", "geothermal", "turret"]},
	{"id": "logi",  "label": "採掘・物流", "items": ["drill", "belt", "lift", "depot"]},
	{"id": "fact",  "label": "加工・艦隊", "items": ["smelter", "assembler", "gantry_printer", "mass_driver"]},
]

const BLD: Dictionary = {
	"solar": {
		"name": "ソーラーパネル", "short": "ソーラー", "tex": "solar", "req": "power_grid",
		"cost": {"fe": 10, "cu": 6}, "craft_time": 2.5, "gen": 44.0, "use": 0.0, "w": 74, "h": 54,
		"desc": "太陽光で発電(44W)。電線でテスラリレーへ繋いで供給します。",
	},
	"tesla": {
		"name": "テスラリレー", "short": "テスラ", "tex": "tesla", "req": "power_grid",
		"cost": {"fe": 10, "cu": 8}, "craft_time": 3.0, "gen": 0.0, "use": 0.0, "w": 54, "h": 78,
		"desc": "電線で受けた電力を周囲の電力ドーム内の機械へ無線配電します。",
	},
	"battery": {
		"name": "夜間バッテリー", "short": "蓄電池", "tex": "battery", "req": "power_grid",
		"cost": {"fe": 12, "cu": 8, "si": 4}, "craft_time": 3.5, "gen": 0.0, "use": 0.0, "w": 58, "h": 56,
		"desc": "余剰電力を18,000kJ蓄電し、夜間も工場を止めずに稼働させます。",
	},
	"geothermal": {
		"name": "地熱発電所", "short": "地熱", "tex": "geothermal", "req": "circuits_geo",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 6}, "craft_time": 4.5, "gen": 135.0, "use": 0.0, "w": 78, "h": 74,
		"desc": "昼夜を問わず135Wを安定発電する大型発電機。電線で接続して使用。",
	},
	"turret": {
		"name": "レーザー砲台", "short": "砲台", "tex": "turret", "req": "circuits_geo",
		"cost": {"plate_fe": 8, "wire_cu": 6}, "craft_time": 3.5, "gen": 0.0, "use": 14.0, "w": 58, "h": 58,
		"desc": "襲来する敵機を自動迎撃します(消費14W)。",
	},
	"drill": {
		"name": "採掘ドリル", "short": "ドリル", "tex": "drill", "req": "cave_logistics",
		"cost": {"fe": 12, "cu": 6}, "craft_time": 3.0, "gen": 0.0, "use": 12.0, "w": 58, "h": 78,
		"desc": "足元の鉱脈を自動採掘(12W)。隣にベルトを置くと自動で流れます。",
	},
	"belt": {
		"name": "コンベアベルト", "short": "ベルト", "tex": "belt", "req": "cave_logistics",
		"cost": {"fe": 2}, "craft_time": 1.2, "gen": 0.0, "use": 1.0, "w": 48, "h": 18,
		"desc": "資源を横へ運びます。設置後タップまたは[R]で向き反転。",
	},
	"lift": {
		"name": "縦リフト", "short": "リフト", "tex": "lift", "req": "cave_logistics",
		"cost": {"fe": 3}, "craft_time": 1.5, "gen": 0.0, "use": 1.0, "w": 24, "h": 54,
		"desc": "地下洞窟から地表へ資源を垂直搬送するエレベーター。",
	},
	"depot": {
		"name": "カーゴデポ", "short": "倉庫", "tex": "depot", "req": "cave_logistics",
		"cost": {"fe": 16, "cu": 6}, "craft_time": 3.5, "gen": 0.0, "use": 0.0, "w": 100, "h": 60,
		"desc": "資源を240個保管。タップすると上下左右の出力フィルタを設定可能！",
	},
	"smelter": {
		"name": "溶鉱炉", "short": "溶鉱炉", "tex": "smelter", "req": "smelting_booster",
		"cost": {"fe": 18, "cu": 10}, "craft_time": 4.0, "gen": 0.0, "use": 18.0, "w": 88, "h": 88,
		"desc": "鉄→鉄板、銅→銅線、ケイ素→基板へ精錬(18W)。タップで手動投入も可。",
	},
	"assembler": {
		"name": "自動組立機", "short": "組立機", "tex": "assembler", "req": "circuits_geo",
		"cost": {"plate_fe": 8, "wire_cu": 6, "si": 4}, "craft_time": 4.5, "gen": 0.0, "use": 22.0, "w": 84, "h": 68,
		"desc": "回路・合金・研究パックを自動生産(22W)。タップでレシピ切替。",
	},
	"gantry_printer": {
		"name": "マクロ3Dプリンタ", "short": "3D印刷", "tex": "gantry_printer", "req": "macro_swarm",
		"cost": {"plate_fe": 16, "circuit": 6, "ti": 8}, "craft_time": 5.5, "gen": 0.0, "use": 34.0, "w": 134, "h": 96,
		"desc": "鉄板と回路から軌道プローブを連続造形(34W)。ベルトで射出機へ。",
	},
	"mass_driver": {
		"name": "マスドライバー", "short": "射出機", "tex": "mass_driver", "req": "macro_swarm",
		"cost": {"plate_fe": 18, "wire_cu": 10, "circuit": 6}, "craft_time": 6.0, "gen": 0.0, "use": 30.0, "w": 134, "h": 112,
		"desc": "プローブを宇宙へ射出し、10,000機スウォーム艦隊を編成(30W)。",
	},
}

const MEGAS: Dictionary = {
	"elevator": {"name": "軌道エレベーター", "cost": {"plate_fe": 18, "wire_cu": 14, "alloy": 6}, "fleet": 300, "desc": "艦隊+300機を軌道上へ即時補給。"},
	"dyson":    {"name": "ダイソンリング",   "cost": {"wafer_si": 14, "circuit": 10, "alloy": 6}, "fleet": 0,   "desc": "全テスラ電力網へ常時+240Wを無線送電。"},
	"citadel":  {"name": "軌道要塞シタデル", "cost": {"alloy": 10, "circuit": 12, "ti": 16},      "fleet": 700, "desc": "艦隊+700機 & 要塞への強襲火力大幅強化。"},
	"warpgate": {"name": "スターワープゲート", "cost": {"alloy": 12, "circuit": 14, "sci_pack": 5}, "fleet": 0,  "desc": "汚染軌道要塞撃破と併せて星系解放を達成！"},
}

const GUIDE_TOPICS: Array[Dictionary] = [
	{
		"title": "1. 移動と採掘",
		"lines": [
			"・移動は常に【画面で見えている方向】に進みます（惑星の裏側でも直感操作！）。",
			"・PCは WASD/矢印キー、スマホは左下のスティックで移動、ブレーキで急停止。",
			"・採掘モードで地面や鉱石をタップ長押し（またはSPACE / 実行ボタン）で採掘します。",
		],
	},
	{
		"title": "2. クラフトと製造キュー",
		"lines": [
			"・右上の【クラフト】から、ドローン・推進機・各種装置を製造できます。",
			"・押したアイテムは【製造キュー】に積まれ、時間経過で順番に完成します。",
			"・キュー内の項目をタップするとキャンセル＆資源100%返却できます。",
			"・ドローンが増えるほど製造速度と採掘ビーム本数がアップします！",
		],
	},
	{
		"title": "3. 装置の設置と解体",
		"lines": [
			"・クラフトが完了した装置は、画面下のバーに【個数バッジ付き】で並びます。",
			"・下部バーから装置を選んで地面をタップすると、ホログラム位置へ設置されます。",
			"・【解体】を選んで既存装置をタップすると、所持インベントリへ100%回収できます。",
		],
	},
	{
		"title": "4. 電力網と電線接続",
		"lines": [
			"・ソーラーパネルや地熱発電所は置いただけでは動きません（出力0W）。",
			"・下部バーの【配線】を選び、発電機 → テスラリレーの順にタップして電線を張ります。",
			"・通電したテスラリレーの青いドーム内にある全機械へ自動で給電されます。",
			"・夜間バッテリーも電線で繋ぐと、夜間の停電を防げます。",
		],
	},
	{
		"title": "5. 物流ラインとカーゴデポ",
		"lines": [
			"・採掘ドリルは6個溜まると停止します。隣にコンベアベルトを置くと自動搬出します。",
			"・ベルト先のカーゴデポ（倉庫）をタップすると在庫確認と4方向出力フィルタを設定可能！",
			"・例：右出力を『鉄』に設定→右のベルト経由で溶鉱炉へ鉄だけを自動供給できます。",
		],
	},
	{
		"title": "6. 軌道飛行と10,000機艦隊",
		"lines": [
			"・軌道ブースターをクラフトすると大気圏を突破し、真空ゼロ抵抗の軌道周回が可能に！",
			"・右上の【指令】から軌道全体マップ切替・艦隊ドクトリン・メガストラクチャーを操作。",
			"・マクロ3Dプリンタ→マスドライバーで艦隊を打ち上げ、上空の汚染軌道要塞を撃破しよう！",
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
	res = {
		"fe": 0, "cu": 0, "si": 0, "ti": 0, "ice": 0,
		"plate_fe": 0, "wire_cu": 0, "wafer_si": 0,
		"circuit": 0, "alloy": 0, "sci_pack": 0, "probe_stock": 0,
	}
	bld_stock.clear()
	craft_queue.clear()
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
	tut_enabled = true
	tut_step = 0
	tut_placed.clear()
	tut_opened_depot = false
	tut_opened_orbit = false
	logs.clear()
	add_log("シード・ユニット降下完了。地面や鉱石をタップして採掘しよう！", "info")

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
	update_tutorial()

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
	if not BLD.has(tool_id): return false
	return has_tech(String(BLD[tool_id]["req"]))

# ------------------------------------------------------------------------------
# 製造キュー（クラフト画面から追加 → 時間経過で完成！）
# ------------------------------------------------------------------------------
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
		add_log("製造開始: ファブリケータードローン（キュー %d件）" % craft_queue.size(), "info")
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
				add_log("資源が不足しています。", "warn")
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
		add_log("ドローン #%d 製造完了＆自動ドッキング！採掘と製造速度UP！" % attached_drones, "good")
		drone_docked.emit(attached_drones)
	elif kind == "propulsion":
		var nxt := int(id)
		propulsion_tier = maxi(propulsion_tier, nxt)
		var info: Dictionary = PROPULSION_TIERS[propulsion_tier]
		max_fuel = float(info["fuel"]); fuel = max_fuel
		max_hp = 100.0 + float(attached_drones) * 15.0 + float(propulsion_tier) * 40.0
		hp = max_hp
		Sfx.play("dock")
		add_log("推進モジュール装着完了: %s！" % String(info["name"]), "good")
		propulsion_upgraded.emit(propulsion_tier)
	elif kind == "building":
		add_stock(id, 1)
		Sfx.play("research")
		add_log("製造完了: %s（下部バーから選択して地面へ設置できます！）" % String(item["name"]), "good")
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
	Sfx.play("research")
	add_log("巨大構造物 完成: %s！" % MEGAS[mid]["name"], "good")
	check_victory()
	return true

func check_victory() -> void:
	if boss_dead and bool(megastructures["warpgate"]) and not game_won:
		game_won = true
		Sfx.play("research")
		add_log("勝利！汚染軌道要塞を撃破し、ワープゲートが起動しました！", "good")

func note_building_placed(bid: String) -> void:
	tut_placed[bid] = int(tut_placed.get(bid, 0)) + 1
	update_tutorial()

# ------------------------------------------------------------------------------
# インタラクティブ・チュートリアル進行判定
# ------------------------------------------------------------------------------
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
				if total_launches >= 1:
					tut_step = 9; changed = true

func get_tutorial_info() -> Dictionary:
	match tut_step:
		0:
			return {
				"step": "1/9", "title": "鉱石を採掘しよう",
				"hint": "画面の行きたい方向へ移動し、地面や赤い鉄・橙の銅をタップ長押し！（鉄 %d/10  銅 %d/6）" % [mini(10, get_r("fe")), mini(6, get_r("cu"))],
				"focus": "mine",
			}
		1:
			var qd := count_queued("drone")
			var h := "製造キュー進行中…完成すると自動で自機にドッキングします！" if qd > 0 else "右上の【クラフト】を開き、『ファブリケータードローン』を製造しよう！"
			return {"step": "2/9", "title": "ドローンをクラフト増設しよう", "hint": h, "focus": "craft_drone"}
		2:
			return {
				"step": "3/9", "title": "電力を研究しよう",
				"hint": "鉄12・銅6を集め、右上の【研究】から『電力とテスラ』を研究しよう！",
				"focus": "research_power",
			}
		3:
			var s_ok := (get_stock("solar") + int(tut_placed.get("solar", 0))) >= 1
			var t_ok := (get_stock("tesla") + int(tut_placed.get("tesla", 0))) >= 1
			return {
				"step": "4/9", "title": "発電装置をクラフトしよう",
				"hint": "【クラフト】→『電力・防衛』でソーラーパネル(%s)とテスラリレー(%s)を製造しよう！" % ["済" if s_ok else "未", "済" if t_ok else "未"],
				"focus": "craft_power",
			}
		4:
			return {
				"step": "5/9", "title": "地表に装置を設置しよう",
				"hint": "下部バーの『ソーラー』と『テスラ』をそれぞれ選び、地表をタップして設置しよう！",
				"focus": "place_power",
			}
		5:
			return {
				"step": "6/9", "title": "電線を張って通電させよう",
				"hint": "下部バーの【配線】を選び、ソーラーパネル → テスラリレーの順にタップして電線を接続！",
				"focus": "wire_power",
			}
		6:
			return {
				"step": "7/9", "title": "自動採掘とカーゴデポ",
				"hint": "『洞窟物流ライン』を研究→ドリル・ベルト・カーゴデポを製造設置し、デポをタップで出力設定！",
				"focus": "logistics",
			}
		7:
			return {
				"step": "8/9", "title": "精錬と宇宙進出",
				"hint": "『精錬と軌道進出』を研究→溶鉱炉で鉄板を作り、【クラフト】で軌道ブースターを製造しよう！",
				"focus": "smelt_orbit",
			}
		8:
			return {
				"step": "9/9", "title": "10,000機スウォーム艦隊",
				"hint": "マクロ3Dプリンタとマスドライバーを建造して艦隊を射出し、【指令】で『強襲』を命じよう！",
				"focus": "swarm",
			}
		_:
			return {
				"step": "完了", "title": "星系解放ミッション",
				"hint": "基本操作マスター！汚染軌道要塞を撃破し、【指令】からワープゲートを建造しよう！",
				"focus": "none",
			}

func add_log(msg: String, kind: String = "info") -> void:
	logs.append({"msg": msg, "kind": kind})
	if logs.size() > 8: logs.pop_front()
	log_added.emit(msg, kind)
