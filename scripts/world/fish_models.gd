class_name FishModels
extends RefCounted
## 12 种鱼和巨鱼的占位模型：程序生成、顶点色、每条不到一百个三角面。
##
## 这些只是让初版能跑的占位美术，造型和配色都是临时的。按设计文档，正式美术要
## 先出风格样板过目，再按同一套颜色、面数预算量产并交付 .glb。
##
## 模型头朝 +X，体长方向沿 X，背朝 +Y。

## 各鱼种的外形参数（临时）。len 体长，h 半高，w 半宽，单位米。
## pattern：0 纯色，1 横纹，2 花斑。
const LOOKS := {
	"matou_tiao": {"len": 0.50, "h": 0.085, "w": 0.050, "tail": 0.12, "dorsal": 0.05, "back": Color("8fa0b5"), "belly": Color("eef3f8"), "pattern": 0},
	"shifeng_hu": {"len": 0.42, "h": 0.100, "w": 0.075, "tail": 0.09, "dorsal": 0.07, "back": Color("a8895c"), "belly": Color("e6d6ae"), "pattern": 1, "alt": Color("3a322b")},
	"huayi_ji": {"len": 0.46, "h": 0.150, "w": 0.070, "tail": 0.12, "dorsal": 0.08, "back": Color("e2583c"), "belly": Color("fbe3b3"), "pattern": 2, "alt": Color("454a57")},
	"lanyao_nian": {"len": 0.70, "h": 0.100, "w": 0.100, "tail": 0.10, "dorsal": 0.03, "back": Color("5a6070"), "belly": Color("cfc8b8"), "pattern": 0, "whiskers": true},
	"qingtai_qiu": {"len": 0.58, "h": 0.065, "w": 0.055, "tail": 0.08, "dorsal": 0.04, "back": Color("3aa66f"), "belly": Color("dcefb4"), "pattern": 1, "alt": Color("1f7a5c")},
	"tiaolang_bai": {"len": 0.58, "h": 0.110, "w": 0.060, "tail": 0.16, "dorsal": 0.07, "back": Color("52d6d0"), "belly": Color("ffffff"), "pattern": 0},
	"pushan_bian": {"len": 0.50, "h": 0.210, "w": 0.050, "tail": 0.12, "dorsal": 0.11, "back": Color("25b3ad"), "belly": Color("d9f6ec"), "pattern": 0},
	"huanggu_lang": {"len": 0.52, "h": 0.120, "w": 0.080, "tail": 0.11, "dorsal": 0.09, "back": Color("f0b23a"), "belly": Color("fbe9a8"), "pattern": 0},
	"wandao_bo": {"len": 0.80, "h": 0.105, "w": 0.050, "tail": 0.16, "dorsal": 0.06, "back": Color("d98443"), "belly": Color("f6ead8"), "pattern": 0},
	"guyan_qing": {"len": 0.62, "h": 0.150, "w": 0.090, "tail": 0.13, "dorsal": 0.08, "back": Color("3f8f8a"), "belly": Color("f2d39b"), "pattern": 2, "alt": Color("c97a2c"), "big_eye": true},
	"yueya_ji": {"len": 0.66, "h": 0.095, "w": 0.045, "tail": 0.22, "dorsal": 0.05, "back": Color("c9dcf2"), "belly": Color("ffffff"), "pattern": 0, "crescent": true},
	"xuelin_fang": {"len": 0.60, "h": 0.220, "w": 0.060, "tail": 0.14, "dorsal": 0.10, "back": Color("f2f7ff"), "belly": Color("ffffff"), "pattern": 2, "alt": Color("b7d4f5")},
}

const GIANT_LOOK := {"len": 3.6, "h": 0.75, "w": 0.60, "tail": 0.9, "dorsal": 0.9, "back": Color("3b2a6b"), "belly": Color("9a86dd"), "pattern": 0}
const GIANT_FIN := Color("2a1d52")

static var _cache: Dictionary = {}


static func look(species_id: String) -> Dictionary:
	return LOOKS[species_id]


static func length(species_id: String) -> float:
	return LOOKS[species_id]["len"]


static func half_height(species_id: String) -> float:
	return LOOKS[species_id]["h"]


## 某种鱼的模型。鱼鳍用稀有度主色，一眼能看出档位。
static func mesh(species_id: String) -> ArrayMesh:
	if not _cache.has(species_id):
		var fin_color := Palette.RARITY[Content.fish_rarity(species_id)]
		_cache[species_id] = _build(LOOKS[species_id], fin_color, false)
	return _cache[species_id]


## 追在后面的巨鱼。
static func giant_mesh() -> ArrayMesh:
	if not _cache.has("__giant"):
		_cache["__giant"] = _build(GIANT_LOOK, GIANT_FIN, true)
	return _cache["__giant"]


static func _build(shape: Dictionary, fin_color: Color, giant: bool) -> ArrayMesh:
	var body_len: float = shape["len"]
	var half_h: float = shape["h"]
	var half_w: float = shape["w"]
	var tail_len: float = shape["tail"]
	var dorsal: float = shape["dorsal"]
	var back: Color = shape["back"]
	var belly: Color = shape["belly"]
	var pattern: int = shape["pattern"]
	var alt: Color = shape.get("alt", back)

	var lp := LowPoly.new()

	# 鱼身：从尾柄到吻端的几圈截面。巨鱼的头更钝。
	var head_ring := Vector3(0.40 * body_len, 0.80 * half_h, 0.85 * half_w) if giant \
			else Vector3(0.36 * body_len, 0.62 * half_h, 0.70 * half_w)
	var rings: Array[Vector3] = [
		Vector3(-0.46 * body_len, 0.0, 0.0),
		Vector3(-0.38 * body_len, 0.30 * half_h, 0.35 * half_w),
		Vector3(-0.12 * body_len, 0.90 * half_h, 0.90 * half_w),
		Vector3(0.14 * body_len, 1.00 * half_h, 1.00 * half_w),
		head_ring,
		Vector3(0.50 * body_len, 0.0, 0.0),
	]
	var color_fn := func(segment: int, face: int, mid: Vector3) -> Color:
		if mid.y < 0.0:
			return belly
		if pattern == 1 and segment % 2 == 1:
			return alt
		if pattern == 2 and (segment + face) % 2 == 1:
			return alt
		return back
	lp.spindle(rings, 6, color_fn)

	# 尾鳍：上下两叶加中间一片。月牙尾的缺口更深、叶更长。
	var root_x := -0.40 * body_len
	var tip_x := root_x - tail_len
	var lobe := maxf(half_h * 1.15, tail_len * 0.55)
	var crescent: bool = shape.get("crescent", false)
	var notch_x := root_x - tail_len * (0.22 if crescent else 0.55)
	var root_top := Vector3(root_x, 0.26 * half_h, 0.0)
	var root_bottom := Vector3(root_x, -0.26 * half_h, 0.0)
	var notch := Vector3(notch_x, 0.0, 0.0)
	lp.fin(PackedVector3Array([root_top, Vector3(tip_x, lobe, 0.0), notch]), fin_color)
	lp.fin(PackedVector3Array([root_bottom, notch, Vector3(tip_x, -lobe, 0.0)]), fin_color)
	lp.fin(PackedVector3Array([root_top, notch, root_bottom]), fin_color)

	# 背鳍。
	lp.fin(PackedVector3Array([
		Vector3(0.18 * body_len, 0.92 * half_h, 0.0),
		Vector3(-0.20 * body_len, 0.80 * half_h, 0.0),
		Vector3(-0.10 * body_len, 0.92 * half_h + dorsal, 0.0),
	]), fin_color)

	# 眼睛。
	var big_eye: bool = shape.get("big_eye", false)
	var eye := body_len * (0.085 if big_eye else 0.05)
	var eye_color := Color("ff4d4d") if giant else Color("ffffff")
	for side: float in [-1.0, 1.0]:
		var eye_pos := Vector3(0.36 * body_len, 0.22 * half_h, side * 0.62 * half_w)
		lp.box(eye_pos, Vector3(eye, eye, eye * 0.6), eye_color)
		lp.box(eye_pos + Vector3(eye * 0.15, 0.0, side * eye * 0.3), Vector3(eye * 0.5, eye * 0.5, eye * 0.3), Color("141821"))

	# 鲶鱼的须。
	if shape.get("whiskers", false):
		for side: float in [-1.0, 1.0]:
			lp.xf = Transform3D(Basis(Vector3.UP, -side * 0.6), Vector3(0.46 * body_len, -0.25 * half_h, side * 0.3 * half_w))
			lp.box(Vector3(0.08, 0.0, 0.0), Vector3(0.16, 0.014, 0.014), Color("2c303a"))
		lp.xf = Transform3D.IDENTITY

	# 巨鱼的牙。
	if giant:
		for side: float in [-1.0, 1.0]:
			for i in 4:
				var x := body_len * (0.34 + 0.035 * i)
				var z := side * half_w * (0.72 - 0.14 * i)
				lp.fin(PackedVector3Array([
					Vector3(x - 0.07, -0.12 * half_h, z),
					Vector3(x + 0.07, -0.12 * half_h, z),
					Vector3(x, -0.46 * half_h, z),
				]), Color("ffffff"))

	return lp.build()
