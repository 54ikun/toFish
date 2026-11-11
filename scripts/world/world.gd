class_name World
extends Node3D
## 三维场景：一个钓点，含出生码头、6 区水面、岸边健身房和 8 个展示台。
## 全部用代码搭，模型是低面数顶点色的占位美术（临时），布局尺寸也是临时的。
##
## 角色可以在岸上和码头上自由走动。走到哪里就能做那里的事：
## 码头尽头钓鱼，健身房门口买哑铃，展示台前面管理展示。举重在哪儿都能做。
## 镜头平时跟在角色身后；站上钓鱼点或走到展示台前，会换成看得清水面或台子的机位。
##
## 手机浏览器的预算：一盏不投影的方向光、不透明的水面、没有贴图、同屏物体很少。
##
## 坐标约定：岸线在 z = 0，陆地在 z > 0，水面向 -Z 铺开；码头从岸边伸进水里。

signal spot_changed(spot: int)
signal near_stand_changed(index: int)

## 角色此刻站在哪种地方，决定这里能做什么。
enum Spot { NONE, FISHING, SHOP, DISPLAY }
## 角色正在做什么。钓鱼和举重期间不能走动。
enum Activity { FREE, FISHING, LIFTING }

const PIER_END_Z := -6.0
const PIER_TOP_Y := 0.55
const PIER_HALF_WIDTH := 1.6
## 码头板在岸上铺到这里，再往里是一小段下到地面的斜坡。
const PIER_LAND_Z := 2.4
const PIER_RAMP_Z := 3.4
const GROUND_Y := 0.2
const SPAWN := Vector3(0.0, PIER_TOP_Y, -5.1)
const GYM_CENTER := Vector3(-13.0, GROUND_Y, 6.5)
## 8 个展示台沿岸边排成一排，正面朝着岸上，人可以沿着走过去挨个看。
const DISPLAY_CENTER := Vector3(17.2, GROUND_Y, 5.0)
const STAND_SPACING := 3.3
## 水里的鱼放大显示，隔着几十米也看得清。
const WATER_FISH_SCALE := 3.0
const GIANT_SCALE := 1.5
const REFERENCE_ASPECT := 16.0 / 9.0

# 可以走的范围（临时）：岸上一块长方形，加上码头。
const WALK_MIN_X := -26.0
const WALK_MAX_X := 31.0
const WALK_MAX_Z := 13.5
## 岸上最靠水的一线。再往外只有码头能走。
const SHORE_Z := 0.7
const PIER_WALK_HALF := 1.25
const PIER_WALK_END_Z := -5.6
const PLAYER_RADIUS := 0.4
## 码头上过了这条线就算站在钓鱼点。
const FISHING_SPOT_Z := -3.2
## 健身房的地垫、展示台前的空地各有多大（从中心算的半宽和前沿）。
const SHOP_HALF_WIDTH := 4.5
const SHOP_FRONT_Z := 3.0
const DISPLAY_HALF_WIDTH := STAND_SPACING * Content.STAND_COUNT * 0.5
## 展示台正面挡路的一线，和台前地垫的前沿（都从展示台中心算）。
const DISPLAY_BLOCK_Z := 1.1
const DISPLAY_FRONT_Z := 4.6
const TREE_SPOTS: Array[Vector3] = [
	Vector3(-21.0, 0.0, 3.2), Vector3(-5.5, 0.0, 3.0), Vector3(3.3, 0.0, 2.0),
	Vector3(12.2, 0.0, 2.2), Vector3(23.8, 0.0, 2.2), Vector3(-25.0, 0.0, 9.0), Vector3(34.0, 0.0, 8.5),
]

# 机位（临时）。
const FISHING_CAM_POS := Vector3(0.0, 11.5, 6.5)
const FISHING_CAM_LOOK := Vector3(0.0, 0.0, -20.0)
const FISHING_CAM_FOV := 50.0
## 展示台机位跟着人左右移，从斜上方越过人的头顶看台子，人不会挡住台上的字。
## 两个量都是相对「人的左右位置、展示台那一排的前后位置」的偏移。
const DISPLAY_CAM_OFFSET := Vector3(0.0, 7.8, 10.0)
const DISPLAY_CAM_LOOK := Vector3(0.0, 1.2, 0.5)
const DISPLAY_CAM_FOV := 34.0
const FOLLOW_CAM_OFFSET := Vector3(0.0, 6.5, 9.5)
const FOLLOW_CAM_LOOK := Vector3(0.0, 1.0, -1.5)
const FOLLOW_CAM_FOV := 50.0
## 镜头追上目标机位的快慢。
const CAMERA_EASE := 5.0

var spot := Spot.FISHING
## 站在展示台前时离哪个台子最近（0 起）；不在台前是 -1。
var near_stand := -1
var avatar: Avatar
var camera: Camera3D
var stands: Array[DisplayStand] = []
## 想往哪边走，长度 0–1。x 向右，y 向岸上（和屏幕方向一致），由 main.gd 每帧写入。
var move_input := Vector2.ZERO

var _activity := Activity.FREE
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_fov := 50.0

var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _target_fish: MeshInstance3D
var _giant: MeshInstance3D
var _ripple: MeshInstance3D
var _stand_marker: MeshInstance3D
var _line_target: Node3D = null
var _landing := Vector3.ZERO
var _reel_scale := WATER_FISH_SCALE
var _shore_point := Vector3(0.0, 0.0, PIER_END_Z - 0.9)
var _fx: Tween
var _time := 0.0
var _earned_timer := 0.0


func _ready() -> void:
	_build_environment()
	_build_land()
	_build_water()
	_build_pier()
	_build_gym()
	_build_display()
	_build_fishing_props()

	avatar = Avatar.new()
	add_child(avatar)

	camera = Camera3D.new()
	camera.near = 0.3
	camera.far = 400.0
	add_child(camera)
	camera.current = true

	GameState.changed.connect(refresh_from_state)
	refresh_from_state()
	# 出生在码头尽头，面朝水面，直接就能钓。
	place_player(SPAWN)
	avatar.face(Vector3.FORWARD)


func _process(delta: float) -> void:
	_time += delta
	_update_player(delta)
	_update_camera(delta)
	_update_line()
	if _bobber.visible and _line_target == _bobber and not _fx_running():
		_bobber.position.y = 0.08 + sin(_time * 5.0) * 0.05
	_stand_marker.visible = near_stand >= 0
	if near_stand >= 0:
		_stand_marker.position = stands[near_stand].position + Vector3(0.0, DisplayStand.HEIGHT + 2.0 + sin(_time * 4.0) * 0.08, 0.0)
		_stand_marker.rotation.y = _time * 2.0
	_earned_timer += delta
	if _earned_timer >= 0.5:
		_earned_timer = 0.0
		for stand in stands:
			stand.refresh_earned()


# ── 走动 ───────────────────────────────────────────────────────────

## 把想去的位置修正到能走的地方：不能下水，不能穿过建筑和树。from 是这一步的起点。
## 只管水平位置，高度另算。
static func walkable(from: Vector3, to: Vector3) -> Vector3:
	var at := Vector3(clampf(to.x, WALK_MIN_X, WALK_MAX_X), to.y, clampf(to.z, PIER_WALK_END_Z, WALK_MAX_Z))
	if at.z < SHORE_Z and absf(at.x) > PIER_WALK_HALF:
		# 留一点余量再比：位置是单精度存的，正好贴在岸线上的人不能被当成在码头上。
		if from.z < SHORE_Z - 0.001 and absf(from.x) <= PIER_WALK_HALF + 0.001:
			# 本来就在码头上：贴着码头边滑，不掉下去。
			at.x = clampf(at.x, -PIER_WALK_HALF, PIER_WALK_HALF)
		else:
			# 本来在岸上：贴着岸线滑，不下水。
			at.z = SHORE_Z
	for block in _blocks():
		var grown := block.grow(PLAYER_RADIUS)
		if not grown.has_point(Vector2(at.x, at.z)):
			continue
		# 从最近的一边推出去。建筑背后一直堵到水里，所以不会往水那边推。
		var left := at.x - grown.position.x
		var right := grown.end.x - at.x
		var front := grown.end.y - at.z
		if front <= left and front <= right:
			at.z = grown.end.y
		elif left <= right:
			at.x = grown.position.x
		else:
			at.x = grown.end.x
	for tree in TREE_SPOTS:
		var away := Vector2(at.x - tree.x, at.z - tree.z)
		var reach := 0.3 + PLAYER_RADIUS
		if away.length() < reach:
			away = away.normalized() * reach if away.length() > 0.001 else Vector2(0.0, reach)
			at.x = tree.x + away.x
			at.z = tree.z + away.y
	return at


## 挡路的建筑，用俯视的长方形表示（x、z）。健身房和展示台的背后一并堵上，
## 免得角色绕到后面被挡住看不见。
static func _blocks() -> Array[Rect2]:
	var behind := -20.0
	return [
		Rect2(GYM_CENTER.x - SHOP_HALF_WIDTH, behind, SHOP_HALF_WIDTH * 2.0, GYM_CENTER.z - 2.7 - behind),
		Rect2(GYM_CENTER.x - 2.6, behind, 5.2, GYM_CENTER.z - 1.85 - behind),
		Rect2(DISPLAY_CENTER.x - DISPLAY_HALF_WIDTH, behind, DISPLAY_HALF_WIDTH * 2.0, DISPLAY_CENTER.z + DISPLAY_BLOCK_Z - behind),
	]


## 脚下的地面有多高：码头板比岸上的地面高一截，靠岸一头有斜坡。
static func ground_height(at: Vector3) -> float:
	if absf(at.x) <= PIER_HALF_WIDTH:
		if at.z <= PIER_LAND_Z:
			return PIER_TOP_Y
		if at.z < PIER_RAMP_Z:
			return lerpf(PIER_TOP_Y, GROUND_Y, (at.z - PIER_LAND_Z) / (PIER_RAMP_Z - PIER_LAND_Z))
	return GROUND_Y


## 站在这个位置能做什么。
static func spot_at(at: Vector3) -> Spot:
	if absf(at.x) <= PIER_HALF_WIDTH and at.z <= FISHING_SPOT_Z:
		return Spot.FISHING
	if absf(at.x - GYM_CENTER.x) <= SHOP_HALF_WIDTH and at.z <= GYM_CENTER.z + SHOP_FRONT_Z and at.z >= GYM_CENTER.z - 2.7:
		return Spot.SHOP
	if absf(at.x - DISPLAY_CENTER.x) <= DISPLAY_HALF_WIDTH and at.z <= DISPLAY_CENTER.z + DISPLAY_FRONT_Z and at.z >= DISPLAY_CENTER.z + DISPLAY_BLOCK_Z:
		return Spot.DISPLAY
	return Spot.NONE


## 把角色直接放到某个位置（开局、测试和截图用），镜头一步到位。
func place_player(at: Vector3) -> void:
	var fixed := walkable(at, at)
	avatar.position = Vector3(fixed.x, ground_height(fixed), fixed.z)
	_set_spot(spot_at(avatar.position))
	snap_camera()


func is_free() -> bool:
	return _activity == Activity.FREE


func _update_player(delta: float) -> void:
	var moving := false
	if _activity == Activity.FREE:
		var push := move_input.limit_length(1.0)
		if push.length() > 0.1:
			var heading := Vector3(push.x, 0.0, push.y)
			var next := walkable(avatar.position, avatar.position + heading * Balance.WALK_SPEED * delta)
			avatar.position.x = next.x
			avatar.position.z = next.z
			_turn_to(heading, delta)
			moving = true
	avatar.position.y = move_toward(avatar.position.y, ground_height(avatar.position), delta * 4.0)
	_set_spot(spot_at(avatar.position))

	match _activity:
		Activity.LIFTING:
			# 举重时转过来面朝镜头，看得清动作。
			_turn_to(Vector3.BACK, delta)
		Activity.FREE:
			if moving:
				avatar.show_rod(false)
				avatar.set_pose(Avatar.Pose.WALK)
			elif spot == Spot.FISHING:
				_turn_to(Vector3.FORWARD, delta)
				avatar.show_rod(true)
				avatar.set_pose(Avatar.Pose.FISH_READY)
			else:
				avatar.show_rod(false)
				avatar.set_pose(Avatar.Pose.IDLE)


func _turn_to(direction: Vector3, delta: float) -> void:
	var target := atan2(-direction.x, -direction.z)
	avatar.rotation.y = lerp_angle(avatar.rotation.y, target, 1.0 - exp(-delta * 14.0))


func _set_spot(next: Spot) -> void:
	if next != spot:
		spot = next
		spot_changed.emit(spot)
	var stand := -1
	if spot == Spot.DISPLAY:
		stand = stand_near(avatar.position)
	if stand != near_stand:
		near_stand = stand
		near_stand_changed.emit(near_stand)


## 站在展示台前的这个位置，正对着的是第几个台子（0 起）。
static func stand_near(at: Vector3) -> int:
	return clampi(roundi((at.x - stand_x(0)) / STAND_SPACING), 0, Content.STAND_COUNT - 1)


## 第 index 个展示台的左右位置。
static func stand_x(index: int) -> float:
	return DISPLAY_CENTER.x + (index - (Content.STAND_COUNT - 1) * 0.5) * STAND_SPACING


# ── 镜头 ───────────────────────────────────────────────────────────

## 镜头立刻切到该在的机位，不走过渡。
func snap_camera() -> void:
	var rig := _camera_rig()
	_cam_pos = rig[0]
	_cam_look = rig[1]
	_cam_fov = rig[2]
	_apply_camera()


## 此刻镜头该在的机位：[位置, 看向哪里, 视角]。
func _camera_rig() -> Array:
	if _activity == Activity.FISHING or spot == Spot.FISHING:
		return [FISHING_CAM_POS, FISHING_CAM_LOOK, FISHING_CAM_FOV]
	if spot == Spot.DISPLAY:
		var base := Vector3(avatar.position.x, 0.0, DISPLAY_CENTER.z)
		return [base + DISPLAY_CAM_OFFSET, base + DISPLAY_CAM_LOOK, DISPLAY_CAM_FOV]
	return [avatar.position + FOLLOW_CAM_OFFSET, avatar.position + FOLLOW_CAM_LOOK, FOLLOW_CAM_FOV]


func _update_camera(delta: float) -> void:
	var rig := _camera_rig()
	var blend := 1.0 - exp(-delta * CAMERA_EASE)
	var pos: Vector3 = rig[0]
	var look: Vector3 = rig[1]
	var fov: float = rig[2]
	_cam_pos = _cam_pos.lerp(pos, blend)
	_cam_look = _cam_look.lerp(look, blend)
	_cam_fov = lerpf(_cam_fov, fov, blend)
	_apply_camera()


func _apply_camera() -> void:
	camera.position = _cam_pos
	camera.look_at(_cam_look, Vector3.UP)
	# 镜头的取景按 16:9 设计。窗口更窄时加大视角，保证左右两侧的东西不被裁掉。
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var fov := _cam_fov
	if aspect < REFERENCE_ASPECT:
		fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_cam_fov) * 0.5) * REFERENCE_ASPECT / aspect))
	camera.fov = clampf(fov, 1.0, 110.0)


# ── 跟随存档刷新 ───────────────────────────────────────────────────

func refresh_from_state() -> void:
	avatar.set_rod_tier(GameState.rod)
	avatar.set_dumbbell_tier(GameState.dumbbell)
	for stand in stands:
		stand.refresh(GameState.stand_fish(stand.index))


## 屏幕上的一点落在哪个展示台上；没点中返回 -1。
func pick_stand(screen_pos: Vector2) -> int:
	for stand in stands:
		var origin := stand.global_position
		var corner_a := camera.unproject_position(origin + Vector3(-STAND_SPACING * 0.5, -0.1, 0.5))
		var corner_b := camera.unproject_position(origin + Vector3(STAND_SPACING * 0.5, DisplayStand.HEIGHT + 1.7, 0.5))
		var rect := Rect2(corner_a, Vector2.ZERO).expand(corner_b)
		if rect.has_point(screen_pos):
			return stand.index
	return -1


# ── 钓鱼演出 ───────────────────────────────────────────────────────

## 一竿开始：站定、面朝水面、拿出鱼竿。到这一竿结束之前不能走动。
func begin_fishing() -> void:
	_activity = Activity.FISHING
	avatar.face(Vector3.FORWARD)
	avatar.show_dumbbells(false)
	avatar.show_rod(true)


func set_charge(value: float) -> void:
	avatar.set_charge(value)
	avatar.set_pose(Avatar.Pose.CHARGE)


## 甩竿：浮标沿弧线飞到落点。distance 是离码头尽头的距离，lateral 是左右偏移。
func play_cast(distance: float, lateral: float, flight_time: float) -> void:
	avatar.set_pose(Avatar.Pose.CAST)
	_landing = Vector3(lateral, 0.0, PIER_END_Z - distance)
	_target_fish.visible = false
	_giant.visible = false
	_bobber.visible = true
	_line_target = _bobber
	var start := avatar.rod_tip_position()
	var height := 2.0 + distance * 0.12
	_restart_fx()
	_fx.tween_method(_fly_bobber.bind(start, height), 0.0, 1.0, flight_time)
	_fx.tween_callback(_splash.bind(_landing))


func _fly_bobber(t: float, start: Vector3, height: float) -> void:
	var pos := start.lerp(_landing + Vector3(0.0, 0.08, 0.0), t)
	pos.y += sin(t * PI) * height
	_bobber.position = pos


## 开始收线：目标鱼在咬钩点冒头，巨鱼出现在它身后。
func begin_reel(species_id: String) -> void:
	_stop_fx()
	avatar.set_pose(Avatar.Pose.REEL)
	_bobber.visible = false
	_target_fish.mesh = FishModels.mesh(species_id)
	_target_fish.visible = true
	_giant.visible = true
	_line_target = _target_fish
	update_reel(0.0, -Balance.CHASE_GAP)


## fish 和 giant 都是 0–1 制的进度：0 在咬钩点，1 在岸边。
func update_reel(fish: float, giant: float) -> void:
	# 模型头朝 +X，转到朝岸边游。
	var heading := _shore_point - _landing
	var yaw := atan2(-heading.z, heading.x)
	# 鱼是扁的，正对镜头游只剩一条缝。让它一边被拖一边左右甩，露出侧面；
	# 再按离镜头的距离放大，远近看起来差不多大。
	var fish_at := _landing.lerp(_shore_point, fish)
	_reel_scale = WATER_FISH_SCALE * _distance_scale(fish_at)
	_target_fish.scale = Vector3.ONE * _reel_scale
	_target_fish.rotation = Vector3(0.0, yaw + sin(_time * 9.0) * 1.15, 0.0)
	_target_fish.position = fish_at + Vector3(0.0, 0.07 * _reel_scale, 0.0)

	var giant_at := _landing + heading * giant
	var giant_scale := GIANT_SCALE * _distance_scale(giant_at)
	_giant.scale = Vector3.ONE * giant_scale
	_giant.rotation = Vector3(0.0, yaw + sin(_time * 3.5) * 0.5, 0.0)
	_giant.position = giant_at + Vector3(0.0, -0.15 * giant_scale, 0.0)


func _distance_scale(at: Vector3) -> float:
	return clampf(camera.global_position.distance_to(at) / 18.0, 1.0, 3.0)


func reel_kick() -> void:
	avatar.reel_kick()


## 收线结束：成功则鱼飞上码头，失败则巨鱼一口吞掉后沉下去。
func finish_reel(success: bool) -> void:
	avatar.set_pose(Avatar.Pose.FISH_READY)
	_restart_fx()
	if success:
		var from := _target_fish.position
		var to := avatar.position + Vector3(0.0, 2.3, 0.0)
		_fx.tween_method(_fly_catch.bind(from, to), 0.0, 1.0, 0.35)
		_fx.parallel().tween_property(_giant, "position:y", -4.0, 0.5)
		_fx.tween_interval(0.5)
		_fx.tween_callback(_hide_fishing_props)
	else:
		_line_target = null
		_splash(_target_fish.position)
		_fx.tween_property(_giant, "position", _target_fish.position + Vector3(0.0, 0.3, 0.0), 0.12)
		_fx.tween_callback(_target_fish.hide)
		_fx.tween_property(_giant, "position:y", -4.0, 0.7).set_delay(0.15)
		_fx.tween_callback(_hide_fishing_props)


func _fly_catch(t: float, from: Vector3, to: Vector3) -> void:
	var pos := from.lerp(to, t)
	pos.y += sin(t * PI) * 1.5
	_target_fish.position = pos
	_target_fish.scale = Vector3.ONE * lerpf(_reel_scale, 1.6, t)


## 一竿结束：收起所有钓鱼道具，角色又可以走动了。
func end_fishing() -> void:
	_stop_fx()
	_hide_fishing_props()
	if _activity == Activity.FISHING:
		_activity = Activity.FREE


func _hide_fishing_props() -> void:
	_bobber.visible = false
	_target_fish.visible = false
	_giant.visible = false
	_ripple.visible = false
	_line_target = null


func _splash(at: Vector3) -> void:
	_ripple.position = Vector3(at.x, 0.03, at.z)
	_ripple.scale = Vector3(0.4, 1.0, 0.4)
	_ripple.visible = true
	var ring := create_tween()
	ring.tween_property(_ripple, "scale", Vector3(2.6, 1.0, 2.6), 0.45)
	ring.tween_callback(_ripple.hide)


func _restart_fx() -> void:
	_stop_fx()
	_fx = create_tween()


func _stop_fx() -> void:
	if _fx != null:
		_fx.kill()
		_fx = null


func _fx_running() -> bool:
	return _fx != null and _fx.is_running()


func _update_line() -> void:
	if _line_target == null or not _line_target.visible:
		_line.visible = false
		return
	var from := avatar.rod_tip_position()
	var to := _line_target.global_position
	var span := to - from
	var length := span.length()
	if length < 0.05:
		_line.visible = false
		return
	_line.visible = true
	_line.position = (from + to) * 0.5
	var up := Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT
	_line.look_at(to, up)
	_line.scale = Vector3(1.0, 1.0, length)


# ── 举重演出 ───────────────────────────────────────────────────────

## 开始举一次：原地站定，拿出哑铃。动作做完之前不能走动。
func begin_lift() -> void:
	_activity = Activity.LIFTING
	avatar.show_rod(false)
	avatar.show_dumbbells(true)
	avatar.set_lift_phase(0.0)
	avatar.set_pose(Avatar.Pose.LIFT)


func set_lift_phase(phase: float) -> void:
	avatar.set_lift_phase(phase)


## 这一次举完了（或者作废了）：收起哑铃。
func end_lift() -> void:
	avatar.set_lift_phase(0.0)
	avatar.show_dumbbells(false)
	if _activity == Activity.LIFTING:
		_activity = Activity.FREE


# ── 搭场景 ─────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffffff")
	env.ambient_light_energy = 0.75
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)


func _build_land() -> void:
	var lp := LowPoly.new()
	lp.box(Vector3(0.0, GROUND_Y - 1.0, 14.0), Vector3(120.0, 2.0, 28.0), Palette.GRASS)
	lp.box(Vector3(0.0, GROUND_Y - 0.99, 0.9), Vector3(120.0, 2.0, 1.8), Palette.SAND)
	# 几棵树，衬在健身房和展示台两侧。
	for tree in TREE_SPOTS:
		var base := tree + Vector3(0.0, GROUND_Y, 0.0)
		lp.prism(base, 0.22, 0.18, 1.0, 5, Palette.WOOD_DARK)
		lp.prism(base + Vector3(0.0, 0.9, 0.0), 1.15, 0.0, 1.7, 6, Color("2fb86a"))
		lp.prism(base + Vector3(0.0, 1.9, 0.0), 0.85, 0.0, 1.5, 6, Color("46cf7c"))
	# 远处两座小岛，给水面一点纵深。
	lp.prism(Vector3(-34.0, -0.3, -78.0), 9.0, 3.0, 3.2, 7, Color("6fcf6a"), Color("8fe07a"))
	lp.prism(Vector3(40.0, -0.3, -92.0), 12.0, 4.0, 4.5, 7, Color("6fcf6a"), Color("8fe07a"))
	add_child(LowPoly.instance(lp.build()))


func _build_water() -> void:
	# 六块长方形水面从码头向外一带接一带铺开，靠颜色区分，不画线框。
	var lp := LowPoly.new()
	var half_width := Balance.ZONE_WIDTH * 0.5
	lp.quad(Vector3(-400.0, -0.06, 0.0), Vector3(400.0, -0.06, 0.0), Vector3(400.0, -0.06, -500.0), Vector3(-400.0, -0.06, -500.0), Palette.OUTER_WATER, Vector3.UP)
	lp.quad(Vector3(-half_width, -0.02, 0.0), Vector3(half_width, -0.02, 0.0), Vector3(half_width, -0.02, PIER_END_Z), Vector3(-half_width, -0.02, PIER_END_Z), Palette.SHALLOWS, Vector3.UP)
	for zone in range(1, Content.ZONE_COUNT + 1):
		var near := PIER_END_Z - Rules.zone_near_edge(zone)
		var far := PIER_END_Z - Rules.zone_far_edge(zone)
		lp.quad(Vector3(-half_width, 0.0, near), Vector3(half_width, 0.0, near), Vector3(half_width, 0.0, far), Vector3(-half_width, 0.0, far), Palette.ZONE_WATER[zone - 1], Vector3.UP)
	add_child(LowPoly.instance(lp.build(), LowPoly.unshaded_material()))

	# 每区两侧各一个带编号的浮标。越远的字做得越大，在屏幕上看起来差不多大。
	var buoys := LowPoly.new()
	var view_origin := FISHING_CAM_POS
	for zone in range(1, Content.ZONE_COUNT + 1):
		var mid := PIER_END_Z - (Rules.zone_near_edge(zone) + Rules.zone_far_edge(zone)) * 0.5
		for side: float in [-1.0, 1.0]:
			var at := Vector3(side * (half_width - 1.3), 0.0, mid)
			buoys.prism(at, 0.42, 0.42, 0.3, 6, Color("ff5a3c"))
			buoys.prism(at + Vector3(0.0, 0.3, 0.0), 0.42, 0.12, 0.45, 6, Color("ffffff"))
			var label := Label3D.new()
			label.font = UiKit.font()
			label.text = "%d区" % zone
			label.font_size = 64
			label.outline_size = 18
			label.outline_modulate = Color("14306b")
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.shaded = false
			# 让字在钓鱼机位里约 22 像素高（按 720 高、视角 50° 估算）。
			var distance := view_origin.distance_to(at)
			label.pixel_size = distance / 772.0 * 22.0 / 64.0
			label.position = at + Vector3(0.0, 0.9 + distance * 0.02, 0.0)
			add_child(label)
	add_child(LowPoly.instance(buoys.build()))


func _build_pier() -> void:
	var lp := LowPoly.new()
	var plank := 0.5
	var z := PIER_END_Z
	var i := 0
	while z < PIER_LAND_Z:
		# 钓鱼点的几块板刷成亮黄色：站上去就能钓。
		var wood := Color("ffd166") if z + plank <= FISHING_SPOT_Z + 0.01 else Palette.WOOD
		var shade := wood if i % 2 == 0 else wood.darkened(0.1)
		lp.box(Vector3(0.0, PIER_TOP_Y - 0.08, z + plank * 0.5), Vector3(PIER_HALF_WIDTH * 2.0, 0.16, plank - 0.03), shade)
		z += plank
		i += 1
	# 靠岸一头的斜坡，从码头板下到地面。
	var run := PIER_RAMP_Z - PIER_LAND_Z
	var drop := PIER_TOP_Y - GROUND_Y
	lp.xf = Transform3D(Basis(Vector3.RIGHT, atan2(drop, run)), Vector3(0.0, (PIER_TOP_Y + GROUND_Y) * 0.5 - 0.08, (PIER_LAND_Z + PIER_RAMP_Z) * 0.5))
	lp.box(Vector3.ZERO, Vector3(PIER_HALF_WIDTH * 2.0, 0.16, sqrt(run * run + drop * drop) + 0.1), Palette.WOOD.darkened(0.1))
	lp.xf = Transform3D.IDENTITY
	for post_z: float in [PIER_END_Z + 0.2, PIER_END_Z + 2.9, PIER_END_Z + 5.6]:
		for side: float in [-1.0, 1.0]:
			lp.prism(Vector3(side * 1.55, -1.2, post_z), 0.16, 0.16, 2.3, 6, Palette.WOOD_DARK)
	add_child(LowPoly.instance(lp.build()))


func _build_gym() -> void:
	var lp := LowPoly.new()
	var c := GYM_CENTER
	lp.box(c + Vector3(0.0, 0.03, 0.0), Vector3(9.0, 0.06, 6.0), Color("ffd166"))
	lp.box(c + Vector3(0.0, 0.07, 0.7), Vector3(3.0, 0.04, 2.2), Color("ef476f"))
	lp.box(c + Vector3(0.0, 1.6, -2.85), Vector3(9.0, 3.2, 0.3), Color("4cc9f0"))
	lp.box(c + Vector3(0.0, 3.35, -2.85), Vector3(9.4, 0.3, 0.5), Color("1f2a44"))
	# 哑铃架：四档哑铃按稀有度颜色排开。
	lp.box(c + Vector3(0.0, 0.45, -2.2), Vector3(5.2, 0.12, 0.7), Palette.WOOD)
	for side: float in [-1.0, 1.0]:
		lp.box(c + Vector3(side * 2.4, 0.2, -2.2), Vector3(0.14, 0.4, 0.6), Palette.WOOD_DARK)
	for tier in Content.tier_count():
		var at := c + Vector3(-1.8 + tier * 1.2, 0.66, -2.2)
		lp.box(at, Vector3(0.7, 0.07, 0.07), Color("3a4150"))
		lp.xf = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), at)
		for side: float in [-1.0, 1.0]:
			lp.prism(Vector3(0.0, side * 0.3 - 0.07, 0.0), 0.2, 0.2, 0.14, 6, Palette.RARITY[tier], Palette.RARITY[tier].darkened(0.2))
		lp.xf = Transform3D.IDENTITY
	add_child(LowPoly.instance(lp.build()))
	_add_sign("健身房", c + Vector3(0.0, 2.55, -2.68), 0.011)


func _build_display() -> void:
	var lp := LowPoly.new()
	var c := DISPLAY_CENTER
	# 地垫一直铺到台前的空地：站在垫子上就能管理展示台。
	var mat_back := -1.2
	lp.box(c + Vector3(0.0, 0.03, (mat_back + DISPLAY_FRONT_Z) * 0.5), Vector3(DISPLAY_HALF_WIDTH * 2.0, 0.06, DISPLAY_FRONT_Z - mat_back), Color("ffe9b0"))
	add_child(LowPoly.instance(lp.build()))

	for i in Content.STAND_COUNT:
		var stand := DisplayStand.new()
		stand.index = i
		stand.position = Vector3(stand_x(i), c.y + 0.06, c.z)
		add_child(stand)
		stands.append(stand)

	# 一个悬在台子上方的黄色箭头，指着此刻正对着的那个台子。
	var arrow := LowPoly.new()
	arrow.prism(Vector3.ZERO, 0.0, 0.3, 0.45, 4, Color("ffd23f"), Color("ffe98a"))
	_stand_marker = LowPoly.instance(arrow.build(), LowPoly.unshaded_material())
	_stand_marker.visible = false
	add_child(_stand_marker)


func _build_fishing_props() -> void:
	var bob := LowPoly.new()
	bob.prism(Vector3(0.0, -0.2, 0.0), 0.0, 0.24, 0.2, 6, Color("ffffff"))
	bob.prism(Vector3(0.0, 0.0, 0.0), 0.24, 0.0, 0.3, 6, Color("ff3b3b"))
	_bobber = LowPoly.instance(bob.build(), LowPoly.unshaded_material())
	_bobber.visible = false
	add_child(_bobber)

	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.05, 0.05, 1.0)
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color("ffffff")
	_line = MeshInstance3D.new()
	_line.mesh = line_mesh
	_line.material_override = line_material
	_line.visible = false
	add_child(_line)

	_target_fish = LowPoly.instance(null)
	_target_fish.visible = false
	add_child(_target_fish)

	_giant = LowPoly.instance(FishModels.giant_mesh())
	_giant.visible = false
	add_child(_giant)

	var ring := LowPoly.new()
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		ring.quad(d0 * 0.75, d1 * 0.75, d1, d0, Color("ffffff"), Vector3.UP)
	_ripple = LowPoly.instance(ring.build(), LowPoly.unshaded_material())
	_ripple.visible = false
	add_child(_ripple)


func _add_sign(text: String, at: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.font = UiKit.font()
	label.text = text
	label.font_size = 96
	label.pixel_size = pixel_size
	label.outline_size = 24
	label.outline_modulate = Color("1f2a44")
	label.shaded = false
	label.position = at
	add_child(label)
