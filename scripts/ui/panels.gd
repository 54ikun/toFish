class_name Panels
extends Control
## 弹出面板：背包、图鉴、鱼竿、哑铃、展示台、离线收益。同一时间只开一个。
## 存档一变，开着的面板就按最新数据重画。

signal opened
signal closed

const PANEL_SIZE := Vector2(940, 640)

var _kind := ""
var _stand := -1
var _offline_seconds := 0.0
var _offline_gold := 0.0
var _sell_all_armed := false
var _rebuild_queued := false

var _dim: ColorRect
var _title: Label
var _header_slot: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer


func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 压暗背景；点面板外面的空白处就关掉。
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.08, 0.16, 0.55)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	_title = UiKit.label("", 36)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_header_slot = HBoxContainer.new()
	header.add_child(_header_slot)
	var close_button := UiKit.button("关闭", "grey", Vector2(130, 72))
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)

	_dim.visible = false
	GameState.changed.connect(_queue_rebuild)


func is_open() -> bool:
	return _kind != ""


func open(kind: String) -> void:
	_kind = kind
	_sell_all_armed = false
	_scroll.scroll_vertical = 0
	_dim.visible = true
	_rebuild()
	opened.emit()


func open_stand(stand_index: int) -> void:
	_stand = stand_index
	open("stand")


func open_offline(seconds: float, gold: float) -> void:
	_offline_seconds = seconds
	_offline_gold = gold
	open("offline")


func close() -> void:
	if not is_open():
		return
	_kind = ""
	_dim.visible = false
	closed.emit()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 重画要延后到这一帧末尾：触发它的往往就是面板里某个按钮自己的点击回调。
func _queue_rebuild() -> void:
	if is_open() and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_open():
		return
	UiKit.clear_children(_body)
	UiKit.clear_children(_header_slot)
	match _kind:
		"backpack":
			_build_backpack()
		"codex":
			_build_codex()
		"rods":
			_build_rods()
		"dumbbells":
			_build_dumbbells()
		"stand":
			_build_stand()
		"offline":
			_build_offline()


# ── 背包 ───────────────────────────────────────────────────────────

func _build_backpack() -> void:
	_title.text = "背包 %d/%d" % [GameState.backpack.size(), Balance.BACKPACK_CAPACITY]
	if GameState.backpack.is_empty():
		_note("背包是空的。去码头钓几条吧。")
		return

	var total := 0
	for fish in GameState.backpack:
		total += GameState.fish_sell_price(fish)
	# 全部卖出要点两次，防止手滑。
	var sell_all := UiKit.button(
		"再点一次确认" if _sell_all_armed else "全部卖出 +%s" % UiKit.fmt_gold(total),
		"danger" if _sell_all_armed else "primary", Vector2(250, 72))
	sell_all.pressed.connect(_on_sell_all)
	_header_slot.add_child(sell_all)

	_note("卖鱼换金币；想留着赚收益，就去展示台上架。卖掉的鱼仍留在图鉴里。")
	for fish in GameState.backpack:
		var uid: int = fish["uid"]
		var sell := UiKit.button("卖出 +%s" % UiKit.fmt_gold(GameState.fish_sell_price(fish)), "primary", Vector2(210, 72))
		sell.pressed.connect(_on_sell.bind(uid))
		_body.add_child(_fish_row(fish, [sell]))


func _on_sell(uid: int) -> void:
	_sell_all_armed = false
	GameState.sell_fish(uid)


func _on_sell_all() -> void:
	if _sell_all_armed:
		_sell_all_armed = false
		GameState.sell_all_backpack()
	else:
		_sell_all_armed = true
		_rebuild()


# ── 图鉴 ───────────────────────────────────────────────────────────

func _build_codex() -> void:
	_title.text = "图鉴 %d/%d" % [GameState.codex_count(), Content.FISH.size()]
	var promise := UiKit.label("钓上岸就永久登记，卖掉也不会消失", 20, Palette.GREY_DARK)
	promise.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_slot.add_child(promise)
	# 12 种鱼排成 4 列 3 行，一屏看全，不用滚动。
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	for fish in Content.FISH:
		var species_id: String = fish["id"]
		var rarity: int = fish["rarity"]
		var caught: int = GameState.codex.get(species_id, 0)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.box(Palette.ROW, Palette.RARITY_TEXT[rarity], 16, 4, 4))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -5)
		card.add_child(box)
		var icon := FishIcon.new(species_id, Vector2(120, 52))
		icon.silhouette = caught == 0
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		box.add_child(_centered(Content.fish_name(species_id), 26, Palette.INK if caught > 0 else Palette.GREY_DARK))
		box.add_child(_centered("%s · %s" % [Content.RARITY_NAMES[rarity], Content.fish_zone_text(species_id)], 18, Palette.RARITY_TEXT[rarity]))
		box.add_child(_centered("已钓到 %d 条" % caught if caught > 0 else "还没登记", 18, Palette.GREEN_DARK if caught > 0 else Palette.GREY_DARK))
		grid.add_child(card)


# ── 鱼竿与哑铃 ─────────────────────────────────────────────────────

func _build_rods() -> void:
	_title.text = "鱼竿"
	_note("好竿运气更高、收线更快。抛得远不远要靠力量，买了哑铃随时能练。")
	for tier in Content.tier_count():
		var detail := "运气 +%.1f · 收线速度 ×%.2f" % [Balance.ROD_LUCK[tier], Balance.ROD_REEL_SPEED[tier]]
		_body.add_child(_gear_row(
			Content.rod_full_name(tier), detail, tier,
			GameState.owned_rods.has(tier), GameState.rod == tier, Balance.ROD_PRICE[tier],
			GameState.buy_rod.bind(tier), GameState.equip_rod.bind(tier)))


func _build_dumbbells() -> void:
	_title.text = "哑铃"
	_note("买了就能换着用，在哪儿都能举。点一下举一次，动作做完才加力量，不花金币和体力。")
	for tier in Content.tier_count():
		var detail := "每举一次 力量 +%d" % Balance.LIFT_GAIN[tier]
		_body.add_child(_gear_row(
			Content.dumbbell_full_name(tier), detail, tier,
			GameState.owned_dumbbells.has(tier), GameState.dumbbell == tier, Balance.DUMBBELL_PRICE[tier],
			GameState.buy_dumbbell.bind(tier), GameState.equip_dumbbell.bind(tier)))


func _gear_row(title: String, detail: String, tier: int, owned: bool, equipped: bool, price: int, buy: Callable, equip: Callable) -> Control:
	var action: Button
	if equipped:
		action = UiKit.button("使用中", "grey", Vector2(230, 72))
		action.disabled = true
	elif owned:
		action = UiKit.button("换上", "green", Vector2(230, 72))
		action.pressed.connect(equip)
	else:
		action = UiKit.button("购买 %s" % UiKit.fmt_gold(price), "primary", Vector2(230, 72))
		action.disabled = not GameState.can_afford(price)
		action.pressed.connect(buy)
	var chip := ColorRect.new()
	chip.color = Palette.RARITY[tier]
	chip.custom_minimum_size = Vector2(22, 64)
	return _row(chip, title, detail, Palette.RARITY_TEXT[tier], [action])


# ── 展示台 ─────────────────────────────────────────────────────────

func _build_stand() -> void:
	var fish: Variant = GameState.stand_fish(_stand)
	if fish == null:
		_title.text = "%d 号展示台 · 选一条鱼上架" % (_stand + 1)
		if GameState.backpack.is_empty():
			_note("背包里没有鱼。先去码头钓几条，再回来上架。")
			return
		_note("上架后按秒产生收益，离线也算，最多结算 4 小时。同种鱼可以摆好几条。")
		for candidate in GameState.backpack:
			var uid: int = candidate["uid"]
			var place := UiKit.button("上架", "green", Vector2(170, 72))
			place.pressed.connect(_on_place.bind(uid))
			_body.add_child(_fish_row(candidate, [place], true))
		return

	var species_id: String = fish["species"]
	var level: int = fish["level"]
	var earned: float = fish["earned"]
	var rarity := Content.fish_rarity(species_id)
	_title.text = "%d 号展示台" % (_stand + 1)

	var icon := FishIcon.new(species_id, Vector2(260, 130))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(icon)
	_body.add_child(_centered("%s · %s · Lv.%d" % [Content.fish_name(species_id), Content.RARITY_NAMES[rarity], level], 34, Palette.RARITY_TEXT[rarity]))
	_body.add_child(_centered("每秒收益 +%s · 已产生 %s" % [UiKit.fmt_rate(Rules.income_per_second(species_id, level)), UiKit.fmt_amount(earned)], 26, Palette.INK))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_body.add_child(buttons)

	var cost := Rules.upgrade_cost(species_id, level)
	var upgrade: Button
	if cost < 0:
		upgrade = UiKit.button("已满级", "grey", Vector2(380, 84))
		upgrade.disabled = true
	else:
		var next_rate := Rules.income_per_second(species_id, level + 1)
		upgrade = UiKit.button("升级 %s 金币（每秒 +%s）" % [UiKit.fmt_gold(cost), UiKit.fmt_rate(next_rate)], "primary", Vector2(380, 84))
		upgrade.disabled = not GameState.can_afford(cost)
		upgrade.pressed.connect(GameState.upgrade_stand_fish.bind(_stand))
	buttons.add_child(upgrade)

	var take := UiKit.button("下架回背包", "secondary", Vector2(230, 84))
	take.disabled = GameState.backpack_full()
	take.pressed.connect(_on_take)
	buttons.add_child(take)

	if GameState.backpack_full():
		_note("背包满了，先卖掉几条才能下架。")
	else:
		_note("等级跟着这条鱼走，下架回背包也不会掉。升过级的鱼卖价只高一点点。")


func _on_place(uid: int) -> void:
	if GameState.place_on_stand(_stand, uid):
		close()


func _on_take() -> void:
	if GameState.take_from_stand(_stand):
		close()


# ── 离线收益 ───────────────────────────────────────────────────────

func _build_offline() -> void:
	_title.text = "展示台替你赚了钱"
	_body.add_child(_centered("+%s 金币" % UiKit.fmt_amount(_offline_gold), 56, Palette.GOLD_DARK))
	_body.add_child(_centered("你离开的这段时间按 %s 结算" % UiKit.fmt_duration(_offline_seconds), 26, Palette.INK))
	if _offline_seconds >= Content.OFFLINE_CAP_SECONDS:
		_body.add_child(_centered("离线收益最多结算 4 小时，记得常回来看看", 22, Palette.GREY_DARK))
	var ok := UiKit.button("收下", "green", Vector2(260, 84), 30)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close)
	_body.add_child(ok)


# ── 零件 ───────────────────────────────────────────────────────────

func _note(text: String) -> void:
	var node := UiKit.label(text, 22, Palette.GREY_DARK)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(node)


func _centered(text: String, font_size: int, color: Color) -> Label:
	var node := UiKit.label(text, font_size, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


## 一条鱼的列表行。show_income 为 true 时副标题写上架后的每秒收益。
func _fish_row(fish: Dictionary, actions: Array, show_income: bool = false) -> Control:
	var species_id: String = fish["species"]
	var level: int = fish["level"]
	var rarity := Content.fish_rarity(species_id)
	var subtitle := "%s · Lv.%d" % [Content.RARITY_NAMES[rarity], level]
	if show_income:
		subtitle += " · 上架后每秒 +%s" % UiKit.fmt_rate(Rules.income_per_second(species_id, level))
	return _row(FishIcon.new(species_id, Vector2(96, 64)), Content.fish_name(species_id), subtitle, Palette.RARITY_TEXT[rarity], actions)


func _row(leading: Control, title: String, subtitle: String, subtitle_color: Color, actions: Array) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.box(Palette.ROW, Color("e3d9c0"), 16, 3, 10))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)
	leading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(leading)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", -2)
	text.add_child(UiKit.label(title, 28))
	text.add_child(UiKit.label(subtitle, 20, subtitle_color))
	line.add_child(text)
	for action: Control in actions:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(action)
	return row
