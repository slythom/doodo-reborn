class_name Kaykit
extends Node3D

# Personnages KayKit sur rig Rig_Medium, CC0 — Kay Lousberg, kaylousberg.com.
# Skeletons 1.1 (assets/skeletons/) et Adventurers 2.0 (assets/adventurers/)
# partagent le même rig : les animations vivent dans les GLBs du rig et leurs
# pistes s'appliquent telles quelles (mêmes noms de bones) — une seule
# AnimationLibrary commune suffit pour tous les packs.

static var _anim_general: PackedScene = load("res://assets/skeletons/Rig_Medium_General.glb")
static var _anim_move: PackedScene = load("res://assets/skeletons/Rig_Medium_MovementBasic.glb")
static var _lib: AnimationLibrary

const TARGET_H := 1.3 # un peu sous le gabarit Mii (1,53) — les KayKit ont des silhouettes larges (capes, épaulettes, chapeaux) qui grossissent l'apparence
const LIFT := 0.22 # les pieds sont cachés par la table → on remonte le buste visible

var ap: AnimationPlayer
var _inst: Node3D
var _skel: Skeleton3D
var _head_bone := -1
var _idle := "Idle_A"
var _face := 0 # compat Mii : main.gd relit _face après une tomate
var _front := 0.2 # surface frontale (+Z) en unités locales, mesurée au build

static func _library() -> AnimationLibrary:
	if _lib == null:
		_lib = AnimationLibrary.new()
		for ps: PackedScene in [_anim_general, _anim_move]:
			if ps == null:
				continue
			var inst: Node = ps.instantiate()
			var src := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if src:
				for anim_name in src.get_animation_list():
					_lib.add_animation(anim_name, src.get_animation(anim_name))
			inst.free()
	return _lib

# AABB union des meshes, transforms accumulés (instancé hors arbre → pas de
# global_transform fiable).
static func _measure(n: Node, t: Transform3D, aabb: AABB) -> AABB:
	if n is Node3D:
		t = t * (n as Node3D).transform
		if n is MeshInstance3D:
			aabb = aabb.merge(t * (n as MeshInstance3D).get_aabb())
	for c in n.get_children():
		aabb = _measure(c, t, aabb)
	return aabb

# models : PackedScenes du pack ; variant : index ; seed : hachage pseudo pour
# varier l'idle ; tilt : inclinaison « tête levée » (chapeau qui masque le
# visage vu d'en face, ex. Mage squelette).
static func build(models: Array, variant: int, seed := 0, tilt := 0.0) -> Kaykit:
	var root := Kaykit.new()
	var ps: PackedScene = models[variant % models.size()]
	if ps == null:
		push_error("kaykit glb manquant : variant %d" % variant)
		return root
	var inst: Node3D = ps.instantiate()
	root.add_child(inst)
	# Normalise sur la hauteur mesurée : les variantes ont des gabarits
	# très différents (Minion 2,17 → Rogue 3,29), un scale fixe ne suffit pas.
	var aabb := _measure(inst, Transform3D.IDENTITY, AABB())
	var h := aabb.size.y
	if h > 0.01:
		var f := TARGET_H / h
		inst.scale = Vector3.ONE * f
		root._front = clamp(aabb.end.z * f + 0.05, 0.12, 0.45)
	inst.rotation.x = tilt
	inst.position.y = LIFT

	var sks := inst.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		root._skel = sks[0] as Skeleton3D
		root._head_bone = root._skel.find_bone("head")
	root._inst = inst

	root.ap = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if root.ap == null:
		root.ap = AnimationPlayer.new()
		inst.add_child(root.ap)
	root.ap.add_animation_library("", _library())
	root._idle = "Idle_B" if seed % 2 else "Idle_A"
	if root.ap.has_animation(root._idle):
		root.ap.play(root._idle)
		root.ap.seek(randf() * root.ap.get_animation(root._idle).length, true)

	# Hitbox identique au Mii : le tap → emote passe par la meta "mii".
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

func play_flinch() -> void:
	if ap and ap.has_animation("Hit_A"):
		ap.stop()
		ap.play("Hit_A")
		ap.queue(_idle)
		return
	var f := create_tween()
	f.tween_property(self, "scale:y", 0.8, 0.08).set_trans(Tween.TRANS_QUAD)
	f.parallel().tween_property(self, "rotation:x", 0.12, 0.08)
	f.tween_property(self, "scale:y", 1.0, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	f.parallel().tween_property(self, "rotation:x", 0.0, 0.45)

func set_face(_idx: int) -> void:
	pass # pas de variantes de visage — API compatible avec Mii

# Point d'accroche du splat de tomate, en espace local du wrapper — la tête
# d'un personnage KayKit n'est ni à la hauteur ni à la profondeur d'un Mii.
func splat_anchor() -> Vector3:
	return Vector3(0, TARGET_H * 0.82, _front)

# Point d'impact de la tomate (espace monde) : visage = juste devant et au-
# dessus de la jointure du bone `head`. Fallback sur l'ancre wrapper.
func impact_point() -> Vector3:
	var face_dir := global_transform.basis.z
	if _skel != null and _head_bone >= 0:
		var head: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(_head_bone)).origin
		return head + face_dir * 0.12 + Vector3.UP * 0.07
	return to_global(splat_anchor())

# Parente le splat à l'os de la tête : pendant Hit_A (recul) le visage bouge
# — un enfant du wrapper resterait en l'air alors que le crâne recule.
func attach_splat(splat: Node3D) -> void:
	if _skel == null or _head_bone < 0:
		add_child(splat)
		splat.position = splat_anchor()
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = _head_bone
	_skel.add_child(ba)
	ba.add_child(splat)
	splat.tree_exiting.connect(ba.queue_free)
	# ba.global_transform n'est pas encore alimenté par le Skeleton3D → on
	# calcule la pose du bone nous-mêmes (espace monde).
	var ba_world: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(_head_bone)
	# +Z du quad vers l'extérieur (direction du regard, espace os) et
	# compensation du scale de l'instance — le mesh 0,2 resterait minuscule.
	var face_dir := global_transform.basis.z
	var zloc := (ba_world.basis.inverse() * face_dir).normalized()
	splat.basis = Basis.looking_at(-zloc).scaled(Vector3.ONE / _inst.scale.y)
	# Le décal se colle là où la tomate a visé — pas sur _front : chez le
	# Mage c'est le bout du chapeau, il flotterait loin devant la tête.
	splat.position = ba_world.affine_inverse() * impact_point()
