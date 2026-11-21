class_name KiwiDebris
extends RefCounted
const VISUAL:=["debris_vfx_enabled","debris_intensity","debris_particles","debris_dust","debris_chips","debris_sparks","debris_lifetime","debris_vfx_preset","debris_vfx_mode","debris_copy"]
const FIELD_ROWS := [
		["debris_enabled","Physical debris",true,{}],["debris_collision","Fragment collisions",true,{}],
		["debris_budget","Fragment budget",96,{"min":2,"max":256,"step":1}],
		["debris_impulse","Fracture impulse multiplier",1.0,{"min":0.0,"max":10.0}],
		["debris_secondary","Secondary fragmentation",false,{}],
		["debris_min_size","Minimum secondary piece size (m)",.08,{"min":.005,"max":5.0,"advanced":true}],
		["debris_secondary_energy","Secondary impact threshold (J)",10.0,{"min":.01,"max":100000.0,"advanced":true}],
		["debris_depth","Maximum secondary depth",2,{"min":0,"max":4,"step":1,"advanced":true}],
		["debris_small_size","Small-debris sphere proxy below (m)",.08,{"min":.005,"max":1.0,"advanced":true}],
		["debris_sleep","Sleep settled fragments",true,{"advanced":true}],
		["debris_use_material_contacts","Use material friction / restitution",true,{"advanced":true}],
		["debris_vfx_enabled","Automatic destruction effects",true,{}],
		["debris_intensity","Effect intensity",1.0,{"min":0.0,"max":10.0}],
		["debris_particles","Particles per event",48,{"min":0,"max":512,"step":1}],
		["debris_dust","Dust multiplier",1.0,{"min":0.0,"max":5.0,"advanced":true}],
		["debris_chips","Chips / sparks multiplier",1.0,{"min":0.0,"max":5.0,"advanced":true}],
		["debris_lifetime","Effect lifetime (s)",2.0,{"min":.05,"max":10.0}],
		["debris_vfx_mode","Custom effect mode",0,{"choices":["Replace automatic","Augment automatic"]}],
		["debris_copy","Copy evaluated debris",0,{"debris_copy":true,"no_keyframes":true}]
]
const PRESET_ROWS := [["name","Name","Custom effect",{}],["style","Particle style",0,{"choices":["Dust cloud","Reflective chips","Splinters","Sparks"]}],["color","Color",Color(.7,.65,.5,.6),{}],["amount","Amount multiplier",1.0,{"min":0.0,"max":5.0}],["particle_size","Particle size (m)",.08,{"min":.001,"max":2.0}],["velocity","Initial speed",2.0,{"min":0.0,"max":50.0}],["gravity","Gravity",Vector3(0,-2,0),{}],["lifetime","Lifetime multiplier",1.0,{"min":.1,"max":5.0}]]
static func extend_actor(d: ActorDefinition) -> void:
	_native().extend_actor(d)
static func preset_definition() -> ActorObjectDefinition:
	return _native().preset_definition()
static func copy_fragments(editor: ActorTimelineEditor,actor: ActorData) -> void:
	_native().copy_fragments(editor,actor)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("debris_definition")
