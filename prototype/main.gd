extends Node3D

const TABLE_TOP_Y := 0.78
const TABLE_RADIUS := 1.15

var dice: Array[Die] = []
var dice_home: Array[Vector3] = []
var miis: Array[Mii] = []
var splat_tex: ImageTexture
var cup: MeshInstance3D
var cup_home := Vector3(0, TABLE_TOP_Y + 0.085, 1.05)
var cam: Camera3D
var busy := false
var thrown := false
var sway_t := 0.0
var _shot := OS.get_cmdline_user_args().has("--shot")
var _frames := 0

static func mat(color: Color, roughness := 0.8, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	return m

func _mesh(mesh: PrimitiveMesh, color: Color, pos: Vector3, roughness := 0.8, emission := false) -> MeshInstance3D:
	mesh.material = mat(color, roughness, emission)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

func _ready() -> void:
	randomize()
	splat_tex = _make_splat_texture()
	_environment()
	_lights()
	_room()
	_table()
	_characters()
	_player_cup_dice()
	_camera()
	_hud()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.46, 0.36)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _lights() -> void:
	var key := OmniLight3D.new()
	key.position = Vector3(0, 2.5, 0.2)
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 1.8
	key.omni_range = 7.0
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.8, -3.8)
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.4
	fill.omni_range = 6.0
	add_child(fill)

	for side in [-1.0, 1.0]:
		var sconce := OmniLight3D.new()
		sconce.position = Vector3(side * 3.5, 2.0, -4.0)
		sconce.light_color = Color(1.0, 0.8, 0.55)
		sconce.light_energy = 0.5
		sconce.omni_range = 4.0
		add_child(sconce)

func _room() -> void:
	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(12, 12)
	add_child(_mesh(floor_m, Color(0.42, 0.28, 0.16), Vector3.ZERO, 0.9))

	var ceil_m := PlaneMesh.new()
	ceil_m.size = Vector2(12, 12)
	var ceil_i := _mesh(ceil_m, Color(0.75, 0.7, 0.62), Vector3(0, 3.0, 0))
	ceil_i.rotation_degrees.x = 180
	add_child(ceil_i)

	var wall_color := Color(0.82, 0.74, 0.6)
	var walls := [
		[Vector3(0, 1.5, -4.5), Vector3(10, 3, 0.12)],
		[Vector3(0, 1.5, 4.5), Vector3(10, 3, 0.12)],
		[Vector3(-4.5, 1.5, 0), Vector3(0.12, 3, 10)],
		[Vector3(4.5, 1.5, 0), Vector3(0.12, 3, 10)],
	]
	for w in walls:
		var wm := BoxMesh.new()
		wm.size = w[1]
		add_child(_mesh(wm, wall_color, w[0]))

	var glass := QuadMesh.new()
	glass.size = Vector2(3.2, 1.6)
	add_child(_mesh(glass, Color(0.06, 0.12, 0.4), Vector3(0, 1.7, -4.42), 0.4, true))

	var frame_mat := Color(0.25, 0.15, 0.08)
	var frame_parts := [
		[Vector3(0, 2.55, -4.4), Vector3(3.4, 0.12, 0.1)],
		[Vector3(0, 0.85, -4.4), Vector3(3.4, 0.12, 0.1)],
		[Vector3(-1.65, 1.7, -4.4), Vector3(0.12, 1.8, 0.1)],
		[Vector3(1.65, 1.7, -4.4), Vector3(0.12, 1.8, 0.1)],
		[Vector3(0, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
		[Vector3(-0.82, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
		[Vector3(0.82, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
	]
	for f in frame_parts:
		var fm := BoxMesh.new()
		fm.size = f[1]
		add_child(_mesh(fm, frame_mat, f[0], 0.6))

	for side in [-1.0, 1.0]:
		var sconce_m := QuadMesh.new()
		sconce_m.size = Vector2(0.25, 0.35)
		add_child(_mesh(sconce_m, Color(1.0, 0.85, 0.55), Vector3(side * 3.5, 2.0, -4.42), 0.5, true))

	var pic := BoxMesh.new()
	pic.size = Vector3(0.9, 0.7, 0.06)
	add_child(_mesh(pic, Color(0.3, 0.45, 0.35), Vector3(-4.42, 1.8, -1.0)))

	for side in [-1.0, 1.0]:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.16
		pot.bottom_radius = 0.12
		pot.height = 0.35
		add_child(_mesh(pot, Color(0.55, 0.35, 0.2), Vector3(side * 3.6, 0.175, -3.6), 0.7))
		for i in 3:
			var leaf := SphereMesh.new()
			leaf.radius = 0.22
			leaf.height = 0.44
			var leaf_m := _mesh(leaf, Color(0.15, 0.4, 0.15).darkened(i * 0.06), Vector3(side * 3.6 + (i - 1) * 0.15, 0.6 + i * 0.12, -3.6), 0.9)
			leaf_m.scale = Vector3(1.0, 1.6, 0.6)
			add_child(leaf_m)

func _table() -> void:
	var top := CylinderMesh.new()
	top.top_radius = TABLE_RADIUS
	top.bottom_radius = TABLE_RADIUS
	top.height = 0.06
	top.radial_segments = 48
	add_child(_mesh(top, Color(0.12, 0.36, 0.2), Vector3(0, 0.75, 0), 0.95))

	var rim := TorusMesh.new()
	rim.inner_radius = TABLE_RADIUS - 0.04
	rim.outer_radius = TABLE_RADIUS + 0.02
	rim.rings = 48
	rim.ring_segments = 12
	add_child(_mesh(rim, Color(0.35, 0.2, 0.1), Vector3(0, 0.78, 0), 0.5))

	var leg := CylinderMesh.new()
	leg.top_radius = 0.12
	leg.bottom_radius = 0.18
	leg.height = 0.75
	add_child(_mesh(leg, Color(0.3, 0.18, 0.09), Vector3(0, 0.375, 0), 0.6))

	var felt_body := StaticBody3D.new()
	var felt_col := CollisionShape3D.new()
	var felt_shape := CylinderShape3D.new()
	felt_shape.radius = TABLE_RADIUS
	felt_shape.height = 0.06
	felt_col.shape = felt_shape
	felt_body.position.y = 0.75
	var felt_pm := PhysicsMaterial.new()
	felt_pm.friction = 1.0
	felt_pm.bounce = 0.05
	felt_body.physics_material_override = felt_pm
	felt_body.add_child(felt_col)
	add_child(felt_body)

	var ring_body := StaticBody3D.new()
	for i in 20:
		var seg := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(0.38, 0.4, 0.05)
		seg.shape = sb
		var a := TAU * i / 20.0
		seg.position = Vector3(cos(a) * (TABLE_RADIUS + 0.03), 0.95, sin(a) * (TABLE_RADIUS + 0.03))
		seg.rotation.y = -a + PI / 2.0
		ring_body.add_child(seg)
	add_child(ring_body)

func _cup_mesh() -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.105
	cm.height = 0.17
	cm.radial_segments = 24
	return _mesh(cm, Color(0.4, 0.23, 0.1), Vector3.ZERO, 0.55)

func _characters() -> void:
	var skins := [Color(0.95, 0.78, 0.6), Color(0.85, 0.62, 0.42), Color(0.98, 0.85, 0.7), Color(0.7, 0.5, 0.35), Color(0.92, 0.72, 0.55)]
	var shirts := [Color(0.2, 0.5, 0.85), Color(0.85, 0.3, 0.25), Color(0.2, 0.65, 0.3), Color(0.9, 0.75, 0.2), Color(0.55, 0.3, 0.7)]
	var hairs := [Color(0.2, 0.12, 0.06), Color(0.5, 0.32, 0.15), Color(0.1, 0.1, 0.1), Color(0.75, 0.55, 0.2), Color(0.35, 0.2, 0.1)]
	var angles := [215.0, 242.5, 270.0, 297.5, 325.0]

	for i in angles.size():
		var a := deg_to_rad(angles[i])
		var pos := Vector3(cos(a) * 1.6, 0, sin(a) * 1.6)
		var mii := Mii.build(skins[i], shirts[i], hairs[i], i == 2, randi_range(0, 5), randi_range(0, 3))
		mii.position = pos
		mii.rotation.y = atan2(-pos.x, -pos.z)
		add_child(mii)
		miis.append(mii)

		var opp_cup := _cup_mesh()
		var cup_pos := Vector3(cos(a) * 0.98, TABLE_TOP_Y + 0.085, sin(a) * 0.98)
		opp_cup.position = cup_pos
		opp_cup.rotation.y = randf_range(0, TAU)
		add_child(opp_cup)

func _player_cup_dice() -> void:
	cup = _cup_mesh()
	cup.position = cup_home
	add_child(cup)

	var offsets := [
		Vector3(-0.022, 0, -0.022), Vector3(0.022, 0, -0.022),
		Vector3(-0.022, 0, 0.022), Vector3(0.022, 0, 0.022),
		Vector3(0, 0, 0),
	]
	for i in 5:
		var d := Die.build()
		var home: Vector3 = cup_home + offsets[i]
		home.y = TABLE_TOP_Y + Die.SIZE / 2.0 + 0.001
		dice_home.append(home)
		d.position = home
		d.freeze = true
		dice.append(d)
		add_child(d)

	var skin := Color(0.95, 0.78, 0.6)
	for side in [-1.0, 1.0]:
		var hand := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.045
		hs.height = 0.09
		hs.material = mat(skin, 0.55)
		hand.mesh = hs
		hand.position = Vector3(side * 0.45, TABLE_TOP_Y + 0.03, 1.3)
		add_child(hand)

func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.55, 3.0), Vector3(0, 0.82, -0.3))

func _hud() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "Espace / Tap : lancer les dés"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.position.y = 24
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(label)
	add_child(layer)

func _process(delta: float) -> void:
	sway_t += delta
	cam.rotation.y += sin(sway_t * 0.6) * 0.00005
	cam.rotation.x += cos(sway_t * 0.45) * 0.00004
	if _shot:
		_frames += 1
		if _frames == 15:
			var img0 := get_viewport().get_texture().get_image()
			img0.save_png("/tmp/doodoo_racked.png")
		elif _frames == 30:
			_lift_and_throw()
		elif _frames == 90:
			_throw_tomato(miis[2])
		elif _frames == 150:
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/doodoo_proto.png")
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if not busy:
			if thrown:
				_rack()
			else:
				_lift_and_throw()
		return

	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = true
	if not pressed:
		return

	var from := cam.project_ray_origin(pos)
	var to := from + cam.project_ray_normal(pos) * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("mii"):
		_throw_tomato(hit.collider.get_meta("mii"))
	elif not busy:
		if thrown:
			_rack()
		else:
			_lift_and_throw()

func _make_splat_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 9:
		var c := Vector2i(32 + randi_range(-14, 14), 32 + randi_range(-14, 14))
		Die._fill_circle(img, c, randi_range(7, 16), Color(0.8, 0.1, 0.05, 0.95))
	return ImageTexture.create_from_image(img)

func _throw_tomato(mii: Mii) -> void:
	var tomato := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.material = mat(Color(0.8, 0.1, 0.05), 0.5)
	tomato.mesh = sm
	add_child(tomato)

	var p0 := Vector3(0, 1.15, 2.5)
	var p2: Vector3 = mii.global_position + Vector3(0, 1.32, 0.05)
	var mid := (p0 + p2) / 2.0 + Vector3(0, 0.8, 0)
	var twn := create_tween()
	twn.tween_method(_bezier_move.bind(tomato, p0, mid, p2), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN)
	twn.tween_callback(_tomato_impact.bind(mii, tomato, p2))

func _bezier_move(t: float, tomato: MeshInstance3D, p0: Vector3, mid: Vector3, p2: Vector3) -> void:
	tomato.global_position = p0.lerp(mid, t).lerp(mid.lerp(p2, t), t)

func _tomato_impact(mii: Mii, tomato: MeshInstance3D, at: Vector3) -> void:
	tomato.queue_free()

	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.03
	ppm.direction = Vector3(0, 0.6, 0.6)
	ppm.spread = 70.0
	ppm.initial_velocity_min = 1.0
	ppm.initial_velocity_max = 2.4
	ppm.gravity = Vector3(0, -6, 0)
	ppm.scale_min = 0.5
	ppm.scale_max = 1.4
	var gp := GPUParticles3D.new()
	gp.process_material = ppm
	gp.amount = 28
	gp.lifetime = 0.7
	gp.one_shot = true
	gp.explosiveness = 1.0
	var dm := SphereMesh.new()
	dm.radius = 0.012
	dm.height = 0.024
	dm.material = mat(Color(0.8, 0.1, 0.05), 0.5)
	gp.draw_pass_1 = dm
	gp.position = at
	add_child(gp)
	gp.emitting = true
	get_tree().create_timer(1.5).timeout.connect(gp.queue_free)

	var splat := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.2, 0.2)
	var sqm := StandardMaterial3D.new()
	sqm.albedo_texture = splat_tex
	sqm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sq.material = sqm
	splat.mesh = sq
	splat.position = Vector3(0, 1.32, 0.16)
	mii.add_child(splat)
	get_tree().create_timer(3.0).timeout.connect(splat.queue_free)

	mii.set_face(3)
	mii.play_flinch()
	get_tree().create_timer(3.0).timeout.connect(func(): mii.set_face(mii._face))

func _lift_and_throw() -> void:
	busy = true
	var twn := create_tween()
	twn.tween_property(cup, "position:y", cup_home.y + 0.4, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twn.tween_callback(_throw_dice)
	twn.tween_interval(0.4)
	twn.tween_property(cup, "position", cup_home + Vector3(0.28, 0, -0.05), 0.3)
	twn.tween_callback(_finish_throw)

func _throw_dice() -> void:
	for d in dice:
		d.freeze = false
		var dir := Vector3(randf_range(-0.55, 0.55), 0, -1.0).normalized()
		d.linear_velocity = dir * randf_range(0.5, 1.1) + Vector3(0, randf_range(0.35, 0.75), 0)
		d.angular_velocity = Vector3(randf_range(-18, 18), randf_range(-14, 14), randf_range(-18, 18))

func _finish_throw() -> void:
	thrown = true
	busy = false

func _rack() -> void:
	busy = true
	var twn := create_tween()
	twn.tween_property(cup, "position", Vector3(0, cup_home.y + 0.4, 1.05), 0.3)
	for i in dice.size():
		var d := dice[i]
		d.freeze = true
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO
		d.rotation = Vector3.ZERO
		twn.parallel().tween_property(d, "global_position", dice_home[i], 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(cup, "position", cup_home, 0.3)
	twn.tween_callback(_finish_rack)

func _finish_rack() -> void:
	thrown = false
	busy = false
