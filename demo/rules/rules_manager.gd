extends Node

var provider: RulesProvider = LiteRulesProvider.new()


func attack(attacker: Actor, target: Actor) -> ActionResult:
	return provider.resolve_attack(attacker, target)


# Door open/lock legality is generic game logic, not an RPG-ruleset variant
# (unlike combat resolution), so it's resolved directly here rather than
# through RulesProvider.
#
# Toggles rather than only ever opening: closing back up needs no key, so
# only the open direction checks locked. Callers that deliver this via a
# continuous approach (PlayerController's click order) must consume the
# interact target once on arrival rather than calling this every frame in
# range, or a closed-then-reopened door would flap on every physics tick.
func open(_actor: Actor, door: Door) -> ActionResult:
	if door.is_open():
		door.set_open(false)
		return ActionResult.new(true, &"closed")
	if door.is_locked():
		return ActionResult.new(false, &"locked")
	door.set_open(true)
	return ActionResult.new(true, &"opened")


# Same reasoning as open(): picking a thing up is generic game logic, not an
# RPG-ruleset variant, so it resolves here rather than through RulesProvider.
#
# This demo has no inventory, so "picked up" means only that the item leaves
# the world -- ItemPickup3D.item_base is carried but never read. A game with
# an inventory resolves pickup by interpreting item_base itself; Bones stays
# out of it deliberately, which is why the property is an untyped Resource.
func pickup(_actor: Actor, pickup_target: ItemPickup3D) -> ActionResult:
	if not is_instance_valid(pickup_target):
		return ActionResult.new(false, &"gone")
	pickup_target.queue_free()
	return ActionResult.new(true, &"picked_up")
