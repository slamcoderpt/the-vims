extends SceneTree
## Dev check: renders the household portrait cards large on a plain backdrop.
## usage: xvfb-run godot --path . -s res://scripts/ui/dev/portrait_test.gd -- --out=/tmp/p.png --scale=3

const Portrait := preload("res://scripts/ui/portrait.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/portraits.png"
	var sc := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--scale="):
			sc = float(a.substr(8))
	var game = root.get_node("Game")
	var bg := ColorRect.new()
	bg.color = Color("6b5a4a")
	bg.size = Vector2(1672, 941)
	root.add_child(bg)
	var holder := Control.new()
	holder.scale = Vector2(sc, sc)
	holder.position = Vector2(20, 20)
	root.add_child(holder)
	var x := 0.0
	for i in game.household.size():
		var m: Dictionary = game.household[i]
		var sel: bool = i == 0
		var p := Portrait.new()
		var sz: Vector2 = Vector2(113, 146) if sel else (Vector2(100, 88) if m.kind == "dog" else Vector2(100, 116))
		p.setup(i, m, sel, sz)
		p.position = Vector2(x, 0)
		holder.add_child(p)
		x += sz.x + 10.0
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("TEST_SAVED ", out)
	quit()
