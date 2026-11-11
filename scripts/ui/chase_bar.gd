class_name ChaseBar
extends Control
## 收线时的追逐条：右端是岸，目标鱼往右拖，巨鱼从左边追。
## 远处水面上的鱼在手机上很小，所以追逐的胜负主要靠这根条来读。

var species_id := ""
var fish := 0.0
var giant := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(760, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(id: String) -> void:
	species_id = id
	set_progress(0.0, -Balance.CHASE_GAP)


func set_progress(fish_pos: float, giant_pos: float) -> void:
	fish = fish_pos
	giant = giant_pos
	queue_redraw()


func _draw() -> void:
	var track := Rect2(8.0, 6.0, size.x - 16.0, size.y - 12.0)
	draw_style_box(UiKit.box(Color("1d64c9"), Palette.INK, 24, 5, 0), track)

	# 右端的岸。
	var shore := Rect2(track.end.x - 70.0, track.position.y + 5.0, 65.0, track.size.y - 10.0)
	draw_style_box(UiKit.box(Palette.SAND, Palette.SAND, 18, 0, 0), shore)
	var font := get_theme_default_font()
	draw_string(font, shore.position + Vector2(0.0, shore.size.y * 0.5 + 9.0), "岸", HORIZONTAL_ALIGNMENT_CENTER, shore.size.x, 26, Palette.INK)

	# 进度 -CHASE_GAP 画在最左，1 画在岸边。
	var left := track.position.x + 60.0
	var right := shore.position.x - 30.0
	var mid_y := track.get_center().y
	var span := 1.0 + Balance.CHASE_GAP
	var giant_x := lerpf(left, right, clampf((giant + Balance.CHASE_GAP) / span, 0.0, 1.0))
	var fish_x := lerpf(left, right, clampf((fish + Balance.CHASE_GAP) / span, 0.0, 1.0))

	# 巨鱼：一张带牙的大嘴，离得越近越红。
	var danger := clampf(1.0 - (fish - giant) / Balance.CHASE_GAP, 0.0, 1.0)
	var giant_color := Color("3b2a6b").lerp(Palette.DANGER, danger * 0.7)
	var jaw := 30.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(giant_x - 58.0, mid_y - jaw * 0.7),
		Vector2(giant_x - 10.0, mid_y - jaw),
		Vector2(giant_x + 12.0, mid_y - jaw * 0.35),
		Vector2(giant_x - 14.0, mid_y),
		Vector2(giant_x + 12.0, mid_y + jaw * 0.35),
		Vector2(giant_x - 10.0, mid_y + jaw),
		Vector2(giant_x - 58.0, mid_y + jaw * 0.7),
	]), giant_color)
	for i in 3:
		var tx := giant_x - 8.0 + i * 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 4.0, mid_y - jaw * 0.62 + i * 5.0), Vector2(tx + 4.0, mid_y - jaw * 0.5 + i * 5.0), Vector2(tx - 2.0, mid_y - jaw * 0.2 + i * 2.0)]), Color("ffffff"))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 4.0, mid_y + jaw * 0.62 - i * 5.0), Vector2(tx + 4.0, mid_y + jaw * 0.5 - i * 5.0), Vector2(tx - 2.0, mid_y + jaw * 0.2 - i * 2.0)]), Color("ffffff"))
	draw_circle(Vector2(giant_x - 30.0, mid_y - jaw * 0.45), 5.0, Color("ff4d4d"))

	if FishModels.LOOKS.has(species_id):
		FishIcon.paint(self, Rect2(fish_x - 8.0, mid_y - 26.0, 78.0, 52.0), species_id)
