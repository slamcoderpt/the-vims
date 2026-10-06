extends Node
## Boots the game: world (location + lighting + camera), the HUD and the
## gameplay layer (scripts/sim/sim_world.gd).
## Command line (after `--`):
##   --shot=<preset> --out=<file.png>   render one screenshot of a preset (see
##                                      shot_presets.gd) and quit (no sim layer).
##   --playtest=<name> [--shots=<dir>]  run scripts/sim/tests/<name>.gd (an
##                                      automated playtest) on top of live play.
##   --location=<name>                  start in another lot (home, backyard, festival, market).

const ShotPresets := preload("res://scripts/core/shot_presets.gd")
const SimWorld := preload("res://scripts/sim/sim_world.gd")

var world: Node3D
var location: Node3D
var lighting: Node
var camera_rig: Node3D
var hud: CanvasLayer
var sim: Node


func _ready() -> void:
	var args := _user_args()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	lighting = preload("res://scripts/world/lighting.gd").new()
	lighting.name = "Lighting"
	world.add_child(lighting)
	camera_rig = preload("res://scripts/world/camera_rig.gd").new()
	camera_rig.name = "CameraRig"
	world.add_child(camera_rig)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	Game.location_changed.connect(load_location)
	if args.has("shot"):
		await _shot(args.shot, args.get("out", "user://shot.png"))
		return
	# Live play: the gameplay layer comes after the HUD so it sees input first
	# in _input (to know whether a menu was open) and after it in GUI handling.
	sim = SimWorld.new()
	sim.main = self
	add_child(sim)
	if args.has("location"):
		Game.location = args.location
	load_location(Game.location)
	if args.has("playtest"):
		var path := "res://scripts/sim/tests/%s.gd" % args.playtest
		var pt: Node = load(path).new()
		pt.name = "Playtest"
		pt.set("main", self)
		pt.set("args", args)
		add_child(pt)


func load_location(loc_name: String) -> void:
	if location:
		world.remove_child(location)
		location.queue_free()
		location = null
	var path := "res://scripts/locations/%s.gd" % loc_name
	location = load(path).new()
	location.name = loc_name.capitalize()
	world.add_child(location)
	if location.has_method("build"):
		location.build()
	Game.location = loc_name
	lighting.configure(location)
	if location.has_method("camera_home"):
		camera_rig.apply(location.camera_home())
	if sim:
		sim.bind_location(location, loc_name)


func _shot(preset_name: String, out: String) -> void:
	var p: Dictionary = ShotPresets.PRESETS[preset_name]
	Game.frozen = true
	Game.season = p.get("season", 0)
	Game.set_time(p.get("day", 0), p.get("hour", 12), p.get("minute", 0))
	if p.has("tasks"):
		Game.set_tasks(p.tasks)
	load_location(p.location)
	if location.has_method("apply_preset"):
		location.apply_preset(preset_name)
	camera_rig.apply(p.camera)
	if hud.has_method("apply_preset"):
		hud.apply_preset(preset_name, p)
	for i in int(p.get("settle_frames", 20)):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT_SAVED ", out, " ", img.get_size())
	get_tree().quit()


func _user_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d
