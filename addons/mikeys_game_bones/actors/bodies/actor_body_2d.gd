class_name ActorBody2D
extends CharacterBody2D

# Pixel-scale, unlike ActorBody3D's small-unit SPEED -- ranges/aggro on
# PlayerController/SimpleAIController are @export, not const, specifically so a
# differently-scaled presentation like this one can retune them per instance
# instead of forcing every presentation onto one shared coordinate scale.
const SPEED = 220.0
const TURN_SPEED = 2.618  # 150 deg/sec, matching ActorBody3D

@onready var actor: Actor = get_parent() as Actor
@onready var polygon: Polygon2D = get_node_or_null("Polygon2D")


func _ready() -> void:
	if polygon:
		polygon.color = actor.color


# No gravity/is_on_floor() here -- a top-down 2D room has no vertical axis
# to fall along, unlike ActorBody3D's ground-based movement.
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var attack_target := actor.controller.get_attack_target() if actor.controller else null
	var interact_target := actor.controller.get_interact_target() if actor.controller else null

	# Same facing priority as ActorBody3D: attack/interact target overrides
	# turn input, which overrides auto-facing the current move direction.
	if attack_target:
		_face_position(_to_2d(attack_target.global_position))
	elif interact_target:
		_face_position((interact_target as Node2D).global_position)
	elif actor.controller:
		var turn_input := actor.controller.get_turn_input()
		if turn_input:
			rotation += -turn_input * TURN_SPEED * delta

	var move_direction := (
		actor.controller.get_move_direction() if actor.controller else Vector3.ZERO
	)
	var move_direction_2d := Vector2(move_direction.x, move_direction.z)
	if move_direction_2d:
		velocity = move_direction_2d * SPEED
		if (
			not attack_target
			and not interact_target
			and actor.controller
			and actor.controller.should_auto_face_movement()
		):
			_face_position(global_position + move_direction_2d)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

	move_and_slide()

	if attack_target:
		actor.try_attack(attack_target)

	if interact_target:
		actor.try_interact(interact_target)


# actor.global_position bridges 2D onto 3D's XZ ground plane (see Actor) --
# this undoes that bridge for a 2D body's own facing math.
func _to_2d(position_3d: Vector3) -> Vector2:
	return Vector2(position_3d.x, position_3d.z)


# The face art sits at local -Y (see scenes/actors/*_2d.tscn), so "forward"
# at rotation 0 is -Y, not Node2D.look_at()'s +X convention -- offset by 90
# degrees to compensate rather than fighting that convention.
func _face_position(target_position: Vector2) -> void:
	if target_position.is_equal_approx(global_position):
		return
	rotation = (target_position - global_position).angle() + PI / 2.0
