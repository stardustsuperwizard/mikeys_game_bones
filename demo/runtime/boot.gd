extends Node

# mikeys_basic_networking is optional -- deleting it should degrade to
# single-player, not fail to boot. Loading it defensively from here, rather
# than giving it its own direct entry in project.godot's [autoload] list,
# is what makes that true: an invalid autoload path is a hard failure Godot
# logs at startup regardless of what the missing script would have done.
const NETWORKING_SCRIPT := "res://addons/mikeys_basic_networking/network_bootstrap.gd"
const SESSION_SPAWNER_SCRIPT := "res://demo/runtime/session_spawner.gd"

func _ready() -> void:
	if ResourceLoader.exists(NETWORKING_SCRIPT):
		add_child((load(NETWORKING_SCRIPT) as GDScript).new())
		add_child((load(SESSION_SPAWNER_SCRIPT) as GDScript).new())
