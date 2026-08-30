# Fixed-angle isometric/strategy camera. Attach to a Camera3D node and
# point target_path at whatever it should track (usually the player).
#
# No mouse-look -- pitch and yaw are fixed exports, tuned once in the
# inspector for the game's grid/art style. Only zoom (scroll wheel) moves
# at runtime, using the same spring-toward-target-distance approach as
# ThirdPersonCamera3D so a zoom step glides in rather than snapping.
#
# Deliberately no view-rotation input: rotating an isometric camera around
# the target needs a dedicated action (e.g. camera_rotate_left/right) that
# doesn't exist in this project's input map yet, and guessing a binding
# risks colliding with something else already there (see the strafe_right/
# interact collision earlier in this project's history). Add rotate_step_
# degrees-style input here once that action exists.
class_name IsometricCamera3D
extends Camera3D

## Node path to the target this camera tracks.
@export var target_path: NodePath = NodePath("")

## Downward tilt, in degrees. ~35.26 is the "true" isometric angle
## (arctan(1/sqrt(2))); many games cheat this up toward 45-60 for readability.
@export var pitch_degrees: float = 45.0

## Horizontal facing, in degrees, around the target.
@export var yaw_degrees: float = 45.0

## Zoom distance the camera starts at.
@export var default_distance: float = 14.0

## Zoom distance clamp, scroll-wheel step, and glide speed, in meters.
@export var min_distance: float = 6.0
@export var max_distance: float = 24.0
@export var zoom_step: float = 1.0
@export var zoom_speed: float = 8.0

var _target: Node3D = null
var _target_distance: float
var _spring_length: float


func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node3D
	_target_distance = clamp(default_distance, min_distance, max_distance)
	_spring_length = _target_distance
	_update_transform(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = max(min_distance, _target_distance - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = min(max_distance, _target_distance + zoom_step)


func _process(delta: float) -> void:
	_update_transform(delta)


func _update_transform(delta: float) -> void:
	if _target == null:
		return

	var pivot := _target.global_position
	var yaw_rad := deg_to_rad(yaw_degrees)
	var pitch_rad := deg_to_rad(pitch_degrees)

	# Same pivot-relative direction math as ThirdPersonCamera3D, just with
	# fixed yaw/pitch instead of mouse-driven values.
	var direction := Vector3(
		sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), cos(yaw_rad) * cos(pitch_rad)
	)

	_spring_length = move_toward(_spring_length, _target_distance, zoom_speed * delta)

	global_position = pivot + direction * _spring_length
	look_at(pivot, Vector3.UP)
