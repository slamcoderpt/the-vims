extends RefCounted
## Dedicated HUD portrait busts (ref1 top-left cards).
##
## The in-world SimActor heads are ~10 voxels wide: at card size they read as
## mush. The ref cards show the same characters as a higher-detail voxel bust
## (head ~16-18 voxels wide, big eyes with highlights, brows, nose, smile,
## defined beard / bangs / knit hat, shirt collar and shoulders). This builds
## that bust procedurally from the look's palette in sim_looks.gd, so the card
## always matches the 3D character's colours, as ONE merged mesh.
##
## Grid: x right, y up (chin = 0), z toward the camera (face plane z = 6).
## build(look) -> {mesh: ArrayMesh, frame: Rect2 (voxel units, y up, the
## card's visible window), yaw: deg, pitch: deg, kind: String}

const LOOKS_PATH := "res://scripts/world/actors/sim_looks.gd"
const VS := 0.05

static var _cache := {}

var b: VoxelBuilder
var L: Dictionary
var kid := false


static func build(look_name: String) -> Dictionary:
	if _cache.has(look_name):
		return _cache[look_name]
	var look := {}
	if ResourceLoader.exists(LOOKS_PATH):
		var s: Script = load(LOOKS_PATH)
		if s != null and s.can_instantiate():
			look = s.get_look(look_name)
	if look.is_empty():
		return {}
	var pb = new()
	var out: Dictionary = pb._make(look)
	_cache[look_name] = out
	return out


func _make(look: Dictionary) -> Dictionary:
	L = look
	b = VoxelBuilder.new()
	b.jitter = 0.022
	var frame: Rect2
	var yaw := 11.0
	var pitch := 6.0
	var kind := "adult"
	if L.get("species", "") == "dog":
		kind = "dog"
		_dog()
		# Head (ears included) fills the card, chest and collar below.
		frame = _frame(-0.5, 16.5, 31.0)
		yaw = 16.0
		pitch = 8.0
	else:
		kid = L.get("body", "") == "child"
		kind = "child" if kid else "adult"
		_torso()
		_head()
		_hair()
		if L.has("hat"):
			_hat()
		if kid:
			# Ref kid cards: hat (ears just cropped) at the top, chin ~80%
			# down, collar and straps along the bottom.
			frame = _frame(-0.5, 26.4, 30.5)
		else:
			# Ref dad card: hair top ~9% from the top, beard ~67% down, plaid
			# shoulders filling the bottom third.
			frame = _frame(-0.5, 23.6, 41.0)
	var mesh := b.build(VS, Vector3(0.5, 0.0, 0.5))
	return {"mesh": mesh, "frame": frame, "yaw": yaw, "pitch": pitch, "kind": kind}


## Card window: centre x, top y, height (voxel units); width follows the
## card aspect at framing time.
func _frame(cx: float, top: float, h: float) -> Rect2:
	return Rect2(cx, top - h, 0.0, h)


func _c(key: String, def: Color) -> Color:
	var v = L.get(key, def)
	return v if v is Color else def


func _h(x: int, y: int, z: int) -> float:
	return VoxelBuilder.hash3(Vector3i(x, y, z))


# ------------------------------------------------------------------ people

func _head() -> void:
	var skin := _c("skin", Color(0.98, 0.78, 0.64))
	var shade := skin.darkened(0.1)
	# 16 x 17 x 14 head, rounded edges.
	for x in range(-8, 8):
		for y in range(0, 17):
			for z in range(-7, 7):
				var ex := x == -8 or x == 7
				var ez := z == -7 or z == 6
				var top := y == 16
				var bot := y == 0
				if (ex and ez) or (top and (ex or ez)) or (bot and ex):
					continue
				# Jaw: soften the lowest row's front corners.
				if bot and z == 6 and (x == -7 or x == 6):
					continue
				var c := skin
				if y <= 2:
					c = skin.lerp(shade, 0.35)
				b.set_v(Vector3i(x, y, z), c)
	# Neck.
	b.box(Vector3i(-3, -4, -3), Vector3i(6, 4, 6), skin.darkened(0.16))
	# Ears.
	for s in [-1, 1]:
		var ex: int = -9 if s < 0 else 8
		b.box(Vector3i(ex, 6, -1), Vector3i(1, 4, 2), skin.darkened(0.04))
		b.set_v(Vector3i(ex, 7, 0), skin.darkened(0.2))
	_face(skin)


func _face(skin: Color) -> void:
	var z := 6
	var eye := _c("eye", Color(0.17, 0.11, 0.08))
	var dark := eye.darkened(0.45)
	var white := Color(0.99, 0.98, 0.96)
	var brow := _c("brow", _c("hair", Color(0.3, 0.18, 0.1)).darkened(0.2))
	if kid:
		# Big round chibi eyes: 3 x 3 dark iris, sparkle top-outer, a second
		# small sparkle low-inner, lashes flicking out at the outer corner.
		for s in [-1, 1]:
			var x0: int = -6 if s < 0 else 3
			for dx in 3:
				for dy in 3:
					var c := dark if dy >= 1 else eye.darkened(0.25)
					b.set_v(Vector3i(x0 + dx, 6 + dy, z), c)
			var outer: int = x0 if s < 0 else x0 + 2
			var inner: int = x0 + 2 if s < 0 else x0
			b.set_v(Vector3i(outer, 8, z), white)
			b.set_v(Vector3i(inner, 6, z), eye.lightened(0.35))
			if L.get("lashes", false):
				b.set_v(Vector3i(outer - s, 8, z), dark)
				b.set_v(Vector3i(outer - s, 9, z), dark)
			# Brow just under the fringe.
			for dx in 3:
				b.set_v(Vector3i(x0 + dx, 10, z), skin.darkened(0.06))
		# Rosy cheeks.
		var blush := skin.lerp(Color(0.98, 0.45, 0.5), 0.5)
		for x in [-7, -6, 5, 6]:
			b.set_v(Vector3i(x, 5, z), blush)
			b.set_v(Vector3i(x, 4, z), skin.lerp(blush, 0.45))
		# Open smile: dark mouth, pink tongue, corners turned up.
		var m := Color(0.5, 0.16, 0.18)
		for x in range(-2, 2):
			b.set_v(Vector3i(x, 3, z), m)
		b.set_v(Vector3i(-1, 2, z), Color(0.93, 0.44, 0.48))
		b.set_v(Vector3i(0, 2, z), Color(0.93, 0.44, 0.48))
		b.set_v(Vector3i(-3, 4, z), m.lightened(0.15))
		b.set_v(Vector3i(2, 4, z), m.lightened(0.15))
		# Tiny nose.
		b.set_v(Vector3i(-1, 5, z + 1), skin.darkened(0.06))
		b.set_v(Vector3i(0, 5, z + 1), skin.darkened(0.1))
	else:
		# Adult: white | iris | iris, warm brown with a sparkle; thick brows.
		for s in [-1, 1]:
			var x0: int = -6 if s < 0 else 3
			var wx: int = x0 if s < 0 else x0 + 2
			for dy in 2:
				b.set_v(Vector3i(wx, 7 + dy, z), white)
			var ix: int = x0 + 1 if s < 0 else x0
			for dx in 2:
				for dy in 3:
					b.set_v(Vector3i(ix + dx, 7 + dy, z), dark if dy < 2 else eye.darkened(0.2))
			# Catchlight top-outer of the iris.
			b.set_v(Vector3i(ix + (0 if s < 0 else 1), 9, z), white)
			# Brows: 4 wide, one row up from the eye, standing proud.
			for dx in 4:
				var bx: int = (-7 + dx) if s < 0 else (3 + dx)
				b.set_v(Vector3i(bx, 11, z), brow)
				b.set_v(Vector3i(bx, 11, z + 1), brow)
			# Lower lid shading.
			for dx in 3:
				b.set_v(Vector3i(x0 + dx, 6, z), skin.darkened(0.07))
		# Nose: two voxels out, bridge + tip.
		for y in [5, 6]:
			b.set_v(Vector3i(-1, y, z + 1), skin.darkened(0.02 if y == 6 else 0.06))
			b.set_v(Vector3i(0, y, z + 1), skin.darkened(0.08 if y == 6 else 0.13))
		b.set_v(Vector3i(-1, 5, z + 2), skin.darkened(0.04))
		b.set_v(Vector3i(0, 5, z + 2), skin.darkened(0.1))
		b.set_v(Vector3i(-2, 5, z), skin.darkened(0.12))
		b.set_v(Vector3i(1, 5, z), skin.darkened(0.12))
		# Warm cheeks.
		for x in [-6, -5, 4, 5]:
			b.set_v(Vector3i(x, 5, z), skin.lerp(Color(0.95, 0.5, 0.45), 0.25))
		if L.get("beard", "") == "":
			var m := Color(0.55, 0.2, 0.2)
			for x in range(-2, 2):
				b.set_v(Vector3i(x, 3, z), m)
			b.set_v(Vector3i(-3, 4, z), m)
			b.set_v(Vector3i(2, 4, z), m)
		else:
			_beard(skin)


func _beard(skin: Color) -> void:
	var bc := _c("beard_color", _c("hair", Color(0.33, 0.18, 0.09)))
	var full: bool = L.get("beard", "") == "full"
	var lo := -4 if full else -1
	for x in range(-9, 9):
		for y in range(lo, 9):
			for z in range(-2, 8):
				var ax := absf(x + 0.5)
				# Shape: chin bulk below the mouth, sideburns up to the ears,
				# cheeks open above the moustache.
				var inside := false
				if y <= 4:
					inside = ax <= 8.5 - maxf(0.0, -float(y)) * 1.1
				elif y <= 6:
					inside = ax >= 5.5 - float(y - 5) * 0.5
				else:
					inside = ax >= 7.0
				if not inside:
					continue
				# Only a shell around the jaw (front, sides, under the chin).
				var front := z >= 6
				var side := ax >= 7.5 and z >= -1
				var under := y < 0 and z >= 0
				if not (front or side or under):
					continue
				if z == 7 and (y > 4 or ax > 7.5):
					continue
				var t := _h(x, y, z)
				var c := bc
				if t > 0.82:
					c = bc.lightened(0.09)
				elif t < 0.12:
					c = bc.darkened(0.1)
				if y < -2:
					c = c.darkened(0.06)
				b.set_v(Vector3i(x, y, z), c)
	# Moustache over the smile.
	for x in range(-4, 4):
		b.set_v(Vector3i(x, 4, 7), bc.darkened(0.05))
	b.set_v(Vector3i(-4, 3, 7), bc.darkened(0.05))
	b.set_v(Vector3i(3, 3, 7), bc.darkened(0.05))
	# Grin: a row of teeth between dark corners, open mouth under it.
	var m := Color(0.36, 0.12, 0.1)
	var teeth := Color(0.98, 0.96, 0.92)
	b.set_v(Vector3i(-3, 3, 7), m)
	b.set_v(Vector3i(2, 3, 7), m)
	for x in range(-2, 2):
		b.set_v(Vector3i(x, 3, 7), teeth)
	b.set_v(Vector3i(-2, 2, 7), m)
	b.set_v(Vector3i(1, 2, 7), m)
	b.set_v(Vector3i(-1, 2, 7), Color(0.62, 0.22, 0.2))
	b.set_v(Vector3i(0, 2, 7), Color(0.62, 0.22, 0.2))
	# Hide the skin under the beard front.
	for x in range(-2, 2):
		b.set_v(Vector3i(x, 3, 6), m)


func _hair() -> void:
	var hc := _c("hair", Color(0.38, 0.21, 0.11))
	var style: String = L.get("hair_style", "short")
	var hat: bool = L.has("hat")
	var hl := hc.lightened(0.22)
	var hd := hc.darkened(0.16)
	var col := func(x: int, y: int, z: int) -> Color:
		var t := _h(x, y, z)
		# Soft strand banding plus a warm sheen on the crown.
		var c: Color = hc
		if (x + 64) % 3 == 0:
			c = hd.lerp(hc, 0.5)
		if t > 0.88:
			c = hl
		elif t < 0.08:
			c = hd
		if y >= 15 and z >= 2:
			c = c.lightened(0.08)
		return c
	if style == "long" or style == "curly_long":
		# Long hair: a mane behind and beside the face down past the
		# shoulders (bunny / cat girl cards).
		for x in range(-10, 10):
			for y in range(-9, 16):
				for z in range(-9, 6):
					var ax := absf(x + 0.5)
					if ax < 8.0 and z > -8:
						continue
					if ax >= 8.0 and z > 4 - maxi(0, -y) / 3:
						continue
					if y < 0 and z < -8:
						continue
					# Wavy ends.
					if y < -6 and _h(x, -9, z) > 0.55 + float(y + 9) * 0.12:
						continue
					if ax > 9.0 and y > 11:
						continue
					b.set_v(Vector3i(x, y, z), col.call(x, y, z))
		# Fringe under the hat brim, choppy bottom edge.
		for x in range(-8, 8):
			var bottom := 11
			if x in [-7, -4, 0, 3, 6]:
				bottom = 10
			for y in range(bottom, 14):
				b.set_v(Vector3i(x, y, 7 if y >= 11 else 6), col.call(x, y, 7))
				b.set_v(Vector3i(x, y, 6), col.call(x, y, 6))
		# Locks framing the cheeks, curving in under the brim.
		for s in [-1, 1]:
			var x0: int = -9 if s < 0 else 8
			var x1: int = -8 if s < 0 else 7
			for y in range(0, 12):
				for z in [5, 6]:
					b.set_v(Vector3i(x0, y, z), col.call(x0, y, z))
				if y >= 2:
					b.set_v(Vector3i(x1, y, 7 if y >= 9 else 6), col.call(x1, y, 7))
			b.set_v(Vector3i(x1 - s, 10, 7), col.call(x1, 10, 7))
		if not hat:
			b.box(Vector3i(-9, 14, -9), Vector3i(18, 3, 16), hc)
		return
	# Shaggy / short: a thick cap with an irregular top, sideburns into the
	# beard and a tousled fringe.
	for x in range(-9, 9):
		for z in range(-9, 8):
			var ax := absf(x + 0.5)
			var az := absf(z + 0.5)
			var crown := 17 + int(_h(x, 99, z) * 2.4)
			if ax > 8.0 and az > 7.0:
				continue
			if ax >= 8.0 or az >= 7.5:
				crown -= 1
			var y0 := 12
			if z < 6:
				y0 = 9
			if z < 3 and ax >= 8.0:
				y0 = 5
			if z < -2:
				y0 = 3
			if z >= 7:
				y0 = 13 + int(_h(x, 7, 7) > 0.65)
				crown = mini(crown, 16)
			# Front layer (z 6): only above the forehead.
			if z == 6:
				y0 = 13
			for y in range(y0, crown + 1):
				if ax < 8.0 and az < 7.0 and y < 16:
					continue  # inside the skull
				b.set_v(Vector3i(x, y, z), col.call(x, y, z))
	# Tousled fringe strands over the forehead.
	for x in [-7, -6, -2, 3, 4]:
		b.set_v(Vector3i(x, 12, 7), col.call(x, 12, 7))
	# Sideburns join the beard.
	for s in [-1, 1]:
		var sx: int = -8 if s < 0 else 7
		for y in range(8, 14):
			b.set_v(Vector3i(sx, y, 6), col.call(sx, y, 6))
			b.set_v(Vector3i(sx - s, y, 5), col.call(sx - s, y, 5))
	# Ears poke through the side hair.
	var skin := _c("skin", Color(0.98, 0.78, 0.64))
	for s in [-1, 1]:
		var ex: int = -10 if s < 0 else 9
		b.box(Vector3i(ex, 6, 0), Vector3i(1, 4, 2), skin.darkened(0.04))
		b.set_v(Vector3i(ex, 7, 1), skin.darkened(0.18))


func _hat() -> void:
	var hc := _c("hat_color", Color(0.99, 0.8, 0.86))
	var ec := _c("ear_color", hc)
	var ei := _c("ear_inner", Color(0.97, 0.56, 0.68))
	var kind: String = L.get("hat", "")
	if kind != "bunny" and kind != "cat":
		return
	# Knit beanie: 18 wide, domed crown with rounded corners, ribbed roll
	# at the brim.
	var prof := [9.0, 9.0, 9.0, 9.0, 9.0, 8.8, 8.3, 7.5, 6.2]
	for y in range(12, 21):
		var hw: float = prof[y - 12]
		var hd: float = hw - 0.5
		var rr := 2.6 if y < 17 else 3.2
		for x in range(-10, 10):
			for z in range(-10, 9):
				var ax := absf(x + 0.5)
				var az := absf(z + 0.5) if z <= 7 else 99.0
				var dx := maxf(ax - (hw - rr), 0.0)
				var dz := maxf(az - (hd - rr), 0.0)
				if ax > hw or az > hd or dx * dx + dz * dz > rr * rr:
					continue
				var c := hc
				# Knit rib: every other column a touch darker.
				if (x + 40) % 2 == 0:
					c = c.darkened(0.045)
				if y >= 19:
					c = c.lightened(0.04)
				if y <= 13:
					# Brim roll: lighter, folded out one voxel.
					c = hc.lerp(Color.WHITE, 0.35)
					if (x + 40) % 2 == 0:
						c = c.darkened(0.06)
				b.set_v(Vector3i(x, y, z), c)
	for x in range(-9, 9):
		for y in [12, 13]:
			var c := hc.lerp(Color.WHITE, 0.35)
			if (x + 40) % 2 == 0:
				c = c.darkened(0.06)
			b.set_v(Vector3i(x, y, 8), c)
	# Little knit ears on the hat.
	for s in [-1, 1]:
		if kind == "bunny":
			var x0: int = -8 if s < 0 else 4
			for y in range(18, 29):
				var lean := 0
				if y >= 26:
					lean = s
				for dx in 4:
					for z in [0, 1]:
						if y == 28 and (dx == 0 or dx == 3):
							continue
						var c := ec
						if z == 1 and (dx == 1 or dx == 2) and y >= 20 and y <= 26:
							c = ei
						b.set_v(Vector3i(x0 + dx + lean, y, z), c)
				# Inner ear is recessed front face; edges a hair darker.
				b.set_v(Vector3i(x0 + lean, y, -1), ec.darkened(0.06))
				b.set_v(Vector3i(x0 + 3 + lean, y, -1), ec.darkened(0.06))
		else:
			# Rounded cat / bear ears: 5 wide base tapering, pink inner.
			var xa: int = -9 if s < 0 else 4
			for y in range(19, 24):
				var w := 5 - maxi(0, y - 21)
				var off := (5 - w) / 2
				for dx in w:
					for z in [-1, 0, 1]:
						var x: int = xa + off + dx
						var c := hc
						var mid := dx > 0 and dx < w - 1 and y < 23
						if z == 1 and mid:
							c = ei
						b.set_v(Vector3i(x, y, z), c)


func _torso() -> void:
	var tc := _c("top_color", Color(0.8, 0.13, 0.12))
	var tc2 := _c("top_color2", tc.darkened(0.5))
	var top: String = L.get("top", "plain")
	var hw := 12 if kid else 15
	var depth_b := -6 if kid else -7
	var depth_f := 4 if kid else 5
	var y_top := -3
	for x in range(-hw, hw):
		for y in range(-22, y_top + 1):
			var ax := absf(x + 0.5)
			# Sloped, rounded shoulders.
			var lim := float(hw) - 0.5
			if y >= -5:
				lim = float(hw) - 0.5 - float(y + 6) * (2.6 if kid else 2.4)
			if ax > lim:
				continue
			for z in range(depth_b, depth_f + 1):
				var c := _pattern(top, tc, tc2, x, y)
				b.set_v(Vector3i(x, y, z), c)
	_collar(top, tc, hw, depth_f)


func _pattern(top: String, tc: Color, tc2: Color, x: int, y: int) -> Color:
	var xm := (x + 60) % 6
	var ym := (y + 60) % 6
	match top:
		"plaid":
			var vx := xm < 2
			var vy := ym < 2
			var c := tc
			if vx and vy:
				c = tc2.lerp(tc, 0.15)
			elif vx or vy:
				c = tc.lerp(tc2, 0.55)
			if xm == 4 and not vy:
				c = c.lerp(Color(0.95, 0.85, 0.8), 0.18)
			return c
		"gingham":
			var gx := ((x + 60) / 2) % 2 == 0
			var gy := ((y + 60) / 2) % 2 == 0
			if gx and gy:
				return tc.darkened(0.04)
			if gx or gy:
				return tc.lerp(tc2, 0.55)
			return tc2
		"striped":
			return tc2 if (y + 60) % 3 == 0 else tc.lightened(0.38)
		_:
			return tc


func _collar(top: String, tc: Color, hw: int, zf: int) -> void:
	var bottom := _c("bottom_color", Color(0.3, 0.45, 0.8))
	var overalls: bool = L.get("bottom", "") == "overalls"
	if top == "plaid":
		# Open shirt over a dark tee: V of tee, folded collar points.
		var tee := _c("tee", Color(0.2, 0.2, 0.23))
		for y in range(-12, -2):
			var half := 1.5 + float(y + 12) * 0.42
			for x in range(-hw, hw):
				var ax := absf(x + 0.5)
				if ax <= half:
					b.set_v(Vector3i(x, y, zf), tee if y < -4 else tee.lightened(0.05))
				elif ax <= half + 2.0 and y > -9:
					var c := tc.lightened(0.06)
					if ax <= half + 1.0:
						c = tc.darkened(0.18)
					b.set_v(Vector3i(x, y, zf + 1), c)
		# Buttons down the placket edge.
		for y in [-15, -19]:
			b.set_v(Vector3i(1, y, zf + 1), Color(0.92, 0.88, 0.8))
		return
	# Kids: round white collar + overall straps with gold buttons.
	var collar := _c("collar", Color(1, 1, 1))
	if top == "gingham":
		for x in range(-6, 6):
			var ax := absf(x + 0.5)
			for y in [-4, -5]:
				if y == -5 and ax < 1.0:
					continue
				b.set_v(Vector3i(x, y, zf + 1), collar)
			if ax > 2.0 and ax < 5.0:
				b.set_v(Vector3i(x, -6, zf + 1), collar.darkened(0.04))
	else:
		# Crew neck rib in the darker stripe colour.
		for x in range(-5, 5):
			b.set_v(Vector3i(x, -4, zf + 1), _c("top_color", tc))
	if overalls:
		for s in [-1, 1]:
			var x0: int = -7 if s < 0 else 5
			for y in range(-22, -4):
				for dx in 2:
					b.set_v(Vector3i(x0 + dx, y, zf + 1), bottom if dx == 0 else bottom.darkened(0.08))
			b.set_v(Vector3i(x0, -12, zf + 2), Color(0.98, 0.8, 0.3))
			b.set_v(Vector3i(x0 + 1, -12, zf + 2), Color(0.9, 0.68, 0.2))
		# Bib top edge.
		for x in range(-7, 7):
			for y in range(-22, -17):
				b.set_v(Vector3i(x, y, zf + 1), bottom.darkened(0.02 if (x + 40) % 2 == 0 else 0.07))


# --------------------------------------------------------------------- dog

func _dog() -> void:
	var tan := _c("tan", Color(0.88, 0.56, 0.27))
	var saddle := _c("saddle", Color(0.52, 0.29, 0.12))
	var wh := _c("white", Color(0.99, 0.97, 0.93))
	var ear := _c("ear", Color(0.66, 0.36, 0.14))
	var collar := _c("collar", Color(0.86, 0.18, 0.18))
	var dark := Color(0.09, 0.06, 0.05)
	# Chest and shoulders.
	for x in range(-10, 10):
		for y in range(-22, -1):
			var ax := absf(x + 0.5)
			var lim := 9.5 - maxf(0.0, float(y + 6)) * 1.0
			if ax > lim:
				continue
			for z in range(-7, 5):
				if z > -6 and z < 3 and ax < lim - 1.0:
					continue
				var c := wh
				if ax > 5.5 - float(-y) * 0.08:
					c = tan
				if z < -3 and ax > 3.0:
					c = saddle
				b.set_v(Vector3i(x, y, z), c)
	# Head 14 x 14, rounded.
	for x in range(-7, 7):
		for y in range(0, 14):
			for z in range(-6, 6):
				var ex := x == -7 or x == 6
				var ez := z == -6 or z == 5
				if (ex and ez) or (y == 13 and (ex or ez)):
					continue
				var ax := absf(x + 0.5)
				var c := tan
				# White blaze up the middle, widening toward the muzzle.
				var blaze := 1.0 + maxf(0.0, 6.0 - float(y)) * 0.5
				if ax <= blaze and y <= 12:
					c = wh
				if y >= 11 and ax > blaze:
					c = tan.lerp(saddle, 0.3)
				b.set_v(Vector3i(x, y, z), c)
	# Muzzle: white block forward, black nose, mouth line, tongue.
	for x in range(-4, 4):
		for y in range(0, 6):
			for z in range(6, 10):
				var ax := absf(x + 0.5)
				if y == 5 and (ax > 2.5 or z > 8):
					continue
				if z == 9 and ax > 3.0:
					continue
				b.set_v(Vector3i(x, y, z), wh.darkened(0.03 if y < 2 else 0.0))
	for x in range(-2, 2):
		for y in [3, 4]:
			b.set_v(Vector3i(x, y, 9), dark)
		b.set_v(Vector3i(x, 4, 8), dark)
	b.set_v(Vector3i(-1, 4, 9), Color(0.3, 0.26, 0.24))
	b.set_v(Vector3i(-1, 2, 9), dark)
	b.set_v(Vector3i(0, 2, 9), dark)
	for x in [-3, -2, 1, 2]:
		b.set_v(Vector3i(x, 1, 9), Color(0.3, 0.2, 0.18))
	b.set_v(Vector3i(-1, 0, 9), Color(0.95, 0.45, 0.5))
	b.set_v(Vector3i(0, 0, 9), Color(0.9, 0.38, 0.45))
	b.set_v(Vector3i(-1, -1, 9), Color(0.95, 0.45, 0.5))
	b.set_v(Vector3i(0, -1, 9), Color(0.9, 0.38, 0.45))
	# Eyes: big glossy dark eyes with a sparkle, tan brow spot above.
	for s in [-1, 1]:
		var x0: int = -5 if s < 0 else 3
		for dx in 2:
			for dy in 3:
				b.set_v(Vector3i(x0 + dx, 6 + dy, 6), dark)
		b.set_v(Vector3i(x0 + (0 if s < 0 else 1), 8, 6), Color(1, 1, 1))
		b.set_v(Vector3i(x0 + (1 if s < 0 else 0), 6, 6), Color(0.3, 0.2, 0.15))
		b.set_v(Vector3i(x0, 10, 6), tan.lightened(0.15))
		b.set_v(Vector3i(x0 + 1, 10, 6), tan.lightened(0.15))
	# Long floppy ears hanging beside the face.
	for s in [-1, 1]:
		var xo: int = -10 if s < 0 else 7
		for x in range(xo, xo + 3):
			for y in range(-4, 12):
				for z in range(-3, 3):
					var outer: bool = (x == xo and s < 0) or (x == xo + 2 and s > 0)
					var inner: bool = not outer and (x == xo + 1)
					if y < -2 and (z == -3 or z == 2):
						continue
					if y == 11 and z < -1:
						continue
					var c := ear
					if outer:
						c = ear.lightened(0.04)
					if y < 1:
						c = ear.darkened(0.12)
					if _h(x, y, z) > 0.85:
						c = c.lightened(0.07)
					if inner and z > -2 and z < 2:
						c = ear.darkened(0.06)
					b.set_v(Vector3i(x, y, z), c)
	# Red collar with a gold tag.
	for x in range(-7, 7):
		for z in range(-6, 7):
			var ax := absf(x + 0.5)
			if ax > 6.0 and absf(z + 0.5) > 5.0:
				continue
			b.set_v(Vector3i(x, -1, z), collar)
			b.set_v(Vector3i(x, -2, z), collar.darkened(0.15))
	b.set_v(Vector3i(-1, -3, 7), Color(1.0, 0.82, 0.3))
	b.set_v(Vector3i(0, -3, 7), Color(0.92, 0.7, 0.2))
	b.set_v(Vector3i(-1, -4, 7), Color(0.92, 0.7, 0.2))
	b.set_v(Vector3i(0, -4, 7), Color(0.85, 0.62, 0.16))
