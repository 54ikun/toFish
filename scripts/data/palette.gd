class_name Palette
extends RefCounted
## 颜色表。全部是占位色值（临时）。
##
## 文档已定的只有方向：明亮、高饱和卡通；四档稀有「黑铁偏暗、绿岩偏青、青铜偏暖、
## 白银偏亮」，鱼、竿、哑铃和等级牌尽量共用。具体色值要等风格样板过目后再定为规范。

## 四档稀有的主色，鱼鳍、鱼竿、哑铃、等级牌共用。
const RARITY: Array[Color] = [
	Color("4f5b6b"),
	Color("1fb8a6"),
	Color("d98a3a"),
	Color("dfeaf6"),
]
## 写在浅色面板上的稀有度文字色（比主色深，保证看得清）。
const RARITY_TEXT: Array[Color] = [
	Color("3d4756"),
	Color("0f8f80"),
	Color("b56a1c"),
	Color("6485ad"),
]

## 6 区水面由近到远的颜色：靠颜色一块块读出远近，不画硬线框。
const ZONE_WATER: Array[Color] = [
	Color("63e2e0"),
	Color("35c9ea"),
	Color("20a8e8"),
	Color("1c86de"),
	Color("1d64c9"),
	Color("2046a8"),
]
const SHALLOWS := Color("a8f3e6")
const OUTER_WATER := Color("183a8a")
const SKY := Color("8fd6ff")

const GRASS := Color("7ed957")
const SAND := Color("ffe39a")
const WOOD := Color("c98b4f")
const WOOD_DARK := Color("9a6436")
const STONE := Color("f1e9d8")

# 界面
const INK := Color("1f2a44")
const PANEL := Color("fff8e7")
## 列表行和图鉴卡片的底色：带一点蓝，白银档的白鱼放上去也看得清。
const ROW := Color("e6f0fb")
const PRIMARY := Color("ff8a1f")
const PRIMARY_DARK := Color("d9660a")
const SECONDARY := Color("27b4f5")
const SECONDARY_DARK := Color("1287c9")
const GREEN := Color("2fbf71")
const GREEN_DARK := Color("1f9455")
const GREY := Color("aab4c3")
const GREY_DARK := Color("8793a6")
const DANGER := Color("ef476f")
const GOLD := Color("ffc93c")
const GOLD_DARK := Color("c98a00")
