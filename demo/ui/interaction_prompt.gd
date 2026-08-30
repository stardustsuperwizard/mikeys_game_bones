class_name InteractionPrompt
extends CanvasLayer

@export var prompt_text: String = "Press F to interact"

# The Player is spawned at runtime by WorldManager, not present when this
# scene is edited, so it can't be wired up as an @export -- found lazily via
# the "players" group PlayerController already adds its Actor to.
var _player_controller: PlayerController

@onready var label: Label = get_node_or_null("Label")


func _ready() -> void:
	if label:
		label.text = prompt_text
		label.visible = false


func _process(_delta: float) -> void:
	if not label:
		return

	if not _player_controller:
		_find_player_controller()
		if not _player_controller:
			label.visible = false
			return

	label.visible = _player_controller.get_nearby_interactable() != null


func _find_player_controller() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		var actor := node as Actor
		if actor and actor.controller is PlayerController:
			_player_controller = actor.controller
			return
