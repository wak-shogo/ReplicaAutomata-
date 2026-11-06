extends Node

# STAR REPLICA: AUTOMA - コアゲームステート＆プログレッション管理 (商用製品版)
# クラフト、自動化、有向物流、電力網、1万体スウォーム、メガストラクチャー、空爆防衛戦、セーブ

# 0. ユーザーストーリー・プログレッシブ進行フェーズ (休眠探査機から宇宙帝国へ)
enum StoryPhase {
	DORMANT,      # 0: 休眠中。何もない地表。画面タップで再起動。
	MOVE,         # 1: 移動確認。数歩移動でセンサーパルスが地下Fe鉱脈を探知。
	MINE,         # 2: 手動採掘。[MINE]ボタンで40 Fe採掘。
	DRONE,        # 3: 子機造形。[DRONE]ボタンで初の子機を3Dプリント＆合体。
	BUILD_MINER,  # 4: 施設建築。[BUILD]ボタンで自動化ドリルをFe鉱脈上に配置。
	FACTORY,      # 5: 工場物流。コンベア・精錬炉の設置。
	SPACE         # 6: 宇宙進出。全機能（星間ナビ、艦隊ドクトリン、メガストラクチャー等）完全開放。
}

var story_phase: StoryPhase = StoryPhase.DORMANT

# 1. 資源データ（原材料 ＆ 宇宙天体固有資源）
var resources = {
	"Fe": 0,         # 鉄鉱石 (初期手動採掘チュートリアル用)
	"Cu": 0,         # 銅鉱石
	"Ti": 0,         # チタン鉱石
	"Si": 0,         # 珪素鉱石
	"Energy": 100.0, # 蓄電グリッド残量 (%)
	"He3": 0,        # 月(Luna): ヘリウム3
	"Plasma": 0,     # 恒星(Sun): 純粋太陽プラズマ
	"Ice": 0,        # 彗星(Comet): 重水素氷・揮発ガス
	"DarkMatter": 0, # ブラックホール(Singularity): 暗黒物質
	"Neutronium": 0  # 中性子星(Pulsar): 中性子縮退物質
}

# 鉱脈の有限埋蔵量 (母星地下)
var vein_reserves = {
	"Fe": 15000,
	"Cu": 9500,
	"Ti": 6000,
	"Si": 8000
}

# 宇宙天体の有限資源埋蔵量
var celestial_reserves: Dictionary = {
	"LUNA-PRIME": 6000,
	"COMET-NEOWISE": 4500,
	"GARGANTUA-ZERO": 5000,
	"PULSAR-X": 3000,
	"HELIOS-PRIME": 999999 # 恒星プラズマ
}

# 2. 中間素材＆アイテムインベントリ
var items = {
	"plate_fe": 0,         # 鉄板
	"wire_cu": 0,          # 銅線
	"silicon_wafer": 0,    # シリコンウェハー
	"circuit": 0,          # 集積回路
	"alloy": 0,            # 耐熱チタン合金
	"drone_unit": 0,       # レプリカドローン機体
	# 建設用ストック
	"miner": 0,            # スタータードリル
	"belt": 0,             # スターターベルト
	"smelter": 0,          # スターター精錬炉
	"assembler": 0,
	"mass_driver": 0,
	"depot": 0,
	"turret": 0,           # スターター防衛タレット
	"solar": 0,            # スターター太陽光パネル
	"geothermal": 0
}

# 3. 電力網ステータス (Power Grid)
var power_generated: float = 0.0   # 総発電量 (kW)
var power_consumed: float = 0.0    # 総消費電力 (kW)
var power_ratio: float = 1.0        # 充足率 (0.0 ~ 1.0)

# 4. 自機サバイバル（耐久値＆シールド）
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var player_shield: float = 100.0
var player_max_shield: float = 100.0
var player_shield_cooldown: float = 0.0

# 5. 艦隊＆スウォームデータ
var fleet_count: int = 0
var fleet_max: int = 10000
var hostile_fleet_count: int = 1500
var hostile_core_health: float = 3000.0
var hostile_core_max_health: float = 3000.0
var liberation_progress: float = 0.0

# ドクトリン: "HARVEST", "MULTIPLY", "ASSAULT"
var fleet_doctrine: String = "HARVEST"

# 6. プレイヤー強化（合体ドローン）
var attached_drones: int = 0
var max_attached_drones: int = 8

# 7. 敵空爆襲来ウェーブ (Air Raid)
var raid_timer: float = 0.0
var raid_interval: float = 50.0
var is_raid_active: bool = false
var raid_wave_count: int = 0

# 7.5 技術ツリー段階的自己開発システム (Progressive Tech Tree)
signal tool_unlocked(tool_name: String)
var unlocked_tools: Dictionary = {
	"miner": false,
	"belt": false,
	"smelter": false,
	"solar": false,
	"assembler": false,
	"depot": false,
	"turret": false,
	"mass_driver": false,
	"geothermal": false,
	"demolish": false
}

func unlock_tool(t_name: String) -> void:
	if unlocked_tools.has(t_name) and not unlocked_tools[t_name]:
		unlocked_tools[t_name] = true
		tool_unlocked.emit(t_name)
		add_log("TECH DISCOVERY: %s BLUEPRINT UNLOCKED!" % t_name.to_upper())
		AudioSynth.play_synth("victory")

func unlock_all_tools() -> void:
	for k in unlocked_tools.keys():
		unlocked_tools[k] = true
		tool_unlocked.emit(k)

# 8. メガストラクチャー建造進捗 (0.0 ~ 1.0)
var megastructures = {
	"elevator": {"name": "Orbital Space Elevator", "cost": {"Fe": 250, "Cu": 180, "Ti": 120, "alloy": 30}, "progress": 0.0, "built": false, "bonus": "Resource Transfer Rate +300%"},
	"dyson": {"name": "Dyson Ring Segment", "cost": {"Fe": 400, "Cu": 300, "Si": 250, "alloy": 60}, "progress": 0.0, "built": false, "bonus": "Factory Speed x2 & Infinite Power"},
	"citadel": {"name": "Orbital Citadel Fortress", "cost": {"Fe": 500, "Ti": 300, "alloy": 100, "circuit": 50}, "progress": 0.0, "built": false, "bonus": "Auto Defense Plasma Battery"},
	"warpgate": {"name": "Stellar Accelerator Cannon", "cost": {"Fe": 800, "Ti": 600, "alloy": 200, "circuit": 120}, "progress": 0.0, "built": false, "bonus": "Final Star System Liberation Weapon"}
}
var active_megastructure_project: String = ""

# 9. クエスト・マイルストーン目標システム (ノンバーバル・ピクトグラム導線対応)
var quest_index: int = 0
var quest_list: Array[Dictionary] = [
	{
		"title": "Awakening & Surface Mining",
		"icon": "tool_pick",
		"short": "MINE Fe",
		"waypoint": "vein_Fe",
		"req_type": "resource",
		"target_res": "Fe",
		"target_val": 40
	},
	{
		"title": "Expansion: Attach Sub-Drone",
		"icon": "item_drone_unit",
		"short": "ATTACH DRONE",
		"waypoint": "player",
		"req_type": "drone",
		"target_val": 1
	},
	{
		"title": "Automation Dawn: Mining Drill",
		"icon": "tool_drill",
		"short": "BUILD DRILL",
		"waypoint": "vein_Fe",
		"req_type": "building",
		"building_type": "miner",
		"target_val": 1
	},
	{
		"title": "Logistics: Conveyor Pipeline",
		"icon": "tool_belt",
		"short": "BUILD BELT",
		"waypoint": "surface",
		"req_type": "building",
		"building_type": "belt",
		"target_val": 3
	},
	{
		"title": "Refining: Electric Smelter",
		"icon": "tool_smelter",
		"short": "BUILD SMELTER",
		"waypoint": "surface",
		"req_type": "building",
		"building_type": "smelter",
		"target_val": 1
	},
	{
		"title": "Fabrication: Auto Assembler",
		"icon": "tool_assembler",
		"short": "BUILD ASSEMBLER",
		"waypoint": "surface",
		"req_type": "building",
		"building_type": "assembler",
		"target_val": 1
	},
	{
		"title": "Orbital Launch: Mass Driver",
		"icon": "tool_mass_driver",
		"short": "BUILD MASS DRIVER",
		"waypoint": "surface",
		"req_type": "building",
		"building_type": "mass_driver",
		"target_val": 1
	},
	{
		"title": "Orbital Fleet: 100 Drone Swarm",
		"icon": "item_drone_unit",
		"short": "FLEET SWARM",
		"waypoint": "space",
		"req_type": "fleet",
		"target_val": 100
	},
	{
		"title": "Lunar Expedition: Harvest Helium-3",
		"icon": "res_he3",
		"short": "HARVEST LUNA He3",
		"waypoint": "LUNA-PRIME",
		"req_type": "resource",
		"target_res": "He3",
		"target_val": 3
	},
	{
		"title": "Deep Space: Solar Plasma & Ice",
		"icon": "res_plasma",
		"short": "HARVEST PLASMA / ICE",
		"waypoint": "HELIOS-PRIME",
		"req_type": "celestial_any",
		"target_val": 5
	},
	{
		"title": "Singularity: Dark Matter Extraction",
		"icon": "res_darkmatter",
		"short": "HARVEST DARK MATTER",
		"waypoint": "GARGANTUA-ZERO",
		"req_type": "resource",
		"target_res": "DarkMatter",
		"target_val": 2
	},
	{
		"title": "Megastructure Construction",
		"icon": "icon_elevator",
		"short": "BUILD MEGASTRUCTURE",
		"waypoint": "megastructure",
		"req_type": "megastructure"
	},
	{
		"title": "Assault Hostile Core & Liberation",
		"icon": "tool_turret",
		"short": "ASSAULT HOSTILE CORE",
		"waypoint": "boss",
		"req_type": "liberation",
		"target_val": 100
	}
]

# ログバッファ
var event_logs: Array[String] = []

# シグナル一覧
signal story_phase_changed(new_phase: int)
signal resource_changed(type: String, amount: int)
signal item_changed(type: String, amount: int)
signal fleet_changed(current: int, maximum: int)
signal log_added(text: String)
signal drone_attached(count: int)
signal quest_updated(quest_idx: int, quest_info: Dictionary)
signal quest_completed(quest_idx: int, quest_info: Dictionary)
signal megastructure_updated(proj_id: String, progress: float, built: bool)
signal doctrine_changed(new_doctrine: String)
signal enemy_damaged(cur_hp: float, max_hp: float)
signal galaxy_liberated()
signal player_health_changed(hp: float, max_hp: float, shield: float, max_shield: float)
signal raid_alert(is_active: bool, message: String)

func _ready() -> void:
	add_log("=== STAR REPLICA: AUTOMA ONLINE ===")
	add_log("SEED UNIT LANDED. PRESS F5 TO QUICK-SAVE, F9 TO QUICK-LOAD.")
	call_deferred("_notify_initial_quest")

func set_story_phase(new_phase: StoryPhase) -> void:
	if story_phase == new_phase:
		return
	story_phase = new_phase
	story_phase_changed.emit(story_phase)
	match story_phase:
		StoryPhase.DORMANT:
			add_log("SYSTEM STATUS: DORMANT PROBE STANDBY")
		StoryPhase.MOVE:
			add_log("CORE INITIALIZED. THRUST SYSTEMS ONLINE.")
		StoryPhase.MINE:
			add_log("SENSOR ALERT: UNDERGROUND Fe VEIN DETECTED!")
		StoryPhase.DRONE:
			add_log("BLUEPRINT UNLOCKED: SUB-DRONE FABRICATION READY.")
		StoryPhase.BUILD_MINER:
			unlock_tool("miner")
			if items.get("miner", 0) <= 0:
				items["miner"] = 1
				item_changed.emit("miner", items["miner"])
			add_log("SCHEMATIC GRANTED: AUTOMATED DRILL (MINER x1).")
		StoryPhase.FACTORY:
			unlock_tool("belt")
			unlock_tool("smelter")
			unlock_tool("solar")
			if items.get("belt", 0) <= 0:
				items["belt"] = 10
				item_changed.emit("belt", items["belt"])
			if items.get("smelter", 0) <= 0:
				items["smelter"] = 1
				item_changed.emit("smelter", items["smelter"])
			add_log("LOGISTICS PROTOCOL: CONVEYORS & SMELTERS UNLOCKED.")
		StoryPhase.SPACE:
			unlock_all_tools()
			add_log("STELLAR ASCENSION: ALL SYSTEMS FULLY OPERATIONAL.")

func _process(delta: float) -> void:
	# シールド自動リチャージ
	if player_shield_cooldown > 0.0:
		player_shield_cooldown -= delta
	elif player_shield < player_max_shield:
		player_shield = minf(player_max_shield, player_shield + delta * 20.0)
		player_health_changed.emit(player_hp, player_max_hp, player_shield, player_max_shield)

	# 敵空爆ウェーブタイマー（工場フェーズ以降に開始）
	if story_phase >= StoryPhase.FACTORY:
		raid_timer += delta
		if raid_timer >= raid_interval:
			raid_timer = 0.0
			_trigger_hostile_air_raid()

func _trigger_hostile_air_raid() -> void:
	raid_wave_count += 1
	is_raid_active = true
	unlock_tool("turret")
	if items.get("turret", 0) <= 0:
		items["turret"] = 1 # 初回防衛用タレット1基支給
		item_changed.emit("turret", items["turret"])
	var alert_msg = "WARNING: HOSTILE AIR RAID INCOMING (WAVE %d) - DEPLOY TURRET TO DEFEND!" % raid_wave_count
	add_log(alert_msg)
	AudioSynth.play_synth("laser")
	raid_alert.emit(true, alert_msg)
	
	# 敵爆撃機スポーンシグナル
	var root_node = get_tree().current_scene
	if root_node and root_node.has_method("spawn_air_raid"):
		root_node.spawn_air_raid(raid_wave_count)

func _notify_initial_quest() -> void:
	if quest_index < quest_list.size():
		quest_updated.emit(quest_index, quest_list[quest_index])

func add_resource(type: String, amount: int) -> void:
	if resources.has(type):
		resources[type] += amount
		resource_changed.emit(type, resources[type])
		_check_quest_progress()
		
		# ストーリーフェーズ自動進行: 40 Fe 到達でドローン造形開放
		if story_phase == StoryPhase.MINE and resources.get("Fe", 0) >= 40:
			set_story_phase(StoryPhase.DRONE)

func mine_celestial_resource(body_id: String, res_type: String, amount: int) -> int:
	var cur = celestial_reserves.get(body_id, 2500)
	if cur <= 0:
		add_log("CELESTIAL VEIN DEPLETED: %s HAS NO REMAINING %s" % [body_id, res_type])
		return 0
	var mined = mini(cur, amount)
	celestial_reserves[body_id] = cur - mined
	add_resource(res_type, mined)
	return mined

func consume_resource(type: String, amount: int) -> bool:
	if resources.has(type) and resources[type] >= amount:
		resources[type] -= amount
		resource_changed.emit(type, resources[type])
		return true
	return false

func add_item(type: String, amount: int) -> void:
	if not items.has(type):
		items[type] = 0
	items[type] += amount
	item_changed.emit(type, items[type])

func consume_item(type: String, amount: int) -> bool:
	if items.has(type) and items[type] >= amount:
		items[type] -= amount
		item_changed.emit(type, items[type])
		return true
	return false

func add_fleet(amount: int) -> void:
	fleet_count = mini(fleet_max, fleet_count + amount)
	fleet_changed.emit(fleet_count, fleet_max)
	_check_quest_progress()

func destroy_fleet(amount: int) -> void:
	if fleet_count > 0:
		var lost = mini(fleet_count, amount)
		fleet_count -= lost
		fleet_changed.emit(fleet_count, fleet_max)
		if randf() < 0.3:
			add_log("SWARM ATTRITION: %d UNITS DESTROYED IN COMBAT" % lost)

func set_fleet_doctrine(doc: String) -> void:
	fleet_doctrine = doc
	doctrine_changed.emit(doc)
	add_log("FLEET DOCTRINE UPDATED: -> [%s]" % doc)

func add_log(text: String) -> void:
	event_logs.append(text)
	if event_logs.size() > 100:
		event_logs.pop_front()
	log_added.emit(text)

func attach_drone() -> bool:
	if attached_drones < max_attached_drones:
		# 初回のドローンは Fe: 40 のみで造形可能！2回目以降は Fe: 30 + Si: 15
		var can_craft = false
		if attached_drones == 0:
			if consume_resource("Fe", 40):
				can_craft = true
			else:
				add_log("CRAFT FAILED: REQUIRES 40 Fe TO FABRICATE SUB-DRONE")
		else:
			if consume_resource("Fe", 30) and consume_resource("Si", 15):
				can_craft = true
			else:
				add_log("CRAFT FAILED: REQUIRES 30 Fe + 15 Si")

		if can_craft:
			attached_drones += 1
			# 自己複製ボーナス：シールド・最大HPの強化
			player_max_shield = 100.0 + float(attached_drones) * 25.0
			player_shield = player_max_shield
			player_max_hp = 100.0 + float(attached_drones) * 20.0
			player_health_changed.emit(player_hp, player_max_hp, player_shield, player_max_shield)
			
			drone_attached.emit(attached_drones)
			add_log("DRONE DOCKED: CHASSIS EXPANDED (%d/%d) - SHIELD & THRUST BOOSTED!" % [attached_drones, max_attached_drones])
			_check_quest_progress()
			if story_phase == StoryPhase.DRONE:
				set_story_phase(StoryPhase.BUILD_MINER)
			return true
	return false

# 自機被弾処理
func damage_player(amount: float) -> bool:
	player_shield_cooldown = 4.5
	if player_shield > 0.0:
		if player_shield >= amount:
			player_shield -= amount
			amount = 0.0
		else:
			amount -= player_shield
			player_shield = 0.0
			
	if amount > 0.0:
		player_hp = maxf(0.0, player_hp - amount)
		
	player_health_changed.emit(player_hp, player_max_hp, player_shield, player_max_shield)
	
	if player_hp <= 0.0:
		add_log("SEED UNIT INTEGRITY CRITICAL: EMERGENCY RECONSTRUCTION!")
		# リスポーン処理
		call_deferred("_respawn_player")
		return true
	return false

func _respawn_player() -> void:
	player_hp = player_max_hp
	player_shield = player_max_shield
	player_health_changed.emit(player_hp, player_max_hp, player_shield, player_max_shield)
	var root_node = get_tree().current_scene
	if root_node:
		var p = root_node.get_node_or_null("Player")
		if p:
			p.global_position = Vector2(780.0, 520.0)
			p.velocity = Vector2.ZERO
			add_log("SEED UNIT RE-FABRICATED AT SEED BAY")

# 手動クラフト処理
func craft_item(recipe_name: String) -> bool:
	match recipe_name:
		"drone":
			return attach_drone()
		"miner":
			if consume_resource("Fe", 20) and consume_resource("Cu", 10):
				add_item("miner", 1)
				add_log("CRAFTED: AUTOMATED MINER x1")
				return true
		"belt":
			if consume_resource("Fe", 6):
				add_item("belt", 5)
				add_log("CRAFTED: CONVEYOR BELT x5")
				return true
		"smelter":
			if consume_resource("Fe", 30) and consume_resource("Cu", 15) and consume_resource("Si", 10):
				add_item("smelter", 1)
				add_log("CRAFTED: ELECTRIC SMELTER x1")
				return true
		"assembler":
			if consume_resource("Fe", 40) and consume_resource("Cu", 25) and consume_resource("Si", 20):
				add_item("assembler", 1)
				add_log("CRAFTED: AUTO ASSEMBLER x1")
				return true
		"mass_driver":
			if consume_resource("Fe", 70) and consume_resource("Cu", 40) and consume_resource("Si", 30):
				add_item("mass_driver", 1)
				add_log("CRAFTED: ORBITAL MASS DRIVER x1")
				return true
		"depot":
			if consume_resource("Fe", 35) and consume_resource("Cu", 20):
				add_item("depot", 1)
				add_log("CRAFTED: LOGISTICS DEPOT x1")
				return true
		"turret":
			if consume_resource("Fe", 35) and consume_resource("Cu", 25) and consume_resource("Si", 15):
				add_item("turret", 1)
				add_log("CRAFTED: DEFENSE TURRET x1")
				return true
		"solar":
			if consume_resource("Fe", 15) and consume_resource("Si", 20):
				add_item("solar", 1)
				add_log("CRAFTED: SOLAR PANEL x1")
				return true
		"geothermal":
			if consume_resource("Fe", 40) and consume_resource("Cu", 25) and consume_resource("Ti", 15):
				add_item("geothermal", 1)
				add_log("CRAFTED: GEOTHERMAL PLANT x1")
				return true
		"plate_fe":
			if consume_resource("Fe", 2):
				add_item("plate_fe", 1)
				return true
		"wire_cu":
			if consume_resource("Cu", 2):
				add_item("wire_cu", 2)
				return true
		"silicon_wafer":
			if consume_resource("Si", 2):
				add_item("silicon_wafer", 1)
				return true
		"circuit":
			if consume_item("wire_cu", 2) and consume_item("silicon_wafer", 1):
				add_item("circuit", 1)
				return true
		"alloy":
			if consume_resource("Fe", 2) and consume_resource("Ti", 2):
				add_item("alloy", 1)
				return true
		"drone_unit":
			if consume_item("plate_fe", 2) and consume_item("circuit", 1):
				add_item("drone_unit", 1)
				return true
	add_log("INSUFFICIENT RESOURCES FOR [%s]" % recipe_name.to_upper())
	return false

# 建造通知
func notify_building_constructed(btype: String) -> void:
	if quest_index < quest_list.size():
		var q = quest_list[quest_index]
		if q.get("req_type") == "building" and q.get("building_type") == btype:
			_advance_quest()

	if btype == "miner":
		unlock_tool("belt")
		unlock_tool("smelter")
		unlock_tool("solar")
		if story_phase == StoryPhase.BUILD_MINER:
			set_story_phase(StoryPhase.FACTORY)
	elif btype == "smelter":
		unlock_tool("assembler")
		unlock_tool("depot")
		if story_phase == StoryPhase.FACTORY:
			set_story_phase(StoryPhase.SPACE)
	elif btype == "assembler":
		unlock_tool("mass_driver")
	elif (btype == "belt") and story_phase == StoryPhase.FACTORY:
		set_story_phase(StoryPhase.SPACE)

# メガストラクチャー建造開始
func start_megastructure(proj_id: String) -> bool:
	if not megastructures.has(proj_id):
		return false
	var proj = megastructures[proj_id]
	if proj["built"]:
		add_log("MEGASTRUCTURE ALREADY OPERATIONAL!")
		return false
	
	var can_afford = true
	for res_k in proj["cost"].keys():
		var need = proj["cost"][res_k]
		if resources.has(res_k) and resources[res_k] < need:
			can_afford = false
			break
		if items.has(res_k) and items[res_k] < need:
			can_afford = false
			break
			
	if can_afford:
		for res_k in proj["cost"].keys():
			var need = proj["cost"][res_k]
			if resources.has(res_k):
				consume_resource(res_k, need)
			elif items.has(res_k):
				consume_item(res_k, need)
		active_megastructure_project = proj_id
		add_log("MEGASTRUCTURE PROJECT LAUNCHED: [%s]" % proj["name"])
		_check_quest_progress()
		return true
	else:
		add_log("INSUFFICIENT RESOURCES FOR MEGASTRUCTURE!")
		return false

# 敵コアへのダメージ
func damage_hostile_core(amount: float) -> void:
	hostile_core_health = maxf(0.0, hostile_core_health - amount)
	enemy_damaged.emit(hostile_core_health, hostile_core_max_health)
	liberation_progress = (1.0 - (hostile_core_health / hostile_core_max_health)) * 100.0
	
	if hostile_core_health <= 0.0 and liberation_progress >= 99.9:
		galaxy_liberated.emit()
		add_log("************************************************")
		add_log("VICTORY! CORRUPTED CORE ANNIHILATED!")
		add_log("STAR SYSTEM LIBERATED: 10,000 SWARM TRIUMPHANT!")
		add_log("************************************************")
		_check_quest_progress()

func _check_quest_progress() -> void:
	if quest_index >= quest_list.size():
		return
	var q = quest_list[quest_index]
	match q.get("req_type"):
		"resource":
			var r_key = q.get("target_res", "Fe")
			if resources.get(r_key, 0) >= q.get("target_val", 0):
				_advance_quest()
		"drone":
			if attached_drones >= q.get("target_val", 0):
				_advance_quest()
		"fleet":
			if fleet_count >= q.get("target_val", 0):
				_advance_quest()
		"celestial_any":
			if resources.get("Plasma", 0) >= q.get("target_val", 0) or resources.get("Ice", 0) >= q.get("target_val", 0):
				_advance_quest()
		"megastructure":
			if active_megastructure_project != "" or megastructures["elevator"]["progress"] > 0.0:
				_advance_quest()
		"liberation":
			if liberation_progress >= 99.9:
				_advance_quest()

func _advance_quest() -> void:
	var q = quest_list[quest_index]
	quest_completed.emit(quest_index, q)
	var r_text = q.get("reward_text", q.get("short", "NEXT"))
	add_log(">>> MISSION COMPLETE: [%s]! REWARD: %s <<<" % [q["title"], r_text])
	quest_index += 1
	if quest_index < quest_list.size():
		quest_updated.emit(quest_index, quest_list[quest_index])
