class_name UiKit
extends RefCounted
## 界面的共用样式和数字格式。
##
## 逻辑分辨率按 1280×720 设计，手机横屏时整体会缩小到一半左右，所以字号和按钮
## 都做得偏大：可点的按钮在逻辑分辨率下不低于 76 像素高。字号是临时的，正式
## 字体字号尚未拍板。

const FONT_PATH := "res://assets/fonts/NotoSansSC-Bold-subset.otf"

static var _font: Font
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = font()
		_theme.default_font_size = 24
		_theme.set_color("font_color", "Label", Palette.INK)
		_theme.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, Palette.INK, 22, 5, 18))
	return _theme


## 圆角色块。bottom_extra 让底边更厚，做出卡通按钮的立体感。
static func box(fill: Color, border: Color, radius: int = 18, border_width: int = 4, padding: int = 14, bottom_extra: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.border_width_bottom = border_width + bottom_extra
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	style.anti_aliasing = true
	return style


static func kind_colors(kind: String) -> Array[Color]:
	match kind:
		"secondary":
			return [Palette.SECONDARY, Palette.SECONDARY_DARK]
		"green":
			return [Palette.GREEN, Palette.GREEN_DARK]
		"danger":
			return [Palette.DANGER, Palette.DANGER.darkened(0.25)]
		"grey":
			return [Palette.GREY, Palette.GREY_DARK]
	return [Palette.PRIMARY, Palette.PRIMARY_DARK]


static func button(text: String, kind: String = "primary", min_size: Vector2 = Vector2(150, 76), font_size: int = 26) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = min_size
	# 按钮不抢键盘焦点，免得空格键（蓄力、收线）误触发上一个点过的按钮。
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(state, Color("ffffff"))
	node.add_theme_color_override("font_disabled_color", Color("f1f4f8"))
	node.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.35))
	node.add_theme_constant_override("outline_size", 4)
	style_button(node, kind)
	return node


static func style_button(node: Button, kind: String) -> void:
	var colors := kind_colors(kind)
	var normal := box(colors[0], colors[1], 18, 3, 12, 5)
	var hover := box(colors[0].lightened(0.08), colors[1], 18, 3, 12, 5)
	var pressed := box(colors[1], colors[1].darkened(0.15), 18, 3, 12, 0)
	pressed.content_margin_top = 17
	var disabled := box(Palette.GREY, Palette.GREY_DARK, 18, 3, 12, 5)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("hover_pressed", pressed)
	node.add_theme_stylebox_override("disabled", disabled)
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func label(text: String, font_size: int = 24, color: Color = Palette.INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


## 直接压在三维画面上的字：白字加深色描边，什么底色上都看得清。
static func outlined_label(text: String, font_size: int = 26, color: Color = Color("ffffff")) -> Label:
	var node := label(text, font_size, color)
	node.add_theme_color_override("font_outline_color", Palette.INK)
	node.add_theme_constant_override("outline_size", 10)
	return node


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# ── 数字格式 ───────────────────────────────────────────────────────

## 整数加千分位：12345 -> 12,345。
static func fmt_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## 金币数：向下取整；十万以上用「万」，一亿以上用「亿」。
static func fmt_gold(value: float) -> String:
	var whole := floorf(value)
	if whole >= 100000000.0:
		return "%.2f亿" % (whole / 100000000.0)
	if whole >= 100000.0:
		return "%.1f万" % (whole / 10000.0)
	return fmt_int(int(whole))


## 会慢慢涨的小数额（比如某条鱼已产生的收益）：小的时候带小数，看得出在动。
static func fmt_amount(value: float) -> String:
	if value < 100.0:
		return "%.1f" % value
	return fmt_gold(value)


## 每秒收益。
static func fmt_rate(value: float) -> String:
	if value < 10.0:
		return "%.2f" % value
	if value < 1000.0:
		return "%.1f" % value
	return fmt_gold(value)


static func fmt_duration(seconds: float) -> String:
	var total := int(seconds)
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%d 小时 %d 分" % [hours, minutes]
	if minutes > 0:
		return "%d 分 %d 秒" % [minutes, total % 60]
	return "%d 秒" % total
