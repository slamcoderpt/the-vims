extends Node
## Per-action animation + hand-prop layer on top of SimActor (owned by the
## gameplay piece). SimActor keeps its base poses (stand / sit / lie, walk
## cycle, blinking, camera presentation); this node runs right after it every
## frame and overrides the bones an action needs with keyframed loops, holds
## per-action props (plate + fork, mug, pan + spoon, knife + chopping board,
## sponge, phone, guitar, watering can, remote...) and runs small effects
## (shower spray, tap water, steam, bath bubbles).
##
## Usage (gameplay):
##   var aa = ActionAnims.of(actor)   (const ActionAnims := preload(".../action_anims.gd"))          # get or create the layer
##   aa.play("eat", {"surface": table_top})   # sets the actor's base pose too
##   aa.set_progress(0.4)                     # staged anims (cook: chop -> stir)
##   aa.stop()                                # fades back to the base pose
##   ActionAnims.anim_for(action, title, kind) -> anim name ("" = none)
##   aa.current, aa.visible_props() -> ["fork", "plate"], aa.fx_active()
##
## No edits to sim_actor.gd are needed: the layer reads the bones the actor
## just wrote and blends its own targets over them (weight fades in/out).

const VS := 0.025   # prop voxel size (body units; the skeleton scales it)

## Animation table. Keys per anim:
##   base:   SimActor pose to set ("*" = keep the action's own pose)
##   period: loop length (s); keys: [[t 0..1, {bone: Vector3 euler}], ...]
##           (bone "hips_pos" = hips offset in body units; "eyes": 1 closes them)
##   osc:    [[bone, Vector3 amplitude, Hz, phase]] additive wobble
##   props:  [[prop, bone, Vector3 pos (body units, hand-relative), Vector3 rot, level?]]
##   world:  [[prop, where]]  "surface" (in front of the sim on the table /
##           counter top) | "tub" (fills the bathtub)
##   fx:     [[fx, where]]    "water" (shower head), "tap" (sink), "steam"
##           (over the pan), "bubbles" (bath)
##   present: radians kept off the camera axis when turning the head (3/4 view)
##   stages: [[until_progress, anim], ...]  (anims switched by action progress)
##   use:    "inside" -> the sim steps into the object (shower stall, tub)
const ANIMS := {
	# ------------------------------------------------------------ eating
	"eat": {"base": "sit", "period": 3.4, "present": 0.95,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.95, 0.0, 0.18), "fore_r": Vector3(-0.55, 0, 0), "arm_l": Vector3(-0.85, 0, -0.16), "fore_l": Vector3(-0.65, 0, 0), "torso": Vector3(0.2, 0, 0), "head": Vector3(0.24, 0, 0)}],
			[0.2, {"arm_r": Vector3(-1.0, 0.0, 0.14), "fore_r": Vector3(-0.42, 0, 0), "arm_l": Vector3(-0.85, 0, -0.16), "fore_l": Vector3(-0.65, 0, 0), "torso": Vector3(0.22, 0, 0), "head": Vector3(0.26, 0, 0)}],
			[0.42, {"arm_r": Vector3(-0.62, 0.0, 0.42), "fore_r": Vector3(-1.95, 0, 0), "arm_l": Vector3(-0.85, 0, -0.16), "fore_l": Vector3(-0.65, 0, 0), "torso": Vector3(0.1, 0, 0), "head": Vector3(0.0, 0, 0)}],
			[0.56, {"arm_r": Vector3(-0.62, 0.0, 0.42), "fore_r": Vector3(-1.95, 0, 0), "arm_l": Vector3(-0.85, 0, -0.16), "fore_l": Vector3(-0.65, 0, 0), "torso": Vector3(0.1, 0, 0), "head": Vector3(0.05, 0, 0)}],
			[0.78, {"arm_r": Vector3(-0.8, 0.0, 0.28), "fore_r": Vector3(-1.1, 0, 0), "arm_l": Vector3(-0.85, 0, -0.16), "fore_l": Vector3(-0.65, 0, 0), "torso": Vector3(0.14, 0, 0), "head": Vector3(0.08, 0, 0)}],
		],
		"osc": [["head", Vector3(0.035, 0, 0), 5.0, 0.0]],
		"props": [["fork", "fore_r", Vector3(0, 0, 0.02), Vector3(-0.9, 0, 0), false]],
		"world": [["plate_food", "surface"]]},
	"snack_eat": {"base": "idle", "period": 3.0, "present": 0.85,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.45, 0, 0.3), "fore_r": Vector3(-1.4, 0, 0), "head": Vector3(0.08, 0, 0)}],
			[0.35, {"arm_r": Vector3(-0.6, 0, 0.42), "fore_r": Vector3(-2.05, 0, 0), "head": Vector3(0.0, 0, 0)}],
			[0.5, {"arm_r": Vector3(-0.6, 0, 0.42), "fore_r": Vector3(-2.05, 0, 0), "head": Vector3(0.06, 0, 0)}],
			[0.75, {"arm_r": Vector3(-0.45, 0, 0.3), "fore_r": Vector3(-1.4, 0, 0), "head": Vector3(0.05, 0, 0)}],
		],
		"osc": [["head", Vector3(0.03, 0, 0), 5.0, 0.0]],
		"props": [["sandwich", "fore_r", Vector3(0, 0.02, 0.05), Vector3.ZERO, true]]},
	"fridge_open": {"base": "idle", "period": 1.6, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.25, 0, -0.05), "fore_r": Vector3(-0.35, 0, 0), "torso": Vector3(0.08, 0, 0), "head": Vector3(0.05, 0, 0)}],
			[0.5, {"arm_r": Vector3(-0.9, 0.3, -0.35), "fore_r": Vector3(-0.6, 0, 0), "arm_l": Vector3(-1.2, 0, 0.1), "fore_l": Vector3(-0.4, 0, 0), "torso": Vector3(0.25, 0, 0), "head": Vector3(0.12, 0, 0)}],
		]},
	"grab_snack": {"stages": [[0.25, "fridge_open"], [1.0, "snack_eat"]]},
	"drink": {"base": "*", "period": 4.2, "present": 0.85,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.45, 0, 0.32), "fore_r": Vector3(-1.45, 0, 0), "head": Vector3(0.05, 0, 0)}],
			[0.32, {"arm_r": Vector3(-0.62, 0, 0.42), "fore_r": Vector3(-2.15, 0, 0), "head": Vector3(-0.2, 0, 0)}],
			[0.55, {"arm_r": Vector3(-0.62, 0, 0.42), "fore_r": Vector3(-2.15, 0, 0), "head": Vector3(-0.22, 0, 0)}],
			[0.75, {"arm_r": Vector3(-0.45, 0, 0.32), "fore_r": Vector3(-1.45, 0, 0), "head": Vector3(0.0, 0, 0)}],
		],
		"props": [["mug", "fore_r", Vector3(0, 0.0, 0.05), Vector3.ZERO, true]]},
	# ------------------------------------------------------------ cooking
	"chop": {"base": "idle", "period": 0.55, "present": 0.95,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.95, 0, 0.22), "fore_r": Vector3(-1.0, 0, 0), "arm_l": Vector3(-0.85, 0, -0.3), "fore_l": Vector3(-0.75, 0, 0.0), "torso": Vector3(0.2, 0, 0), "head": Vector3(0.3, 0, 0)}],
			[0.5, {"arm_r": Vector3(-0.92, 0, 0.22), "fore_r": Vector3(-0.5, 0, 0), "arm_l": Vector3(-0.85, 0, -0.3), "fore_l": Vector3(-0.75, 0, 0.0), "torso": Vector3(0.22, 0, 0), "head": Vector3(0.3, 0, 0)}],
		],
		"props": [["knife", "fore_r", Vector3(0, 0, 0.02), Vector3(-1.2, 0, 0), false]],
		"world": [["board_veg", "surface"]]},
	"stir": {"base": "idle", "period": 1.3, "present": 0.95,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.0, 0, 0.12), "fore_r": Vector3(-0.75, 0, 0), "arm_l": Vector3(-0.95, 0, -0.18), "fore_l": Vector3(-0.45, 0, 0), "torso": Vector3(0.14, 0, 0), "head": Vector3(0.28, 0, 0)}],
			[0.25, {"arm_r": Vector3(-1.12, 0, 0.24), "fore_r": Vector3(-0.7, 0, 0), "arm_l": Vector3(-0.95, 0, -0.18), "fore_l": Vector3(-0.45, 0, 0), "torso": Vector3(0.14, 0, 0), "head": Vector3(0.28, 0, 0)}],
			[0.5, {"arm_r": Vector3(-1.0, 0, 0.36), "fore_r": Vector3(-0.75, 0, 0), "arm_l": Vector3(-0.95, 0, -0.18), "fore_l": Vector3(-0.45, 0, 0), "torso": Vector3(0.14, 0, 0), "head": Vector3(0.28, 0, 0)}],
			[0.75, {"arm_r": Vector3(-0.88, 0, 0.24), "fore_r": Vector3(-0.8, 0, 0), "arm_l": Vector3(-0.95, 0, -0.18), "fore_l": Vector3(-0.45, 0, 0), "torso": Vector3(0.14, 0, 0), "head": Vector3(0.28, 0, 0)}],
		],
		"osc": [["fore_l", Vector3(0.05, 0, 0), 1.1, 0.0]],
		"props": [["spoon", "fore_r", Vector3(0, 0, 0.02), Vector3(-1.4, 0, 0), false], ["pan", "fore_l", Vector3(0, -0.02, 0.0), Vector3.ZERO, true]],
		"fx": [["steam", "pan"]]},
	"cook": {"stages": [[0.35, "chop"], [1.0, "stir"]]},
	# ------------------------------------------------------------ bathroom
	"shower": {"base": "idle", "period": 5.0, "present": 0.7, "use": "inside",
		"keys": [
			[0.0, {"arm_r": Vector3(-2.55, 0, 0.3), "fore_r": Vector3(-1.75, 0, 0), "arm_l": Vector3(-2.55, 0, -0.3), "fore_l": Vector3(-1.75, 0, 0), "head": Vector3(0.12, 0, 0), "eyes": Vector3.ONE}],
			[0.42, {"arm_r": Vector3(-2.55, 0, 0.3), "fore_r": Vector3(-1.75, 0, 0), "arm_l": Vector3(-2.55, 0, -0.3), "fore_l": Vector3(-1.75, 0, 0), "head": Vector3(0.12, 0, 0), "eyes": Vector3.ONE}],
			[0.52, {"arm_r": Vector3(-0.55, 0, 0.62), "fore_r": Vector3(-1.5, 0, 0), "arm_l": Vector3(-0.35, 0, 0.85), "fore_l": Vector3(-0.3, 0, 0), "head": Vector3(-0.05, 0, 0)}],
			[0.92, {"arm_r": Vector3(-0.55, 0, 0.62), "fore_r": Vector3(-1.5, 0, 0), "arm_l": Vector3(-0.35, 0, 0.85), "fore_l": Vector3(-0.3, 0, 0), "head": Vector3(-0.05, 0, 0)}],
		],
		"osc": [["arm_r", Vector3(0.0, 0.0, 0.12), 5.0, 0.0], ["arm_l", Vector3(0.0, 0.0, 0.12), 5.0, 1.6], ["fore_r", Vector3(0.18, 0, 0), 3.5, 0.0]],
		"props": [["sponge", "fore_r", Vector3(0, 0.0, 0.03), Vector3.ZERO, false]],
		"fx": [["water", "head"], ["steam", "head"]]},
	"bath": {"base": "sit", "period": 7.0, "present": 0.8, "use": "inside", "seat": 0.12,
		"keys": [
			[0.0, {"thigh_l": Vector3(-1.5, 0.08, 0), "thigh_r": Vector3(-1.5, -0.08, 0), "shin_l": Vector3(0.12, 0, 0), "shin_r": Vector3(0.2, 0, 0),
				"torso": Vector3(-0.32, 0, 0), "head": Vector3(0.1, 0, 0), "arm_l": Vector3(-0.15, 0, 0.75), "fore_l": Vector3(-0.55, 0, 0), "arm_r": Vector3(-0.15, 0, -0.75), "fore_r": Vector3(-0.55, 0, 0), "eyes": Vector3.ONE}],
			[0.5, {"thigh_l": Vector3(-1.5, 0.08, 0), "thigh_r": Vector3(-1.5, -0.08, 0), "shin_l": Vector3(0.12, 0, 0), "shin_r": Vector3(0.2, 0, 0),
				"torso": Vector3(-0.32, 0, 0), "head": Vector3(0.1, 0, 0), "arm_l": Vector3(-0.15, 0, 0.75), "fore_l": Vector3(-0.55, 0, 0), "arm_r": Vector3(-0.15, 0, -0.75), "fore_r": Vector3(-0.55, 0, 0), "eyes": Vector3.ONE}],
			[0.6, {"thigh_l": Vector3(-1.5, 0.08, 0), "thigh_r": Vector3(-1.5, -0.08, 0), "shin_l": Vector3(0.12, 0, 0), "shin_r": Vector3(0.2, 0, 0),
				"torso": Vector3(-0.12, 0, 0), "head": Vector3(0.12, 0, 0), "arm_l": Vector3(-0.75, 0, 0.1), "fore_l": Vector3(-0.6, 0, 0), "arm_r": Vector3(-0.75, 0, 0.5), "fore_r": Vector3(-1.2, 0, 0)}],
			[0.92, {"thigh_l": Vector3(-1.5, 0.08, 0), "thigh_r": Vector3(-1.5, -0.08, 0), "shin_l": Vector3(0.12, 0, 0), "shin_r": Vector3(0.2, 0, 0),
				"torso": Vector3(-0.12, 0, 0), "head": Vector3(0.12, 0, 0), "arm_l": Vector3(-0.75, 0, 0.1), "fore_l": Vector3(-0.6, 0, 0), "arm_r": Vector3(-0.75, 0, 0.5), "fore_r": Vector3(-1.2, 0, 0)}],
		],
		"osc": [["fore_r", Vector3(0.2, 0, 0), 3.0, 0.0]],
		"props": [["sponge", "fore_r", Vector3(0, 0.0, 0.03), Vector3.ZERO, false]],
		"world": [["bath_water", "tub"]],
		"fx": [["bubbles", "tub"]]},
	"toilet": {"base": "sit", "period": 5.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.6, 0, 0.32), "fore_r": Vector3(-1.35, 0, 0), "arm_l": Vector3(-0.55, 0, -0.3), "fore_l": Vector3(-1.3, 0, 0), "torso": Vector3(0.16, 0, 0), "head": Vector3(0.3, 0, 0)}],
			[0.55, {"arm_r": Vector3(-0.6, 0, 0.32), "fore_r": Vector3(-1.35, 0, 0), "arm_l": Vector3(-0.55, 0, -0.3), "fore_l": Vector3(-1.3, 0, 0), "torso": Vector3(0.16, 0, 0), "head": Vector3(0.3, 0, 0)}],
			[0.68, {"arm_r": Vector3(-0.55, 0, 0.3), "fore_r": Vector3(-1.3, 0, 0), "arm_l": Vector3(-0.5, 0, -0.3), "fore_l": Vector3(-1.25, 0, 0), "torso": Vector3(0.06, 0, 0), "head": Vector3(0.0, 0, 0)}],
			[0.85, {"arm_r": Vector3(-0.55, 0, 0.3), "fore_r": Vector3(-1.3, 0, 0), "arm_l": Vector3(-0.5, 0, -0.3), "fore_l": Vector3(-1.25, 0, 0), "torso": Vector3(0.06, 0, 0), "head": Vector3(0.0, 0, 0)}],
		],
		"osc": [["fore_r", Vector3(0.05, 0, 0), 3.0, 0.0]],
		"props": [["phone", "fore_r", Vector3(0, 0.0, 0.035), Vector3(-0.6, 0, 0), false]]},
	"wash_hands": {"base": "idle", "period": 1.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.8, 0, 0.32), "fore_r": Vector3(-0.6, 0, 0), "arm_l": Vector3(-0.8, 0, -0.32), "fore_l": Vector3(-0.6, 0, 0), "torso": Vector3(0.22, 0, 0), "head": Vector3(0.25, 0, 0)}],
		],
		"osc": [["arm_r", Vector3(0.0, 0.18, 0.05), 6.0, 0.0], ["arm_l", Vector3(0.0, -0.18, -0.05), 6.0, 0.0]],
		"fx": [["tap", "hands"]]},
	"dishes": {"base": "idle", "period": 1.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.85, 0, 0.3), "fore_r": Vector3(-0.75, 0, 0), "arm_l": Vector3(-0.85, 0, -0.25), "fore_l": Vector3(-0.6, 0, 0), "torso": Vector3(0.22, 0, 0), "head": Vector3(0.28, 0, 0)}],
		],
		"osc": [["arm_r", Vector3(0.08, 0.0, 0.1), 3.0, 0.0], ["arm_r", Vector3(0.0, 0.0, 0.1), 3.0, 1.57]],
		"props": [["sponge", "fore_r", Vector3(0, 0.0, 0.03), Vector3.ZERO, false], ["plate", "fore_l", Vector3(0, 0.0, 0.06), Vector3.ZERO, true]],
		"fx": [["tap", "hands"]]},
	# ------------------------------------------------------------ hobbies
	"guitar": {"base": "idle", "period": 2.0, "present": 0.8,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.3, 0, 0.5), "fore_r": Vector3(-1.2, 0, 0), "arm_l": Vector3(-0.75, 0, 0.75), "fore_l": Vector3(-1.1, 0, 0), "head": Vector3(0.18, 0, 0)}],
			[0.5, {"arm_r": Vector3(-0.3, 0, 0.5), "fore_r": Vector3(-1.2, 0, 0), "arm_l": Vector3(-0.8, 0, 0.75), "fore_l": Vector3(-1.15, 0, 0), "head": Vector3(0.1, 0, 0)}],
		],
		"osc": [["fore_r", Vector3(0.22, 0, 0), 5.0, 0.0], ["head", Vector3(0.05, 0, 0.04), 2.0, 0.0]],
		"props": [["guitar", "torso", Vector3(0, 0.0, 0.0), Vector3.ZERO, false]]},
	"water_plant": {"base": "idle", "period": 2.4, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.0, 0, 0.1), "fore_r": Vector3(-0.35, 0, 0), "torso": Vector3(0.15, 0, 0), "head": Vector3(0.3, 0, 0)}],
			[0.5, {"arm_r": Vector3(-1.05, 0, 0.1), "fore_r": Vector3(-0.2, 0, 0), "torso": Vector3(0.18, 0, 0), "head": Vector3(0.32, 0, 0)}],
		],
		"props": [["watering_can", "fore_r", Vector3(0, 0.0, 0.0), Vector3(1.2, 0, 0), false]],
		"fx": [["sprinkle", "can"]]},
	"crouch_tend": {"base": "idle", "period": 1.6, "present": 0.85,
		"keys": [
			[0.0, {"thigh_l": Vector3(-1.35, 0.15, 0), "thigh_r": Vector3(-1.1, -0.15, 0), "shin_l": Vector3(2.0, 0, 0), "shin_r": Vector3(2.1, 0, 0), "hips_pos": Vector3(0, -0.45, 0),
				"torso": Vector3(0.5, 0, 0), "head": Vector3(0.1, 0, 0), "arm_r": Vector3(-0.9, 0, 0.1), "fore_r": Vector3(-0.2, 0, 0), "arm_l": Vector3(-0.6, 0, -0.1), "fore_l": Vector3(-0.5, 0, 0)}],
			[0.5, {"thigh_l": Vector3(-1.35, 0.15, 0), "thigh_r": Vector3(-1.1, -0.15, 0), "shin_l": Vector3(2.0, 0, 0), "shin_r": Vector3(2.1, 0, 0), "hips_pos": Vector3(0, -0.45, 0),
				"torso": Vector3(0.5, 0, 0), "head": Vector3(0.1, 0, 0), "arm_r": Vector3(-1.05, 0, 0.1), "fore_r": Vector3(-0.35, 0, 0), "arm_l": Vector3(-0.6, 0, -0.1), "fore_l": Vector3(-0.5, 0, 0)}],
		]},
	"pet_dog": {"base": "idle", "period": 1.4, "present": 0.75,
		"keys": [
			[0.0, {"thigh_l": Vector3(-1.35, 0.15, 0), "thigh_r": Vector3(-1.1, -0.15, 0), "shin_l": Vector3(2.0, 0, 0), "shin_r": Vector3(2.1, 0, 0), "hips_pos": Vector3(0, -0.45, 0),
				"torso": Vector3(0.45, 0, 0), "head": Vector3(-0.05, 0, 0), "arm_r": Vector3(-0.85, 0, 0.12), "fore_r": Vector3(-0.15, 0, 0), "arm_l": Vector3(-0.55, 0, -0.1), "fore_l": Vector3(-0.6, 0, 0)}],
			[0.5, {"thigh_l": Vector3(-1.35, 0.15, 0), "thigh_r": Vector3(-1.1, -0.15, 0), "shin_l": Vector3(2.0, 0, 0), "shin_r": Vector3(2.1, 0, 0), "hips_pos": Vector3(0, -0.45, 0),
				"torso": Vector3(0.45, 0, 0), "head": Vector3(-0.05, 0, 0), "arm_r": Vector3(-1.05, 0, 0.12), "fore_r": Vector3(-0.35, 0, 0), "arm_l": Vector3(-0.55, 0, -0.1), "fore_l": Vector3(-0.6, 0, 0)}],
		]},
	"feed_dog": {"base": "idle", "period": 1.2, "present": 0.8,
		"keys": [
			[0.0, {"thigh_l": Vector3(-1.35, 0.15, 0), "thigh_r": Vector3(-1.1, -0.15, 0), "shin_l": Vector3(2.0, 0, 0), "shin_r": Vector3(2.1, 0, 0), "hips_pos": Vector3(0, -0.45, 0),
				"torso": Vector3(0.4, 0, 0), "head": Vector3(0.15, 0, 0), "arm_r": Vector3(-1.0, 0, 0.1), "fore_r": Vector3(-0.5, 0, 0), "arm_l": Vector3(-0.55, 0, -0.1), "fore_l": Vector3(-0.6, 0, 0)}],
		],
		"osc": [["arm_r", Vector3(0.06, 0, 0), 4.0, 0.0]],
		"props": [["kibble", "fore_r", Vector3(0, 0.0, 0.03), Vector3(2.2, 0, 0), false]]},
	"telescope": {"base": "idle", "period": 4.0, "present": 1.2,
		"keys": [
			[0.0, {"torso": Vector3(0.35, 0, 0), "head": Vector3(-0.2, 0, 0), "arm_r": Vector3(-1.15, 0, 0.15), "fore_r": Vector3(-0.9, 0, 0), "arm_l": Vector3(-1.15, 0, -0.15), "fore_l": Vector3(-0.9, 0, 0)}],
			[0.6, {"torso": Vector3(0.35, 0, 0), "head": Vector3(-0.2, 0, 0), "arm_r": Vector3(-1.15, 0, 0.15), "fore_r": Vector3(-0.9, 0, 0), "arm_l": Vector3(-1.15, 0, -0.15), "fore_l": Vector3(-0.9, 0, 0)}],
			[0.75, {"torso": Vector3(0.05, 0, 0), "head": Vector3(-0.3, 0, 0), "arm_r": Vector3(-0.2, 0, -0.1), "fore_r": Vector3(-0.3, 0, 0), "arm_l": Vector3(-1.1, 0, -0.15), "fore_l": Vector3(-0.9, 0, 0)}],
		]},
	"watch_tv": {"base": "*", "period": 6.0, "present": 1.0,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.6, 0, 0.2), "fore_r": Vector3(-0.85, 0, 0)}],
			[0.8, {"arm_r": Vector3(-0.6, 0, 0.2), "fore_r": Vector3(-0.85, 0, 0)}],
			[0.86, {"arm_r": Vector3(-0.95, 0, 0.12), "fore_r": Vector3(-0.6, 0, 0)}],
		],
		"osc": [["head", Vector3(0.0, 0.05, 0.02), 0.3, 0.0]],
		"props": [["remote", "fore_r", Vector3(0, 0.0, 0.03), Vector3(-1.3, 0, 0), false]]},
	"phone_call": {"base": "*", "period": 3.0, "present": 0.8,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.35, 0, 0.62), "fore_r": Vector3(-2.35, 0, 0), "arm_l": Vector3(-0.3, 0, -0.1), "fore_l": Vector3(-0.9, 0, 0), "head": Vector3(0.0, 0, -0.12)}],
			[0.5, {"arm_r": Vector3(-0.35, 0, 0.62), "fore_r": Vector3(-2.35, 0, 0), "arm_l": Vector3(-0.6, 0, -0.35), "fore_l": Vector3(-1.1, 0, 0), "head": Vector3(-0.05, 0, -0.1)}],
		],
		"props": [["phone", "fore_r", Vector3(0, 0.0, 0.035), Vector3(-0.2, 0, 0), false]]},
	# ------------------------------------------------------------ socials
	"chat": {"base": "idle", "period": 3.6, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.55, 0, -0.18), "fore_r": Vector3(-1.15, 0, 0), "arm_l": Vector3(-0.12, 0, 0.12), "fore_l": Vector3(-0.35, 0, 0)}],
			[0.3, {"arm_r": Vector3(-0.65, 0.2, -0.38), "fore_r": Vector3(-1.3, 0, 0), "arm_l": Vector3(-0.6, -0.2, 0.38), "fore_l": Vector3(-1.2, 0, 0)}],
			[0.62, {"arm_r": Vector3(-0.15, 0, -0.12), "fore_r": Vector3(-0.4, 0, 0), "arm_l": Vector3(-0.6, 0, 0.25), "fore_l": Vector3(-1.25, 0, 0)}],
		],
		"osc": [["head", Vector3(0.06, 0.08, 0.04), 1.4, 0.0], ["torso", Vector3(0.0, 0.05, 0.0), 0.7, 0.0]]},
	"listen": {"base": "idle", "period": 4.0, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.5, 0, 0.5), "fore_r": Vector3(-1.75, 0, 0.35), "arm_l": Vector3(-0.5, 0, -0.5), "fore_l": Vector3(-1.75, 0, -0.35)}],
			[0.7, {"arm_r": Vector3(-0.5, 0, 0.5), "fore_r": Vector3(-1.75, 0, 0.35), "arm_l": Vector3(-0.5, 0, -0.5), "fore_l": Vector3(-1.75, 0, -0.35)}],
			[0.8, {"arm_r": Vector3(-0.55, 0, -0.18), "fore_r": Vector3(-1.2, 0, 0), "arm_l": Vector3(-0.1, 0, 0.12), "fore_l": Vector3(-0.3, 0, 0)}],
		],
		"osc": [["head", Vector3(0.1, 0.0, 0.0), 1.6, 0.0]]},
	"deep_talk": {"base": "idle", "period": 5.0, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.42, 0, 0.5), "fore_r": Vector3(-2.2, 0, 0), "arm_l": Vector3(-0.35, 0, -0.45), "fore_l": Vector3(-1.6, 0, -0.2), "head": Vector3(0.08, 0, 0.1)}],
			[0.55, {"arm_r": Vector3(-0.42, 0, 0.5), "fore_r": Vector3(-2.2, 0, 0), "arm_l": Vector3(-0.35, 0, -0.45), "fore_l": Vector3(-1.6, 0, -0.2), "head": Vector3(0.08, 0, 0.1)}],
			[0.7, {"arm_r": Vector3(-0.7, 0.2, -0.3), "fore_r": Vector3(-1.1, 0, 0), "arm_l": Vector3(-0.35, 0, -0.45), "fore_l": Vector3(-1.6, 0, -0.2), "head": Vector3(-0.05, 0, 0)}],
		],
		"osc": [["head", Vector3(0.05, 0.0, 0.0), 0.8, 0.0]]},
	"joke": {"base": "idle", "period": 2.6, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.55, 0, -0.95), "fore_r": Vector3(-0.85, 0, 0), "arm_l": Vector3(-0.55, 0, 0.95), "fore_l": Vector3(-0.85, 0, 0), "head": Vector3(-0.1, 0, 0), "torso": Vector3(-0.05, 0, 0)}],
			[0.35, {"arm_r": Vector3(-0.7, 0, -0.3), "fore_r": Vector3(-1.4, 0, 0), "arm_l": Vector3(-0.7, 0, 0.3), "fore_l": Vector3(-1.4, 0, 0), "head": Vector3(0.05, 0, 0.1), "torso": Vector3(0.1, 0, 0)}],
			[0.6, {"arm_r": Vector3(-2.5, 0, -0.3), "fore_r": Vector3(-0.25, 0, 0), "arm_l": Vector3(-0.3, 0, 0.3), "fore_l": Vector3(-1.4, 0, 0), "head": Vector3(-0.18, 0, 0), "torso": Vector3(-0.08, 0, 0)}],
			[0.82, {"arm_r": Vector3(-0.6, 0, 0.25), "fore_r": Vector3(-1.5, 0, 0), "arm_l": Vector3(-0.6, 0, -0.25), "fore_l": Vector3(-1.5, 0, 0), "head": Vector3(-0.25, 0, 0), "torso": Vector3(-0.15, 0, 0), "eyes": Vector3.ONE}],
		]},
	"laugh": {"base": "idle", "period": 0.8, "present": 0.6,
		"keys": [
			[0.0, {"torso": Vector3(-0.22, 0, 0), "head": Vector3(-0.32, 0, 0), "arm_l": Vector3(-0.4, 0, -0.38), "fore_l": Vector3(-1.5, 0, 0), "arm_r": Vector3(-0.15, 0, -0.28), "fore_r": Vector3(-0.3, 0, 0), "eyes": Vector3.ONE}],
			[0.5, {"torso": Vector3(-0.1, 0, 0), "head": Vector3(-0.2, 0, 0), "arm_l": Vector3(-0.4, 0, -0.38), "fore_l": Vector3(-1.5, 0, 0), "arm_r": Vector3(-0.55, 0, -0.2), "fore_r": Vector3(-0.95, 0, 0), "eyes": Vector3.ONE}],
		],
		"osc": [["hips_pos", Vector3(0, 0.02, 0), 2.5, 0.0], ["head", Vector3(0, 0, 0.06), 5.0, 0.0]]},
	"hug": {"base": "idle", "period": 3.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.3, 0, 0.35), "fore_r": Vector3(-0.35, 0, 1.0), "arm_l": Vector3(-1.3, 0, -0.35), "fore_l": Vector3(-0.35, 0, -1.0), "torso": Vector3(0.15, 0, 0), "head": Vector3(0.05, 0.5, 0.1), "eyes": Vector3.ONE}],
		],
		"osc": [["hips", Vector3(0, 0, 0.05), 0.9, 0.0], ["torso", Vector3(0, 0, -0.05), 0.9, 0.0]]},
	"kiss": {"base": "idle", "period": 3.0, "present": 1.4,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.4, 0, 0.25), "fore_r": Vector3(-0.3, 0, 0), "arm_l": Vector3(-1.4, 0, -0.25), "fore_l": Vector3(-0.3, 0, 0), "torso": Vector3(0.22, 0, 0), "head": Vector3(0.05, 0.0, 0.25), "eyes": Vector3.ONE}],
		]},
	"flirt": {"base": "idle", "period": 2.4, "present": 0.6,
		"keys": [
			[0.0, {"arm_r": Vector3(-2.3, 0, -0.55), "fore_r": Vector3(-2.0, 0, 0), "arm_l": Vector3(0.1, 0, 0.5), "fore_l": Vector3(-1.4, 0, -0.6), "head": Vector3(0.1, 0, 0.18), "torso": Vector3(0, 0, 0.06)}],
			[0.5, {"arm_r": Vector3(-2.3, 0, -0.55), "fore_r": Vector3(-2.0, 0, 0), "arm_l": Vector3(0.1, 0, 0.5), "fore_l": Vector3(-1.4, 0, -0.6), "head": Vector3(0.1, 0, -0.1), "torso": Vector3(0, 0, -0.04)}],
		]},
	"argue": {"base": "idle", "period": 1.1, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.3, 0, 0.12), "fore_r": Vector3(-0.2, 0, 0), "arm_l": Vector3(0.1, 0, 0.55), "fore_l": Vector3(-1.5, 0, -0.7), "torso": Vector3(0.15, 0, 0), "head": Vector3(0.12, 0, 0)}],
			[0.5, {"arm_r": Vector3(-1.15, 0, 0.12), "fore_r": Vector3(-0.65, 0, 0), "arm_l": Vector3(0.1, 0, 0.55), "fore_l": Vector3(-1.5, 0, -0.7), "torso": Vector3(0.2, 0, 0), "head": Vector3(0.05, 0, 0)}],
		],
		"osc": [["head", Vector3(0, 0.12, 0), 4.0, 0.0]]},
	"upset": {"base": "idle", "period": 3.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.5, 0, 0.5), "fore_r": Vector3(-1.75, 0, 0.35), "arm_l": Vector3(-0.5, 0, -0.5), "fore_l": Vector3(-1.75, 0, -0.35), "head": Vector3(-0.18, 0.45, 0.0), "torso": Vector3(-0.06, 0, 0)}],
		]},
	"apologize": {"base": "idle", "period": 3.0, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.55, 0, 0.5), "fore_r": Vector3(-1.6, 0, 0), "arm_l": Vector3(-0.55, 0, -0.5), "fore_l": Vector3(-1.6, 0, 0), "head": Vector3(0.28, 0, 0), "torso": Vector3(0.1, 0, 0)}],
			[0.6, {"arm_r": Vector3(-0.6, 0, 0.5), "fore_r": Vector3(-1.75, 0, 0), "arm_l": Vector3(-0.6, 0, -0.5), "fore_l": Vector3(-1.75, 0, 0), "head": Vector3(0.0, 0, 0.12), "torso": Vector3(0.05, 0, 0)}],
		]},
	"high_five": {"base": "idle", "period": 1.2, "present": 0.7,
		"keys": [
			[0.0, {"arm_r": Vector3(-2.75, 0, -0.15), "fore_r": Vector3(-0.35, 0, 0), "head": Vector3(-0.15, 0, 0)}],
			[0.45, {"arm_r": Vector3(-2.35, 0, -0.05), "fore_r": Vector3(-0.1, 0, 0), "head": Vector3(-0.15, 0, 0), "torso": Vector3(0.08, 0, 0)}],
			[0.7, {"arm_r": Vector3(-0.4, 0, -0.3), "fore_r": Vector3(-2.2, 0, 0), "head": Vector3(-0.1, 0, 0)}],
		]},
	# ------------------------------------------------------------ transitions & reactions
	"pull_chair": {"base": "idle", "period": 1.0, "present": 0.9,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.85, 0, 0.12), "fore_r": Vector3(-0.35, 0, 0), "arm_l": Vector3(-0.85, 0, -0.12), "fore_l": Vector3(-0.35, 0, 0), "torso": Vector3(0.3, 0, 0), "head": Vector3(0.1, 0, 0)}],
			[0.6, {"arm_r": Vector3(-0.55, 0, 0.12), "fore_r": Vector3(-0.9, 0, 0), "arm_l": Vector3(-0.55, 0, -0.12), "fore_l": Vector3(-0.9, 0, 0), "torso": Vector3(0.12, 0, 0), "head": Vector3(0.05, 0, 0)}],
		]},
	"step_in": {"base": "walk", "period": 1.0, "present": 0.6, "keys": []},
	"react_yes": {"base": "idle", "period": 0.7, "present": 0.3,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.45, 0, -0.35), "fore_r": Vector3(-2.3, 0, 0), "head": Vector3(-0.15, 0, 0), "torso": Vector3(-0.05, 0, 0)}],
			[0.5, {"arm_r": Vector3(-0.15, 0, -0.25), "fore_r": Vector3(-2.45, 0, 0), "head": Vector3(-0.05, 0, 0), "torso": Vector3(0.08, 0, 0)}],
		]},
	"react_satisfied": {"base": "idle", "period": 0.8, "present": 0.3,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.35, 0, 0.42), "fore_r": Vector3(-1.35, 0, 0), "arm_l": Vector3(-0.3, 0, -0.4), "fore_l": Vector3(-1.3, 0, 0), "torso": Vector3(-0.12, 0, 0), "head": Vector3(-0.12, 0, 0), "eyes": Vector3.ONE}],
		],
		"osc": [["fore_r", Vector3(0.15, 0, 0), 3.0, 0.0]]},
	"react_stretch": {"base": "idle", "period": 2.0, "present": 0.3,
		"keys": [
			[0.0, {"arm_r": Vector3(-2.9, 0, -0.25), "fore_r": Vector3(-0.3, 0, 0), "arm_l": Vector3(-2.9, 0, 0.25), "fore_l": Vector3(-0.3, 0, 0), "torso": Vector3(-0.15, 0, 0), "head": Vector3(-0.25, 0, 0), "eyes": Vector3.ONE}],
		],
		"osc": [["torso", Vector3(0, 0, 0.08), 0.6, 0.0]]},
	"react_shake": {"base": "idle", "period": 1.0, "present": 0.3,
		"keys": [
			[0.0, {"arm_r": Vector3(-0.2, 0, -0.45), "fore_r": Vector3(-0.4, 0, 0), "arm_l": Vector3(-0.2, 0, 0.45), "fore_l": Vector3(-0.4, 0, 0), "eyes": Vector3.ONE}],
		],
		"osc": [["torso", Vector3(0, 0.18, 0.06), 7.0, 0.0], ["head", Vector3(0, 0.25, 0), 7.0, 0.5], ["arm_r", Vector3(0, 0, 0.2), 7.0, 0.0], ["arm_l", Vector3(0, 0, 0.2), 7.0, 0.0]]},
	"react_relief": {"base": "idle", "period": 1.2, "present": 0.3,
		"keys": [
			[0.0, {"arm_r": Vector3(-1.6, 0, 0.45), "fore_r": Vector3(-1.95, 0, 0), "head": Vector3(-0.12, 0, 0), "eyes": Vector3.ONE}],
			[0.5, {"arm_r": Vector3(-1.6, 0, 0.15), "fore_r": Vector3(-1.95, 0, 0), "head": Vector3(-0.12, 0, 0)}],
		]},
}

## Action id -> anim (object-specific ids are resolved in anim_for()).
const ACTION_ANIM := {
	"eat": "eat", "meal": "eat", "eat_meal": "eat", "eat_serving": "eat",
	"grab_snack": "grab_snack", "cook": "cook", "cook_fridge": "cook", "cook_meal": "cook", "gourmet": "cook",
	"shower": "shower", "bath": "bath", "use_toilet": "toilet",
	"wash": "wash_hands", "dishes": "dishes",
	"guitar": "guitar", "practice_guitar": "guitar", "busk": "guitar",
	"water": "water_plant", "tend": "crouch_tend", "prune": "crouch_tend", "harvest": "crouch_tend",
	"feed_dog": "feed_dog", "pet": "pet_dog", "s_pet": "pet_dog",
	"stargaze": "telescope", "watch": "watch_tv", "watch_tv": "watch_tv", "watch_show": "watch_tv",
	"s_chat": "chat", "s_day": "chat", "s_hobbies": "chat", "s_compliment": "chat", "s_homework": "chat",
	"s_deep": "deep_talk", "s_joke": "joke", "s_hug": "hug", "s_kiss": "kiss", "s_flirt": "flirt",
	"s_tease": "argue", "s_argue": "argue", "s_makeup": "apologize", "s_highfive": "high_five", "s_handshake": "high_five",
	"call_friend": "phone_call", "phone": "phone_call", "drink": "drink", "coffee": "drink", "lemonade": "drink",
}
## What the other sim does during a social (initiator anim -> partner anim).
const PARTNER_ANIM := {"chat": "listen", "deep_talk": "listen", "joke": "laugh", "hug": "hug", "kiss": "kiss",
	"flirt": "laugh", "argue": "upset", "apologize": "listen", "high_five": "high_five", "pet_dog": ""}
## End-of-action reactions by anim.
const REACTION := {"eat": "react_satisfied", "grab_snack": "react_satisfied", "snack_eat": "react_satisfied",
	"shower": "react_shake", "bath": "react_stretch", "toilet": "react_relief", "cook": "react_yes"}

var actor: Node3D
var current := ""          # requested anim (may be staged)
var active := ""           # resolved anim being shown
var progress := 0.0
var ctx := {}
var _skel: Skeleton3D
var _t := 0.0
var _w := 0.0              # blend weight
var _fading := false
var _bones := {}           # name -> index
var _cur := {}             # name -> Vector3 (smoothed euler)
var _hips_off := Vector3.ZERO
var _props := {}           # key -> {"mi": MeshInstance3D, "bone": int, "pos", "rot", "level"}
var _world := {}           # name -> Node3D (top-level)
var _fx := {}              # name -> CPUParticles3D
var _eyes := 0.0
var _base_pose := ""

static var _mesh_cache := {}


## The layer on `a` (created on first use). Null for non-SimActors.
static func of(a: Node) -> Node:
	if a == null or not is_instance_valid(a) or not (a is SimActor):
		return null
	var n := a.get_node_or_null("ActionAnims")
	if n != null and n.has_method("play"):
		return n
	var aa: Node = load("res://scripts/world/actors/action_anims.gd").new()
	aa.name = "ActionAnims"
	aa.actor = a
	a.add_child(aa)
	return aa


## The anim for an Interactable action (or "" to keep the plain SimActor pose).
static func anim_for(a: Dictionary, title := "", kind := "adult") -> String:
	if kind == "dog":
		return ""
	var id := str(a.get("id", ""))
	if id == "snack":
		# Fridge "Grab a Snack" vs counter "Prepare Snack".
		return "chop" if (title == "Kitchen Counter" or str(a.get("label", "")).begins_with("Prepare")) else "grab_snack"
	if a.has("anim"):
		return str(a.anim)
	if title == "Grill" or title.begins_with("BBQ"):
		return ""   # the actor's own grill pose (spatula over the grill)
	return ACTION_ANIM.get(id, "")


static func info(anim: String) -> Dictionary:
	var d: Dictionary = ANIMS.get(anim, {})
	if d.has("stages"):
		var first: Dictionary = ANIMS.get(d.stages[0][1], {})
		var out := first.duplicate()
		for st in d.stages:
			var sd: Dictionary = ANIMS.get(st[1], {})
			if sd.has("use"):
				out["use"] = sd.use
		return out
	return d


static func partner_anim(anim: String) -> String:
	return PARTNER_ANIM.get(anim, "listen" if anim != "" else "")


static func reaction_for(anim: String, a: Dictionary, leveled := false) -> String:
	if leveled or int(a.get("money", 0)) > 0:
		return "react_yes"
	return REACTION.get(anim, "")


func _ready() -> void:
	process_priority = 50   # after SimActor wrote its pose this frame
	if actor == null:
		actor = get_parent()


func _resolve() -> String:
	var d: Dictionary = ANIMS.get(current, {})
	if d.has("stages"):
		for st in d.stages:
			if progress <= float(st[0]):
				return st[1]
		return d.stages[-1][1]
	return current


## Start an anim. ctx: surface (Vector3 top of the table / counter in front),
## tub_center / tub_half / tub_yaw (bath water), base (pose for base "*").
func play(anim: String, p_ctx := {}) -> void:
	if not ANIMS.has(anim):
		stop()
		return
	ctx = p_ctx
	current = anim
	progress = 0.0
	_fading = false
	_switch(_resolve())


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	if current == "" or _fading:
		return
	var want := _resolve()
	if want != active:
		_switch(want)


func stop() -> void:
	if current == "" and active == "":
		return
	current = ""
	_fading = true
	_clear_props()


func is_playing() -> bool:
	return current != "" and not _fading


func visible_props() -> Array:
	var out: Array = []
	for k in _props:
		var mi: MeshInstance3D = _props[k].mi
		if mi.visible:
			out.append(str(k).get_slice("@", 0))
	for k in _world:
		if (_world[k] as Node3D).visible:
			out.append(k)
	return out


func fx_active() -> Array:
	var out: Array = []
	for k in _fx:
		var p: CPUParticles3D = _fx[k]
		if p.emitting:
			out.append(k)
	return out


func _switch(anim: String) -> void:
	_clear_props()
	active = anim
	_t = 0.0
	var d: Dictionary = ANIMS.get(anim, {})
	if actor == null or not is_instance_valid(actor):
		return
	var base: String = d.get("base", "idle")
	if base == "*":
		base = str(ctx.get("base", "idle"))
	_base_pose = base
	if d.has("seat"):
		actor.set("seat_height", float(d.seat))
	if actor.get("pose") != base:
		actor.set_pose(base)
	for pr in d.get("props", []):
		_show_prop(pr)
	for w in d.get("world", []):
		_show_world(w[0], w[1])
	for f in d.get("fx", []):
		_show_fx(f[0], f[1])


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if _skel == null:
		_skel = actor.get("skeleton")
		if _skel == null:
			return
		for i in _skel.get_bone_count():
			_bones[_skel.get_bone_name(i)] = i
	delta = minf(delta, 0.1)
	if _fading:
		_w = maxf(0.0, _w - delta / 0.3)
		if _w <= 0.0:
			_fading = false
			active = ""
			_cur.clear()
			_hips_off = Vector3.ZERO
			_eyes = 0.0
			return
	elif active != "":
		_w = minf(1.0, _w + delta / 0.3)
		# Someone else changed the actor's pose (walk, cancel): let go.
		var bp: String = actor.get("pose")
		if bp != _base_pose and active != "step_in":
			stop()
			return
	else:
		return
	_t += delta
	var d: Dictionary = ANIMS.get(active, {})
	var tgt := _sample(d)
	_present(d, tgt)
	var k := 1.0 - exp(-delta * 12.0)
	for bn in tgt:
		var v: Vector3 = tgt[bn]
		if not _cur.has(bn):
			_cur[bn] = _actor_euler(bn) if bn != "hips_pos" and bn != "eyes" else Vector3.ZERO
		_cur[bn] = (_cur[bn] as Vector3).lerp(v, k)
	# Bones the previous anim moved but this one doesn't: ease back to the base.
	for bn in _cur.keys():
		if not tgt.has(bn):
			if bn == "hips_pos" or bn == "eyes":
				_cur[bn] = (_cur[bn] as Vector3).lerp(Vector3.ZERO, k)
			else:
				_cur[bn] = (_cur[bn] as Vector3).lerp(_actor_euler(bn), k)
	_apply()
	_update_props()


func _actor_euler(bn: String) -> Vector3:
	var i: int = _bones.get(bn, -1)
	if i < 0:
		return Vector3.ZERO
	return _skel.get_bone_pose_rotation(i).get_euler()


## Keyframe sample (smoothstep between keys, looping) plus oscillators.
func _sample(d: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = d.get("keys", [])
	var period: float = maxf(0.05, d.get("period", 1.0))
	var u := fmod(_t / period, 1.0)
	if not keys.is_empty():
		var n := keys.size()
		var i0 := n - 1
		for i in n:
			if float(keys[i][0]) <= u:
				i0 = i
		var i1 := (i0 + 1) % n
		var t0: float = keys[i0][0]
		var t1: float = keys[i1][0] if i1 > i0 else float(keys[0][0]) + 1.0
		var uu := u if u >= t0 else u + 1.0
		var f := smoothstep(0.0, 1.0, clampf((uu - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0))
		var a: Dictionary = keys[i0][1]
		var b: Dictionary = keys[i1][1]
		for bn in a:
			out[bn] = (a[bn] as Vector3).lerp(b.get(bn, a[bn]), f)
		for bn in b:
			if not out.has(bn):
				out[bn] = b[bn]
	for o in d.get("osc", []):
		var bn: String = o[0]
		var amp: Vector3 = o[1]
		var s := sin(_t * TAU * float(o[2]) + float(o[3]))
		var base: Vector3 = out.get(bn, Vector3.ZERO if bn in ["hips_pos", "hips"] else _actor_euler(bn))
		out[bn] = base + amp * s
	return out


## Head (and a touch of torso) turn toward the camera: faces read in 3/4
## while the body stays square to the activity.
func _present(d: Dictionary, tgt: Dictionary) -> void:
	var keep: float = d.get("present", 0.85)
	var a: float = actor.get("_cam_a") if actor.get("_cam_a") != null else 0.0
	if absf(a) <= keep:
		return
	var want := clampf(a - signf(a) * keep, -1.0, 1.0)
	if tgt.has("head"):
		tgt["head"] = tgt["head"] + Vector3(0, want * 0.85, 0)
	if tgt.has("torso"):
		tgt["torso"] = tgt["torso"] + Vector3(0, want * 0.1, 0)


func _apply() -> void:
	var w := smoothstep(0.0, 1.0, _w)
	for bn in _cur:
		var v: Vector3 = _cur[bn]
		if bn == "hips_pos":
			var hi: int = _bones.get("hips", -1)
			if hi >= 0:
				var meta: Dictionary = actor.get("_meta")
				var hy: float = meta.get("hip_y", 0.5)
				_skel.set_bone_pose_position(hi, _skel.get_bone_pose_position(hi) + v * hy * w)
			continue
		if bn == "eyes":
			var ei: int = _bones.get("eyes", -1)
			if ei >= 0 and v.x * w > 0.5:
				_skel.set_bone_pose_scale(ei, Vector3.ZERO)
			continue
		var i: int = _bones.get(bn, -1)
		if i < 0:
			continue
		var q := Quaternion.from_euler(v)
		if w < 0.999:
			q = _skel.get_bone_pose_rotation(i).slerp(q, w)
		_skel.set_bone_pose_rotation(i, q)


# ------------------------------------------------------------------ props

func _show_prop(pr: Array) -> void:
	var pname: String = pr[0]
	var bone: String = pr[1]
	var key := pname + "@" + bone
	if not _props.has(key):
		var mi := MeshInstance3D.new()
		mi.mesh = prop_mesh(pname)
		mi.top_level = true
		mi.name = "Prop_" + pname
		add_child(mi)
		_props[key] = {"mi": mi, "bone": bone}
	var e: Dictionary = _props[key]
	e["pos"] = pr[2]
	e["rot"] = pr[3]
	e["level"] = pr[4]
	(e.mi as MeshInstance3D).visible = true


func _clear_props() -> void:
	for k in _props:
		(_props[k].mi as MeshInstance3D).visible = false
	for k in _world:
		(_world[k] as Node3D).visible = false
	for k in _fx:
		(_fx[k] as CPUParticles3D).emitting = false


func _hand_xf(bone: String) -> Transform3D:
	var i: int = _bones.get(bone, -1)
	if i < 0:
		return actor.global_transform
	var meta: Dictionary = actor.get("_meta")
	var g := _skel.global_transform * _skel.get_bone_global_pose(i)
	if bone.begins_with("fore"):
		g = g * Transform3D(Basis(), Vector3(0, -float(meta.get("fore_len", 0.2)) + 0.02, 0))
	elif bone == "torso":
		g = g * Transform3D(Basis(), Vector3(0, 0.12, float(meta.get("torso_half", 0.1)) + 0.03))
	elif bone == "head":
		g = g * Transform3D(Basis(), Vector3(0, float(meta.get("head_h", 0.4)) + 0.1, 0))
	return g


func _update_props() -> void:
	var s: float = _skel.global_transform.basis.get_scale().x
	var yaw := Basis(Vector3.UP, actor.global_rotation.y)
	for k in _props:
		var e: Dictionary = _props[k]
		var mi: MeshInstance3D = e.mi
		if not mi.visible:
			continue
		var h := _hand_xf(e.bone)
		var pos: Vector3 = e.get("pos", Vector3.ZERO)
		if e.get("level", false):
			mi.global_transform = Transform3D(yaw.scaled(Vector3.ONE * s), h.origin + yaw * (pos * s))
		else:
			var r: Vector3 = e.get("rot", Vector3.ZERO)
			mi.global_transform = h * Transform3D(Basis.from_euler(r), pos)
	var steam: CPUParticles3D = _fx.get("steam")
	if steam and steam.emitting and _props.has("pan@fore_l"):
		var pan: MeshInstance3D = _props["pan@fore_l"].mi
		steam.global_position = pan.global_position + yaw * Vector3(0, 0.08, 0.12 * s)
	var tap: CPUParticles3D = _fx.get("tap")
	if tap and tap.emitting:
		var hr := _hand_xf("fore_r").origin
		var hl := _hand_xf("fore_l").origin
		tap.global_position = (hr + hl) * 0.5 + Vector3(0, 0.3, 0) + yaw * Vector3(0, 0, 0.05)
	var spr: CPUParticles3D = _fx.get("sprinkle")
	if spr and spr.emitting and _props.has("watering_can@fore_r"):
		var can: MeshInstance3D = _props["watering_can@fore_r"].mi
		spr.global_position = can.global_transform * Vector3(0, -0.02, 0.2)


func _show_world(pname: String, where: String) -> void:
	var n: Node3D = _world.get(pname)
	if n == null:
		n = _make_world(pname)
		if n == null:
			return
		n.top_level = true
		add_child(n)
		_world[pname] = n
	var yaw := Basis(Vector3.UP, actor.global_rotation.y)
	match where:
		"surface":
			var sp: Vector3 = ctx.get("surface", Vector3.INF)
			if sp == Vector3.INF:
				n.visible = false
				return
			var fwd := yaw * Vector3(0, 0, 1)
			var from: Vector3 = actor.global_position
			var to := Vector3(sp.x, from.y, sp.z) - from
			var dist := clampf(to.dot(fwd) if to.length() > 0.05 else 0.45, 0.32, 0.55)
			n.global_transform = Transform3D(yaw, Vector3(from.x, sp.y, from.z) + fwd * dist)
		"tub":
			var c: Vector3 = ctx.get("tub_center", Vector3.INF)
			if c == Vector3.INF:
				n.visible = false
				return
			# tub_half: x = half length along tub_yaw's local x, y = half height, z = half width.
			var half: Vector3 = ctx.get("tub_half", Vector3(0.8, 0.3, 0.4))
			var ty: float = ctx.get("tub_yaw", 0.0)
			n.global_transform = Transform3D(Basis(Vector3.UP, ty), Vector3(c.x, c.y + half.y - 0.1, c.z))
			var water: Node3D = n.get_child(0)
			water.scale = Vector3(maxf(0.2, half.x * 2.0 - 0.16), 1.0, maxf(0.2, half.z * 2.0 - 0.16))
			var foam: Node3D = n.get_child(1)
			foam.scale = Vector3(clampf((half.x * 2.0 - 0.3) / 0.9, 0.3, 1.2), 1.0, clampf((half.z * 2.0 - 0.2) / 0.45, 0.3, 1.2))
	n.visible = true


func _make_world(pname: String) -> Node3D:
	match pname:
		"bath_water":
			var root := Node3D.new()
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1, 0.04, 1)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.55, 0.8, 0.95, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
			m.metallic_specular = 0.8
			bm.material = m
			mi.mesh = bm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			# Foam: a few white voxel clumps floating on the surface.
			var foam := MeshInstance3D.new()
			foam.mesh = prop_mesh("foam")
			foam.position = Vector3(0, 0.02, 0)
			root.add_child(foam)
			return root
		_:
			var mi := MeshInstance3D.new()
			mi.mesh = prop_mesh(pname)
			return mi


func _show_fx(fx: String, _where: String) -> void:
	var p: CPUParticles3D = _fx.get(fx)
	if p == null:
		p = _make_fx(fx)
		p.top_level = true
		add_child(p)
		_fx[fx] = p
	var ht: Vector3 = actor.head_top() if actor.has_method("head_top") else actor.global_position + Vector3(0, 1.8, 0)
	match fx:
		"water":
			p.global_position = Vector3(actor.global_position.x, ht.y + 0.55, actor.global_position.z)
		"steam":
			if _where == "head":
				p.global_position = Vector3(actor.global_position.x, ht.y - 0.2, actor.global_position.z)
		"bubbles":
			var c: Vector3 = ctx.get("tub_center", actor.global_position)
			var half: Vector3 = ctx.get("tub_half", Vector3(0.6, 0.3, 0.3))
			p.global_transform = Transform3D(Basis(Vector3.UP, float(ctx.get("tub_yaw", 0.0))), Vector3(c.x, c.y + half.y - 0.08, c.z))
			p.emission_box_extents = Vector3(maxf(0.1, half.x - 0.15), 0.02, maxf(0.1, half.z - 0.15))
	p.emitting = true


func _make_fx(fx: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "FX_" + fx
	p.local_coords = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	var bm := BoxMesh.new()
	match fx:
		"water", "tap", "sprinkle":
			bm.size = Vector3(0.018, 0.07, 0.018)
			m.albedo_color = Color(0.7, 0.88, 1.0, 0.75)
			p.amount = 60 if fx == "water" else 24
			p.lifetime = 0.5 if fx == "water" else 0.35
			p.direction = Vector3(0, -1, 0)
			p.spread = 10.0 if fx == "water" else 4.0
			p.initial_velocity_min = 2.0 if fx == "water" else 0.6
			p.initial_velocity_max = 2.6 if fx == "water" else 0.9
			p.gravity = Vector3(0, -9.8, 0)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.14 if fx == "water" else 0.02
		"steam":
			bm.size = Vector3(0.07, 0.07, 0.07)
			m.albedo_color = Color(1, 1, 1, 0.35)
			p.amount = 12
			p.lifetime = 1.4
			p.direction = Vector3(0, 1, 0)
			p.spread = 20.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.45
			p.gravity = Vector3(0, 0.1, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.4
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 0.0))
			g.add_point(0.25, Color(1, 1, 1, 0.6))
			g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
			p.color_ramp = g
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.06
		"bubbles":
			bm.size = Vector3(0.035, 0.035, 0.035)
			m.albedo_color = Color(1, 1, 1, 0.85)
			p.amount = 14
			p.lifetime = 1.6
			p.direction = Vector3(0, 1, 0)
			p.spread = 25.0
			p.initial_velocity_min = 0.12
			p.initial_velocity_max = 0.3
			p.gravity = Vector3.ZERO
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(0.4, 0.02, 0.2)
	bm.material = m
	p.mesh = bm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _exit_tree() -> void:
	for k in _world:
		if is_instance_valid(_world[k]):
			(_world[k] as Node3D).visible = false


# ------------------------------------------------------------------ prop meshes

static func _fill(vb: VoxelBuilder, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c: Color) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				vb.set_v(Vector3i(x, y, z), c)


## Voxel prop meshes (cached). Tools extend along +Z from the grip (origin);
## level props (plate, pan, mug, board) sit on their bottom face.
static func prop_mesh(pname: String) -> ArrayMesh:
	if _mesh_cache.has(pname):
		return _mesh_cache[pname]
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	var origin := Vector3.ZERO
	var size := VS
	var steel := Color(0.78, 0.8, 0.84)
	var white := Color(0.97, 0.96, 0.92)
	match pname:
		"fork":
			_fill(vb, 0, 0, 0, 0, -1, 4, steel)
			_fill(vb, -1, 1, 0, 0, 5, 5, steel)
			vb.set_v(Vector3i(-1, 0, 6), steel)
			vb.set_v(Vector3i(1, 0, 6), steel)
			vb.set_v(Vector3i(0, 0, 6), steel)
			vb.set_v(Vector3i(0, 1, 6), Color(0.95, 0.7, 0.3))   # a bite of food
			origin = Vector3(0.5, 0.5, 0.5)
			size = 0.022
		"spoon":
			_fill(vb, 0, 0, 0, 0, -1, 6, Color(0.62, 0.42, 0.24))
			_fill(vb, -1, 1, -1, 0, 7, 8, Color(0.62, 0.42, 0.24))
			origin = Vector3(0.5, 0.5, 0.5)
			size = 0.024
		"knife":
			_fill(vb, 0, 0, 0, 0, -1, 2, Color(0.18, 0.16, 0.15))
			_fill(vb, 0, 0, -1, 0, 3, 8, steel)
			vb.set_v(Vector3i(0, -1, 9), steel)
			origin = Vector3(0.5, 0.5, 0.5)
			size = 0.022
		"sponge":
			_fill(vb, 0, 3, 0, 1, 0, 2, Color(0.98, 0.85, 0.3))
			_fill(vb, 0, 3, 2, 2, 0, 2, Color(0.4, 0.75, 0.45))
			vb.set_v(Vector3i(1, 3, 1), white)
			vb.set_v(Vector3i(3, 3, 2), white)
			vb.set_v(Vector3i(0, 3, 0), white)
			origin = Vector3(2, 1.5, 1.5)
		"phone":
			_fill(vb, 0, 3, 0, 5, 0, 0, Color(0.16, 0.17, 0.2))
			_fill(vb, 0, 3, 0, 5, 1, 1, Color(0.18, 0.2, 0.24))
			for y in range(1, 5):
				for x in range(0, 4):
					if x > 0 and x < 3:
						vb.set_v(Vector3i(x, y, 1), Color(0.45, 0.75, 0.95), true)
			origin = Vector3(2, 1, 0)
			size = 0.02
		"remote":
			_fill(vb, 0, 1, 0, 0, 0, 6, Color(0.15, 0.15, 0.17))
			vb.set_v(Vector3i(0, 1, 5), Color(0.9, 0.25, 0.25))
			vb.set_v(Vector3i(1, 1, 3), Color(0.6, 0.6, 0.65))
			origin = Vector3(1, 0.5, 0.5)
			size = 0.022
		"mug":
			var mc := Color(0.92, 0.38, 0.32)
			_fill(vb, 0, 3, 0, 4, 0, 3, mc)
			_fill(vb, 1, 2, 4, 4, 1, 2, Color(0.36, 0.2, 0.1))
			_fill(vb, 4, 4, 1, 3, 1, 2, mc)
			vb.erase(Vector3i(4, 2, 1))
			vb.erase(Vector3i(4, 2, 2))
			_fill(vb, 5, 5, 1, 3, 1, 2, mc)
			origin = Vector3(2, 0, 2)
		"sandwich":
			_fill(vb, 0, 5, 0, 0, 0, 3, Color(0.86, 0.64, 0.36))
			_fill(vb, 0, 5, 1, 1, 0, 3, Color(0.42, 0.75, 0.32))
			_fill(vb, 0, 5, 2, 2, 0, 3, Color(0.9, 0.36, 0.3))
			_fill(vb, 0, 5, 3, 3, 0, 3, Color(0.88, 0.68, 0.4))
			origin = Vector3(3, 0, 2)
		"plate", "plate_food":
			for x in range(-4, 5):
				for z in range(-4, 5):
					if x * x + z * z <= 19:
						vb.set_v(Vector3i(x, 0, z), white)
						if x * x + z * z >= 12:
							vb.set_v(Vector3i(x, 1, z), Color(0.9, 0.9, 0.86))
			if pname == "plate_food":
				_fill(vb, -2, 0, 1, 2, -2, 0, Color(0.95, 0.72, 0.3))   # pasta / rice
				_fill(vb, -1, 0, 3, 3, -1, 0, Color(0.95, 0.75, 0.32))
				_fill(vb, 1, 2, 1, 2, -1, 1, Color(0.6, 0.32, 0.2))     # meat
				vb.set_v(Vector3i(0, 1, 2), Color(0.35, 0.72, 0.3))     # greens
				vb.set_v(Vector3i(-1, 1, 2), Color(0.3, 0.65, 0.28))
				vb.set_v(Vector3i(1, 1, 2), Color(0.9, 0.3, 0.25))      # tomato
			origin = Vector3(0.5, 0, 0.5)
			size = 0.03
		"pan":
			var dark := Color(0.2, 0.2, 0.22)
			for x in range(-4, 5):
				for z in range(-4, 5):
					var r2 := x * x + z * z
					if r2 <= 19:
						vb.set_v(Vector3i(x, 0, z + 9), dark)
						if r2 >= 12:
							vb.set_v(Vector3i(x, 1, z + 9), dark)
			_fill(vb, 0, 0, 1, 1, 0, 4, Color(0.15, 0.12, 0.1))   # handle toward the hand
			_fill(vb, -2, 1, 1, 1, 7, 10, Color(0.95, 0.7, 0.3))  # food
			vb.set_v(Vector3i(-1, 1, 11), Color(0.85, 0.3, 0.2))
			vb.set_v(Vector3i(1, 1, 8), Color(0.4, 0.7, 0.3))
			vb.set_v(Vector3i(2, 1, 10), Color(0.85, 0.3, 0.2))
			origin = Vector3(0.5, 1.0, 0.5)
			size = 0.026
		"board_veg":
			_fill(vb, -5, 5, 0, 0, -3, 3, Color(0.72, 0.52, 0.3))
			_fill(vb, -3, 1, 1, 1, -1, -1, Color(0.95, 0.5, 0.15))   # carrot
			vb.set_v(Vector3i(-4, 1, -1), Color(0.35, 0.7, 0.3))
			for x in [2, 3]:
				vb.set_v(Vector3i(x, 1, 1), Color(0.95, 0.55, 0.2))   # slices
			vb.set_v(Vector3i(-1, 1, 1), Color(0.9, 0.3, 0.25))
			vb.set_v(Vector3i(0, 1, 1), Color(0.9, 0.3, 0.25))
			origin = Vector3(0.5, 0, 0.5)
			size = 0.03
		"guitar":
			# Acoustic guitar slung across the belly: body at the right hip,
			# neck up to the left shoulder (actor-forward = +Z).
			var wood := Color(0.82, 0.55, 0.28)
			var dk := Color(0.35, 0.2, 0.1)
			for x in range(-4, 4):
				for y in range(-5, 3):
					var dx := (x + 0.5) / 4.2
					var dy := (y + 1.5) / 4.5
					if dx * dx + dy * dy <= 1.0:
						vb.set_v(Vector3i(x, y, 0), wood)
						vb.set_v(Vector3i(x, y, -1), dk)
			vb.set_v(Vector3i(0, -1, 1), Color(0.15, 0.1, 0.06))
			vb.set_v(Vector3i(-1, -1, 1), Color(0.15, 0.1, 0.06))
			for k in range(0, 10):
				vb.set_v(Vector3i(3 + k, 2 + k / 2, 0), dk)
			vb.set_v(Vector3i(13, 7, 0), Color(0.2, 0.12, 0.06))
			vb.set_v(Vector3i(13, 8, 0), Color(0.2, 0.12, 0.06))
			origin = Vector3(2, 0, -2)
			size = 0.03
		"watering_can":
			var gc := Color(0.35, 0.65, 0.55)
			_fill(vb, -2, 2, -6, -2, -2, 2, gc)
			_fill(vb, 0, 0, -1, 0, -1, 1, gc)   # handle
			for k in range(0, 5):
				vb.set_v(Vector3i(0, -4 + k / 2, 3 + k), gc)   # spout
			origin = Vector3(0.5, 0.5, 0.5)
			size = 0.028
		"kibble":
			_fill(vb, -2, 2, -5, 0, -1, 1, Color(0.85, 0.4, 0.25))
			_fill(vb, -1, 1, -3, -2, 2, 2, Color(0.98, 0.9, 0.6))
			origin = Vector3(0.5, 0.5, 0.5)
			size = 0.028
		"foam":
			var pts := [Vector3i(-12, 0, -5), Vector3i(-9, 0, 4), Vector3i(-3, 0, -6), Vector3i(4, 0, 5), Vector3i(10, 0, -3), Vector3i(13, 0, 4), Vector3i(0, 0, 0)]
			for i in pts.size():
				var c: Vector3i = pts[i]
				for dx in range(-2, 3):
					for dz in range(-2, 3):
						if absi(dx) + absi(dz) <= 3:
							vb.set_v(c + Vector3i(dx, 0, dz), white)
				vb.set_v(c + Vector3i(0, 1, 0), white)
			origin = Vector3(0.5, 0, 0.5)
			size = 0.03
	var m := vb.build(size, origin)
	_mesh_cache[pname] = m
	return m
