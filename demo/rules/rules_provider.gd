class_name RulesProvider
extends RefCounted

func resolve_attack(_attacker: Actor, _defender: Actor) -> ActionResult:
	push_error("RulesProvider.resolve_attack() not implemented")
	return ActionResult.new(false)
