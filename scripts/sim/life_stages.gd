extends RefCounted
## Sims 3 life stages: baby -> toddler -> child -> teen -> young adult ->
## adult -> elder (dogs: puppy -> adult -> elder). Pure data + the look /
## body work for each stage.
##
## Body proportions per stage: every stage has its own rig. A household look
## ("bunny_girl", "dad", a townie "npc_0" or a born sim's own look) is the
## look at its NATIVE stage (child looks are children, adult looks adults);
## other stages get a derived look dictionary (baby: chubby onesie, no hat;
## teen / young adult grown from a child look: slim adult body; elder:
## stooped, grey hair) built once through SimRigBuilder and cached under
## "<look>@<stage>". Height per stage (HEIGHT, metres at life size) sets the
## scale, so a toddler is a toddler and an elder slightly shorter.

const RigBuilder := preload("res://scripts/world/actors/sim_rig_builder.gd")
const Looks := preload("res://scripts/world/actors/sim_looks.gd")
const Bust := preload("res://scripts/ui/portrait_bust.gd")

const STAGES := ["baby", "toddler", "child", "teen", "young_adult", "adult", "elder"]
const DOG_STAGES := ["puppy", "adult", "elder"]
const NAMES := {"baby": "Baby", "toddler": "Toddler", "child": "Child", "teen": "Teen",
	"young_adult": "Young Adult", "adult": "Adult", "elder": "Elder", "puppy": "Puppy"}
## In-game days spent in each stage (Sims 3 "short" lifespan, compressed for
## a phone session). The last stage's length is the life expectancy.
const DAYS := {"baby": 2, "toddler": 3, "child": 6, "teen": 6, "young_adult": 8, "adult": 10, "elder": 6}
const DOG_DAYS := {"puppy": 3, "adult": 24, "elder": 8}
## Gameplay kind of each stage (what actions / socials / careers see).
const KIND := {"baby": "baby", "toddler": "child", "child": "child", "teen": "child",
	"young_adult": "adult", "adult": "adult", "elder": "adult"}
## Standing height (m) at life size. Adult 1.75, child ~70 %, etc.
const HEIGHT := {"baby": 0.62, "toddler": 0.88, "child": 1.22, "teen": 1.6,
	"young_adult": 1.75, "adult": 1.75, "elder": 1.68}
const DOG_SCALE := {"puppy": 0.7, "adult": 1.0, "elder": 0.97}
## Traits a sim has room for by stage (a new one is picked at some birthdays).
const TRAIT_SLOTS := {"baby": 1, "toddler": 1, "child": 2, "teen": 3, "young_adult": 3, "adult": 3, "elder": 3}
## Baby / born-sim first names.
const GIRL_NAMES := ["Rose", "Ivy", "Poppy", "Clara", "Nell", "Hazel", "Iris", "Mabel"]
const BOY_NAMES := ["Theo", "Finn", "Ollie", "Jasper", "Milo", "Arlo", "Ezra", "Hugo"]
## Onesie / outfit palettes for born sims.
const ONESIES := [Color(0.99, 0.86, 0.55), Color(0.70, 0.86, 0.98), Color(0.98, 0.76, 0.84),
	Color(0.78, 0.93, 0.72), Color(0.86, 0.80, 0.98)]


static func stages_for(kind: String) -> Array:
	return DOG_STAGES if kind == "dog" else STAGES


static func days_in(stage: String, kind := "") -> int:
	if kind == "dog":
		return int(DOG_DAYS.get(stage, 10))
	return int(DAYS.get(stage, 10))


static func next_stage(stage: String, kind := "") -> String:
	var list := stages_for(kind)
	var k := list.find(stage)
	if k < 0 or k + 1 >= list.size():
		return ""
	return list[k + 1]


static func stage_name(stage: String) -> String:
	return NAMES.get(stage, stage.capitalize())


## The look dictionary of a member (born sims carry their own).
static func look_dict(m: Dictionary) -> Dictionary:
	if m.has("look_def") and m.look_def is Dictionary and not (m.look_def as Dictionary).is_empty():
		return m.look_def
	return Looks.get_look(str(m.get("look", "")))


## Stage a look is modelled at (no derived rig needed there).
static func native_stage(L: Dictionary) -> String:
	if L.get("species", "human") == "dog":
		return "adult"
	return "child" if L.get("body", "") == "child" else "adult"


static func is_native(L: Dictionary, stage: String) -> bool:
	var nat := native_stage(L)
	if nat == "adult":
		return stage in ["adult", "young_adult"] or (stage == "elder" and L.get("elderly", false)) or L.get("species", "human") == "dog"
	return stage == nat


## Rig key SimActor.create() should use for this member right now.
static func rig_key(m: Dictionary) -> String:
	var look := str(m.get("look", ""))
	var L := look_dict(m)
	var stage := str(m.get("life_stage", native_stage(L)))
	if is_native(L, stage):
		return look
	return "%s@%s" % [look, stage]


## Builds (once) and caches the rig for this member's current stage; also
## registers custom looks of born sims so their portrait bust renders them.
## Returns the key for SimActor.create().
static func ensure_rig(m: Dictionary) -> String:
	register_look(m)
	var key := rig_key(m)
	if RigBuilder._cache.has(key):
		return key
	var L := look_dict(m)
	var stage := str(m.get("life_stage", native_stage(L)))
	var D := L if is_native(L, stage) else derive(L, stage, str(m.get("sex", "")))
	if D.get("species", "human") == "dog":
		return key
	var r: Dictionary = RigBuilder._build_human(D)
	(r.mesh as ArrayMesh).surface_set_material(0, RigBuilder.character_material(true))
	RigBuilder._cache[key] = r
	return key


## Born sims have a look of their own (not in sim_looks.gd): register its
## rig and HUD bust under the member's look key.
static func register_look(m: Dictionary) -> void:
	if not m.has("look_def") or not (m.look_def is Dictionary) or (m.look_def as Dictionary).is_empty():
		return
	var key := str(m.get("look", ""))
	if key == "":
		return
	if not RigBuilder._cache.has(key):
		var r: Dictionary = RigBuilder._build_human(m.look_def)
		(r.mesh as ArrayMesh).surface_set_material(0, RigBuilder.character_material(true))
		RigBuilder._cache[key] = r
	if not Bust._cache.has(key):
		var pb = Bust.new()
		Bust._cache[key] = pb._make(m.look_def)


## A look dictionary for `stage` grown from look L.
static func derive(L: Dictionary, stage: String, sex := "") -> Dictionary:
	var D: Dictionary = L.duplicate(true)
	var girl: bool = L.get("lashes", false) or sex == "f"
	match stage:
		"baby":
			D.body = "child"
			for k in ["hat", "hat_color", "ear_color", "ear_inner", "glasses", "beard", "apron", "belt"]:
				D.erase(k)
			D.hair_style = "short"
			var onesie: Color = L.get("onesie", L.get("top_color", Color(0.99, 0.86, 0.55)))
			onesie = onesie.lerp(Color(1, 1, 1), 0.35)
			D.top = "plain"
			D.top_color = onesie
			D.collar = Color(1, 1, 1)
			D.sleeves = "long"
			D.bottom = "pants"
			D.bottom_color = onesie
			D.socks = onesie
			D.shoes = onesie.darkened(0.08)
			D.shoe_style = "sneaker"
		"toddler":
			D.body = "child"
			D.erase("glasses")
			D.erase("beard")
		"child":
			D.body = "child"
			D.erase("beard")
		"teen", "young_adult":
			D.body = "slim"
			if stage == "teen" and not girl:
				D.erase("beard")
		"adult":
			D.body = "big" if not girl and L.get("body", "") == "child" else ("slim" if L.get("body", "") == "child" else L.get("body", "slim"))
		"elder":
			if L.get("body", "") == "child":
				D.body = "slim"
			D.elderly = true
			var grey := Color(0.86, 0.86, 0.84)
			D.hair = (L.get("hair", grey) as Color).lerp(grey, 0.85)
			if L.has("beard_color"):
				D.beard_color = (L.beard_color as Color).lerp(grey, 0.85)
			if L.has("brow"):
				D.brow = (L.brow as Color).lerp(grey, 0.7)
			D.glasses = true
	return D


## A new baby's own look (its child-stage look: the baby / toddler stages
## derive from it): skin and hair from the parents' looks.
static func baby_look(sex: String, parent_a: Dictionary, parent_b: Dictionary, seed_n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var pa := parent_a if rng.randf() < 0.5 else parent_b
	var pb := parent_b if pa == parent_a else parent_a
	if pb.is_empty():
		pb = pa
	var skin: Color = (pa.get("skin", Color(0.96, 0.78, 0.64)) as Color).lerp(pb.get("skin", Color(0.96, 0.78, 0.64)), rng.randf_range(0.2, 0.5))
	var hair: Color = pa.get("hair", Color(0.4, 0.25, 0.12))
	if (hair.v > 0.8 and hair.s < 0.1) or hair.v < 0.08:
		hair = pb.get("hair", Color(0.4, 0.25, 0.12))
	var onesie: Color = ONESIES[rng.randi() % ONESIES.size()]
	var girl := sex == "f"
	var top: Color = Color(0.97, 0.62, 0.74) if girl else Color(0.36, 0.58, 0.92)
	top = top.lerp(onesie, 0.35)
	var L := {
		"body": "child", "skin": skin, "hair": hair, "hair_style": "long" if girl else "messy",
		"eye": pa.get("eye", Color(0.2, 0.12, 0.08)),
		"top": "striped" if rng.randf() < 0.5 else "plain", "top_color": top, "top_color2": Color(0.98, 0.97, 0.95),
		"collar": Color(1, 1, 1), "sleeves": "short",
		"bottom": "overalls" if girl else "shorts", "bottom_color": Color(0.36, 0.5, 0.8) if girl else Color(0.72, 0.62, 0.44),
		"socks": Color(0.98, 0.98, 0.98), "shoes": onesie.darkened(0.2), "shoe_style": "sneaker",
		"shoe_accent": Color(1, 1, 1), "onesie": onesie,
	}
	if girl:
		L["lashes"] = true
	return L


## World height of a SimActor (metres): rig height x skeleton x node scale.
static func actor_height(a: Node) -> float:
	if a == null or not is_instance_valid(a):
		return 0.0
	var meta = a.get("_meta")
	var sk = a.get("skeleton")
	if not (meta is Dictionary) or sk == null:
		return 0.0
	return float(meta.get("height", 0.0)) * (sk as Node3D).scale.y * (a as Node3D).scale.y


## body_scale for a new actor of rig `key` at `stage`, where `factor` is the
## lot's display factor (world height / life-size height of its household).
static func scale_for(key: String, stage: String, factor: float) -> float:
	var r: Dictionary = RigBuilder.get_rig(key)
	var h: float = float(r.meta.get("height", 1.75))
	if r.meta.get("species", "") == "dog":
		return 1.0
	return HEIGHT.get(stage, 1.75) * factor / maxf(h, 0.1)
