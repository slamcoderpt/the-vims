extends Node
## Debug probe: Jack showers upstairs, then cooks at the stove; prints his state.
var main: Node
var args := {}
const ActionAnims := preload("res://scripts/world/actors/action_anims.gd")


func _ready() -> void:
	await get_tree().process_frame
	var sim = main.sim
	var jack = null
	for a in sim.agents:
		if a and a.display_name() == "Jack":
			jack = a
	jack.autonomy = false
	var sh = null
	var stove = null
	for it in sim.interactables:
		if it.title == "Shower":
			sh = it
		if it.title == "Stove":
			stove = it
	var r: Dictionary = sim.approach(jack, {"action": {"id": "shower", "pose": "idle"}, "target": sh})
	jack.actor.global_position = r.spot
	var act: Dictionary = {}
	for a in sim.actions_for(stove, jack.member):
		if a.id == "cook":
			act = a
	print("cook action: ", act)
	Game.speed = 3
	var ok: bool = jack.command({"action": act, "target": stove})
	print("command ok=", ok, " phase=", jack.phase, " spot=", jack.spot, " path=", jack.path.size())
	var t0 := Game.total_minutes()
	while Game.total_minutes() - t0 < 120.0:
		await get_tree().create_timer(1.0).timeout
		var aa = ActionAnims.of(jack.actor)
		print("  t=%.0f phase=%s beat=%s anim=%s active=%s pos=%s label=%s props=%s" % [Game.total_minutes() - t0, jack.phase, jack.beat, jack.anim, aa.active if aa else "-", str(jack.actor.global_position), jack.current_label(), str(aa.visible_props()) if aa else ""])
		if jack.phase == "idle":
			break
	print("RESULT PASS probe")
	get_tree().quit(0)
