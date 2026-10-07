extends SceneTree
## Dev harness: renders the household portrait cards at large and HUD size.
## godot --path . -s res://scripts/ui/dev/portrait_lab.gd -- --out=/path.png

const Portrait := preload("res://scripts/ui/portrait.gd")

func _initialize() -> void:
	var out := "/tmp/portrait_lab.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color("6b5a48")
	bg.size = Vector2(1400, 800)
	root.add_child(bg)
	var members := [
		{"name": "Jack", "look": "dad", "kind": "adult"},
		{"name": "Lily", "look": "bunny_girl", "kind": "child"},
		{"name": "Maya", "look": "cat_girl", "kind": "child"},
		{"name": "Biscuit", "look": "beagle", "kind": "dog"},
	]
	for i in members.size():
		var big := Portrait.new()
		big.position = Vector2(20 + i * 340, 20)
		root.add_child(big)
		big.setup(i, members[i], i == 0, Vector2(300, 390))
		var small := Portrait.new()
		small.position = Vector2(20 + i * 130, 450)
		root.add_child(small)
		small.setup(i, members[i], i == 0, [Vector2(113, 146), Vector2(100, 110), Vector2(100, 110), Vector2(100, 92)][i])
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("LAB OK ", out)
	quit()
