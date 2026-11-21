class_name KiwiDestructionMaterial
extends RefCounted
## Artistic local energy/yield model, not a finite-element stress solver.
const NAMES := ["Glass","Steel","Aluminum","Wood","Stone","Concrete","Plastic","Ceramic","Rubber"]
const VISUAL := ["material_name","material_id","interior","exterior","vfx_family","vfx_preset"]
const FIELD_ROWS=[
		["material_name","Name","Glass",{}],["material_id","Material ID","",{"no_keyframes":true}],
		["strength","Strength (J reference energy)",8.0,{"min":.01,"max":1000.0}],
		["toughness","Toughness (J)",3.0,{"min":.01,"max":1000.0}],
		["bendability","Bendability",.03,{"min":0.0,"max":1.0}],
		["hardness","Indentation resistance (J)",12.0,{"min":.01,"max":1000.0}],
		["brittleness","Brittleness",.98,{"min":0.0,"max":1.0}],
		["density","Density (kg/m³)",2500.0,{"min":1.0,"max":30000.0}],
		["debris_friction","Debris friction",.35,{"min":0.0,"max":1.0}],
		["debris_restitution","Debris restitution",.45,{"min":0.0,"max":1.0}],
		["grain_direction","Preferred direction (local)",Vector3.UP,{}],
		["anisotropy","Directional weakness",0.0,{"min":0.0,"max":1.0}],
		["branching","Fracture branching",.9,{"min":0.0,"max":1.0}],
		["irregularity","Split-plane irregularity",.1,{"min":0.0,"max":1.0}],
		["fragment_size","Fragment size bias",.4,{"min":.1,"max":2.0}],
		["accumulation","Local damage accumulation",.7,{"min":0.0,"max":2.0}],
		["fatigue","Fatigue resistance",.4,{"min":.01,"max":5.0}],
		["rate_sensitivity","Strain-rate sensitivity",.0,{"min":0.0,"max":1.0}],
		["seed","Fracture seed",31,{"no_keyframes":true}],
		["advanced","Explicit yield / failure energies",false,{"refresh_inspector":true}],
		["yield_energy","Yield energy (J)",3.0,{"min":.01,"max":10000.0}],
		["fracture_energy","Fracture energy (J)",14.0,{"min":.01,"max":10000.0}],
		["stiffness","Elastic stiffness",1.0,{"min":.01,"max":20.0}],
		["tensile","Tensile resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["compressive","Compressive resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["shear","Shear resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["plastic_limit","Plastic deformation limit (m)",.3,{"min":.001,"max":5.0}]
	]

static func definition() -> ActorObjectDefinition:
	return _native_material().definition()

static func preset(index: int) -> ActorObjectData:
	return _native_material().preset(index)

static func resolve(values: Dictionary,point: Vector3=Vector3.ZERO) -> ActorObjectData:
	return _native_material().resolve(values,point)

static func region_definition() -> ActorObjectDefinition:
	return _native_material().region_definition()

static func physical(value: Variant) -> Variant:
	return _native_material().physical(value)

static func response(material: ActorObjectData,event: Dictionary,cell: Dictionary,thickness: float) -> Dictionary:
	return _native_material().response(material,event,cell,thickness)


static func _native_material() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_material")
