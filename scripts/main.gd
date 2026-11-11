extends Node
## 游戏入口：把场景、界面、钓鱼流程和举重接到一起，并负责「下一步」提示。
##
## 角色自由走动：左下角摇杆，或键盘的 WASD / 方向键。走到哪里就能做那里的事：
##   - 码头尽头（黄色木板）：右下角的键是钓鱼；
##   - 健身房的地垫上：右下角的键是买哑铃；
##   - 展示台前的地垫上：右下角的键管理正对着的那个台子，直接点台子也行；
##   - 举重在哪儿都能做，有单独的「举重」键。
## 这些都是临时方案：设计文档没有规定角色怎么移动、各处怎么触发。

var world: World
var hud: Hud
var panels: Panels
var fishing: FishingController
var gym: GymController

var _dumbbell_seen := -1


func _ready() -> void:
	world = World.new()
	add_child(world)
	fishing = FishingController.new()
	add_child(fishing)
	gym = GymController.new()
	add_child(gym)
	hud = Hud.new()
	add_child(hud)
	panels = Panels.new()
	hud.root.add_child(panels)

	hud.action_down.connect(on_action_down)
	hud.action_up.connect(on_action_up)
	hud.lift_pressed.connect(on_lift)
	hud.menu_pressed.connect(panels.open)
	panels.opened.connect(_refresh_ui)
	panels.closed.connect(_refresh_ui)

	world.spot_changed.connect(_on_spot_changed)
	world.near_stand_changed.connect(_on_spot_changed)

	fishing.state_changed.connect(_on_fishing_state)
	fishing.charge_changed.connect(_on_charge)
	fishing.cast_thrown.connect(_on_cast)
	fishing.wheel_started.connect(_on_wheel)
	fishing.reel_started.connect(_on_reel_started)
	fishing.reel_progress.connect(_on_reel_progress)
	fishing.reel_tapped.connect(world.reel_kick)
	fishing.finished.connect(_on_finished)
	fishing.blocked.connect(hud.toast)

	gym.lift_started.connect(world.begin_lift)
	gym.lift_progress.connect(world.set_lift_phase)
	gym.lift_done.connect(_on_lift_done)
	gym.lift_cancelled.connect(world.end_lift)
	gym.blocked.connect(_on_gym_blocked)

	GameState.changed.connect(_on_state_changed)
	GameState.offline_settled.connect(_on_offline)
	_dumbbell_seen = GameState.dumbbell
	_refresh_ui()

	# 开发用：带 --shots=目录 启动时自动巡场截图。导出包里不含这个脚本。
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots=") and ResourceLoader.exists("res://tests/shot_tour.gd"):
			var tour: Node = load("res://tests/shot_tour.gd").new()
			tour.set("out_dir", arg.trim_prefix("--shots="))
			add_child(tour)


func _process(_delta: float) -> void:
	# 开着面板时不走动。摇杆和键盘可以同时用，合起来不超过全速。
	var push := Vector2.ZERO
	if not panels.is_open():
		push = (hud.move_vector() + _keyboard_vector()).limit_length(1.0)
	world.move_input = push


func _keyboard_vector() -> Vector2:
	var push := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		push.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		push.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		push.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		push.y += 1.0
	return push


func _unhandled_input(event: InputEvent) -> void:
	if panels.is_open():
		return
	# 电脑上：空格是右下角那个键；眼下没有那个键时，空格就是举重。F 键随时举重。
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			if event.pressed:
				if _has_action():
					on_action_down()
				else:
					on_lift()
			else:
				on_action_up()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and event.pressed:
			on_lift()
			get_viewport().set_input_as_handled()
		return
	# 站在展示台前：除了右下角的键，直接点哪个台子也能管哪个台子。
	# 手指直接认触摸（第二根手指不会被模拟成鼠标），鼠标只认真鼠标，免得一次点击算两次。
	var tapped := false
	if event is InputEventScreenTouch:
		tapped = event.pressed
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if tapped and world.spot == World.Spot.DISPLAY and world.is_free() and fishing.is_idle():
		var stand := world.pick_stand(event.position)
		if stand >= 0:
			panels.open_stand(stand)
			get_viewport().set_input_as_handled()


# ── 右下角的键 ─────────────────────────────────────────────────────

## 眼下右下角有没有「这里能做的事」那个键。
func _has_action() -> bool:
	return not fishing.is_idle() or world.spot != World.Spot.NONE


func on_action_down() -> void:
	if panels.is_open() or gym.is_lifting():
		return
	if not fishing.is_idle() or world.spot == World.Spot.FISHING:
		fishing.press()
	elif world.spot == World.Spot.SHOP:
		panels.open("dumbbells")
	elif world.spot == World.Spot.DISPLAY and world.near_stand >= 0:
		panels.open_stand(world.near_stand)


func on_action_up() -> void:
	fishing.release()


## 举重：在哪儿都能举，但一竿进行中不行。
func on_lift() -> void:
	if panels.is_open() or not fishing.is_idle():
		return
	gym.lift()


# ── 钓鱼 ───────────────────────────────────────────────────────────

func _on_fishing_state(state: int) -> void:
	if state == FishingController.State.IDLE:
		world.end_fishing()
	else:
		world.begin_fishing()
	_refresh_ui()


func _on_charge(value: float) -> void:
	hud.set_charge(value)
	world.set_charge(value)


func _on_cast(info: Dictionary) -> void:
	var distance: float = info["distance"]
	var lateral: float = info["lateral"]
	world.play_cast(distance, lateral, Balance.CAST_FLIGHT_TIME)
	var quality: float = info["quality"]
	if quality >= 0.9:
		hud.float_text("完美出手！", Color("ffe14d"))
	elif quality >= 0.6:
		hud.float_text("出手不错", Color("ffffff"))


func _on_wheel(info: Dictionary) -> void:
	var stop_offset: float = info["stop_offset"]
	hud.show_wheel(info, Balance.WHEEL_SPIN_TIME, stop_offset)


func _on_reel_started(species_id: String) -> void:
	hud.begin_chase(species_id)
	world.begin_reel(species_id)


func _on_reel_progress(fish: float, giant: float) -> void:
	hud.update_chase(fish, giant)
	world.update_reel(fish, giant)


func _on_finished(success: bool, species_id: String, is_new: bool) -> void:
	world.finish_reel(success)
	hud.show_result(success, species_id, is_new)


# ── 举重 ───────────────────────────────────────────────────────────

func _on_lift_done(gain: int) -> void:
	world.end_lift()
	if gain > 0:
		hud.float_text("力量 +%d" % gain, Color("9dffb0"))
	else:
		hud.toast("力量已经到上限了")


func _on_gym_blocked(_reason: String) -> void:
	# 还没有哑铃。正站在健身房就直接打开货架，否则告诉玩家去哪儿买。
	if world.spot == World.Spot.SHOP:
		panels.open("dumbbells")
	else:
		hud.toast("还没有哑铃：走到健身房去买一个")


# ── 存档变化与提示 ─────────────────────────────────────────────────

func _on_spot_changed(_spot: int) -> void:
	_refresh_ui()


func _on_state_changed() -> void:
	# 举到一半换了哑铃：这一次作废。
	if GameState.dumbbell != _dumbbell_seen:
		_dumbbell_seen = GameState.dumbbell
		gym.cancel()
	_refresh_ui()


func _on_offline(seconds: float, gold: float) -> void:
	# 钓鱼进行中不打断，只给一条短提示；金币已经到账。
	if fishing.is_idle() and not panels.is_open():
		panels.open_offline(seconds, gold)
	else:
		hud.toast("展示台收益 +%s 金币" % UiKit.fmt_amount(gold))


func _refresh_ui() -> void:
	hud.joystick.enabled = not panels.is_open()
	hud.set_context(world.spot, fishing.state, world.near_stand)
	hud.set_hint(_next_step_hint())


## 让玩家随时知道下一步该干什么。
func _next_step_hint() -> String:
	match fishing.state:
		FishingController.State.CHARGING:
			return "看准蓄满的一刻松手"
		FishingController.State.CASTING, FishingController.State.WHEEL:
			return "滚轮停在哪条鱼，就是哪条咬钩"
		FishingController.State.REELING:
			return "连点屏幕把鱼拖上岸，别让后面的巨鱼追上！"
		FishingController.State.RESULT:
			return ""
	match world.spot:
		World.Spot.FISHING:
			if GameState.backpack_full():
				return "背包满了：打开背包卖鱼，或去展示台上架"
			return "按住右下角蓄力，松手投竿"
		World.Spot.SHOP:
			if GameState.dumbbell < 0:
				return "点「买哑铃」挑一个，买了以后在哪儿都能举"
			return "这里可以买哑铃、换哑铃；举重在哪儿都行"
		World.Spot.DISPLAY:
			if GameState.total_income_per_second() <= 0.0:
				return "走到空台前面，点右下角把背包里的鱼摆上去赚收益"
			return "走到哪个台子前面，就能给哪个台子上架、升级或下架"
	if GameState.backpack_full():
		return "背包满了：打开背包卖鱼，或去展示台上架"
	if GameState.dumbbell < 0 and GameState.can_afford(Balance.DUMBBELL_PRICE[0]):
		return "金币够了：去健身房买哑铃，练力量才能抛得更远"
	if GameState.dumbbell >= 0 and not GameState.strength_capped():
		return "点「举重」随时练力量；走上码头尽头的黄木板钓鱼"
	return "推摇杆走动；走上码头尽头的黄木板钓鱼"
