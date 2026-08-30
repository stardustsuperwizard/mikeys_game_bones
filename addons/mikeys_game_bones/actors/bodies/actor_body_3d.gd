class_name ActorBody3D
extends CharacterBody3D

const SPEED = 5.0
const TURN_SPEED = 2.618  # 150 deg/sec

@onready var actor: Actor = get_parent() as Actor
@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")


func _ready() -> void:
	if mesh and not _has_own_material(mesh):
		var material := StandardMaterial3D.new()
		material.albedo_color = actor.color
		mesh.material_override = material


# Placeholder actors (bare primitive meshes, no material of their own) rely
# on `color` for visibility. A real imported model already brings its own
# materials/textures and shouldn't have them stomped by a flat color.
func _has_own_material(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.get_surface_override_material(0):
		return true
	var mesh_resource := mesh_instance.mesh
	return (
		mesh_resource
		and mesh_resource.get_surface_count() > 0
		and mesh_resource.surface_get_material(0) != null
	)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var attack_target := actor.controller.get_attack_target() if actor.controller else null
	var interact_target := actor.controller.get_interact_target() if actor.controller else null

	# Facing priority: whatever's being attacked or interacted with this
	# frame overrides everything else -- combat and interaction read wrong
	# from any angle but forward, so snapping to face the target beats
	# waiting on the player to have manually aimed there. Below that,
	# explicit turn input (the player's turn keys), applied before reading
	# move_direction so a held turn key and a held move key this same frame
	# produce movement along the new heading instead of lagging a frame.
	# Below that, AI (and anything else with no explicit turn control)
	# faces wherever it's currently walking.
	if attack_target:
		_face_position(attack_target.global_position)
	elif interact_target:
		_face_position((interact_target as Node3D).global_position)
	elif actor.controller:
		var turn_input := actor.controller.get_turn_input()
		if turn_input:
			rotate_y(-turn_input * TURN_SPEED * delta)

	var move_direction := (
		actor.controller.get_move_direction() if actor.controller else Vector3.ZERO
	)
	if move_direction:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
		if (
			not attack_target
			and not interact_target
			and actor.controller
			and actor.controller.should_auto_face_movement()
		):
			_face_position(global_position + move_direction)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	if attack_target:
		actor.try_attack(attack_target)

	if interact_target:
		actor.try_interact(interact_target)


# Yaw-only turn toward a world position -- ignores height differences so
# looking at something above/below doesn't pitch the Body off its feet.
func _face_position(target_position: Vector3) -> void:
	var flat_target := Vector3(target_position.x, global_position.y, target_position.z)
	if flat_target.is_equal_approx(global_position):
		return
	look_at(flat_target, Vector3.UP)
