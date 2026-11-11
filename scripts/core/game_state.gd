extends Node
## 玩家进度：金币、力量、装备、背包、展示台、图鉴，以及存档和展示收益结算。
## 作为自动加载单例 GameState 使用；测试里也可以单独 new 一份（不进场景树就不读写磁盘）。
##
## 预留接口（第一版都不实装，界面也不出示）：
##   - 鱼饵：extra_luck() 目前恒为 0，以后在这里汇总鱼饵等运气加成；
##   - 内购：金币只经 add_gold() / spend() 进出，以后内购到账接在 add_gold()；
##   - 自动钓鱼：钓鱼流程只认 FishingController 的 press / release / tap，
##     以后由另一个驱动者调用即可，不需要改规则。

## 存档数据发生了离散变化（买卖、上架、升级、举重等）。界面据此刷新。
signal changed
## 展示收益按离线结算了一笔：seconds 是实际计入的时长（已封顶），gold 是到账金币。
signal offline_settled(seconds: float, gold: float)

const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 5.0

var save_path := "user://save.json"
var io_enabled := true

var gold := 0.0
var strength := 0
## 已拥有的鱼竿档位，以及当前装备的档位。
var owned_rods: Array[int] = [0]
var rod := 0
## 已拥有的哑铃档位，以及当前装备的档位（-1 表示还没有哑铃）。
var owned_dumbbells: Array[int] = []
var dumbbell := -1
## 背包里的鱼。每条鱼是一个个体：{uid, species, level, earned}。
## level 是展示等级，跟着这条鱼走；earned 是这条鱼展示以来产生的收益。
var backpack: Array[Dictionary] = []
## 8 个展示台，每项是一条鱼或 null。
var stands: Array = []
## 图鉴：鱼种 id -> 成功捕获次数。只增不减，和持有的鱼无关。
var codex: Dictionary = {}
var next_uid := 1
## 上次结算展示收益的时刻（Unix 秒）。0 表示还没结算过。
var last_accrual := 0.0

var _dirty := false
var _since_save := 0.0


func _ready() -> void:
	if "--no-save" in OS.get_cmdline_user_args():
		io_enabled = false
	reset()
	if io_enabled:
		load_game()


func _process(delta: float) -> void:
	accrue(Time.get_unix_time_from_system())
	_since_save += delta
	if _dirty and _since_save >= AUTOSAVE_INTERVAL:
		save_game()


func _notification(what: int) -> void:
	# 网页版关标签页时不一定有关闭通知，所以失去焦点、切到后台时也抢存一次。
	var leaving := [
		NOTIFICATION_WM_CLOSE_REQUEST,
		NOTIFICATION_WM_GO_BACK_REQUEST,
		NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_WM_WINDOW_FOCUS_OUT,
	]
	if what in leaving and is_inside_tree() and _dirty:
		save_game()


func reset() -> void:
	gold = 0.0
	strength = Balance.START_STRENGTH
	owned_rods = [0]
	rod = 0
	owned_dumbbells = []
	dumbbell = -1
	backpack = []
	stands = []
	stands.resize(Content.STAND_COUNT)
	codex = {}
	next_uid = 1
	last_accrual = 0.0
	_dirty = false


# ── 金币 ───────────────────────────────────────────────────────────

func add_gold(amount: float) -> void:
	gold += maxf(amount, 0.0)
	_touch()


func can_afford(cost: float) -> bool:
	return gold >= cost


func spend(cost: float) -> bool:
	if cost < 0.0 or gold < cost:
		return false
	gold -= cost
	_touch()
	return true


## 预留：鱼饵等额外运气加成。第一版没有鱼饵。
func extra_luck() -> float:
	return 0.0


# ── 背包与图鉴 ─────────────────────────────────────────────────────

func backpack_full() -> bool:
	return backpack.size() >= Balance.BACKPACK_CAPACITY


func codex_count() -> int:
	return codex.size()


func is_registered(species_id: String) -> bool:
	return codex.has(species_id)


## 成功捕获：永久登记图鉴，鱼进背包。返回这条新鱼。
## 满包时不允许投竿，所以正常流程里调用时背包一定有空位。
func catch_fish(species_id: String) -> Dictionary:
	var count: int = codex.get(species_id, 0)
	codex[species_id] = count + 1
	var fish := {"uid": next_uid, "species": species_id, "level": 1, "earned": 0.0}
	next_uid += 1
	backpack.append(fish)
	_touch()
	return fish


func find_in_backpack(uid: int) -> int:
	for i in backpack.size():
		var fish_uid: int = backpack[i]["uid"]
		if fish_uid == uid:
			return i
	return -1


static func fish_sell_price(fish: Dictionary) -> int:
	var species_id: String = fish["species"]
	var level: int = fish["level"]
	return Rules.sell_price(species_id, level)


static func fish_income(fish: Dictionary) -> float:
	var species_id: String = fish["species"]
	var level: int = fish["level"]
	return Rules.income_per_second(species_id, level)


## 卖掉背包里的一条鱼，返回到手的金币。出售不影响图鉴。
func sell_fish(uid: int) -> int:
	var index := find_in_backpack(uid)
	if index < 0:
		return 0
	var price := fish_sell_price(backpack[index])
	backpack.remove_at(index)
	gold += price
	_touch()
	return price


## 卖掉背包里的全部鱼（展示中的不动），返回到手的金币。
func sell_all_backpack() -> int:
	var total := 0
	for fish in backpack:
		total += fish_sell_price(fish)
	backpack.clear()
	gold += total
	_touch()
	return total


# ── 展示台 ─────────────────────────────────────────────────────────

func stand_fish(stand_index: int) -> Variant:
	if stand_index < 0 or stand_index >= stands.size():
		return null
	return stands[stand_index]


## 把背包里的一条鱼放上空展示台。同种鱼可以重复展示。
func place_on_stand(stand_index: int, uid: int) -> bool:
	if stand_index < 0 or stand_index >= stands.size() or stands[stand_index] != null:
		return false
	var index := find_in_backpack(uid)
	if index < 0:
		return false
	stands[stand_index] = backpack[index]
	backpack.remove_at(index)
	_touch()
	return true


## 下架：鱼带着等级回背包。背包满了就下不来。
func take_from_stand(stand_index: int) -> bool:
	var fish: Variant = stand_fish(stand_index)
	if fish == null or backpack_full():
		return false
	backpack.append(fish)
	stands[stand_index] = null
	_touch()
	return true


## 用金币给展示中的鱼升一级。等级跟着这条鱼。
func upgrade_stand_fish(stand_index: int) -> bool:
	var fish: Variant = stand_fish(stand_index)
	if fish == null:
		return false
	var species_id: String = fish["species"]
	var level: int = fish["level"]
	var cost := Rules.upgrade_cost(species_id, level)
	if cost < 0 or not spend(cost):
		return false
	fish["level"] = level + 1
	_touch()
	return true


func total_income_per_second() -> float:
	var total := 0.0
	for fish: Variant in stands:
		if fish != null:
			total += fish_income(fish)
	return total


## 按现实时间结算展示收益。now 是 Unix 秒。
## 在线时每帧调用；关掉游戏或切到后台后再回来，间隔会很长，这时按离线结算，
## 计入的时长最多 4 小时，并发出 offline_settled。
func accrue(now: float) -> void:
	if last_accrual <= 0.0:
		last_accrual = now
		return
	var elapsed := now - last_accrual
	last_accrual = now
	if elapsed <= 0.0:
		return  # 系统时钟被往回拨了：不结算，从现在重新计时
	var counted := minf(elapsed, Content.OFFLINE_CAP_SECONDS)
	var earned := 0.0
	for fish: Variant in stands:
		if fish != null:
			var income := fish_income(fish) * counted
			var so_far: float = fish["earned"]
			fish["earned"] = so_far + income
			earned += income
	if earned <= 0.0:
		return
	gold += earned
	_dirty = true
	if elapsed >= Balance.OFFLINE_NOTICE_GAP:
		offline_settled.emit(counted, earned)
		changed.emit()


# ── 装备与举重 ─────────────────────────────────────────────────────

func buy_rod(tier: int) -> bool:
	if tier < 0 or tier >= Content.tier_count() or owned_rods.has(tier):
		return false
	if not spend(Balance.ROD_PRICE[tier]):
		return false
	owned_rods.append(tier)
	rod = tier
	_touch()
	return true


func equip_rod(tier: int) -> bool:
	if not owned_rods.has(tier):
		return false
	rod = tier
	_touch()
	return true


func buy_dumbbell(tier: int) -> bool:
	if tier < 0 or tier >= Content.tier_count() or owned_dumbbells.has(tier):
		return false
	if not spend(Balance.DUMBBELL_PRICE[tier]):
		return false
	owned_dumbbells.append(tier)
	dumbbell = tier
	_touch()
	return true


func equip_dumbbell(tier: int) -> bool:
	if not owned_dumbbells.has(tier):
		return false
	dumbbell = tier
	_touch()
	return true


func strength_capped() -> bool:
	return strength >= Balance.STRENGTH_CAP


## 一次完整的举重动作做完时调用：按当前装备的哑铃加一次力量，返回实际增加值。
## 不消耗金币或体力。到上限后返回 0。
func complete_lift() -> int:
	if dumbbell < 0:
		return 0
	var before := strength
	strength = mini(strength + Balance.LIFT_GAIN[dumbbell], Balance.STRENGTH_CAP)
	if strength != before:
		_touch()
	return strength - before


# ── 存档 ───────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"gold": gold,
		"strength": strength,
		"owned_rods": owned_rods,
		"rod": rod,
		"owned_dumbbells": owned_dumbbells,
		"dumbbell": dumbbell,
		"backpack": backpack,
		"stands": stands,
		"codex": codex,
		"next_uid": next_uid,
		"last_accrual": last_accrual,
	}


## 从存档字典恢复。存档可能来自旧版本或被改坏，所以逐项校验，认不出的就丢弃。
func from_dict(data: Dictionary) -> void:
	reset()
	gold = maxf(_number(data.get("gold"), 0.0), 0.0)
	strength = clampi(int(_number(data.get("strength"), Balance.START_STRENGTH)), 0, Balance.STRENGTH_CAP)

	owned_rods = _tier_list(data.get("owned_rods"))
	if not owned_rods.has(0):
		owned_rods.push_front(0)  # 最低档鱼竿是开局自带的
	rod = int(_number(data.get("rod"), 0.0))
	if not owned_rods.has(rod):
		rod = 0

	owned_dumbbells = _tier_list(data.get("owned_dumbbells"))
	dumbbell = int(_number(data.get("dumbbell"), -1.0))
	if not owned_dumbbells.has(dumbbell):
		dumbbell = -1

	var highest_uid := 0
	var raw_backpack: Variant = data.get("backpack")
	if raw_backpack is Array:
		for item: Variant in raw_backpack:
			var fish: Variant = _fish_from(item)
			if fish != null:
				backpack.append(fish)
				highest_uid = maxi(highest_uid, fish["uid"])

	var raw_stands: Variant = data.get("stands")
	if raw_stands is Array:
		for i in mini(raw_stands.size(), Content.STAND_COUNT):
			var fish: Variant = _fish_from(raw_stands[i])
			if fish != null:
				stands[i] = fish
				highest_uid = maxi(highest_uid, fish["uid"])

	var raw_codex: Variant = data.get("codex")
	if raw_codex is Dictionary:
		for key: Variant in raw_codex:
			if key is String and Content.has_fish(key):
				codex[key] = maxi(int(_number(raw_codex[key], 1.0)), 1)

	next_uid = maxi(int(_number(data.get("next_uid"), 1.0)), highest_uid + 1)
	last_accrual = maxf(_number(data.get("last_accrual"), 0.0), 0.0)
	_dirty = false


func save_game() -> bool:
	_since_save = 0.0
	_dirty = false
	if not io_enabled:
		return false
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败：%s（错误码 %d）" % [save_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var text := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		# 存档读不出来：留一份备份再从头开始，免得下次自动存档把它直接盖掉。
		push_warning("存档无法解析，已另存为 %s.bad 并重新开始" % save_path)
		DirAccess.copy_absolute(save_path, save_path + ".bad")
		return false
	from_dict(parsed)
	changed.emit()
	return true


func _touch() -> void:
	_dirty = true
	changed.emit()


static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


static func _tier_list(value: Variant) -> Array[int]:
	var tiers: Array[int] = []
	if value is Array:
		for item: Variant in value:
			if item is float or item is int:
				var tier := int(item)
				if tier >= 0 and tier < Content.tier_count() and not tiers.has(tier):
					tiers.append(tier)
	return tiers


static func _fish_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var species: Variant = value.get("species")
	if not species is String or not Content.has_fish(species):
		return null
	return {
		"uid": int(_number(value.get("uid"), 0.0)),
		"species": species,
		"level": clampi(int(_number(value.get("level"), 1.0)), 1, Balance.DISPLAY_MAX_LEVEL),
		"earned": maxf(_number(value.get("earned"), 0.0), 0.0),
	}
