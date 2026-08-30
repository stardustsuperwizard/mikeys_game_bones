# WoW-style third-person "chase" camera. Attach to a Camera3D node and
# configure the target via exports.
#
# This addon is the canonical home for this camera. It began life as
# mikeys_game_bones-rules-moba/scripts/third_person_camera_3d.gd and was
# copied into mikeys_game_world before either repo had a shared package to
# put it in; both of those copies had already drifted apart by the time this
# addon was created. Improvements land here and flow outward -- do not edit a
# consumer's copy.
#
# Current behavior: the camera holds whatever yaw you last mouse-looked
# to. Holding the right mouse button free-looks around the target; the
# camera keeps that angle on release rather than swinging back behind the
# target. The scroll wheel zooms, and a raycast keeps the camera from
# clipping through walls. The recenter_action input action snaps the view
# back to the default over-the-shoulder framing -- behind the target, default
# pitch and zoom.
#
# Setting auto_realign restores the WoW-style chase camera: the view tracks
# the target's facing (so turning with A/D turns the camera too) and
# realigns behind them after a free-look.
#
# This camera owns Input.mouse_mode outright. It captures the mouse on
# right-button press, and _process() reconciles the mode against the button's
# real state every frame (see should_release_capture), so any capture set
# elsewhere without the right button held is cleared within a frame. Nothing
# else writes mouse_mode today; a future system that needs a captured cursor of
# its own has to coordinate with this reconciliation rather than set the mode
# behind it.
class_name MikeyThirdPersonCamera3D
extends Camera3D

## Node path to the target this camera tracks.
@export var target_path: NodePath = NodePath("")

## Input action that snaps the view back to its default framing. The action
## is looked up by name at runtime and is entirely optional -- if the project
## has no such action the camera just never recenters, and nothing errors.
## Set to &"" to disable recentering outright. See this addon's README.
@export var recenter_action: StringName = &"camera_recenter"

## Vertical offset added to the target's position; roughly chest/head height.
@export var target_height_offset: float = 1.4

## Mouse look sensitivity in degrees per pixel of motion.
@export var mouse_sensitivity: float = 0.2

## Whether the camera follows the target's facing and swings back behind
## them after a free-look. Off for now -- the camera stays where you point
## it -- but the chase behavior is intact behind this flag.
@export var auto_realign: bool = false

## How fast (degrees/sec) the camera yaw settles back behind the target
## once the right mouse button is released. Only used when auto_realign.
@export var realign_speed_degrees: float = 180.0

## Pitch the camera starts at and returns to when recentered.
@export var default_pitch_degrees: float = 20.0

## Pitch clamp, in degrees. Positive pitch elevates the camera above the
## target (looking down at them); this is clamped so it can't dive below
## the target's own height or flip over into a top-down view.
@export var min_pitch_degrees: float = -10.0
@export var max_pitch_degrees: float = 80.0

## Zoom distance the camera starts at and returns to when recentered.
@export var default_distance: float = 8.0

## Zoom distance clamp and scroll-wheel step, in meters.
@export var min_distance: float = 2.5
@export var max_distance: float = 16.0
@export var zoom_step: float = 1.0
@export var zoom_speed: float = 8.0

## Physics layers the wall-collision raycast checks against.
@export_flags_3d_physics var collision_mask: int = 1

## Gap kept between the camera and any wall it collides with.
@export var collision_margin: float = 0.3

## Group searched for a target if target_path doesn't resolve at _ready()
## (or is left empty), for players spawned at runtime rather than authored
## into the scene: Godot readies children before parents, so a camera whose
## _ready() runs before the spawner's has no target to bind yet. The group
## member may be the player root; its "Body" child is preferred when present
## (see _try_find_fallback_target). Ignored once a target is found; set to
## &"" to disable and rely on target_path only.
##
## This default is the one place this addon assumes anything about its host
## -- &"players" is the group mikeys_game_bones' PlayerController adds. It is
## a default, not a dependency: nothing here imports Bones.
@export var fallback_target_group: StringName = &"players"

var _target: Node3D = null
var _yaw_degrees: float = 0.0
var _pitch_degrees: float  # seeded from default_pitch_degrees by recenter() in _ready
var _target_distance: float  # both seeded from default_distance by
var _spring_length: float  # recenter() in _ready


func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node3D
	recenter()
	_update_transform(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _is_recenter_pressed(event):
		recenter()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
			)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = max(min_distance, _target_distance - zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = min(max_distance, _target_distance + zoom_step)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw_degrees -= event.relative.x * mouse_sensitivity
		_pitch_degrees = clamp(
			_pitch_degrees - event.relative.y * mouse_sensitivity,
			min_pitch_degrees,
			max_pitch_degrees
		)


# Snaps the whole view back to its default framing: behind the target, at
# the default pitch and zoom. Also doubles as the camera's initial setup in
# _ready(), which is what keeps "the default view" a single definition
# rather than two that can drift apart.
#
# _spring_length is set alongside _target_distance so the zoom snaps with
# everything else instead of gliding in afterwards at zoom_speed.
func recenter() -> void:
	if _target:
		_yaw_degrees = rad_to_deg(_target.global_rotation.y)
	_pitch_degrees = clamp(default_pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	_target_distance = clamp(default_distance, min_distance, max_distance)
	_spring_length = _target_distance


# Whether a capture in `mouse_mode` should be released given the right button's
# actual pressed state.
#
# Capture is entered on right-button press and released on its release, so a
# release event that never arrives -- a trackpad gesture that generates none, a
# focus change, a dropped OS event -- otherwise strands the mouse in
# MOUSE_MODE_CAPTURED for the rest of the session, silently swallowing every
# left click.
#
# Static and pure so the reconciliation rule is testable: `Input.mouse_mode` is
# a no-op under the headless DisplayServer, which makes the live behavior
# unobservable in a headless test.
static func should_release_capture(mouse_mode: int, right_button_pressed: bool) -> bool:
	return mouse_mode == Input.MOUSE_MODE_CAPTURED and not right_button_pressed


func _process(delta: float) -> void:
	if should_release_capture(Input.mouse_mode, Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _target == null:
		_try_find_fallback_target()

	_update_transform(delta)


# See fallback_target_group -- a player that doesn't exist yet at _ready()
# joins the group within a frame or two of spawning. The group member is
# often a logical node rather than a Node3D (Bones' Actor is a plain Node),
# so the "Body" child is what actually gets tracked when there is one.
func _try_find_fallback_target() -> void:
	if fallback_target_group == &"":
		return
	var candidates := get_tree().get_nodes_in_group(fallback_target_group)
	if candidates.is_empty():
		return
	var body := (candidates[0] as Node).get_node_or_null("Body") as Node3D
	if body:
		_target = body
		recenter()


func _update_transform(delta: float) -> void:
	if _target == null:
		return

	var pivot := _target.global_position + Vector3(0, target_height_offset, 0)

	if auto_realign and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var target_yaw := rad_to_deg(_target.global_rotation.y)
		var yaw_diff := wrapf(target_yaw - _yaw_degrees, -180.0, 180.0)
		_yaw_degrees += clamp(
			yaw_diff, -realign_speed_degrees * delta, realign_speed_degrees * delta
		)

	var yaw_rad := deg_to_rad(_yaw_degrees)
	var pitch_rad := deg_to_rad(_pitch_degrees)

	# Unit vector from the pivot to the camera: behind and above the
	# target once yaw/pitch are applied (yaw = 0 matches the target's own
	# un-rotated facing, since the target's forward is -Z).
	var direction := Vector3(
		sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), cos(yaw_rad) * cos(pitch_rad)
	)

	_spring_length = move_toward(_spring_length, _target_distance, zoom_speed * delta)
	var distance := _resolve_collision_distance(pivot, direction, _spring_length)

	global_position = pivot + direction * distance
	look_at(pivot, Vector3.UP)


func _resolve_collision_distance(
	pivot: Vector3, direction: Vector3, desired_distance: float
) -> float:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot, pivot + direction * desired_distance)
	query.collision_mask = collision_mask
	if _target is CollisionObject3D:
		query.exclude = [(_target as CollisionObject3D).get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		return maxf(pivot.distance_to(result.position) - collision_margin, 0.1)
	return desired_distance


# True only when `recenter_action` is both configured and actually present in
# the project's InputMap.
#
# The guard is not defensive padding: `InputEvent.is_action_pressed()` on an
# action the project never defined raises "Request for nonexistent InputMap
# action" on *every* input event, so a consumer who installs this addon and
# hasn't added the binding yet gets an error storm rather than a camera that
# simply doesn't recenter. A library cannot assume its host's InputMap.
func _is_recenter_pressed(event: InputEvent) -> bool:
	if recenter_action == &"":
		return false
	if not InputMap.has_action(recenter_action):
		return false
	return event.is_action_pressed(recenter_action)
