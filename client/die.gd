class_name Die
extends RigidBody3D

const SIZE := 0.08

static var _textures: Dictionary = {}

static func _fill_circle(img: Image, center: Vector2i, r: int, color: Color) -> void:
	for x in range(center.x - r, center.x + r + 1):
		for y in range(center.y - r, center.y + r + 1):
			if (x - center.x) ** 2 + (y - center.y) ** 2 <= r * r \
					and x >= 0 and x < 64 and y >= 0 and y < 64:
				img.set_pixel(x, y, color)

static func pip_texture(value: int) -> ImageTexture:
	if _textures.has(value):
		return _textures[value]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.97, 0.96, 0.92))
	var a := 16
	var b := 32
	var c := 48
	var pips: Array[Vector2i] = []
	match value:
		1: pips = [Vector2i(b, b)]
		2: pips = [Vector2i(a, a), Vector2i(c, c)]
		3: pips = [Vector2i(a, a), Vector2i(b, b), Vector2i(c, c)]
		4: pips = [Vector2i(a, a), Vector2i(c, a), Vector2i(a, c), Vector2i(c, c)]
		5: pips = [Vector2i(a, a), Vector2i(c, a), Vector2i(b, b), Vector2i(a, c), Vector2i(c, c)]
		6: pips = [Vector2i(a, a), Vector2i(a, b), Vector2i(a, c), Vector2i(c, a), Vector2i(c, b), Vector2i(c, c)]
	for p in pips:
		_fill_circle(img, p, 7, Color(0.1, 0.1, 0.12))
	var tex := ImageTexture.create_from_image(img)
	_textures[value] = tex
	return tex

static func _mat(color: Color, roughness := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

static func build() -> Die:
	var body := Die.new()
	body.mass = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.12
	body.physics_material_override = pm
	body.continuous_cd = true

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * SIZE
	col.shape = box
	body.add_child(col)

	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (SIZE * 0.985)
	bm.material = _mat(Color(0.97, 0.96, 0.92))
	core.mesh = bm
	body.add_child(core)

	var half := SIZE / 2.0 + 0.0005
	var faces := [
		[Vector3.UP, Vector3(-90, 0, 0), 5],
		[Vector3.DOWN, Vector3(90, 0, 0), 2],
		[Vector3.RIGHT, Vector3(0, 90, 0), 3],
		[Vector3.LEFT, Vector3(0, -90, 0), 4],
		[Vector3.FORWARD, Vector3(0, 180, 0), 1], # -Z : orienter le quad vers l'extérieur
		[Vector3.BACK, Vector3.ZERO, 6],         # +Z : idem

	]
	for f in faces:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * SIZE
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = pip_texture(f[2])
		fm.roughness = 0.35
		qm.material = fm
		q.mesh = qm
		q.position = f[0] * half
		q.rotation_degrees = f[1]
		body.add_child(q)

	return body
