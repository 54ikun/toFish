extends Node
## 自动测试。在项目根目录运行：
##   godot --headless --path . res://tests/test_runner.tscn -- --no-save
## 退出码是失败的检查条数，0 表示全部通过。
## 触摸相关的检查（摇杆、两根手指同时按）在无头模式下会跳过，要全部检查就去掉 --headless。
##
## 分三部分：
##   1. 规则与数值：公式对不对，临时值有没有守住设计文档已定的原则；
##      哪里能走、站在哪里能做什么；选鱼滚轮怎么排；
##   2. 进度与存档：背包、图鉴、展示、离线结算、存档往返；
##   3. 整局流程：把真实的主场景跑起来，用键盘和触摸事件走动、投竿、收线、
##      买哑铃、举重、上架、开面板。

const GameStateScript := preload("res://scripts/core/game_state.gd")

## 估算主动钓鱼收益时用的一竿耗时（秒）：蓄力、飞行、转盘、收线、结果加起来。
const CYCLE_SECONDS := 8.0

var _checks := 0
var _failures := 0
var _walk_slips := 0
## 无头模式下引擎只记按键状态，不把触摸事件派发给界面，触摸相关的检查要带窗口才跑得了。
var _touch_works := DisplayServer.get_name() != "headless"


func _ready() -> void:
	print("== 规则与数值 ==")
	_test_cast_distance()
	_test_zones()
	_test_wheel()
	_test_growth_is_grindy()
	_test_reel_is_short()
	_test_economy()
	_test_display_never_beats_fishing()
	_test_walking_rules()
	_test_reel_strip()
	print("== 进度与存档 ==")
	_test_inventory_and_codex()
	_test_stands()
	_test_offline()
	_test_lifting()
	_test_save_round_trip()
	_test_font_covers_all_text()
	print("== 整局流程 ==")
	await _test_full_loop()

	print("")
	print("共 %d 条检查，%d 条失败" % [_checks, _failures])
	get_tree().quit(_failures)


func check(condition: bool, what: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  [失败] " + what)


func near(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) <= tolerance


func new_state() -> Node:
	var state: Node = GameStateScript.new()
	state.io_enabled = false
	state.reset()
	return state


# ── 规则与数值 ─────────────────────────────────────────────────────

func _test_cast_distance() -> void:
	check(Balance.STRENGTH_CAP > 0, "力量上限为正")
	check(Balance.CAST_DCAP > Balance.CAST_D0 and Balance.CAST_D0 > 0.0, "Dcap > D0 > 0")
	check(Balance.CAST_GAMMA > 0.0 and Balance.CAST_A > 0.0 and Balance.CAST_B > 0.0, "γ、a、b 为正")
	check(Balance.CAST_A + Balance.CAST_B < 1.0, "a + b < 1")
	check(near(Balance.CAST_DCAP, Rules.total_water_depth()), "满力量的最大抛距正好够到 6 区尽头")

	check(near(Rules.max_cast_distance(0), Balance.CAST_D0), "零力量的最大抛距是 D0")
	check(near(Rules.max_cast_distance(Balance.STRENGTH_CAP), Balance.CAST_DCAP), "满力量的最大抛距是 Dcap")
	check(near(Rules.max_cast_distance(Balance.STRENGTH_CAP * 3), Balance.CAST_DCAP), "力量超过上限也不会再远")

	var previous := 0.0
	var monotonic := true
	for strength in range(0, Balance.STRENGTH_CAP + 1, 500):
		var reach := Rules.max_cast_distance(strength)
		monotonic = monotonic and reach > previous
		previous = reach
	check(monotonic, "力量越高，最大抛距越远")

	# 实际抛距始终在 M×(1-a-b) 和 M 之间：出手再好也突破不了力量给的上限。
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var in_range := true
	for i in 2000:
		var strength := rng.randf_range(0.0, Balance.STRENGTH_CAP)
		var reach := Rules.max_cast_distance(strength)
		var distance := Rules.cast_distance(strength, rng.randf(), rng.randf(), rng.randf())
		in_range = in_range and distance <= reach + 0.0001 and distance >= reach * (1.0 - Balance.CAST_A - Balance.CAST_B) - 0.0001
	check(in_range, "实际抛距落在 M×(1-a-b) 与 M 之间")
	check(near(Rules.cast_distance(1000, 1.0, 0.0, 0.0), Rules.max_cast_distance(1000)), "完美出手且无波动时打满最大抛距")

	# 出手时机和落点波动只是小幅修正，压不过力量。
	check(Balance.CAST_A <= 0.15, "出手时机对距离的修正是小幅的")
	check(Balance.CAST_B <= 0.15, "落点自然波动是小幅的")
	var weak_perfect := Rules.cast_distance(Balance.STRENGTH_CAP * 0.1, 1.0, 0.0, 0.0)
	var strong_sloppy := Rules.cast_distance(Balance.STRENGTH_CAP * 0.5, 0.0, 1.0, 1.0)
	check(strong_sloppy > weak_perfect, "力量高出一截时，最差的一竿也比弱力量的完美一竿远")

	# 同力量、同出手，落点仍有波动；力量相近时落点范围可以重叠。
	check(Rules.cast_distance(3000, 0.8, 0.1, 0.1) != Rules.cast_distance(3000, 0.8, 0.9, 0.9), "同力量同出手的落点有波动")
	check(Rules.cast_distance(3000, 0.8, 0.0, 0.0) > Rules.cast_distance(3100, 0.8, 1.0, 1.0), "力量相近时落点范围重叠")


func _test_zones() -> void:
	check(Balance.ZONE_DEPTH.size() == Content.ZONE_COUNT, "6 个水域都有进深")
	check(Rules.zone_at(0.0) == 1, "码头边是 1 区")
	check(Rules.zone_at(Rules.zone_far_edge(1) - 0.01) == 1, "1 区远端之内仍是 1 区")
	check(Rules.zone_at(Rules.zone_far_edge(1)) == 2, "过了 1 区远端是 2 区")
	check(Rules.zone_at(Rules.total_water_depth() - 0.01) == Content.ZONE_COUNT, "最远处是 6 区")
	check(Rules.zone_at(9999.0) == Content.ZONE_COUNT, "再远也只算 6 区")
	check(Rules.farthest_zone(0) == 1, "开局只够得到 1 区")
	check(Rules.farthest_zone(Balance.STRENGTH_CAP) == Content.ZONE_COUNT, "满力量够得到 6 区")


func _test_wheel() -> void:
	check(Content.FISH.size() == 12, "第一版 12 种鱼")
	check(Content.RARITY_NAMES.size() == 4, "4 档稀有")
	check(Content.ROD_NAMES.size() == 4 and Content.DUMBBELL_NAMES.size() == 4, "4 档鱼竿、4 档哑铃")
	for fish in Content.FISH:
		var species_id: String = fish["id"]
		check(Balance.FISH_PRICE.has(species_id), "%s 有卖价" % species_id)
		check(FishModels.LOOKS.has(species_id), "%s 有模型" % species_id)

	var seen := {}
	var share_ok := true
	var previous_rare := -1.0
	var rarer_farther := true
	for zone in range(1, Content.ZONE_COUNT + 1):
		var entries := Rules.wheel_entries(zone, 0.5)
		check(not entries.is_empty(), "%d 区转盘上有鱼" % zone)
		var total := 0.0
		var rare := 0.0
		for entry in entries:
			var species_id: String = entry["species"]
			var share: float = entry["share"]
			seen[species_id] = true
			total += share
			share_ok = share_ok and share > 0.0
			if Content.fish_rarity(species_id) >= 2:
				rare += share
		check(near(total, 1.0), "%d 区各扇区加起来是一整盘" % zone)
		rarer_farther = rarer_farther and rare >= previous_rare
		previous_rare = rare
	check(share_ok, "转盘上每种鱼都有份额")
	check(seen.size() == Content.FISH.size(), "12 种鱼在 6 个区里都钓得到")
	check(rarer_farther, "越远的区，青铜和白银的占比越高")

	# 每种鱼在自己的倾向区里权重最高。
	var prefers_home := true
	for fish in Content.FISH:
		var species_id: String = fish["id"]
		for zone in range(1, Content.ZONE_COUNT + 1):
			var inside := zone >= Content.fish_zone_min(species_id) and zone <= Content.fish_zone_max(species_id)
			if not inside:
				prefers_home = prefers_home and Rules.zone_factor(species_id, zone) < 1.0
	check(prefers_home, "鱼在倾向区之外更少见")

	# 运气越高，稀有鱼份额越大；出手越好运气越高。
	var silver_low := _rarity_share(Rules.wheel_entries(6, 0.0), 3)
	var silver_high := _rarity_share(Rules.wheel_entries(6, 2.0), 3)
	check(silver_high > silver_low, "运气高时白银份额更大")
	check(Rules.cast_luck(1.0, 0) > Rules.cast_luck(0.2, 0), "出手越好运气越高")
	check(Rules.cast_luck(0.5, 3) > Rules.cast_luck(0.5, 0), "好鱼竿运气更高")

	var entries := Rules.wheel_entries(3, 0.5)
	check(Rules.pick_entry(entries, 0.0) == 0, "随机数为 0 选中第一项")
	check(Rules.pick_entry(entries, 0.999999) == entries.size() - 1, "随机数接近 1 选中最后一项")


func _rarity_share(entries: Array[Dictionary], rarity: int) -> float:
	var total := 0.0
	for entry in entries:
		var species_id: String = entry["species"]
		var share: float = entry["share"]
		if Content.fish_rarity(species_id) == rarity:
			total += share
	return total


func _test_growth_is_grindy() -> void:
	# 力量成长要偏肝：单次加得少，量大才明显变强，仍有上限。
	var best_gain := Balance.LIFT_GAIN[Balance.LIFT_GAIN.size() - 1]
	check(float(best_gain) / Balance.STRENGTH_CAP <= 0.001, "最好的哑铃举一次，也不到力量上限的千分之一")
	var increasing := true
	for tier in range(1, Balance.LIFT_GAIN.size()):
		increasing = increasing and Balance.LIFT_GAIN[tier] > Balance.LIFT_GAIN[tier - 1]
	check(increasing, "哑铃品质越高，每次加的力量越多")
	var one_lift := Rules.max_cast_distance(Balance.START_STRENGTH + Balance.LIFT_GAIN[0]) - Rules.max_cast_distance(Balance.START_STRENGTH)
	check(one_lift < 0.5, "举一次几乎看不出抛距变化（实际 +%.3f 米）" % one_lift)
	var lifts_to_cap := float(Balance.STRENGTH_CAP - Balance.START_STRENGTH) / best_gain
	check(lifts_to_cap >= 1000.0, "练满力量至少要举上千次（最好的哑铃也要 %d 次）" % int(lifts_to_cap))
	check(Balance.LIFT_GAIN.size() == Content.tier_count(), "每档哑铃都有力量值")


func _test_reel_is_short() -> void:
	# 收线要短、爽快：同档鱼竿对同档鱼，手速正常就能赢，几秒内结束。
	for tier in Content.tier_count():
		var taps := ceilf(1.0 / Rules.tap_gain(tier, tier))
		var needed_rate := taps * Balance.CHASE_SPEED / (1.0 + Balance.CHASE_GAP)
		check(needed_rate <= 4.0, "%s 钓同档鱼：每秒点 %.1f 下就能上岸" % [Content.rod_full_name(tier), needed_rate])
		check(taps / 5.0 <= 5.0, "%s 钓同档鱼：每秒点 5 下，%.1f 秒收完" % [Content.rod_full_name(tier), taps / 5.0])
	check(Rules.tap_gain(3, 0) > Rules.tap_gain(0, 0), "好鱼竿收线更快")
	check(Rules.tap_gain(0, 3) < Rules.tap_gain(0, 0), "越稀有的鱼越难拖")


func _test_economy() -> void:
	for fish in Content.FISH:
		var species_id: String = fish["id"]
		var base := Rules.sell_price(species_id, 1)
		var maxed := Rules.sell_price(species_id, Balance.DISPLAY_MAX_LEVEL)
		check(base == Rules.base_price(species_id), "%s 未升级时按原价卖" % species_id)
		check(maxed > base and maxed <= base * 1.25, "%s 升满后卖价只略高（+%d%%）" % [species_id, roundi((float(maxed) / base - 1.0) * 100.0)])
		check(Rules.income_per_second(species_id, 2) > Rules.income_per_second(species_id, 1), "%s 升级后每秒收益更高" % species_id)
		check(Rules.upgrade_cost(species_id, 1) > 0, "%s 升级要花金币" % species_id)
		check(Rules.upgrade_cost(species_id, Balance.DISPLAY_MAX_LEVEL) == -1, "%s 满级后不能再升" % species_id)
	check(Rules.base_price("xuelin_fang") > Rules.base_price("matou_tiao"), "稀有的鱼更值钱")


## 设计文档：展示收益不应高过自己去钓鱼，8 台全部升满也要守这条。
## 逐区检查：把到这个区为止钓得到的最值钱的鱼摆满 8 台并全部升满，
## 每秒收益仍低于就在这个区主动钓鱼（按最差的鱼竿、平平的出手估算）。
func _test_display_never_beats_fishing() -> void:
	var best_price := 0
	var best_species := ""
	for zone in range(1, Content.ZONE_COUNT + 1):
		var entries := Rules.wheel_entries(zone, Rules.cast_luck(0.5, 0))
		var gold_per_cast := 0.0
		for entry in entries:
			var species_id: String = entry["species"]
			var share: float = entry["share"]
			gold_per_cast += share * Rules.base_price(species_id)
			if Rules.base_price(species_id) > best_price:
				best_price = Rules.base_price(species_id)
				best_species = species_id
		var fishing_rate := gold_per_cast / CYCLE_SECONDS
		var display_rate := Content.STAND_COUNT * Rules.income_per_second(best_species, Balance.DISPLAY_MAX_LEVEL)
		check(display_rate < fishing_rate, "%d 区：8 台升满每秒 %.2f，低于钓鱼每秒 %.2f" % [zone, display_rate, fishing_rate])


# ── 进度与存档 ─────────────────────────────────────────────────────

func _test_inventory_and_codex() -> void:
	var state := new_state()
	check(state.owned_rods == [0] and state.rod == 0, "开局自带最低档鱼竿")
	check(state.dumbbell == -1, "开局没有哑铃")
	check(state.codex_count() == 0, "开局图鉴是空的")

	var fish: Dictionary = state.catch_fish("huayi_ji")
	check(state.backpack.size() == 1, "钓到的鱼进背包")
	check(state.is_registered("huayi_ji"), "成功捕获即登记图鉴")
	var price: int = state.sell_fish(fish["uid"])
	check(price == Rules.base_price("huayi_ji") and near(state.gold, price), "卖鱼拿到金币")
	check(state.backpack.is_empty(), "卖掉的鱼离开背包")
	check(state.is_registered("huayi_ji"), "出售不撤销图鉴")

	for i in Balance.BACKPACK_CAPACITY:
		state.catch_fish("matou_tiao")
	check(state.backpack_full(), "背包有容量上限")
	check(state.codex["matou_tiao"] == Balance.BACKPACK_CAPACITY, "图鉴记下捕获次数")
	var total: int = state.sell_all_backpack()
	check(total == Balance.BACKPACK_CAPACITY * Rules.base_price("matou_tiao"), "全部卖出按每条的卖价结算")
	check(state.backpack.is_empty(), "全部卖出后背包清空")
	state.free()


func _test_stands() -> void:
	var state := new_state()
	check(state.stands.size() == 8, "8 个展示台")
	var first: Dictionary = state.catch_fish("pushan_bian")
	var second: Dictionary = state.catch_fish("pushan_bian")
	check(state.place_on_stand(0, first["uid"]), "背包里的鱼可以上架")
	check(state.place_on_stand(1, second["uid"]), "同种鱼可以重复展示")
	check(state.backpack.is_empty(), "上架的鱼离开背包")
	var third: Dictionary = state.catch_fish("matou_tiao")
	check(not state.place_on_stand(0, third["uid"]), "一个台子只放一条鱼")

	check(not state.upgrade_stand_fish(0), "金币不够不能升级")
	var cost := Rules.upgrade_cost("pushan_bian", 1)
	state.add_gold(cost)
	check(state.upgrade_stand_fish(0), "金币够了可以升级")
	check(near(state.gold, 0.0), "升级扣掉对应金币")
	check(state.stands[0]["level"] == 2 and state.stands[1]["level"] == 1, "等级跟着这条鱼，不跟鱼种")
	check(near(state.total_income_per_second(), Rules.income_per_second("pushan_bian", 2) + Rules.income_per_second("pushan_bian", 1)), "总收益是各台之和")

	check(state.take_from_stand(0), "可以下架")
	var back: Dictionary = state.backpack[state.backpack.size() - 1]
	check(back["uid"] == first["uid"] and back["level"] == 2, "下架回背包后等级保留")
	check(state.sell_fish(back["uid"]) == Rules.sell_price("pushan_bian", 2), "升过级的鱼按略高的价卖")
	check(state.is_registered("pushan_bian"), "上架、下架、出售都不影响图鉴")

	state.sell_all_backpack()
	for i in Balance.BACKPACK_CAPACITY:
		state.catch_fish("matou_tiao")
	check(not state.take_from_stand(1), "背包满了不能下架")
	check(state.stands[1] != null, "下架失败时鱼还在台上")
	state.free()


func _test_offline() -> void:
	var state := new_state()
	var fish: Dictionary = state.catch_fish("xuelin_fang")
	state.place_on_stand(0, fish["uid"])
	var rate := Rules.income_per_second("xuelin_fang", 1)
	var reports: Array = []
	state.offline_settled.connect(func(seconds: float, gold: float) -> void: reports.append([seconds, gold]))

	state.accrue(1000.0)
	check(near(state.gold, 0.0), "第一次结算只记下时刻")
	state.accrue(1001.0)
	check(near(state.gold, rate, 0.001), "在线时按秒产生收益")
	check(near(state.stands[0]["earned"], rate, 0.001), "台前记下这条鱼已产生的收益")
	check(reports.is_empty(), "在线结算不弹离线提示")

	var before: float = state.gold
	state.accrue(1001.0 + 3600.0)
	check(near(state.gold - before, rate * 3600.0, 0.01), "离线 1 小时按 1 小时结算")
	check(reports.size() == 1, "离线回来有收益提示")

	before = state.gold
	state.accrue(1001.0 + 3600.0 + 50.0 * 3600.0)
	check(near(state.gold - before, rate * 4.0 * 3600.0, 0.01), "离线 50 小时也只按 4 小时结算")
	check(reports.size() == 2 and near(reports[1][0], 4.0 * 3600.0), "提示里的时长是封顶后的 4 小时")

	before = state.gold
	state.accrue(500.0)
	check(near(state.gold, before), "系统时钟回拨不产生收益")
	state.accrue(501.0)
	check(near(state.gold - before, rate, 0.001), "回拨之后从新时刻继续正常结算")
	state.free()


func _test_lifting() -> void:
	var state := new_state()
	check(state.complete_lift() == 0, "没有哑铃举不了")
	check(not state.buy_dumbbell(0), "金币不够买不了哑铃")
	state.add_gold(Balance.DUMBBELL_PRICE[0] + Balance.DUMBBELL_PRICE[2])
	check(state.buy_dumbbell(0) and state.dumbbell == 0, "买了哑铃就装备上")
	var gold_before: float = state.gold
	check(state.complete_lift() == Balance.LIFT_GAIN[0], "举一次按这档哑铃加力量")
	check(near(state.gold, gold_before), "举重不花金币")
	check(state.buy_dumbbell(2) and state.dumbbell == 2, "可以买更好的哑铃")
	check(state.complete_lift() == Balance.LIFT_GAIN[2], "更好的哑铃每次加得更多")
	check(state.equip_dumbbell(0) and state.dumbbell == 0, "买过的哑铃可以换回来")
	check(not state.equip_dumbbell(3), "没买的哑铃换不上")

	state.strength = Balance.STRENGTH_CAP - 1
	state.equip_dumbbell(2)
	check(state.complete_lift() == 1 and state.strength == Balance.STRENGTH_CAP, "力量加到上限为止")
	check(state.complete_lift() == 0 and state.strength_capped(), "到上限后不再增加")

	state.add_gold(Balance.ROD_PRICE[1])
	check(state.buy_rod(1) and state.rod == 1, "可以买更好的鱼竿")
	check(not state.buy_rod(1), "同一根鱼竿不能买两次")
	check(state.equip_rod(0) and state.rod == 0, "买过的鱼竿可以换回来")
	state.free()


func _test_save_round_trip() -> void:
	var state := new_state()
	state.add_gold(1234.5)
	state.strength = 321
	state.add_gold(Balance.ROD_PRICE[1] + Balance.DUMBBELL_PRICE[0])
	state.buy_rod(1)
	state.buy_dumbbell(0)
	var shown: Dictionary = state.catch_fish("yueya_ji")
	state.catch_fish("matou_tiao")
	state.place_on_stand(5, shown["uid"])
	state.stands[5]["level"] = 4
	state.stands[5]["earned"] = 77.5
	state.last_accrual = 123456.0

	var path := "user://test_save.json"
	state.io_enabled = true
	state.save_path = path
	check(state.save_game(), "存档写得进去")

	var loaded := new_state()
	loaded.io_enabled = true
	loaded.save_path = path
	check(loaded.load_game(), "存档读得出来")
	check(near(loaded.gold, state.gold) and loaded.strength == 321, "金币和力量原样恢复")
	check(loaded.owned_rods == [0, 1] and loaded.rod == 1, "鱼竿原样恢复")
	check(loaded.owned_dumbbells == [0] and loaded.dumbbell == 0, "哑铃原样恢复")
	check(loaded.backpack.size() == 1 and loaded.backpack[0]["species"] == "matou_tiao", "背包原样恢复")
	var restored: Variant = loaded.stands[5]
	check(restored != null and restored["species"] == "yueya_ji" and restored["level"] == 4 and near(restored["earned"], 77.5), "展示台上的鱼连同等级和收益恢复")
	check(loaded.codex.size() == 2 and loaded.codex["yueya_ji"] == 1, "图鉴原样恢复")
	check(loaded.next_uid == state.next_uid and near(loaded.last_accrual, 123456.0), "编号和结算时刻恢复")
	var fresh: Dictionary = loaded.catch_fish("matou_tiao")
	check(fresh["uid"] != shown["uid"] and fresh["uid"] != loaded.backpack[0]["uid"], "读档后新鱼的编号不重复")

	# 存档被改坏或来自别的版本：认不出的丢掉，其余照常。
	var broken := new_state()
	broken.from_dict({
		"gold": "很多", "strength": 99999999, "owned_rods": [3, 9, "x"], "rod": 2,
		"dumbbell": 1, "backpack": [{"species": "不存在的鱼"}, {"species": "huayi_ji", "level": 500}, 42],
		"stands": "坏的", "codex": {"huayi_ji": 2, "假鱼": 9},
	})
	check(near(broken.gold, 0.0), "金币不是数字就归零")
	check(broken.strength == Balance.STRENGTH_CAP, "力量不会超过上限")
	check(broken.owned_rods == [0, 3] and broken.rod == 0, "不存在的鱼竿档位被丢掉，开局竿总在")
	check(broken.dumbbell == -1, "没拥有的哑铃不会被装备")
	check(broken.backpack.size() == 1 and broken.backpack[0]["level"] == Balance.DISPLAY_MAX_LEVEL, "认不出的鱼被丢掉，等级被夹到上限")
	check(broken.stands.size() == 8 and broken.codex.size() == 1, "展示台和图鉴仍然可用")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	state.free()
	loaded.free()
	broken.free()


## 网页版没有系统字体可回退：界面上出现的每个字都必须在裁剪后的字体里。
## 这条失败说明改了文字却没重跑 tools/build_font.py。
func _test_font_covers_all_text() -> void:
	var font: FontFile = load(UiKit.FONT_PATH)
	check(font != null, "字体能加载")
	if font == null:
		return
	var missing := {}
	var files := ["res://project.godot"]
	_collect_scripts("res://scripts", files)
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for i in text.length():
			var code := text.unicode_at(i)
			if code > 0x20 and not font.has_char(code):
				missing[text[i]] = true
	check(missing.is_empty(), "字体缺字：%s（重跑 tools/build_font.py）" % "".join(missing.keys()))


func _collect_scripts(directory: String, out: Array) -> void:
	for sub in DirAccess.get_directories_at(directory):
		_collect_scripts(directory.path_join(sub), out)
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			out.append(directory.path_join(file))


# ── 走动与滚轮 ─────────────────────────────────────────────────────

func _test_walking_rules() -> void:
	var pier := Vector3(0.0, 0.0, -5.0)
	var shore := Vector3(10.0, 0.0, 1.0)
	var gym_mat := World.GYM_CENTER + Vector3(0.0, 0.0, 1.0)
	var display_mat := World.DISPLAY_CENTER + Vector3(0.0, 0.0, 3.0)

	check(World.spot_at(World.SPAWN) == World.Spot.FISHING, "出生点就在钓鱼点")
	check(World.spot_at(Vector3(0.0, 0.0, 0.0)) == World.Spot.NONE, "码头靠岸的一段不是钓鱼点")
	check(World.spot_at(Vector3(0.0, 0.0, 8.0)) == World.Spot.NONE, "空地上没有特别的事可做")
	check(World.spot_at(gym_mat) == World.Spot.SHOP, "健身房地垫上可以买哑铃")
	check(World.spot_at(display_mat) == World.Spot.DISPLAY, "展示台前的地垫上可以管理展示")
	var each_reachable := true
	for i in Content.STAND_COUNT:
		var front := Vector3(World.stand_x(i), 0.0, World.DISPLAY_CENTER.z + 2.0)
		each_reachable = each_reachable and World.walkable(front, front) == front and World.spot_at(front) == World.Spot.DISPLAY and World.stand_near(front) == i
	check(each_reachable, "8 个展示台每个都走得到跟前")
	check(World.stand_x(Content.STAND_COUNT - 1) + 1.0 < World.WALK_MAX_X, "最后一个展示台在场地里面")
	check(World.walkable(gym_mat, gym_mat) == gym_mat and World.walkable(display_mat, display_mat) == display_mat, "两块地垫都走得上去")

	check(absf(World.walkable(pier, pier + Vector3(3.0, 0.0, 0.0)).x) <= World.PIER_WALK_HALF + 0.0001, "从码头侧面走不下水")
	check(World.walkable(pier, pier + Vector3(0.0, 0.0, -9.0)).z >= World.PIER_WALK_END_Z - 0.0001, "走到码头尽头就停")
	check(World.walkable(shore, shore + Vector3(0.0, 0.0, -4.0)).z >= World.SHORE_Z - 0.0001, "从岸边走不下水")
	# 顶着岸线斜着走：顺着岸滑过去，不能下水，也不能被一下拽到码头上。
	var along := Vector3(-2.0, 0.0, 2.0)
	var smooth := true
	for i in 80:
		var next := World.walkable(along, along + Vector3(-0.05, 0.0, -0.1))
		smooth = smooth and absf(next.x - along.x) < 0.06 and next.z > World.SHORE_Z - 0.001
		along = next
	check(smooth and along.x < -5.0 and near(along.z, World.SHORE_Z, 0.001), "顶着岸线走是顺着岸滑")
	# 顶着码头边斜着走：顺着码头滑，一直能走到岸上。
	along = Vector3(0.0, 0.0, -4.0)
	smooth = true
	for i in 80:
		var next := World.walkable(along, along + Vector3(0.05, 0.0, 0.1))
		smooth = smooth and absf(next.z - along.z) < 0.11 and (next.z >= World.SHORE_Z - 0.001 or absf(next.x) <= World.PIER_WALK_HALF + 0.001)
		along = next
	check(smooth and along.z > 3.0 and along.x > World.PIER_WALK_HALF, "顶着码头边走是顺着码头滑，能走上岸")
	var near_corner := Vector3(World.WALK_MIN_X, 0.0, World.SHORE_Z)
	check(World.walkable(near_corner, near_corner).distance_to(near_corner) < 0.001, "岸线最左端站得住")
	var far_corner := World.walkable(shore, Vector3(-99.0, 0.0, 99.0))
	check(near(far_corner.x, World.WALK_MIN_X) and near(far_corner.z, World.WALK_MAX_Z), "走不出场地")
	check(World.walkable(gym_mat, gym_mat + Vector3(0.0, 0.0, -5.0)).z > World.GYM_CENTER.z - 1.85, "穿不过健身房的哑铃架")
	check(World.walkable(display_mat, display_mat + Vector3(0.0, 0.0, -5.0)).z > World.DISPLAY_CENTER.z + World.DISPLAY_BLOCK_Z, "穿不过展示台")
	var through_trees := true
	for tree in World.TREE_SPOTS:
		var at := World.walkable(tree + Vector3(1.0, 0.0, 0.5), tree)
		through_trees = through_trees and Vector2(at.x - tree.x, at.z - tree.z).length() >= 0.69
	check(through_trees, "穿不过树")

	check(near(World.ground_height(pier), World.PIER_TOP_Y) and near(World.ground_height(shore), World.GROUND_Y), "码头板比地面高一截")
	var ramp := World.ground_height(Vector3(0.0, 0.0, (World.PIER_LAND_Z + World.PIER_RAMP_Z) * 0.5))
	check(ramp < World.PIER_TOP_Y and ramp > World.GROUND_Y, "码头靠岸一头是斜坡")
	check(Balance.WALK_SPEED > 0.0, "走路速度为正")


func _test_reel_strip() -> void:
	# 选鱼滚轮：每种能出的鱼都在滚轮上，越容易出的鱼占的格子越多。
	for zone in range(1, Content.ZONE_COUNT + 1):
		var entries := Rules.wheel_entries(zone, 0.5)
		var strip := FishReel.build_strip(entries, FishReel.STRIP_CELLS, zone)
		var counts: Array[int] = []
		counts.resize(entries.size())
		counts.fill(0)
		for index in strip:
			counts[index] += 1
		var all_present := true
		var common := 0
		for i in entries.size():
			all_present = all_present and counts[i] >= 1
			var share: float = entries[i]["share"]
			var top_share: float = entries[common]["share"]
			if share > top_share:
				common = i
		check(all_present, "%d 区滚轮上每种鱼至少有一格" % zone)
		check(counts[common] == counts.max(), "%d 区最容易出的鱼在滚轮上格子最多" % zone)
		check(strip.size() >= FishReel.STRIP_CELLS / 2 and strip.size() <= FishReel.STRIP_CELLS + entries.size(), "%d 区滚轮长度合理（%d 格）" % [zone, strip.size()])
	check(FishReel.WINDOW_CELLS < 3.0, "滚轮窗口一次只露出几格，不把所有鱼都摆出来")


# ── 整局流程 ───────────────────────────────────────────────────────

func _test_full_loop() -> void:
	GameState.reset()
	Engine.time_scale = 8.0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var fishing: FishingController = main.fishing
	var world: World = main.world
	var panels: Panels = main.panels
	var gym: GymController = main.gym
	var hud: Hud = main.hud

	check(world.spot == World.Spot.FISHING, "开局就站在钓鱼点")

	# 一竿成功：蓄力、松手、等滚轮、连点上岸。
	main.on_action_down()
	check(fishing.state == FishingController.State.CHARGING, "按下开始蓄力")
	await _wait(0.4)
	main.on_action_up()
	check(fishing.state == FishingController.State.CASTING, "松手投竿")
	check(await _until(func() -> bool: return fishing.state == FishingController.State.WHEEL), "浮标落水后出现选鱼滚轮")
	check(GameState.backpack.is_empty(), "滚轮选中不等于已经捕获")
	check(await _until(func() -> bool: return fishing.state == FishingController.State.REELING), "滚轮停下后开始收线")
	var reel: FishReel = hud._wheel
	var landed: String = reel.entries[reel.center_index()]["species"]
	var taps := 0
	while fishing.state == FishingController.State.REELING and taps < 200:
		fishing.tap()
		taps += 1
	check(fishing.state == FishingController.State.RESULT, "连点 %d 下把鱼拖上岸" % taps)
	check(GameState.backpack.size() == 1, "上岸的鱼进了背包")
	check(GameState.codex_count() == 1, "上岸的鱼登记了图鉴")
	check(GameState.backpack[0]["species"] == landed, "滚轮停在哪条鱼，钓上来的就是哪条")
	check(Content.fish_zone_min(GameState.backpack[0]["species"]) <= 2, "零力量只钓得到近岸的鱼")
	check(await _until(func() -> bool: return fishing.is_idle()), "结果展示完回到待机")

	# 一竿失败：不点，等巨鱼追上。这一竿期间推摇杆也走不动。
	var stood := world.avatar.position
	main.on_action_down()
	await _wait(0.4)
	main.on_action_up()
	_key(KEY_S, true)
	check(await _until(func() -> bool: return fishing.state == FishingController.State.REELING), "第二竿进入收线")
	check(await _until(func() -> bool: return fishing.state == FishingController.State.RESULT), "不点就被巨鱼追上")
	check(GameState.backpack.size() == 1 and GameState.codex_count() == 1, "被吃掉的鱼不入背包、不登记图鉴")
	check(world.avatar.position.distance_to(stood) < 0.01, "一竿进行中不能走动")
	_key(KEY_S, false)
	await _until(func() -> bool: return fishing.is_idle())

	# 背包满了不能投竿。
	while not GameState.backpack_full():
		GameState.catch_fish("matou_tiao")
	main.on_action_down()
	check(fishing.is_idle(), "背包满了不能投竿")
	main.on_action_up()

	# 开关各个面板。
	for kind: String in ["backpack", "codex", "rods", "dumbbells"]:
		panels.open(kind)
		await _frames(2)
		check(panels.is_open(), "面板 %s 能打开" % kind)
		panels.close()
	GameState.sell_all_backpack()
	GameState.catch_fish("tiaolang_bai")

	# 手机上的两根手指：左手按着摇杆，右手照样能按右下角的键。
	if _touch_works:
		await _test_touch(main)
	else:
		print("  [跳过] 无头模式下引擎不派发触摸事件，触摸相关的检查没有跑；去掉 --headless 带窗口运行才会检查")

	# 走下码头：离开钓鱼点就不能投竿，镜头改成跟着人走。
	check(await _walk_to(main, Vector3(0.0, 0.0, 1.5)), "沿着码头走回岸边")
	check(world.spot == World.Spot.NONE, "走出钓鱼点")
	main.on_action_down()
	check(fishing.is_idle() and not panels.is_open(), "不在钓鱼点不能投竿")
	main.on_action_up()
	main.on_lift()
	check(not gym.is_lifting() and not panels.is_open(), "没有哑铃举不了，离健身房远也不弹货架")

	# 走到健身房：靠近了才能买哑铃。
	check(await _walk_to(main, World.GYM_CENTER + Vector3(0.0, 0.0, 0.8)), "走到健身房")
	check(world.spot == World.Spot.SHOP, "站上健身房的地垫")
	main.on_action_down()
	check(panels.is_open(), "在健身房可以打开哑铃货架")
	main.on_action_up()
	panels.close()
	GameState.add_gold(Balance.DUMBBELL_PRICE[0] + Balance.DUMBBELL_PRICE[1])
	GameState.buy_dumbbell(0)

	# 点一次举一次，动作做完才加力量；举的时候走不动。
	var strength_before := GameState.strength
	var lift_spot := world.avatar.position
	main.on_lift()
	check(gym.is_lifting(), "点一下开始举重")
	check(not gym.lift(), "动作没做完时再点无效")
	_key(KEY_D, true)
	await _wait(Balance.LIFT_DURATION * 0.5)
	check(GameState.strength == strength_before, "动作做到一半还不加力量")
	check(world.avatar.position.distance_to(lift_spot) < 0.01, "举重时不能走动")
	_key(KEY_D, false)
	check(await _until(func() -> bool: return not gym.is_lifting()), "动作做完")
	check(GameState.strength == strength_before + Balance.LIFT_GAIN[0], "完整动作结束才加一次力量")
	await _wait(Balance.LIFT_DURATION * 2.0)
	check(GameState.strength == strength_before + Balance.LIFT_GAIN[0], "不点就不会自己继续举")

	# 举到一半换哑铃：这一次作废。
	main.on_lift()
	GameState.buy_dumbbell(1)
	check(not gym.is_lifting(), "举到一半换哑铃，动作取消")
	check(GameState.strength == strength_before + Balance.LIFT_GAIN[0], "取消的动作不加力量")
	GameState.equip_dumbbell(0)

	# 哑铃随时能用：走到空地上照样举。
	check(await _walk_to(main, Vector3(0.0, 0.0, 9.0)), "走到空地")
	check(world.spot == World.Spot.NONE, "空地上没有特别的事可做")
	main.on_action_down()
	check(not panels.is_open(), "离开健身房就不能买哑铃")
	main.on_action_up()
	main.on_lift()
	check(gym.is_lifting(), "不在健身房也能举重")
	check(await _until(func() -> bool: return not gym.is_lifting()), "空地上的这一次举完")
	check(GameState.strength == strength_before + Balance.LIFT_GAIN[0] * 2, "在空地举重照样加力量")
	check(world.is_free(), "举完又可以走动")

	# 展示台：走到台前，点台子上架、升级。
	check(await _walk_to(main, Vector3(World.stand_x(4), 0.0, World.DISPLAY_CENTER.z + 3.0)), "走到 5 号展示台前")
	check(world.spot == World.Spot.DISPLAY, "站上展示台前的地垫")
	check(world.near_stand == 4, "正对着的是 5 号台")
	main.on_action_down()
	main.on_action_up()
	check(panels.is_open() and panels._stand == 4, "右下角的键打开正对着的那个台子")
	panels.close()
	world.snap_camera()
	await _frames(2)
	var stand_on_screen := world.camera.unproject_position(world.stands[4].global_position + Vector3(0.0, 1.0, 0.5))
	check(world.pick_stand(stand_on_screen) == 4, "点到 5 号台能认出是 5 号台")
	check(world.pick_stand(Vector2(-50.0, -50.0)) == -1, "点在空处不算点中展示台")
	if _touch_works:
		_touch(0, stand_on_screen, true)
		_touch(0, stand_on_screen, false)
		await _frames(2)
		check(panels.is_open(), "在台前点一下台子，打开这个台子的面板")
		panels.close()
	check(GameState.place_on_stand(2, GameState.backpack[0]["uid"]), "把鱼摆上 3 号台")
	GameState.add_gold(Rules.upgrade_cost("tiaolang_bai", 1))
	panels.open_stand(2)
	await _frames(2)
	check(GameState.upgrade_stand_fish(2), "在展示台上升级")
	await _frames(2)
	panels.close()
	panels.open_offline(3600.0, 12.5)
	await _frames(2)
	panels.close()
	await _frames(2)

	# 走回码头尽头，又能钓了；在钓鱼点也能举重。
	check(await _walk_to(main, Vector3(0.0, 0.0, 1.5)), "走回码头口")
	check(await _walk_to(main, Vector3(0.0, 0.0, -5.0)), "走到码头尽头")
	check(world.spot == World.Spot.FISHING, "回到钓鱼点")
	check(_walk_slips == 0, "一路上没有掉进水里（%d 帧出界）" % _walk_slips)
	main.on_lift()
	check(gym.is_lifting(), "站在钓鱼点也能举重")
	main.on_action_down()
	check(fishing.is_idle(), "举重做到一半不能投竿")
	main.on_action_up()
	await _until(func() -> bool: return not gym.is_lifting())
	main.on_action_down()
	check(fishing.state == FishingController.State.CHARGING, "举完可以接着钓")
	main.on_lift()
	check(not gym.is_lifting(), "一竿进行中不能举重")
	fishing.cancel_charge()

	# 滚轮自己滚到指定的鱼停下。
	var entries := Rules.wheel_entries(2, 0.5)
	var spare := FishReel.new()
	add_child(spare)
	var lands_right := true
	for index in entries.size():
		spare.setup(entries, 100 + index)
		spare.spin_to(index, 0.3, 0.37 * index - floorf(0.37 * index))
		await spare.stopped
		lands_right = lands_right and spare.center_index() == index
	check(lands_right, "滚轮每次都停在定好的那种鱼上")
	spare.queue_free()

	Engine.time_scale = 1.0
	main.queue_free()
	await _frames(2)


## 用真的触摸事件走一遍：摇杆、右下角的键、两根手指同时按。
func _test_touch(main: Node) -> void:
	var fishing: FishingController = main.fishing
	var hud: Hud = main.hud
	var presses: Array = []
	var on_press := func() -> void: presses.append(1)
	hud.action_down.connect(on_press)
	var stick := hud.joystick.get_global_rect().get_center()
	var button: Vector2 = hud._action.get_global_rect().get_center()

	# 一根手指点右下角的键：只算一次按下。
	_touch(0, button, true)
	await _frames(2)
	check(presses.size() == 1, "一根手指按一下只算一次（实际 %d 次）" % presses.size())
	check(fishing.state == FishingController.State.CHARGING, "手指按住右下角开始蓄力")
	_touch(0, button, false)
	await _frames(2)
	check(fishing.state == FishingController.State.CASTING, "手指松开就投竿")
	await _until(func() -> bool: return fishing.state == FishingController.State.REELING)
	# 收线时点屏幕任何地方都算。
	var progress: Array = []
	var on_tap := func() -> void: progress.append(1)
	fishing.reel_tapped.connect(on_tap)
	_touch(0, Vector2(640.0, 360.0), true)
	_touch(0, Vector2(640.0, 360.0), false)
	await _frames(2)
	check(progress.size() == 1, "收线时点一下屏幕算一下（实际 %d 下）" % progress.size())
	fishing.reel_tapped.disconnect(on_tap)
	while fishing.state == FishingController.State.REELING:
		fishing.tap()
	await _until(func() -> bool: return fishing.is_idle())

	# 第一根手指推摇杆，第二根手指按右下角的键。
	presses.clear()
	_touch(0, stick, true)
	_drag(0, stick + Vector2(80.0, 0.0))
	await _frames(2)
	check(hud.joystick.vector.x > 0.5 and absf(hud.joystick.vector.y) < 0.1, "手指往右推，摇杆指向右")
	_drag(0, stick)
	await _frames(2)
	check(hud.joystick.vector == Vector2.ZERO, "手指回到中间，摇杆归零")
	_touch(1, button, true)
	await _frames(2)
	check(presses.size() == 1 and fishing.state == FishingController.State.CHARGING, "左手按着摇杆时，右手照样能蓄力")
	_touch(1, button, false)
	await _frames(2)
	check(fishing.state == FishingController.State.CASTING, "右手松开就投竿")
	_touch(0, stick, false)
	await _frames(2)
	hud.action_down.disconnect(on_press)
	await _until(func() -> bool: return fishing.state == FishingController.State.REELING)
	while fishing.state == FishingController.State.REELING:
		fishing.tap()
	await _until(func() -> bool: return fishing.is_idle())
	GameState.sell_all_backpack()
	GameState.catch_fish("tiaolang_bai")


## 按着方向键走到 target 附近（只看水平位置）。走的过程中顺带检查没有掉进水里。
func _walk_to(main: Node, target: Vector3, timeout: float = 40.0) -> bool:
	var world: World = main.world
	var held := {}
	var waited := 0.0
	var arrived := false
	while waited <= timeout:
		var at := world.avatar.position
		var gap := Vector2(target.x - at.x, target.z - at.z)
		arrived = absf(gap.x) <= 0.5 and absf(gap.y) <= 0.5
		var want := {
			KEY_A: gap.x < -0.5 and not arrived, KEY_D: gap.x > 0.5 and not arrived,
			KEY_W: gap.y < -0.5 and not arrived, KEY_S: gap.y > 0.5 and not arrived,
		}
		for code: Key in want:
			var down: bool = want[code]
			if down != held.get(code, false):
				_key(code, down)
				held[code] = down
		if at.z < World.SHORE_Z - 0.01 and absf(at.x) > World.PIER_WALK_HALF + 0.01:
			_walk_slips += 1
		if arrived:
			break
		await get_tree().process_frame
		waited += get_process_delta_time()
	for code: Key in held:
		if held[code]:
			_key(code, false)
	await _frames(2)
	return arrived


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _touch(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## 等到条件成立；超时返回 false。
func _until(condition: Callable, timeout: float = 30.0) -> bool:
	var waited := 0.0
	while not condition.call():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > timeout:
			return false
	return true
