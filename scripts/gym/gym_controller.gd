class_name GymController
extends Node
## 举重：点一次按钮做一次完整动作，动作做完才加一次力量。
##
## 已拍板：不消耗金币或体力；一次完整动作只结算一次；第一版不做自动举重
## （所以按住不放也只举一次）。
## 买了哑铃以后在哪儿都能举，不用待在健身房。
## 临时方案：动作期间再点无效、也不能走动；中途换哑铃，这一次作废、不加力量。

signal lift_started
signal lift_progress(phase: float)
## gain 是这次实际加的力量；力量已到上限时为 0。
signal lift_done(gain: int)
signal lift_cancelled
## 想举但举不了（还没有哑铃）。
signal blocked(reason: String)

var _lifting := false
var _elapsed := 0.0


func is_lifting() -> bool:
	return _lifting


func lift() -> bool:
	if _lifting:
		return false
	if GameState.dumbbell < 0:
		blocked.emit("先买一个哑铃，才能举重练力量")
		return false
	_lifting = true
	_elapsed = 0.0
	lift_started.emit()
	return true


func cancel() -> void:
	if _lifting:
		_lifting = false
		lift_cancelled.emit()


func _process(delta: float) -> void:
	if not _lifting:
		return
	_elapsed += delta
	if _elapsed < Balance.LIFT_DURATION:
		lift_progress.emit(_elapsed / Balance.LIFT_DURATION)
		return
	_lifting = false
	lift_progress.emit(0.0)
	lift_done.emit(GameState.complete_lift())
