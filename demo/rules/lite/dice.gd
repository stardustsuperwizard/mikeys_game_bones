class_name Dice

static func roll(sides: int) -> int:
	return randi_range(1, sides)

static func d6() -> int:
	return roll(6)

static func d20() -> int:
	return roll(20)
