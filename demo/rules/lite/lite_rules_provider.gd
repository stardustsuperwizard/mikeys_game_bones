class_name LiteRulesProvider
extends RulesProvider

func resolve_attack(attacker: Actor, target: Actor) -> ActionResult:
	var attacker_sheet := attacker.character_sheet
	var target_sheet := target.character_sheet
	var modifier := AbilityScores.modifier(attacker_sheet.ability_scores.strength)
	var roll := Dice.d20()
	var total := roll + modifier

	if total < target_sheet.armor_class:
		print("%s misses %s (%d+%d=%d vs AC %d)" % [attacker_sheet.character_name, target_sheet.character_name, roll, modifier, total, target_sheet.armor_class])
		return ActionResult.new(false, &"miss")

	var damage := maxi(1, Dice.d6() + modifier)
	print("%s hits %s (%d+%d=%d vs AC %d) for %d damage" % [attacker_sheet.character_name, target_sheet.character_name, roll, modifier, total, target_sheet.armor_class, damage])
	target.take_damage(damage)
	return ActionResult.new(true, &"hit")
