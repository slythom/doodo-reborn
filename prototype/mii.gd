class_name Mii
extends Node3D

static var _scene: PackedScene = load("res://assets/mii.glb")

var ap: AnimationPlayer
var _inst: Node3D
var _face := 0

static func _mat(color: Color, roughness := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

static func _recolor(node: Node, skin: Color, shirt: Color, hair: Color) -> void:
	for child in node.get_children():
		_recolor(child, skin, shirt, hair)
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var am: Material = node.get_active_material(i)
			if am == null:
				continue
			var col := Color.TRANSPARENT
			match am.resource_name.get_slice(".", 0):
				"Skin": col = skin
				"Shirt": col = shirt
				"Hair": col = hair
			if col != Color.TRANSPARENT:
				var m := _mat(col, 0.6)
				node.set_surface_override_material(i, m)

func set_face(idx: int) -> void:
	if _inst == null:
		return
	for n in _inst.find_children("Face*"):
		n.visible = n.name.begins_with("Face%d" % idx)

func play_flinch() -> void:
	if ap and not ap.get_animation_list().is_empty():
		ap.play(ap.get_animation_list()[0])
		return
	var f := create_tween()
	f.tween_property(self, "scale:y", 0.8, 0.08).set_trans(Tween.TRANS_QUAD)
	f.parallel().tween_property(self, "rotation:x", 0.12, 0.08)
	f.tween_property(self, "scale:y", 1.0, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	f.parallel().tween_property(self, "rotation:x", 0.0, 0.45)

static func build(skin: Color, shirt: Color, hair: Color, glasses := false, hair_style := 0, face := 0) -> Mii:
	var root := Mii.new()

	if _scene == null:
		push_error("mii.glb manquant, relancer assets/make_mii.py")
		return root

	var inst := _scene.instantiate()
	inst.rotation.y = PI
	root.add_child(inst)
	root._inst = inst
	root._face = face
	_recolor(inst, skin, shirt, hair)

	for n in inst.find_children("*"):
		var nm := n.name as String
		if nm.begins_with("Hair"):
			n.visible = nm.begins_with("Hair%d" % hair_style)
		elif nm.begins_with("Face"):
			n.visible = nm.begins_with("Face%d" % face)
		elif nm.begins_with("Glasses"):
			n.visible = glasses

	root.ap = inst.get_node_or_null("AnimationPlayer") as AnimationPlayer

	var hitbox := StaticBody3D.new()
	var hcol := CollisionShape3D.new()
	var hcaps := CapsuleShape3D.new()
	hcaps.radius = 0.24
	hcaps.height = 0.85
	hcol.shape = hcaps
	hcol.position.y = 1.05
	hitbox.add_child(hcol)
	hitbox.set_meta("mii", root)
	root.add_child(hitbox)

	return root
