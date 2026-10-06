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
## Gameplay overlay (queue strip, mood, skills) shown in screenshot mode too
## when VIMS_GAMEPLAY_UI=1 or --gameplay_ui=1.
var args_gameplay_ui := false
const SimOverlay := preload("res://scripts/sim/ui/sim_overlay.gd")

## Staged gameplay state per preset: the selected sim's queue and moodlets.
const STAGED := {
	"home_day": {
		"queue": {"Jack": [["Work", "laptop", 0.32], ["Pay Bills", "bill"], ["Chat", "chat"], ["Play Fetch", "ball"]],
			"Lily": [["Paint", "palette", 0.48], ["Do Homework", "book"]],
			"Maya": [["Play", "toys", 0.55], ["Practice", "music"]]},
		"moodlets": {"Jack": [["productive", "Productive", "work", 12.0, 3.0, "Earned $180"], ["coffee", "Had Coffee", "coffee", 8.0, 2.0, ""], ["lonely", "Lonely", "need_social", -8.0, 0.0, ""]],
			"Lily": [["had_fun", "Had Fun", "need_fun", 10.0, 3.0, "Paint"], ["learned", "Learned Something", "bulb", 12.0, 4.0, "Reached Creativity level 2"]],
			"Maya": [["had_fun", "Had Fun", "need_fun", 10.0, 3.0, "Play"], ["tired", "Tired", "need_energy", -12.0, 0.0, ""]],
			"Biscuit": [["belly_rubs", "Belly Rubs", "paw", 12.0, 3.0, "Loved by Lily"]]},
	},
}


func _ready() -> void:
	var args := _user_args()
	args_gameplay_ui = args.get("gameplay_ui", "") != ""
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
	if OS.get_environment("VIMS_GAMEPLAY_UI") != "" or args_gameplay_ui:
		_stage_gameplay(preset_name)
	for i in int(p.get("settle_frames", 20)):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT_SAVED ", out, " ", img.get_size())
	get_tree().quit()


## Screenshot mode: show the gameplay overlay with a staged queue / moodlets.
func _stage_gameplay(preset_name: String) -> void:
	var st: Dictionary = STAGED.get(preset_name, {})
	for i in Game.household.size():
		var m: Dictionary = Game.household[i]
		var q: Array = st.get("queue", {}).get(m.name, [])
		var view: Array = []
		for k in q.size():
			var e: Array = q[k]
			view.append({"label": e[0], "icon": e[1], "progress": e[2] if e.size() > 2 else 0.0,
				"auto": false, "current": k == 0, "forced": false})
		Game.set_queue_view(i, view)
		for ml in st.get("moodlets", {}).get(m.name, []):
			Game.add_moodlet(i, ml[0], ml[1], ml[2], ml[3], ml[4], ml[5])
	var ov := SimOverlay.new()
	ov.name = "SimOverlay"
	ov.hud = hud
	ov.static_mode = true
	add_child(ov)


func _user_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d
