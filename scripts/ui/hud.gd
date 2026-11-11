class_name Hud
extends CanvasLayer
## 常驻界面：金币与力量、功能按钮、摇杆、右下角的操作键，以及钓鱼过程中的
## 蓄力条、选鱼滚轮、追逐条和结果横幅。
##
## 手机横屏为主：左手拇指推摇杆走动，右手拇指点右下角的键；中间留给画面。
## 第一版没有鱼饵、内购和自动钓鱼，所以这里没有对应的栏位和入口。

signal action_down
signal action_up
signal lift_pressed
signal menu_pressed(which: String)

## 四边留白。网页默认不让页面伸进刘海和圆角区域，这里再留一点余量。
const EDGE_MARGIN := 20

var root: Control
var joystick: Joystick

var _area: Control
var _gold: Label
var _strength: Label
var _reach: Label
var _menu: HBoxContainer
var _backpack_button: Button
var _codex_button: Button
var _action: Button
var _lift: Button
var _hint: Label
var _charge: ChargeMeter
var _chase: ChaseBar
var _wheel_panel: PanelContainer
var _wheel: FishReel
var _wheel_title: Label
var _wheel_result: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _toast: Label
var _toast_tween: Tween
var _rotate_notice: ColorRect
var _poll := 0.0
var _wheel_entries: Array[Dictionary] = []
var _wheel_index := -1
var _last_press := {}


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.theme = UiKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe := MarginContainer.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe.add_theme_constant_override(side, EDGE_MARGIN)
	root.add_child(safe)
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area = Control.new()
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(_area)

	_build_status()
	_build_menu()
	_build_joystick()
	_build_action()
	_build_overlays()
	_build_rotate_notice()

	GameState.changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	# 金币会被展示收益一点点推高，定时轮询即可，不必每帧刷。
	_poll += delta
	if _poll >= 0.2:
		_poll = 0.0
		_gold.text = UiKit.fmt_gold(GameState.gold)
	var size := root.get_viewport_rect().size
	_rotate_notice.visible = size.y > size.x * 1.05


## 摇杆此刻推向哪边，长度 0–1。x 向右，y 向下。
func move_vector() -> Vector2:
	return joystick.vector if joystick.visible else Vector2.ZERO


# ── 搭界面 ─────────────────────────────────────────────────────────

func _build_status() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(row, Control.PRESET_TOP_LEFT)

	var gold_pill := _pill()
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 10)
	gold_row.add_child(UiKit.label("金币", 22, Palette.GOLD_DARK))
	_gold = UiKit.label("0", 30)
	gold_row.add_child(_gold)
	gold_pill.add_child(gold_row)
	row.add_child(gold_pill)

	var power_pill := _pill()
	var power_box := VBoxContainer.new()
	power_box.add_theme_constant_override("separation", -4)
	_strength = UiKit.label("", 24)
	_reach = UiKit.label("", 18, Palette.SECONDARY_DARK)
	power_box.add_child(_strength)
	power_box.add_child(_reach)
	power_pill.add_child(power_box)
	row.add_child(power_pill)

	_hint = UiKit.outlined_label("", 26)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_hint, Control.PRESET_CENTER_TOP, Vector2(0.0, 92.0))


func _build_menu() -> void:
	_menu = HBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	_pin(_menu, Control.PRESET_TOP_RIGHT)
	_backpack_button = UiKit.button("背包", "secondary", Vector2(170, 76))
	_backpack_button.pressed.connect(menu_pressed.emit.bind("backpack"))
	_menu.add_child(_backpack_button)
	_codex_button = UiKit.button("图鉴", "secondary", Vector2(170, 76))
	_codex_button.pressed.connect(menu_pressed.emit.bind("codex"))
	_menu.add_child(_codex_button)
	var rods := UiKit.button("鱼竿", "secondary", Vector2(120, 76))
	rods.pressed.connect(menu_pressed.emit.bind("rods"))
	_menu.add_child(rods)


func _build_joystick() -> void:
	joystick = Joystick.new()
	_pin(joystick, Control.PRESET_BOTTOM_LEFT)


func _build_action() -> void:
	# 右下角一排两个键：左边是随时能点的举重，右边是眼下这个地方能做的事。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(row, Control.PRESET_BOTTOM_RIGHT)
	_lift = UiKit.button("举重", "green", Vector2(170, 160), 34)
	row.add_child(_lift)
	_action = UiKit.button("", "primary", Vector2(230, 160), 38)
	row.add_child(_action)
	_listen(_lift, "lift")
	_listen(_action, "action")


## 让一个键同时认鼠标和每一根手指。
## 引擎只把第一根手指当成鼠标：左手按着摇杆时，右手是第二根手指，普通按钮收不到。
func _listen(button: Button, key: String) -> void:
	button.button_down.connect(_press.bind(key, true))
	button.button_up.connect(_press.bind(key, false))
	button.gui_input.connect(_on_button_touch.bind(button, key))


func _on_button_touch(event: InputEvent, button: Button, key: String) -> void:
	if event is InputEventScreenTouch and not button.disabled:
		_press(key, event.pressed)


func _press(key: String, down: bool) -> void:
	# 第一根手指既算触摸又算鼠标，会连报两次；同一帧里只认一次。
	var stamp := "%s:%s" % [key, down]
	var frame := Engine.get_process_frames()
	if _last_press.get(stamp, -1) == frame:
		return
	_last_press[stamp] = frame
	match key:
		"action":
			if down:
				action_down.emit()
			else:
				action_up.emit()
		"lift":
			if down:
				lift_pressed.emit()


func _build_overlays() -> void:
	# 蓄力条放在角色头顶上方，不盖住人。
	_charge = ChargeMeter.new()
	_pin(_charge, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -190.0))
	_charge.visible = false

	_chase = ChaseBar.new()
	_pin(_chase, Control.PRESET_CENTER_TOP, Vector2(0.0, 136.0))
	_chase.visible = false

	# 选鱼滚轮：上面写落点，中间是滚轮，下面报结果。
	_wheel_panel = PanelContainer.new()
	_wheel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_wheel_panel, Control.PRESET_CENTER, Vector2(0.0, 40.0))
	var wheel_box := VBoxContainer.new()
	wheel_box.add_theme_constant_override("separation", 8)
	_wheel_panel.add_child(wheel_box)
	_wheel_title = UiKit.label("", 26)
	_wheel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel_box.add_child(_wheel_title)
	_wheel = FishReel.new()
	_wheel.stopped.connect(_on_wheel_stopped)
	wheel_box.add_child(_wheel)
	_wheel_result = UiKit.label("", 30, Palette.PRIMARY_DARK)
	_wheel_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wheel_result.custom_minimum_size = Vector2(0, 44)
	wheel_box.add_child(_wheel_result)
	_wheel_panel.visible = false

	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_banner, Control.PRESET_CENTER, Vector2(0.0, -70.0))
	var banner_box := VBoxContainer.new()
	banner_box.add_theme_constant_override("separation", 2)
	_banner.add_child(banner_box)
	_banner_title = UiKit.label("", 44)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.custom_minimum_size = Vector2(460, 0)
	banner_box.add_child(_banner_title)
	_banner_sub = UiKit.label("", 26)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(_banner_sub)
	_banner.visible = false

	_toast = UiKit.outlined_label("", 28, Color("fff3b0"))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_toast, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -300.0))
	_toast.visible = false


func _build_rotate_notice() -> void:
	# 手机以横屏为主：竖着拿的时候请玩家把手机横过来。
	_rotate_notice = ColorRect.new()
	_rotate_notice.color = Color("1f2a44")
	root.add_child(_rotate_notice)
	_rotate_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var text := UiKit.label("请把手机横过来玩", 44, Color("ffffff"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rotate_notice.add_child(text)
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rotate_notice.visible = false


## 把控件钉在安全区的某个角或某条边上，内容变多时朝屏幕里面长。
func _pin(node: Control, preset: Control.LayoutPreset, offset: Vector2 = Vector2.ZERO) -> void:
	_area.add_child(node)
	node.set_anchors_preset(preset)
	match preset:
		Control.PRESET_TOP_RIGHT:
			node.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			node.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			node.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			node.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			node.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_BOTTOM:
			node.grow_horizontal = Control.GROW_DIRECTION_BOTH
			node.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER:
			node.grow_horizontal = Control.GROW_DIRECTION_BOTH
			node.grow_vertical = Control.GROW_DIRECTION_BOTH
	node.offset_left = offset.x
	node.offset_right = offset.x
	node.offset_top = offset.y
	node.offset_bottom = offset.y


func _pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiKit.box(Color(1.0, 0.97, 0.9, 0.94), Palette.INK, 22, 4, 10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	pill.add_theme_stylebox_override("panel", style)
	pill.custom_minimum_size = Vector2(0, 76)
	return pill


# ── 刷新 ───────────────────────────────────────────────────────────

func refresh() -> void:
	_gold.text = UiKit.fmt_gold(GameState.gold)
	var cap_note := "（已到上限）" if GameState.strength_capped() else ""
	_strength.text = "力量 %s%s" % [UiKit.fmt_int(GameState.strength), cap_note]
	var reach := Rules.max_cast_distance(GameState.strength)
	_reach.text = "最远 %.1f 米 · 够得到 %d 区" % [reach, Rules.farthest_zone(GameState.strength)]
	_backpack_button.text = "背包 %d/%d" % [GameState.backpack.size(), Balance.BACKPACK_CAPACITY]
	UiKit.style_button(_backpack_button, "danger" if GameState.backpack_full() else "secondary")
	_codex_button.text = "图鉴 %d/%d" % [GameState.codex_count(), Content.FISH.size()]
	# 举重键：有哑铃时写明举一次加多少；没有时是灰的，点了会提示去买。
	if GameState.dumbbell >= 0:
		_lift.text = "举重\n力量 +%d" % Balance.LIFT_GAIN[GameState.dumbbell]
		UiKit.style_button(_lift, "green")
	else:
		_lift.text = "举重"
		UiKit.style_button(_lift, "grey")


## 按角色站的地方和钓鱼阶段，决定哪些键出现、右下角的键写什么。
## 一竿进行中收起其他键，免得连点收线时误触。
## near_stand 是站在展示台前时正对着的台子（0 起），不在台前是 -1。
func set_context(spot: int, fishing_state: int, near_stand: int) -> void:
	var idle := fishing_state == FishingController.State.IDLE
	_menu.visible = idle
	joystick.visible = idle
	_lift.visible = idle

	var fishing_here := not idle or spot == World.Spot.FISHING
	var at_stand := spot == World.Spot.DISPLAY and near_stand >= 0
	_action.visible = fishing_here or spot == World.Spot.SHOP or at_stand
	var kind := "primary"
	if not fishing_here:
		kind = "secondary"
		if at_stand:
			var verb := "上架" if GameState.stand_fish(near_stand) == null else "管理"
			_action.text = "%d 号台\n%s" % [near_stand + 1, verb]
		else:
			_action.text = "买哑铃"
	else:
		match fishing_state:
			FishingController.State.CHARGING:
				_action.text = "松手\n投竿"
			FishingController.State.CASTING, FishingController.State.WHEEL:
				_action.text = "等鱼\n咬钩"
				kind = "grey"
			FishingController.State.REELING:
				_action.text = "连点\n收线"
				kind = "danger"
			_:
				_action.text = "按住\n蓄力"
	UiKit.style_button(_action, kind)

	_charge.visible = fishing_state == FishingController.State.CHARGING
	_chase.visible = fishing_state == FishingController.State.REELING
	if fishing_state != FishingController.State.WHEEL:
		_wheel_panel.visible = false
	if fishing_state != FishingController.State.RESULT:
		_banner.visible = false


func set_hint(text: String) -> void:
	_hint.text = text


func set_charge(value: float) -> void:
	_charge.value = value


## 浮标落水后亮出选鱼滚轮并开滚。info 是这一竿的数据，index 是已经定下的结果。
func show_wheel(info: Dictionary, spin_time: float, stop_offset: float) -> void:
	var raw: Array = info["entries"]
	_wheel_entries.assign(raw)
	_wheel_index = info["index"]
	var zone: int = info["zone"]
	var distance: float = info["distance"]
	_wheel_title.text = "抛出 %.1f 米 · 落在 %d 区" % [distance, zone]
	_wheel_result.text = "会是哪条鱼？"
	_wheel.setup(_wheel_entries, int(stop_offset * 1000000.0))
	_wheel_panel.visible = true
	_wheel.spin_to(_wheel_index, spin_time, stop_offset)


func _on_wheel_stopped() -> void:
	if _wheel_index < 0 or _wheel_index >= _wheel_entries.size():
		return
	var species_id: String = _wheel_entries[_wheel_index]["species"]
	_wheel_result.text = "%s 咬钩了！" % Content.fish_name(species_id)


func begin_chase(species_id: String) -> void:
	_chase.begin(species_id)


func update_chase(fish: float, giant: float) -> void:
	_chase.set_progress(fish, giant)


func show_result(success: bool, species_id: String, is_new: bool) -> void:
	var rarity := Content.fish_rarity(species_id)
	if success:
		_banner_title.text = "钓到 %s！" % Content.fish_name(species_id)
		_banner_title.add_theme_color_override("font_color", Palette.RARITY_TEXT[rarity])
		var note := "新登记图鉴 · " if is_new else ""
		_banner_sub.text = "%s%s · 已放进背包 %d/%d" % [note, Content.RARITY_NAMES[rarity], GameState.backpack.size(), Balance.BACKPACK_CAPACITY]
	else:
		_banner_title.text = "被巨鱼吃掉了…"
		_banner_title.add_theme_color_override("font_color", Palette.DANGER)
		_banner_sub.text = "%s没能上岸，下一竿点快一点" % Content.fish_name(species_id)
	_banner.visible = true


## 屏幕下方一闪而过的短提示。
func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_toast.hide)


## 从屏幕中间往上飘的字，比如「力量 +1」。
func float_text(text: String, color: Color = Color("ffffff")) -> void:
	var node := UiKit.outlined_label(text, 44, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(node, Control.PRESET_CENTER, Vector2(0.0, -150.0))
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "offset_top", -240.0, 0.7)
	tween.tween_property(node, "offset_bottom", -240.0, 0.7)
	tween.tween_property(node, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)
