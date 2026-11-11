class_name Content
extends RefCounted
## 已拍板的内容清单：名称、档位与对应关系，全部出自设计文档。
##
## 这里不放任何可调数值。几率、价格、力量、公式参数等都在 balance.gd，
## 而且那里全是临时值。

const GAME_TITLE := "钓鱼，耍起嘛"

## 第一版水面分 6 区，从码头向外一带带铺开。
const ZONE_COUNT := 6
## 第一版 8 个展示台，每台一条鱼。
const STAND_COUNT := 8
## 展示收益离线也结算，最多按 4 小时封顶。
const OFFLINE_CAP_SECONDS := 4.0 * 3600.0

## 稀有度。与鱼竿、哑铃的档位一一对应。
const RARITY_NAMES: Array[String] = ["黑铁", "绿岩", "青铜", "白银"]
## 第五档只预留名称，第一版不实装。往上面的数组里追加即可扩档。
const RARITY_RESERVED: Array[String] = ["黄金"]

## 12 种鱼。zone_min / zone_max 是文档里的「分区倾向」，不是硬性出没范围。
## 系统预留到 16 种：往这里追加条目即可，核心循环不需要改。
const FISH: Array[Dictionary] = [
	{"id": "matou_tiao", "name": "码头鲦", "rarity": 0, "zone_min": 1, "zone_max": 2},
	{"id": "shifeng_hu", "name": "石缝虎", "rarity": 0, "zone_min": 1, "zone_max": 2},
	{"id": "huayi_ji", "name": "花衣鲫", "rarity": 0, "zone_min": 1, "zone_max": 2},
	{"id": "lanyao_nian", "name": "懒腰鲶", "rarity": 0, "zone_min": 1, "zone_max": 2},
	{"id": "qingtai_qiu", "name": "青苔鳅", "rarity": 1, "zone_min": 2, "zone_max": 4},
	{"id": "tiaolang_bai", "name": "跳浪白", "rarity": 1, "zone_min": 2, "zone_max": 4},
	{"id": "pushan_bian", "name": "蒲扇鳊", "rarity": 1, "zone_min": 2, "zone_max": 4},
	{"id": "huanggu_lang", "name": "黄骨郎", "rarity": 2, "zone_min": 3, "zone_max": 5},
	{"id": "wandao_bo", "name": "弯刀鲌", "rarity": 2, "zone_min": 3, "zone_max": 5},
	{"id": "guyan_qing", "name": "鼓眼青", "rarity": 2, "zone_min": 3, "zone_max": 5},
	{"id": "yueya_ji", "name": "月牙鲚", "rarity": 3, "zone_min": 5, "zone_max": 6},
	{"id": "xuelin_fang", "name": "雪鳞鲂", "rarity": 3, "zone_min": 5, "zone_max": 6},
]

## 4 档鱼竿，下标即档位，与稀有度对齐。第五档预留，先不起名。
const ROD_NAMES: Array[String] = ["桩头竿", "苔石竿", "铜梢竿", "银浪竿"]
## 4 档哑铃，与鱼竿一一对应。第五档预留。
const DUMBBELL_NAMES: Array[String] = ["铁砂铃", "苔石铃", "铜饼铃", "银锭铃"]


static func tier_count() -> int:
	return RARITY_NAMES.size()


static func fish_index(species_id: String) -> int:
	for i in FISH.size():
		if FISH[i]["id"] == species_id:
			return i
	return -1


static func has_fish(species_id: String) -> bool:
	return fish_index(species_id) >= 0


static func fish_id(index: int) -> String:
	return FISH[index]["id"]


static func fish_name(species_id: String) -> String:
	return FISH[fish_index(species_id)]["name"]


static func fish_rarity(species_id: String) -> int:
	return FISH[fish_index(species_id)]["rarity"]


static func fish_zone_min(species_id: String) -> int:
	return FISH[fish_index(species_id)]["zone_min"]


static func fish_zone_max(species_id: String) -> int:
	return FISH[fish_index(species_id)]["zone_max"]


static func fish_zone_text(species_id: String) -> String:
	return "偏 %d–%d 区" % [fish_zone_min(species_id), fish_zone_max(species_id)]


## 带稀有度前缀的全名，如「黑铁桩头竿」。
static func rod_full_name(tier: int) -> String:
	return RARITY_NAMES[tier] + ROD_NAMES[tier]


static func dumbbell_full_name(tier: int) -> String:
	return RARITY_NAMES[tier] + DUMBBELL_NAMES[tier]
