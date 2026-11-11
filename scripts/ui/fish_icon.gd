class_name FishIcon
extends Control
## 平面的小鱼图标，颜色和高矮取自这种鱼的占位模型参数。头朝右。
## silhouette 为 true 时只画剪影，用于图鉴里还没登记的鱼。

var species_id := "":
	set(value):
		species_id = value
		queue_redraw()
var silhouette := false:
	set(value):
		silhouette = value
		queue_redraw()


func _init(id: String = "", min_size: Vector2 = Vector2(72, 48)) -> void:
	species_id = id
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not FishModels.LOOKS.has(species_id):
		return
	paint(self, Rect2(Vector2.ZERO, size), species_id, silhouette)


## 在任意 CanvasItem 的 _draw 里画一条鱼（选鱼滚轮、追逐条也用它）。
static func paint(canvas: CanvasItem, rect: Rect2, id: String, as_silhouette: bool = false, flip: bool = false) -> void:
	var shape: Dictionary = FishModels.LOOKS[id]
	var body_len: float = shape["len"]
	var half_h: float = shape["h"]
	var back: Color = shape["back"]
	var belly: Color = shape["belly"]
	var fin_color := Palette.RARITY[Content.fish_rarity(id)]
	var ink := Palette.INK
	if as_silhouette:
		back = Color("b9c2cf")
		belly = back
		fin_color = back
		ink = back

	var center := rect.get_center()
	var direction := -1.0 if flip else 1.0
	var length := minf(rect.size.x * 0.62, rect.size.y * 1.5)
	var half_len := length * 0.5
	var half_height := half_len * clampf(half_h / body_len * 2.4, 0.22, 0.8)
	half_height = minf(half_height, rect.size.y * 0.44)
	var body_center := center + Vector2(direction * rect.size.x * 0.07, 0.0)

	# 尾巴。
	var tail_root := body_center + Vector2(-direction * half_len * 0.82, 0.0)
	var tail_tip := tail_root.x - direction * half_len * 0.55
	canvas.draw_colored_polygon(PackedVector2Array([
		tail_root,
		Vector2(tail_tip, tail_root.y - half_height * 0.95),
		Vector2(tail_root.x - direction * half_len * 0.3, tail_root.y),
		Vector2(tail_tip, tail_root.y + half_height * 0.95),
	]), fin_color)

	# 鱼身：上半用背色，下半用腹色。
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var angle := PI * i / steps
		var x := cos(angle) * half_len * direction
		var y := sin(angle) * half_height
		upper.append(body_center + Vector2(x, -y))
		lower.append(body_center + Vector2(x, y))
	canvas.draw_colored_polygon(upper, back)
	canvas.draw_colored_polygon(lower, belly)

	# 背鳍和眼睛。
	canvas.draw_colored_polygon(PackedVector2Array([
		body_center + Vector2(direction * half_len * 0.25, -half_height * 0.9),
		body_center + Vector2(-direction * half_len * 0.35, -half_height * 0.8),
		body_center + Vector2(-direction * half_len * 0.15, -half_height * 1.45),
	]), fin_color)
	var eye := body_center + Vector2(direction * half_len * 0.62, -half_height * 0.2)
	var eye_radius := maxf(half_len * 0.1, 2.0)
	if not as_silhouette:
		canvas.draw_circle(eye, eye_radius, Color("ffffff"))
	canvas.draw_circle(eye + Vector2(direction * eye_radius * 0.2, 0.0), eye_radius * 0.55, ink)
