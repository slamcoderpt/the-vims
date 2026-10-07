extends SceneTree
## Dev-only: renders the household portrait cards large + at native size.
## usage: godot --path . -s res://scripts/ui/dev_portrait_test.gd -- --out=/abs.png

const Portrait := preload("res://scripts/ui/portrait.gd")

func _initialize() -> void:
	var out := "/tmp/portraits.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.4, 0.3)
	bg.size = Vector2(1672, 941)
	root.add_child(bg)
	var members := [
		{"name": "Dad", "look": "dad", "kind": "adult"},
		{"name": "Bunny", "look": "bunny_girl", "kind": "child"},
		{"name": "Cat", "look": "cat_girl", "kind": "child"},
		{"name": "Dog", "look": "beagle", "kind": "dog"},
	]
	for i in members.size():
		var big = Portrait.new()
		big.position = Vector2(20 + i * 240, 20)
		root.add_child(big)
		big.setup(i, members[i], i == 0, Vector2(220, 293))
		var sm = Portrait.new()
		sm.position = Vector2(20 + i * 130, 340)
		root.add_child(sm)
		sm.setup(i, members[i], i == 0, Vector2(102, 136))
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	var n := 0
	for c in root.get_children():
		if c.get("_vp") != null:
			c._vp.get_texture().get_image().save_png(out.replace(".png", "_vp%d.png" % n))
			n += 1
	print("SAVED ", out)
	quit()
