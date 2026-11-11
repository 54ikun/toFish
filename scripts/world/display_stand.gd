class_name DisplayStand
extends Node3D
## 一个展示台。信息都直接写在台上：
##   - 鱼头顶：这条鱼的每秒收益；
##   - 台前立牌：这条鱼已产生的收益；
##   - 台身等级牌：鱼名、品质、等级、升级所需金币。
## 文字排在鱼的上方和下方，不挡鱼。占位美术（临时）。

const WIDTH := 3.0
## 台身分上下两截：上面是等级牌，下面留给台前的收益立牌，互不遮挡。
const HEIGHT := 1.0
const BOARD_HEIGHT := 0.62
const TEXT_PIXEL := 0.005
const EMPTY_BOARD := Color("8d99a6")

var index := 0

var _fish: Variant = null
var _fish_holder: Node3D
var _fish_mesh: MeshInstance3D
var _board_material: StandardMaterial3D
var _plaque: Label3D
var _income: Label3D
var _earned: Label3D
var _earned_sign: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	var lp := LowPoly.new()
	lp.box(Vector3(0.0, HEIGHT * 0.5, 0.0), Vector3(WIDTH, HEIGHT, 1.0), Palette.STONE)
	lp.box(Vector3(0.0, HEIGHT + 0.04, 0.0), Vector3(WIDTH + 0.2, 0.08, 1.15), Color("fffdf5"))
	lp.prism(Vector3(0.0, HEIGHT + 0.08, 0.0), 0.05, 0.05, 0.22, 5, Palette.WOOD_DARK)
	add_child(LowPoly.instance(lp.build()))

	# 等级牌底板：有鱼时染成这条鱼的稀有度颜色。
	_board_material = StandardMaterial3D.new()
	_board_material.roughness = 1.0
	_board_material.metallic_specular = 0.0
	_board_material.albedo_color = EMPTY_BOARD
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(WIDTH - 0.2, BOARD_HEIGHT, 0.04)
	board.mesh = board_mesh
	board.material_override = _board_material
	var board_y := HEIGHT - 0.04 - BOARD_HEIGHT * 0.5
	board.position = Vector3(0.0, board_y, 0.51)
	add_child(board)

	_plaque = _label(46, Color("ffffff"))
	_plaque.position = Vector3(0.0, board_y, 0.545)
	_plaque.line_spacing = -6.0
	add_child(_plaque)

	_fish_holder = Node3D.new()
	_fish_holder.position = Vector3(0.0, HEIGHT + 0.6, 0.0)
	add_child(_fish_holder)
	_fish_mesh = LowPoly.instance(null)
	_fish_holder.add_child(_fish_mesh)

	_income = _label(52, Color("ffe14d"))
	_income.position = Vector3(0.0, HEIGHT + 1.33, 0.0)
	add_child(_income)

	# 台前的小立牌，向上仰一点，从斜上方的镜头看得清。
	var sign_lp := LowPoly.new()
	sign_lp.box(Vector3.ZERO, Vector3(1.9, 0.32, 0.04), Color("2a3550"))
	_earned_sign = LowPoly.instance(sign_lp.build())
	_earned_sign.position = Vector3(0.0, 0.17, 0.84)
	_earned_sign.rotation.x = deg_to_rad(-30.0)
	add_child(_earned_sign)
	_earned = _label(42, Color("bff4ff"))
	_earned.position = Vector3(0.0, 0.0, 0.03)
	_earned_sign.add_child(_earned)

	refresh(null)


func _process(delta: float) -> void:
	if _fish == null:
		return
	_time += delta
	_fish_holder.rotation.y = sin(_time * 0.7 + index) * 0.35
	_fish_holder.position.y = HEIGHT + 0.6 + sin(_time * 1.3 + index * 0.7) * 0.04


## 换上一条鱼（或 null 表示空台），并重写台上的全部文字。
func refresh(fish: Variant) -> void:
	_fish = fish
	if fish == null:
		_fish_mesh.visible = false
		_income.visible = false
		_earned_sign.visible = false
		_board_material.albedo_color = EMPTY_BOARD
		_plaque.text = "%d 号空台\n点一下上架" % (index + 1)
		return
	var species_id: String = fish["species"]
	var level: int = fish["level"]
	var rarity := Content.fish_rarity(species_id)

	_fish_mesh.mesh = FishModels.mesh(species_id)
	_fish_mesh.visible = true
	# 统一缩放到差不多的展示尺寸，高体的鱼按高度收一下，免得顶到上面的字。
	var fit := minf(1.35 / FishModels.length(species_id), 0.4 / FishModels.half_height(species_id))
	_fish_mesh.scale = Vector3.ONE * fit

	_board_material.albedo_color = Palette.RARITY[rarity]
	var cost := Rules.upgrade_cost(species_id, level)
	var upgrade_text := "已满级" if cost < 0 else "升级 %s 金币" % UiKit.fmt_gold(cost)
	_plaque.text = "%s · %s · Lv.%d\n%s" % [Content.fish_name(species_id), Content.RARITY_NAMES[rarity], level, upgrade_text]

	_income.visible = true
	_income.text = "+%s/秒" % UiKit.fmt_rate(Rules.income_per_second(species_id, level))
	_earned_sign.visible = true
	refresh_earned()


## 只刷新「已产生的收益」这一行，它每秒都在变。
func refresh_earned() -> void:
	if _fish == null:
		return
	var earned: float = _fish["earned"]
	_earned.text = "已产 %s" % UiKit.fmt_amount(earned)


func _label(font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.font = UiKit.font()
	label.font_size = font_size
	label.pixel_size = TEXT_PIXEL
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color("1a2238")
	label.shaded = false
	label.double_sided = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return label
