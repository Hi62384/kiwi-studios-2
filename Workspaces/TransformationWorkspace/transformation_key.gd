class_name KiwiTransformationKey
extends Resource
const MODES := ["Auto Morph","Shape Morph","Guided Morph","Grow / Reveal","Step","Crossfade"]
const LEGACY_MODES := ["Smooth morph","Linear morph","Reveal"]
@export var id := ""
@export var time := 0.
@export var state_id := ""
@export var mode := "Auto Morph"
@export var turns := 0
@export var curve: Curve
@export var points_a := PackedVector2Array()
@export var points_b := PackedVector2Array()
@export var reveal_path := PackedVector2Array()
@export var reveal_width := .3
@export var alignment := "Bounds"
@export var preservation := .8
@export var appearance := "Feature reveal"
@export var quality := "Fast"
@export var reveal_mode := "Point"
@export var origin_enabled := false
@export var morph_origin := Vector2(.5,.5)
@export var direction := 90.
@export var topology_bias := 0.
func settings() -> Dictionary: return {"alignment":alignment,"preservation":preservation,"quality":quality,"strategy":mode if mode in ["Shape Morph","Guided Morph"] else "Auto Morph"}
func copy_key(new_identity: bool=false) -> KiwiTransformationKey:
	var result := KiwiTransformationKey.new()
	for property in ["id","time","state_id","mode","turns","points_a","points_b","reveal_path","reveal_width","alignment","preservation","appearance","quality","reveal_mode","origin_enabled","morph_origin","direction","topology_bias"]: result.set(property,get(property))
	# Packed arrays are reference-backed. History and independent copies must
	# own their correction/path arrays before live point dragging mutates them.
	result.points_a=points_a.duplicate(); result.points_b=points_b.duplicate(); result.reveal_path=reveal_path.duplicate()
	if new_identity: result.id=ActorData.new_id()
	result.curve=curve.duplicate() if curve!=null else null
	return result
func progress(value: float) -> float:
	if curve!=null: return clampf(curve.sample(value),0,1)
	return smoothstep(0.,1.,value) if mode in ["Smooth morph","Auto Morph","Shape Morph","Guided Morph"] else value
