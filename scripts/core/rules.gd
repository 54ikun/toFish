class_name Rules
extends RefCounted
## 规则计算：抛距、分区、运气、转盘权重、收线和经济公式。
## 全是无状态的纯函数，数值一律取自 Balance（临时值），方便单独测试和整体换参。


# ── 抛距与分区 ─────────────────────────────────────────────────────

## 当前力量的理论最大抛距 M(P)。力量主导远近，并限定上限。
static func max_cast_distance(strength: float) -> float:
	var p := clampf(strength / float(Balance.STRENGTH_CAP), 0.0, 1.0)
	return Balance.CAST_D0 + (Balance.CAST_DCAP - Balance.CAST_D0) * pow(p, Balance.CAST_GAMMA)


## 本竿实际抛距 D。quality 是出手质量 Q（0–1），u1、u2 是每竿独立的 0–1 随机数。
## 结果始终落在 M × (1 - a - b) 与 M 之间：出手和波动只做小幅修正，突破不了力量上限。
static func cast_distance(strength: float, quality: float, u1: float, u2: float) -> float:
	var q := clampf(quality, 0.0, 1.0)
	var r := (clampf(u1, 0.0, 1.0) + clampf(u2, 0.0, 1.0)) * 0.5
	return max_cast_distance(strength) * (1.0 - Balance.CAST_A * (1.0 - q) - Balance.CAST_B * r)


static func total_water_depth() -> float:
	var total := 0.0
	for depth in Balance.ZONE_DEPTH:
		total += depth
	return total


## 第 zone 区（从 1 起）靠码头一侧的边界离码头多远。
static func zone_near_edge(zone: int) -> float:
	var edge := 0.0
	for i in zone - 1:
		edge += Balance.ZONE_DEPTH[i]
	return edge


static func zone_far_edge(zone: int) -> float:
	return zone_near_edge(zone) + Balance.ZONE_DEPTH[zone - 1]


## 落点所在的区（1–6）。落点在哪个长方形里就算哪个区，没有额外的力量门槛。
static func zone_at(distance: float) -> int:
	for zone in range(1, Content.ZONE_COUNT + 1):
		if distance < zone_far_edge(zone):
			return zone
	return Content.ZONE_COUNT


## 当前力量最远能够到的区。
static func farthest_zone(strength: float) -> int:
	return zone_at(max_cast_distance(strength))


# ── 运气与转盘 ─────────────────────────────────────────────────────

## 本竿的运气。出手时机主要影响的就是它。extra 留给以后的鱼饵等加成。
static func cast_luck(quality: float, rod_tier: int, extra: float = 0.0) -> float:
	return clampf(quality, 0.0, 1.0) * Balance.LUCK_FROM_QUALITY + Balance.ROD_LUCK[rod_tier] + extra


## 某种鱼在某个区的出现系数：倾向区内为 1，紧邻一格为小系数，再远为 0。
static func zone_factor(species_id: String, zone: int) -> float:
	var low := Content.fish_zone_min(species_id)
	var high := Content.fish_zone_max(species_id)
	if zone >= low and zone <= high:
		return 1.0
	var gap := low - zone if zone < low else zone - high
	return Balance.ADJACENT_ZONE_FACTOR if gap == 1 else 0.0


## 某区在给定运气下的转盘：每项 {species, weight, share}，share 是占整盘的比例。
## 转盘是竖着滚的滚轮（FishReel），每种鱼在滚轮上占几格按 share 分。
static func wheel_entries(zone: int, luck: float) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var total := 0.0
	for fish in Content.FISH:
		var species_id: String = fish["id"]
		var factor := zone_factor(species_id, zone)
		if factor <= 0.0:
			continue
		var rarity: int = fish["rarity"]
		var weight := Balance.RARITY_WEIGHT[rarity] * factor
		weight *= 1.0 + maxf(luck, 0.0) * Balance.LUCK_RARITY_STEP * rarity
		entries.append({"species": species_id, "weight": weight, "share": 0.0})
		total += weight
	for entry in entries:
		var weight: float = entry["weight"]
		entry["share"] = weight / total
	return entries


## 用一个 0–1 随机数在转盘上选中一项，返回下标。
static func pick_entry(entries: Array[Dictionary], roll: float) -> int:
	var cursor := 0.0
	for i in entries.size():
		var share: float = entries[i]["share"]
		cursor += share
		if roll < cursor:
			return i
	return entries.size() - 1


# ── 收线 ───────────────────────────────────────────────────────────

## 每点一下，目标鱼向岸边前进多少进度（0–1 制）。
static func tap_gain(rod_tier: int, rarity: int) -> float:
	return Balance.ROD_REEL_SPEED[rod_tier] / Balance.REEL_TAPS[rarity]


# ── 经济 ───────────────────────────────────────────────────────────

static func base_price(species_id: String) -> int:
	return Balance.FISH_PRICE[species_id]


## 卖价。升级过的鱼只比未升级的同种鱼略高。
static func sell_price(species_id: String, level: int) -> int:
	var premium := 1.0 + Balance.SELL_PREMIUM_PER_LEVEL * (level - 1)
	return roundi(base_price(species_id) * premium)


## 展示时的每秒收益。
static func income_per_second(species_id: String, level: int) -> float:
	var growth := 1.0 + Balance.DISPLAY_LEVEL_STEP * (level - 1)
	return base_price(species_id) * Balance.DISPLAY_RATE * growth


## 从 level 升到 level + 1 的费用；已满级返回 -1。
static func upgrade_cost(species_id: String, level: int) -> int:
	if level >= Balance.DISPLAY_MAX_LEVEL:
		return -1
	return roundi(base_price(species_id) * Balance.UPGRADE_COST_FACTOR * pow(level, Balance.UPGRADE_COST_POWER))
