class_name CharacterSheet
extends Resource

@export var character_name: String = "Character"
@export var ability_scores: AbilityScores = AbilityScores.new()
@export var max_hp: int = 10
@export var armor_class: int = 10

var current_hp: int
