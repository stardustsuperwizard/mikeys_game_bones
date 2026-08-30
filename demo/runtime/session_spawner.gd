extends Node
# Bridges Godot's own multiplayer signals to this game's spawn/despawn
# behavior. Deliberately not part of mikes_basic_networking -- an addon
# meant for any game has no business knowing which scene/data file to
# spawn. Connects directly to multiplayer.peer_connected/peer_disconnected
# rather than a custom signal, since those are already the swap point any
# MultiplayerPeer implementation (ENet, or something else later) fires.

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	print("SESSION: peer connected id=%d" % id)

	var world_manager := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if not world_manager:
		push_error("SESSION: no WorldManager found to spawn peer %d into" % id)
		return

	var spawn_point := SpawnPoint.new()
	spawn_point.actor_scene = load("res://demo/scenes/actors/player.tscn")
	spawn_point.character_sheet = load("res://demo/data/players/mike.tres")

	var actor := world_manager.spawn(spawn_point, id)
	actor.owner_id = id
	print("SESSION: spawned actor for peer %d, owner_id=%d" % [id, actor.owner_id])

func _on_peer_disconnected(id: int) -> void:
	print("SESSION: peer disconnected id=%d" % id)

	for node in get_tree().get_nodes_in_group("players"):
		var actor := node as Actor
		if actor and actor.owner_id == id:
			print("SESSION: despawning actor for peer %d" % id)
			actor.queue_free()
			return
