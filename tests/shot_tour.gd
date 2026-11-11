extends Node
## 开发用的截图巡场：自动把各个画面走一遍并存成 PNG，用来检查画面和排版。
## 需要真实窗口（无头模式不渲染）。在项目根目录运行：
##   godot --path . --resolution 1280x720 -- --no-save --shots=shots/desktop
## 这个脚本不进导出包。

var out_dir := "shots"

var _main: Node


func _ready() -> void:
	_main = get_parent()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))
	_run.call_deferred()


func _run() -> void:
	var fishing: FishingController = _main.fishing
	var world: World = _main.world
	var panels: Panels = _main.panels
	var gym: GymController = _main.gym

	# 摆一个玩到中期的存档，画面上才有东西可看。
	GameState.reset()
	GameState.add_gold(52340.0)
	GameState.strength = 2600
	GameState.owned_rods = [0, 1]
	GameState.rod = 1
	GameState.owned_dumbbells = [0, 1]
	GameState.dumbbell = 1
	for species: String in ["matou_tiao", "shifeng_hu", "huayi_ji", "lanyao_nian", "qingtai_qiu", "tiaolang_bai", "pushan_bian", "huanggu_lang", "wandao_bo", "guyan_qing", "yueya_ji", "xuelin_fang"]:
		GameState.catch_fish(species)
	var shown := ["xuelin_fang", "yueya_ji", "guyan_qing", "pushan_bian", "wandao_bo", "huayi_ji"]
	for i in shown.size():
		for fish in GameState.backpack:
			if fish["species"] == shown[i]:
				GameState.place_on_stand(i, fish["uid"])
				break
	GameState.stands[0]["level"] = 10
	GameState.stands[1]["level"] = 3
	GameState.stands[0]["earned"] = 18234.0
	GameState.stands[1]["earned"] = 42.7
	GameState.changed.emit()

	await _wait(0.4)
	await _shot("01_fishing_spot")

	_main.on_action_down()
	await _wait(0.62)
	await _shot("02_charge")
	_main.on_action_up()
	await _wait(0.3)
	await _shot("03_cast")
	await _until(func() -> bool: return fishing.state == FishingController.State.WHEEL)
	await _wait(0.35)
	await _shot("04_reel_rolling")
	await _wait(0.5)
	await _shot("05_reel_slowing")
	await _wait(Balance.WHEEL_SPIN_TIME - 0.75)
	await _shot("06_reel_stopped")
	await _until(func() -> bool: return fishing.state == FishingController.State.REELING)
	for i in 3:
		fishing.tap()
	await _wait(0.5)
	await _shot("07_chase")
	while fishing.state == FishingController.State.REELING:
		fishing.tap()
		await _wait(0.05)
	await _wait(0.25)
	await _shot("08_caught")
	await _until(func() -> bool: return fishing.is_idle())

	_main.on_action_down()
	await _wait(0.5)
	_main.on_action_up()
	await _until(func() -> bool: return fishing.state == FishingController.State.RESULT)
	await _wait(0.3)
	await _shot("09_eaten")
	await _until(func() -> bool: return fishing.is_idle())

	for kind: String in ["backpack", "codex", "rods"]:
		panels.open(kind)
		await _wait(0.2)
		await _shot("10_panel_" + kind)
		panels.close()

	# 走下码头：镜头跟在人身后。
	world.place_player(Vector3(0.0, 0.0, -1.0))
	_key(KEY_S, true)
	await _wait(0.5)
	await _shot("11_walking_on_pier")
	_key(KEY_S, false)
	world.place_player(Vector3(0.0, 0.0, 8.0))
	await _wait(0.3)
	await _shot("12_open_ground")
	_key(KEY_A, true)
	await _wait(0.45)
	await _shot("13_walking_left")
	_key(KEY_A, false)
	await _wait(0.1)
	_main.on_lift()
	await _wait(Balance.LIFT_DURATION * 0.5)
	await _shot("14_lifting_anywhere")
	await _until(func() -> bool: return not gym.is_lifting())
	await _wait(0.1)
	await _shot("15_lift_gain")

	# 健身房：靠近了才能买哑铃。
	world.place_player(World.GYM_CENTER + Vector3(-1.5, 0.0, 1.2))
	await _wait(0.3)
	await _shot("16_gym")
	_main.on_action_down()
	_main.on_action_up()
	await _wait(0.2)
	await _shot("17_panel_dumbbells")
	panels.close()

	# 展示台：站到台前，镜头换成看得清台子的机位，跟着人左右移。
	world.place_player(Vector3(World.stand_x(0) - 3.0, 0.0, World.DISPLAY_CENTER.z + 4.0))
	await _wait(0.3)
	await _shot("18_near_display")
	world.place_player(Vector3(World.stand_x(1), 0.0, World.DISPLAY_CENTER.z + 3.4))
	await _wait(0.3)
	await _shot("19_display")
	world.place_player(Vector3(World.stand_x(4) + 0.9, 0.0, World.DISPLAY_CENTER.z + 1.6))
	await _wait(0.3)
	await _shot("19_display_close")
	world.place_player(Vector3(World.stand_x(7), 0.0, World.DISPLAY_CENTER.z + 4.4))
	await _wait(0.3)
	await _shot("19_display_last")
	panels.open_stand(1)
	await _wait(0.2)
	await _shot("20_panel_stand_fish")
	panels.close()
	panels.open_stand(7)
	await _wait(0.2)
	await _shot("21_panel_stand_empty")
	panels.close()
	panels.open_offline(4.0 * 3600.0, 15872.0)
	await _wait(0.2)
	await _shot("22_panel_offline")
	panels.close()

	# 场地的两个角，看镜头会不会拍到场外。
	world.place_player(Vector3(World.WALK_MAX_X, 0.0, World.WALK_MAX_Z))
	await _wait(0.3)
	await _shot("23_corner_far_right")
	world.place_player(Vector3(World.WALK_MIN_X, 0.0, World.SHORE_Z))
	await _wait(0.3)
	await _shot("24_corner_near_left")

	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("res://%s/%s.png" % [out_dir, shot_name])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _until(condition: Callable) -> void:
	var waited := 0.0
	while not condition.call() and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
