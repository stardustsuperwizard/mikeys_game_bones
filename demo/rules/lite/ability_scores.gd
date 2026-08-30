class_name AbilityScores
extends Resource

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

static func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)
