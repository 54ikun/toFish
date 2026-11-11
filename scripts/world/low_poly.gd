class_name LowPoly
extends RefCounted
## 低面数网格拼装器：平直着色、只用顶点色、不用贴图。
## 按手机浏览器的预算来：所有模型共用一两个材质，颜色都写在顶点上。

static var _lit: StandardMaterial3D
static var _unshaded: StandardMaterial3D

## 之后提交的顶点都会先经过这个变换，用来摆放、旋转零件。
var xf := Transform3D.IDENTITY
var _st := SurfaceTool.new()


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## 受光的共用材质（陆地、角色、鱼等）。
static func lit_material() -> StandardMaterial3D:
	if _lit == null:
		_lit = StandardMaterial3D.new()
		_lit.vertex_color_use_as_albedo = true
		_lit.vertex_color_is_srgb = true
		_lit.roughness = 1.0
		_lit.metallic_specular = 0.0
	return _lit


## 不受光的共用材质（水面、鱼线等），颜色所见即所得。
static func unshaded_material() -> StandardMaterial3D:
	if _unshaded == null:
		_unshaded = StandardMaterial3D.new()
		_unshaded.vertex_color_use_as_albedo = true
		_unshaded.vertex_color_is_srgb = true
		_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _unshaded


## 提交一个三角形。outward 是大致朝外的方向，用来统一法线和绕序，
## 调用方不用关心顶点顺序。
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	if normal.dot(xf.basis * outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	# 此刻从外侧看 a、b、c 是逆时针；Godot 以顺时针为正面，所以按 a、c、b 提交。
	_st.set_color(color)
	_st.set_normal(normal)
	_st.add_vertex(a)
	_st.set_color(color)
	_st.set_normal(normal)
	_st.add_vertex(c)
	_st.set_color(color)
	_st.set_normal(normal)
	_st.add_vertex(b)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	tri(a, b, c, color, outward)
	tri(a, c, d, color, outward)


## 两面都看得见的薄片（鱼鳍、旗子等）。points 按顺序围成一个凸多边形。
func fin(points: PackedVector3Array, color: Color) -> void:
	if points.size() < 3:
		return
	var normal := (points[1] - points[0]).cross(points[2] - points[0])
	for i in range(1, points.size() - 1):
		tri(points[0], points[i], points[i + 1], color, normal)
		tri(points[0], points[i], points[i + 1], color, -normal)


func box(center: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	for axis in 3:
		var j := (axis + 1) % 3
		var k := (axis + 2) % 3
		var u := Vector3.ZERO
		u[j] = half[j]
		var v := Vector3.ZERO
		v[k] = half[k]
		for direction: float in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = direction
			var face := center + normal * half[axis]
			quad(face - u - v, face + u - v, face + u + v, face - u + v, color, normal)


## 沿 +Y 的棱柱、棱台或棱锥：底面半径 r0，顶面半径 r1（为 0 就收成尖）。
func prism(base: Vector3, r0: float, r1: float, height: float, sides: int, color: Color, cap_color: Variant = null) -> void:
	var cap: Color = color if cap_color == null else cap_color
	var top := base + Vector3.UP * height
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var outward := (d0 + d1).normalized()
		if r0 > 0.0 and r1 > 0.0:
			quad(base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1, color, outward)
		elif r0 > 0.0:
			tri(base + d0 * r0, base + d1 * r0, top, color, outward)
		elif r1 > 0.0:
			tri(top + d0 * r1, top + d1 * r1, base, color, outward)
		if r0 > 0.0:
			tri(base, base + d0 * r0, base + d1 * r0, cap, Vector3.DOWN)
		if r1 > 0.0:
			tri(top, top + d0 * r1, top + d1 * r1, cap, Vector3.UP)


## 沿 X 轴的纺锤体，用来做鱼身。rings 每项是 Vector3(x, 半高, 半宽)，按 x 从小到大；
## 半高为 0 表示这一圈收成一个尖。color_fn(段号, 面号, 面中心) 返回这个面的颜色。
func spindle(rings: Array[Vector3], sides: int, color_fn: Callable) -> void:
	for j in rings.size() - 1:
		var ring_a := rings[j]
		var ring_b := rings[j + 1]
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var pa0 := _ring_point(ring_a, a0)
			var pa1 := _ring_point(ring_a, a1)
			var pb0 := _ring_point(ring_b, a0)
			var pb1 := _ring_point(ring_b, a1)
			var mid := (pa0 + pa1 + pb0 + pb1) * 0.25
			var outward := Vector3(0.0, mid.y, mid.z)
			if outward.length_squared() < 1e-10:
				outward = Vector3.UP
			var color: Color = color_fn.call(j, k, mid)
			if ring_a.y <= 0.0:
				tri(pa0, pb0, pb1, color, outward)
			elif ring_b.y <= 0.0:
				tri(pa0, pa1, pb0, color, outward)
			else:
				quad(pa0, pa1, pb1, pb0, color, outward)


func build() -> ArrayMesh:
	return _st.commit()


## 把网格包成一个节点，默认用受光的共用材质。
static func instance(mesh: Mesh, material: Material = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = lit_material() if material == null else material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _ring_point(ring: Vector3, angle: float) -> Vector3:
	# angle = 0 在正上方，这样鱼背有一条棱。
	return Vector3(ring.x, ring.y * cos(angle), ring.z * sin(angle))
