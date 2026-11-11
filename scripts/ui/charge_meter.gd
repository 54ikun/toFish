class_name ChargeMeter
extends Control
## 蓄力条：来回涨落，松手那一刻填得越满，出手质量越高。
## 出手质量主要影响运气，对抛距只有小幅修正，所以这里只说运气。

var value := 0.0:
	set(next):
		value = clampf(next, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(520, 92)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, Vector2(0.0, 26.0), "蓄得越满，运气越好", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 10, Palette.INK)
	draw_string(font, Vector2(0.0, 26.0), "蓄得越满，运气越好", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color("ffffff"))

	var track := Rect2(0.0, 38.0, size.x, size.y - 38.0)
	draw_style_box(UiKit.box(Color("ffffff"), Palette.INK, 22, 5, 0), track)
	var inner := track.grow(-9.0)
	var fill := Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y))
	if fill.size.x > 2.0:
		var color := Palette.SECONDARY.lerp(Palette.PRIMARY, value)
		if value >= 0.9:
			color = Palette.DANGER
		draw_style_box(UiKit.box(color, color, 12, 0, 0), fill)
	# 最右一小段是「完美」区。
	var perfect_x := inner.position.x + inner.size.x * 0.9
	draw_line(Vector2(perfect_x, inner.position.y), Vector2(perfect_x, inner.end.y), Palette.INK, 3.0)
