class_name FishReel
extends Control
## 竖着滚的选鱼转盘，像老虎机的一条滚轮：窗口里一次只露出中间一格和上下各半格，
## 鱼从上往下滚，慢下来以后停在中间那格的，就是咬钩的鱼。
##
## 滚轮上每种鱼占几格按出鱼比例分（至少一格），所以滚过去得多的鱼就是更容易中的鱼。
## 滚轮自己滚、自己停（临时方案；怎么停、滚多久尚未拍板）。

signal stopped

const CELL_HEIGHT := 104.0
## 窗口高度相当于几格：中间一整格，上下各露出一部分。
const WINDOW_CELLS := 2.3
## 一条滚轮大约有多少格。格数越多，稀有鱼占的比例越接近真实几率。
const STRIP_CELLS := 16
## 每次从开滚到停下一共滚过多少格。太多的话一帧就跳过一整格，看不出在滚。
const TRAVEL_CELLS := 18.0

## 每项 {species, weight, share}，来自 Rules.wheel_entries。
var entries: Array[Dictionary] = []
## 滚轮上从头到尾每一格是哪一项（entries 的下标），首尾相接循环。
var strip := PackedInt32Array()
## 滚轮滚到了第几格（可以是小数）：这一格正对窗口中间。
var scroll := 0.0:
	set(value):
		scroll = value
		queue_redraw()

var _settled := false
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(400.0, CELL_HEIGHT * WINDOW_CELLS)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## 按出鱼比例排出一条滚轮。同种鱼的格子尽量均匀摊开，不挤在一起。
static func build_strip(reel_entries: Array[Dictionary], cells: int, seed_value: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slots: Array = []
	for i in reel_entries.size():
		var share: float = reel_entries[i]["share"]
		var copies := maxi(roundi(share * cells), 1)
		var phase := rng.randf()
		for copy in copies:
			slots.append([(copy + phase) / copies, i])
	slots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedInt32Array()
	for slot: Array in slots:
		out.append(slot[1])
	return out


func setup(new_entries: Array[Dictionary], seed_value: int = 0) -> void:
	if _tween != null:
		_tween.kill()
	entries = new_entries
	strip = build_strip(entries, STRIP_CELLS, seed_value)
	_settled = false
	scroll = 0.0


## 滚到第 index 项停下。这种鱼在滚轮上可能有好几格，offset（0–1）决定停在其中哪一格。
func spin_to(index: int, duration: float, offset: float = 0.5) -> void:
	var cells: Array[int] = []
	for i in strip.size():
		if strip[i] == index:
			cells.append(i)
	if cells.is_empty():
		return
	var target := float(cells[mini(int(clampf(offset, 0.0, 1.0) * cells.size()), cells.size() - 1)])
	_settled = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scroll", target, duration).from(target - TRAVEL_CELLS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_on_settled)


## 此刻正对窗口中间的是哪一项（entries 的下标）；滚轮还没排好时返回 -1。
func center_index() -> int:
	if strip.is_empty():
		return -1
	return strip[posmod(roundi(scroll), strip.size())]


func _on_settled() -> void:
	_settled = true
	queue_redraw()
	stopped.emit()


func _draw() -> void:
	var window := Rect2(Vector2.ZERO, size)
	draw_rect(window, Palette.INK)
	if strip.is_empty():
		return
	var mid := size.y * 0.5
	var first := floori(scroll) - 2
	for cell in range(first, first + 5):
		# 格子编号越大越靠上：滚轮往下滚，新的鱼从上面进来。
		var center_y := mid + (scroll - cell) * CELL_HEIGHT
		_draw_cell(strip[posmod(cell, strip.size())], Rect2(10.0, center_y - CELL_HEIGHT * 0.5 + 5.0, size.x - 20.0, CELL_HEIGHT - 10.0))

	# 上下两头压暗，只有中间一格是亮的。
	var shade_height := mid - CELL_HEIGHT * 0.5
	var shade := Color(Palette.INK, 0.5)
	draw_rect(Rect2(0.0, 0.0, size.x, shade_height), shade)
	draw_rect(Rect2(0.0, size.y - shade_height, size.x, shade_height), shade)

	# 中间一格的框，停稳后变成金色。
	var focus := Rect2(4.0, mid - CELL_HEIGHT * 0.5, size.x - 8.0, CELL_HEIGHT)
	var frame := UiKit.box(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD if _settled else Color("ffffff"), 16, 6, 0)
	draw_style_box(frame, focus)

	# 两侧的指针。
	for side: float in [-1.0, 1.0]:
		var edge := size.x * 0.5 + side * size.x * 0.5
		var tip := Vector2(edge - side * 30.0, mid)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(edge, mid - 24.0), Vector2(edge, mid + 24.0)]), Palette.INK)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(side * 9.0, 0.0), Vector2(edge, mid - 15.0), Vector2(edge, mid + 15.0)]), Palette.DANGER)

	# 外框压住四角。
	draw_style_box(UiKit.box(Color(0.0, 0.0, 0.0, 0.0), Palette.INK, 18, 6, 0), window)


func _draw_cell(index: int, rect: Rect2) -> void:
	var species_id: String = entries[index]["species"]
	var rarity := Content.fish_rarity(species_id)
	draw_style_box(UiKit.box(Palette.ROW, Palette.RARITY_TEXT[rarity], 14, 5, 0), rect)
	FishIcon.paint(self, Rect2(rect.position + Vector2(14.0, 10.0), Vector2(132.0, rect.size.y - 20.0)), species_id)
	var font := get_theme_default_font()
	var text_x := rect.position.x + 158.0
	var text_width := rect.end.x - text_x - 30.0
	draw_string(font, Vector2(text_x, rect.position.y + rect.size.y * 0.5 + 2.0), Content.fish_name(species_id), HORIZONTAL_ALIGNMENT_LEFT, text_width, 32, Palette.INK)
	draw_string(font, Vector2(text_x, rect.position.y + rect.size.y * 0.5 + 30.0), Content.RARITY_NAMES[rarity], HORIZONTAL_ALIGNMENT_LEFT, text_width, 20, Palette.RARITY_TEXT[rarity])
