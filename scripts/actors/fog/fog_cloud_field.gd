extends RefCounted
const FIELD_ROWS := [
		["cloud_type","Formation",0,{"choices":["Cumulus","Stratus","Wispy / cirrus","Storm","Ground mist","Atmospheric haze"]}],
		["cloud_coverage","Coverage",.55,{"min":0.,"max":1.}],
		["cloud_size","Macro scale",1.,{"min":.05,"max":16.}],
		["cloud_macro","Macro irregularity",.65,{"min":0.,"max":2.}],
		["cloud_detail","Billow detail",.35,{"min":0.,"max":2.}],
		["cloud_erosion","Edge erosion",.25,{"min":0.,"max":1.}],
		["cloud_softness","Silhouette softness",.12,{"min":.005,"max":.5}],
		["cloud_base","Base altitude (local fraction)",.1,{"min":0.,"max":.95}],
		["cloud_thickness","Layer thickness",.8,{"min":.01,"max":1.}],
		["cloud_profile","Vertical density profile",1.,{"min":.1,"max":8.}],
		["cloud_stretch","Streak direction / scale",Vector3(5.,1.,1.),{}],
		["cloud_ground_height","Ground elevation (world m)",0.,{}],
		["cloud_follow_ground","Follow scene collision surfaces",false,{"tooltip":"Samples a cached 16² height field from configured timeline colliders. Missing surfaces use Ground elevation."}],
		["cloud_ground_search","Surface search range (m)",1000.,{"min":1.,"max":10000.}],
		["cloud_ground_mask","Surface collision layer mask",1,{"min":1,"max":2147483647}],
		["cloud_ground_falloff","Ground height falloff (m)",2.,{"min":.01,"max":10000.}]
]
static func extend_definition(d: ActorObjectDefinition) -> void:
	_native().extend_definition(d)
static func prepare(v: Dictionary) -> Dictionary:
	return _native().prepare(v)
static func sample_density(v: Dictionary,noise: Dictionary,p: Vector3,world: Vector3=Vector3.ZERO) -> float:
	return _native().sample_density(v,noise,p,world)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_cloud_field")
