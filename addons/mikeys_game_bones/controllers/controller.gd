class_name Controller
extends Node

@onready var actor: Actor = get_parent() as Actor


func get_move_direction() -> Vector3:
	return Vector3.ZERO


func get_turn_input() -> float:
	return 0.0


# Whether the Body should auto-rotate to face get_move_direction() when
# nothing else claims facing this frame (no attack/interact target, no
# turn input). True by default for AI, which has no other way to turn;
# PlayerController overrides this false since strafing without a turn
# key held is deliberate -- it shouldn't spin the player to face travel.
func should_auto_face_movement() -> bool:
	return true


func get_attack_target() -> Actor:
	return null


func get_interact_target() -> Node:
	return null
