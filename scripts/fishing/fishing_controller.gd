class_name FishingController
extends Node
## 一竿的完整流程：蓄力 → 投竿 → 转盘选鱼 → 追逐收线 → 结果。
##
## 这里只管规则和节奏，不碰画面；画面和界面靠信号跟着走。
## 对外只有三个动作：press（按下）、release（松手）、tap（收线时点一下）。
## 以后要接自动钓鱼，由别的驱动者调这三个动作即可。
##
## 已拍板的规则：
##   - 力量决定最大抛距；出手时机主要影响运气，对距离只做小幅修正；
##   - 转盘转到哪种鱼，就由哪种鱼咬钩，但转中不等于捕获；
##   - 连点把鱼拖上岸才算捕获并登记图鉴；先被巨鱼追上，本竿失败，鱼不入包、不登记。
## 其余细节（转盘自动停、巨鱼与收线同时开始、同时到达算玩家赢、满包不能投竿等）
## 都是临时方案，对应的数值在 Balance。

signal state_changed(state: int)
signal charge_changed(value: float)
## 竿甩出去了。info 含 distance、lateral、zone、quality、luck、entries、index。
signal cast_thrown(info: Dictionary)
signal wheel_started(info: Dictionary)
signal reel_started(species_id: String)
signal reel_progress(fish: float, giant: float)
signal reel_tapped
signal finished(success: bool, species_id: String, is_new: bool)
## 想投竿但被拦下了（比如背包满），reason 是给玩家看的话。
signal blocked(reason: String)

enum State { IDLE, CHARGING, CASTING, WHEEL, REELING, RESULT }

var state := State.IDLE
var rng := RandomNumberGenerator.new()

var _charge_time := 0.0
var _charge := 0.0
var _timer := 0.0
var _cast: Dictionary = {}
var _target := ""
var _fish_pos := 0.0
var _giant_pos := 0.0
var _tap_gain := 0.0
var _result_age := 0.0


func _ready() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	match state:
		State.CHARGING:
			_charge_time += delta
			# 三角波：涨到满再落回空，循环往复。
			var t := fposmod(_charge_time / (Balance.CHARGE_PERIOD * 0.5), 2.0)
			_charge = t if t <= 1.0 else 2.0 - t
			charge_changed.emit(_charge)
		State.CASTING:
			_timer -= delta
			if _timer <= 0.0:
				_timer = Balance.WHEEL_SPIN_TIME + Balance.WHEEL_HOLD_TIME
				_set_state(State.WHEEL)
				wheel_started.emit(_cast)
		State.WHEEL:
			_timer -= delta
			if _timer <= 0.0:
				_begin_reel()
		State.REELING:
			# 单帧步长有上限：切到后台再回来时追逐等于暂停，不会瞬间判负。
			_giant_pos += Balance.CHASE_SPEED * minf(delta, Balance.CHASE_MAX_STEP)
			reel_progress.emit(_fish_pos, _giant_pos)
			if _giant_pos >= _fish_pos:
				_finish(false)
		State.RESULT:
			_result_age += delta
			_timer -= delta
			if _timer <= 0.0:
				_set_state(State.IDLE)


func _input(event: InputEvent) -> void:
	# 收线阶段整个屏幕都是按键：任何一次按下都算一下，鼠标、触屏、空格都行。
	if state != State.REELING:
		return
	var hit := false
	if event is InputEventScreenTouch:
		hit = event.pressed
	elif event is InputEventMouseButton:
		# 触屏会顺带模拟出一次鼠标点击，那一次不能重复计数。
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			hit = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		hit = event.pressed and not event.echo and event.keycode == KEY_SPACE
	else:
		return
	get_viewport().set_input_as_handled()
	if hit:
		tap()


func _notification(what: int) -> void:
	# 蓄力时窗口失去焦点，就收不到松手了：直接取消这次蓄力。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_charge()


func is_idle() -> bool:
	return state == State.IDLE


## 按下：开始蓄力。
func press() -> void:
	if state == State.RESULT and _result_age >= Balance.RESULT_INPUT_LOCK:
		_set_state(State.IDLE)  # 不想等结果横幅，直接开下一竿
	if state != State.IDLE:
		return
	if GameState.backpack_full():
		blocked.emit("背包满了，先去卖鱼或上架再钓")
		return
	_charge_time = 0.0
	_charge = 0.0
	_set_state(State.CHARGING)
	charge_changed.emit(_charge)


## 松手：按此刻的蓄力程度出手，同时定下落点和转盘结果。
func release() -> void:
	if state != State.CHARGING:
		return
	var quality := _charge
	var distance := Rules.cast_distance(GameState.strength, quality, rng.randf(), rng.randf())
	var zone := Rules.zone_at(distance)
	var luck := Rules.cast_luck(quality, GameState.rod, GameState.extra_luck())
	var entries := Rules.wheel_entries(zone, luck)
	var index := Rules.pick_entry(entries, rng.randf())
	_target = entries[index]["species"]
	_cast = {
		"distance": distance,
		"lateral": rng.randf_range(-Balance.CAST_LATERAL_SPREAD, Balance.CAST_LATERAL_SPREAD),
		"zone": zone,
		"quality": quality,
		"luck": luck,
		"entries": entries,
		"index": index,
		"stop_offset": rng.randf(),
	}
	_timer = Balance.CAST_FLIGHT_TIME
	_set_state(State.CASTING)
	cast_thrown.emit(_cast)


func cancel_charge() -> void:
	if state == State.CHARGING:
		_set_state(State.IDLE)


## 收线时点一下：把鱼往岸边拖一截。
func tap() -> void:
	if state != State.REELING:
		return
	_fish_pos = minf(_fish_pos + _tap_gain, 1.0)
	reel_tapped.emit()
	reel_progress.emit(_fish_pos, _giant_pos)
	# 先判上岸：鱼和巨鱼同时到，算玩家赢。
	if _fish_pos >= 1.0:
		_finish(true)


func _begin_reel() -> void:
	_fish_pos = 0.0
	_giant_pos = -Balance.CHASE_GAP
	_tap_gain = Rules.tap_gain(GameState.rod, Content.fish_rarity(_target))
	_set_state(State.REELING)
	reel_started.emit(_target)
	reel_progress.emit(_fish_pos, _giant_pos)


func _finish(success: bool) -> void:
	var is_new := false
	if success:
		is_new = not GameState.is_registered(_target)
		GameState.catch_fish(_target)
	_timer = Balance.RESULT_TIME
	_result_age = 0.0
	_set_state(State.RESULT)
	finished.emit(success, _target, is_new)


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(state)
