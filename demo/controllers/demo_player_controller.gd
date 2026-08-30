# The demo's player controller: click-to-order movement plus keyboard
# steering, on top of Bones' Controller contract.
#
# Keyboard: W/S forward and back, Q/E strafe, A/D turn, F interact.
# Mouse: left click is the contextual action button. What it does depends on
# what was clicked -- ground walks there, a wall walks up to it and stops, a
# hostile actor closes to melee range and attacks, an interactable closes and
# uses it. Each click issues a single order carried out over the following
# frames; a new click, or any keyboard movement, replaces or cancels it.
#
# This lives in demo/, NOT in addons/. It arrived here from
# mikeys_game_world, where it had been written by editing the framework's
# own PlayerController in place -- 64 lines becoming 282. The behavior was
# never the problem; the location was. A controller decides things, and
# deciding is what varies per game, so concrete controllers belong to the
# game and only the Controller contract belongs to the framework. See
# docs/ARCHITECTURE_BOUNDARIES.md.
#
# It extends Controller directly rather than the framework's reference
# PlayerController: it overrides every method that one defines, so
# inheriting it would buy nothing and imply a relationship that is not
# there.
class_name DemoPlayerController
extends Controller

# A surface at least this upright counts as ground the player can stand on;
# anything steeper is a wall, which is walked up to rather than onto.
const WALKABLE_NORMAL_Y := 0.7

# How head-on a wall contact must be to count as "arrived" rather than
# "brushing past" -- roughly 60 degrees either side of straight into it.
const WALL_BLOCK_DOT := -0.5

# Exported (not const) so a differently-scaled presentation can retune them
# per instance -- same pattern SimpleAIController already uses for aggro_range/
# attack_range. The 2D room is pixel-scale, not small-unit like 3D, so its
# Player overrides these; 3D's default here is unchanged.
@export var attack_range := 2.0
@export var interact_range := 2.0

## How close the player must get to a clicked ground point to have arrived.
@export var move_arrival_distance := 0.4

## How far the click raycast reaches into the world, in meters.
@export var max_click_distance := 100.0

## Physics layers the click raycast can select.
@export_flags_3d_physics var click_collision_mask: int = 1

## How long an order may go without progress before it's abandoned. There's
## no pathfinding, so an order stuck behind an obstacle would otherwise
## leave the player shoving into it forever.
@export var order_stall_timeout := 0.75

## Distance, in meters, that counts as real progress toward an order.
@export var order_stall_progress := 0.05

var _interact_requested := false

# The current click order -- at most one of these is ever live. Set by a
# left click (action_primary), classified by what the raycast hit; cleared
# by keyboard movement, arrival, an invalidated target, or a new click.
var _order_destination := Vector3.ZERO
var _order_destination_is_wall := false
var _has_order_destination := false
var _order_attack_target: Actor = null
var _order_interact_target: Node = null

var _order_closest_distance := INF
var _order_stall_timer := 0.0


func _ready() -> void:
	actor.add_to_group("players")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_interact_requested = true
	# basic_attack is intentionally NOT read here -- it shares mouse1 with
	# action_primary in project.godot, and consuming both would fire an
	# extra attack alongside the click order below. Attacking a clicked
	# target happens automatically, in get_attack_target(), once the order
	# below brings the player into range.
	if event.is_action_pressed("action_primary"):
		_issue_order_from_click(get_viewport().get_mouse_position())


# This project steers with turn_left/turn_right (see get_turn_input()) plus
# strafe_left/strafe_right rather than a top-down left/right axis, so
# forward/back and strafe are local to the actor's current facing --
# transformed by the Body's own rotation, not applied directly as a world
# vector. Body may be either presentation (see actors/bodies/), so both a
# Node3D's basis and a Node2D's transform need handling here.
#
# Keyboard movement takes precedence over, and cancels, any click order --
# grabbing the controls manually should always win outright.
func get_move_direction() -> Vector3:
	var local_dir := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		0,
		Input.get_axis("move_forward", "move_back")
	)

	if local_dir != Vector3.ZERO:
		_cancel_order()
	elif _has_active_order():
		return _order_move_direction()

	if local_dir == Vector3.ZERO:
		return Vector3.ZERO

	var body_3d := actor.get_node("Body") as Node3D
	if body_3d:
		return (body_3d.global_transform.basis * local_dir).normalized()

	var body_2d := actor.get_node("Body") as Node2D
	if body_2d:
		var world_2d := body_2d.global_transform.basis_xform(Vector2(local_dir.x, local_dir.z))
		return Vector3(world_2d.x, 0, world_2d.y).normalized()

	return Vector3.ZERO


func get_turn_input() -> float:
	return Input.get_axis("turn_left", "turn_right")


# Strafing/turning with no order active is deliberate manual aim -- the
# Body shouldn't spin to face wherever that happens to be carrying the
# player. A click-issued move order, like AI's chase, should auto-face the
# direction it's walking; an attack/interact target still overrides this
# at the Body level regardless of what this returns.
func should_auto_face_movement() -> bool:
	return _has_active_order()


func get_attack_target() -> Actor:
	if _order_attack_target and not is_instance_valid(_order_attack_target):
		_order_attack_target = null
	if _order_attack_target and _in_order_range(_order_attack_target, attack_range):
		return _order_attack_target
	return null


func get_interact_target() -> Node:
	if _order_interact_target and not is_instance_valid(_order_interact_target):
		_order_interact_target = null
	if _order_interact_target and _in_order_range(_order_interact_target, interact_range):
		# Consumed once on arrival, unlike an attack order -- Rules.open()
		# toggles, so returning this every frame in range (the way an
		# attack target does) would flip a door open/closed on every
		# physics tick instead of once.
		var target := _order_interact_target
		_order_interact_target = null
		return target

	if not _interact_requested:
		return null
	_interact_requested = false
	return get_nearby_interactable()


# Same search as get_interact_target(), but non-consuming and independent of
# whether interact was actually pressed -- for UI (an on-screen "Press F to
# interact" prompt) that needs to know what's in range every frame.
func get_nearby_interactable() -> Node:
	var nearest: Node = null
	var nearest_dist := interact_range
	for node in actor.get_tree().get_nodes_in_group("interactables"):
		var interactable := node as Node3D
		if not interactable:
			continue
		var dist := actor.global_position.distance_to(interactable.global_position)
		if dist <= nearest_dist:
			nearest = interactable
			nearest_dist = dist
	return nearest


func _has_active_order() -> bool:
	return _has_order_destination or _order_attack_target != null or _order_interact_target != null


func _cancel_order() -> void:
	_has_order_destination = false
	_order_destination_is_wall = false
	_order_attack_target = null
	_order_interact_target = null
	_order_closest_distance = INF
	_order_stall_timer = 0.0


# Raycasts from the camera through the clicked pixel and turns whatever it
# hits into an order: a hostile actor is attacked, an interactable is used,
# anything else -- walls included -- is walked to. A click that hits
# nothing clears the current order. No-ops without a 3D camera (this click
# system doesn't have a 2D equivalent yet).
func _issue_order_from_click(screen_position: Vector2) -> void:
	var body := actor.get_node_or_null("Body") as Node3D
	var camera := get_viewport().get_camera_3d()
	if not body or not camera:
		return

	var from := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(screen_position) * max_click_distance
	)
	query.collision_mask = click_collision_mask
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)

	_cancel_order()
	if hit.is_empty():
		return

	var collider := hit["collider"] as Node
	var hit_actor := collider.get_parent() as Actor if collider else null
	if hit_actor and hit_actor != actor and hit_actor.hostile:
		_order_attack_target = hit_actor
	elif collider and collider.is_in_group("interactables"):
		_order_interact_target = collider
	else:
		_order_destination = hit["position"]
		_order_destination_is_wall = (hit["normal"] as Vector3).y < WALKABLE_NORMAL_Y
		_has_order_destination = true


# Drops an order whose target has gone away, and reports whether one is still
# live. Split out of _order_move_direction() to keep that function under the
# linter's return-count limit; the checks and their order are unchanged, and
# every branch it replaced returned Vector3.ZERO.
func _order_is_live() -> bool:
	if _order_attack_target and not is_instance_valid(_order_attack_target):
		_cancel_order()
		return false
	if _order_interact_target and not is_instance_valid(_order_interact_target):
		_cancel_order()
		return false
	return _has_active_order()


# Walks toward the live order until inside the distance at which it
# resolves (get_attack_target()/get_interact_target() take over from
# there, and keep returning the target every frame it stays in range --
# Rules' attack cooldown and idempotent open()/pickup() make repeat calls
# safe, so there's no need to track a separate "resolved" state here).
# Also where stall detection is metered, since ActorBody3D calls this
# exactly once per physics frame.
func _order_move_direction() -> Vector3:
	var body := actor.get_node_or_null("Body") as Node3D
	if not body:
		return Vector3.ZERO

	if not _order_is_live():
		return Vector3.ZERO

	var goal := _order_goal()
	var stop_distance := _order_stop_distance()
	var to_goal := goal - body.global_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	if distance <= stop_distance:
		# A plain destination is done once reached; an attack/interact
		# order stays live so combat/interaction keeps resolving while in
		# range (see the doc comment above).
		if _order_attack_target == null and _order_interact_target == null:
			_cancel_order()
		return Vector3.ZERO

	var direction := to_goal / distance

	# A wall destination is reached as soon as the body is pushing into
	# something blocking the way there -- the walk can never close the
	# last body-radius of distance, so waiting on move_arrival_distance
	# would leave the player grinding into the wall until the stall guard
	# eventually fired instead.
	if (
		_order_destination_is_wall
		and body is CharacterBody3D
		and (body as CharacterBody3D).is_on_wall()
		and (body as CharacterBody3D).get_wall_normal().dot(direction) < WALL_BLOCK_DOT
	):
		_cancel_order()
		return Vector3.ZERO

	if distance < _order_closest_distance - order_stall_progress:
		_order_closest_distance = distance
		_order_stall_timer = 0.0
	else:
		_order_stall_timer += actor.get_physics_process_delta_time()
		if _order_stall_timer >= order_stall_timeout:
			_cancel_order()
			return Vector3.ZERO

	return direction


func _order_goal() -> Vector3:
	if _order_attack_target:
		return _order_attack_target.global_position
	if _order_interact_target:
		return (_order_interact_target as Node3D).global_position
	return _order_destination


func _order_stop_distance() -> float:
	if _order_attack_target:
		return attack_range
	if _order_interact_target:
		return interact_range
	return move_arrival_distance


# Range is measured on the ground plane, matching _order_move_direction()'s
# own arrival check -- measuring in 3D would deadlock on a target whose
# origin sits above the floor (a door's does) by never satisfying a range
# check the walk itself considers close enough.
func _in_order_range(node: Node, range_limit: float) -> bool:
	var target_position: Vector3 = (
		(node as Actor).global_position if node is Actor else (node as Node3D).global_position
	)
	var offset := target_position - actor.global_position
	return Vector2(offset.x, offset.z).length() <= range_limit
