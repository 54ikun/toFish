class_name Avatar
extends Node3D
## 玩家角色：方块小人，动作全靠代码摆关节。占位美术（临时）。
## 默认面朝 -Z。

enum Pose { IDLE, WALK, FISH_READY, CHARGE, CAST, REEL, LIFT }

const SKIN := Color("ffd2a6")
const SHIRT := Color("ff6b4a")
const PANTS := Color("2f6fde")
const SHOES := Color("4a3426")
const HAT := Color("ffe08a")
const HAT_BAND := Color("ef476f")

const ROD_LENGTH := 2.6
## 手臂抬起的角度（弧度）：0 垂在身侧，90° 平举向前，180° 举过头顶。
const ARM_READY := deg_to_rad(72.0)
const ARM_CHARGED := deg_to_rad(168.0)
const ARM_CAST := deg_to_rad(38.0)

var pose := Pose.IDLE

var _body: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _rod: Node3D
var _rod_mesh: MeshInstance3D
var _rod_tip: Node3D
var _bells: Array[MeshInstance3D] = []

var _time := 0.0
var _charge := 0.0
var _lift_phase := 0.0
var _cast_time := 0.0
var _kick := 0.0


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)

	_leg_left = _limb(Vector3(-0.13, 0.62, 0.0), _leg_mesh())
	_leg_right = _limb(Vector3(0.13, 0.62, 0.0), _leg_mesh())
	_body.add_child(LowPoly.instance(_torso_mesh()))
	_arm_left = _limb(Vector3(-0.37, 1.22, 0.0), _arm_mesh())
	_arm_right = _limb(Vector3(0.37, 1.22, 0.0), _arm_mesh())

	# 鱼竿握在右手。竿身在自己的坐标里沿 +Y，转 -135° 后手臂平举时竿尖斜向前上方。
	_rod = Node3D.new()
	_rod.position = Vector3(0.0, -0.52, 0.0)
	_rod.rotation.x = deg_to_rad(-135.0)
	_arm_right.add_child(_rod)
	_rod_mesh = LowPoly.instance(null)
	_rod.add_child(_rod_mesh)
	_rod_tip = Node3D.new()
	_rod_tip.position = Vector3(0.0, ROD_LENGTH, 0.0)
	_rod.add_child(_rod_tip)

	# 两只手各一只哑铃。
	for arm: Node3D in [_arm_left, _arm_right]:
		var bell := LowPoly.instance(null)
		bell.position = Vector3(0.0, -0.56, 0.0)
		bell.visible = false
		arm.add_child(bell)
		_bells.append(bell)

	set_rod_tier(0)
	show_rod(false)


func _process(delta: float) -> void:
	_time += delta
	_kick = move_toward(_kick, 0.0, delta * 4.0)
	var arm_l := 0.0
	var arm_r := 0.0
	var leg := 0.0
	var bob := 0.0
	var lean := 0.0
	match pose:
		Pose.IDLE:
			arm_l = sin(_time * 1.6) * 0.05
			arm_r = -arm_l
			bob = sin(_time * 1.6) * 0.012
		Pose.WALK:
			leg = sin(_time * 13.0) * 0.7
			arm_l = leg * 0.8
			arm_r = -leg * 0.8
			bob = absf(sin(_time * 13.0)) * 0.05
		Pose.FISH_READY:
			arm_r = ARM_READY + sin(_time * 1.8) * 0.03
			arm_l = 0.25
			bob = sin(_time * 1.8) * 0.012
		Pose.CHARGE:
			arm_r = lerpf(ARM_READY, ARM_CHARGED, _charge)
			arm_l = 0.25 + _charge * 0.5
			lean = _charge * 0.18
		Pose.CAST:
			_cast_time += delta
			var swing := clampf(_cast_time / 0.14, 0.0, 1.0)
			var settle := clampf((_cast_time - 0.14) / 0.3, 0.0, 1.0)
			arm_r = lerpf(lerpf(ARM_CHARGED, ARM_CAST, swing), ARM_READY, settle)
			arm_l = 0.3
			lean = -0.12 * (1.0 - settle) * swing
		Pose.REEL:
			arm_r = ARM_READY + 0.25 + _kick * 0.35
			arm_l = 1.0 + sin(_time * 22.0) * 0.25
			lean = 0.1 + _kick * 0.08
			bob = _kick * 0.03
		Pose.LIFT:
			# 一次完整动作：举过头顶再放下。
			var raise := sin(_lift_phase * PI)
			arm_l = raise * deg_to_rad(176.0)
			arm_r = arm_l
			bob = -raise * 0.06 + 0.06
	_arm_left.rotation.x = arm_l
	_arm_right.rotation.x = arm_r
	_leg_left.rotation.x = leg
	_leg_right.rotation.x = -leg
	_body.position.y = bob
	_body.rotation.x = lean


func set_pose(next: Pose) -> void:
	if next == Pose.CAST:
		_cast_time = 0.0
	pose = next


func set_charge(value: float) -> void:
	_charge = clampf(value, 0.0, 1.0)


## 举重动作的进度，0–1。
func set_lift_phase(phase: float) -> void:
	_lift_phase = clampf(phase, 0.0, 1.0)


## 收线时每点一下，角色往后顿一下。
func reel_kick() -> void:
	_kick = 1.0


func face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() > 1e-6:
		rotation.y = atan2(-direction.x, -direction.z)


func show_rod(on: bool) -> void:
	_rod.visible = on


func show_dumbbells(on: bool) -> void:
	for bell in _bells:
		bell.visible = on and bell.mesh != null


func set_rod_tier(tier: int) -> void:
	var lp := LowPoly.new()
	var color := Palette.RARITY[tier]
	lp.prism(Vector3(0.0, -0.18, 0.0), 0.045, 0.045, 0.42, 6, Palette.WOOD_DARK)
	lp.prism(Vector3(0.0, 0.24, 0.0), 0.035, 0.012, ROD_LENGTH - 0.24, 5, color)
	lp.box(Vector3(0.0, 0.34, -0.07), Vector3(0.07, 0.12, 0.12), color.darkened(0.25))
	_rod_mesh.mesh = lp.build()


## tier 为 -1 表示还没有哑铃。
func set_dumbbell_tier(tier: int) -> void:
	var mesh: ArrayMesh = null
	if tier >= 0:
		var lp := LowPoly.new()
		var color := Palette.RARITY[tier]
		lp.box(Vector3.ZERO, Vector3(0.46, 0.05, 0.05), Color("3a4150"))
		# 哑铃片沿 X 排，所以把棱柱从 +Y 转到 +X。
		lp.xf = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3.ZERO)
		for side: float in [-1.0, 1.0]:
			lp.prism(Vector3(0.0, side * 0.2 - 0.05, 0.0), 0.13, 0.13, 0.1, 6, color, color.darkened(0.2))
		mesh = lp.build()
	var was_visible := _bells.size() > 0 and _bells[0].visible
	for bell in _bells:
		bell.mesh = mesh
		bell.visible = was_visible and mesh != null


func rod_tip_position() -> Vector3:
	return _rod_tip.global_position


func _limb(pivot: Vector3, mesh: ArrayMesh) -> Node3D:
	var node := Node3D.new()
	node.position = pivot
	node.add_child(LowPoly.instance(mesh))
	_body.add_child(node)
	return node


func _leg_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	lp.box(Vector3(0.0, -0.28, 0.0), Vector3(0.2, 0.56, 0.22), PANTS)
	lp.box(Vector3(0.0, -0.57, -0.04), Vector3(0.22, 0.1, 0.3), SHOES)
	return lp.build()


func _arm_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	lp.box(Vector3(0.0, -0.14, 0.0), Vector3(0.17, 0.3, 0.19), SHIRT)
	lp.box(Vector3(0.0, -0.41, 0.0), Vector3(0.14, 0.26, 0.16), SKIN)
	return lp.build()


func _torso_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	lp.box(Vector3(0.0, 0.95, 0.0), Vector3(0.56, 0.66, 0.32), SHIRT)
	# 头、眼睛、草帽。
	lp.box(Vector3(0.0, 1.5, 0.0), Vector3(0.42, 0.4, 0.4), SKIN)
	for side: float in [-1.0, 1.0]:
		lp.box(Vector3(side * 0.1, 1.52, -0.2), Vector3(0.06, 0.08, 0.03), Color("2b2b35"))
	lp.prism(Vector3(0.0, 1.69, 0.0), 0.46, 0.46, 0.04, 8, HAT)
	lp.prism(Vector3(0.0, 1.73, 0.0), 0.25, 0.25, 0.06, 8, HAT_BAND)
	lp.prism(Vector3(0.0, 1.79, 0.0), 0.25, 0.18, 0.16, 8, HAT)
	return lp.build()
