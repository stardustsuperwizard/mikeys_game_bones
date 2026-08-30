# Head-mounted first-person camera. Attach to a Camera3D node and point
# target_path at the actor whose head it should ride.
#
# Unlike ThirdPersonCamera3D, this camera captures the mouse unconditionally
# while active (standard FPS convention -- there's no free-look toggle,
# since the camera *is* the look direction) and has no zoom or wall-collision
# handling, since it never leaves the target's head to begin with.
#
# This camera only turns the head (yaw + pitch); it does not rotate the
# target's body or feed movement input. A controller that wants movement to
# follow look direction should read get_look_yaw_degrees() itself rather
# than this script reaching into the target to steer it -- the same
# presentation/logic separation ActorBody3D and Controller already keep for
# movement.
class_name FirstPersonCamera3D
extends Camera3D

## Node path to the target this camera rides.
@export var target_path: NodePath = NodePath("")

## Vertical offset added to the target's position; eye height.
@export var eye_height_offset: float = 1.6

## Mouse look sensitivity in degrees per pixel of motion.
@export var mouse_sensitivity: float = 0.15

## Pitch clamp, in degrees, so the camera can't flip over past straight up/down.
@export var min_pitch_degrees: float = -85.0
@export var max_pitch_degrees: float = 85.0

var _target: Node3D = null
var _yaw_degrees: float = 0.0
var _pitch_degrees: float = 0.0


func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node3D
	if _target:
		_yaw_degrees = rad_to_deg(_target.global_rotation.y)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_transform()


# Releases the capture this camera took in _ready() -- otherwise switching
# away from first-person (to a third-person or isometric camera) leaves the
# mouse stuck captured with no cursor visible and nothing to release it.
func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_recenter"):
		_pitch_degrees = 0.0
		return
	if event is InputEventMouseMotion:
		_yaw_degrees -= event.relative.x * mouse_sensitivity
		_pitch_degrees = clamp(
			_pitch_degrees - event.relative.y * mouse_sensitivity,
			min_pitch_degrees,
			max_pitch_degrees
		)


# Exposed so a movement controller can steer the body toward where the
# player is actually looking, without this camera needing to know anything
# about controllers/actors itself.
func get_look_yaw_degrees() -> float:
	return _yaw_degrees


func _process(_delta: float) -> void:
	_update_transform()


func _update_transform() -> void:
	if _target == null:
		return
	global_position = _target.global_position + Vector3(0, eye_height_offset, 0)
	global_rotation = Vector3(deg_to_rad(_pitch_degrees), deg_to_rad(_yaw_degrees), 0)
