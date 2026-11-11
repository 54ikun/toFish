class_name Joystick
extends Control
## 左下角的虚拟摇杆：按住往哪边推，角色就往哪边走。
##
## 手机上左手推摇杆的同时，右手还要点别的键，所以手指直接从触摸事件里认，
## 一根手指占住摇杆后，别的手指不受影响。电脑上可以用鼠标拖，也可以用键盘
## （键盘在 main.gd 里读）。

const RADIUS := 92.0
const KNOB_RADIUS := 42.0
## 推出去不到这个比例不算，免得手指轻轻一搭角色就挪步。
const DEAD_ZONE := 0.18
const NOBODY := -1
const MOUSE := -2

## 推的方向和力度，长度 0–1。x 向右，y 向下（屏幕方向）。
var vector := Vector2.ZERO
## 关掉以后不认手指，已经按着的也松开（开着面板时用）。
var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_let_go()

var _holder := NOBODY
var _raw := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(250.0, 250.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _holder == NOBODY and get_global_rect().has_point(event.position):
				_holder = event.index
				_aim(event.position)
				get_viewport().set_input_as_handled()
		elif event.index == _holder:
			_let_go()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _holder:
		_aim(event.position)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# 电脑上用鼠标拖。触屏顺带模拟出来的鼠标事件不算，手指已经在 _input 里认过了。
	if not enabled or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _holder == NOBODY:
			_holder = MOUSE
			_aim(event.global_position)
		elif not event.pressed and _holder == MOUSE:
			_let_go()
	elif event is InputEventMouseMotion and _holder == MOUSE:
		_aim(event.global_position)


func _notification(what: int) -> void:
	# 被藏起来或窗口失去焦点时收不到松手，直接当作松开。
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_let_go()


func _aim(at: Vector2) -> void:
	_raw = ((at - get_global_rect().get_center()) / RADIUS).limit_length(1.0)
	vector = _raw if _raw.length() >= DEAD_ZONE else Vector2.ZERO
	queue_redraw()


func _let_go() -> void:
	_holder = NOBODY
	_raw = Vector2.ZERO
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, RADIUS + 6.0, Color(Palette.INK, 0.4))
	draw_circle(center, RADIUS, Color(1.0, 1.0, 1.0, 0.3))
	var knob := center + _raw * (RADIUS - KNOB_RADIUS * 0.5)
	draw_circle(knob, KNOB_RADIUS + 5.0, Color(Palette.INK, 0.7))
	draw_circle(knob, KNOB_RADIUS, Color(1.0, 1.0, 1.0, 0.95))
