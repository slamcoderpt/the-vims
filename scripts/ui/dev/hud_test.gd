extends SceneTree
## Dev check for the HUD: boots main, drops SimActors into the location so
## bubbles/plumbob/portraits anchor to real actors, stages a preset, saves PNG.
## usage: xvfb-run godot --path . -s res://scripts/ui/dev/hud_test.gd -- --preset=home_day --out=/tmp/x.png

const ShotPresets := preload("res://scripts/core/shot_presets.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var preset: String = args.get("preset", "home_day")
	var out: String = args.get("out", "/tmp/hud_test.png")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var p: Dictionary = ShotPresets.PRESETS[preset]
	var game = root.get_node("Game")
	game.frozen = true
	game.season = p.get("season", 0)
	game.set_time(p.get("day", 0), p.get("hour", 12), p.get("minute", 0))
	if p.has("tasks"):
		game.set_tasks(p.tasks)
	main.load_location(p.location)
	var SA = load("res://scripts/world/actors/sim_actor.gd")
	var spots := {"Jack": Vector3(-1.5, 0, -0.5), "Lily": Vector3(1.0, 0, -1.5), "Maya": Vector3(2.0, 0, 1.5), "Biscuit": Vector3(-0.5, 0, 2.0)}
	for m in game.household:
		var a = SA.create(m.look)
		a.name = m.name
		main.location.add_child(a)
		a.position = spots.get(m.name, Vector3.ZERO)
	main.camera_rig.apply(p.camera)
	main.hud.apply_preset(preset, p)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("TEST_SAVED ", out)
	quit()
