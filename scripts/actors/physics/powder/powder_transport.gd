class_name KiwiPowderTransport
extends RefCounted
## Surface-local sleeping deposits. IDs and mass never change at phase transitions.
enum Phase { ACTIVE, DEPOSITED, AIRBORNE }
const FIELDS=[
		["powder_deposition","Deposition enabled",false,{}],
		["powder_adhesion","Surface adhesion (N/grain)",0.0,{"min":0.0,"max":2.0,"step":.001}],
		["powder_settling","Settling speed (m/s)",.08,{"min":.001,"max":2.0}],
		["powder_coating","Maximum attached coating (m)",.25,{"min":.001,"max":5.0}],
		["powder_deposit_compaction","Deposit compaction rate",.3,{"min":0.0,"max":5.0}],
		["powder_displacement","Collision displacement",true,{}],
		["powder_displacement_resistance","Displacement resistance",.2,{"min":0.0,"max":10.0}],
		["powder_reactivation","Detachment exposure (s)",.15,{"min":.01,"max":5.0}],
		["powder_erosion","Erosion enabled",true,{}],
		["powder_erosion_resistance","Erosion resistance",1.0,{"min":.01,"max":20.0}],
		["powder_wind_erosion","Wind erosion influence",1.0,{"min":0.0,"max":10.0}],
		["powder_fluid_erosion","Fluid erosion influence",1.0,{"min":0.0,"max":10.0}],
		["powder_airborne","Airborne classification",true,{}],
		["powder_airborne_threshold","Airborne speed (m/s)",.2,{"min":.01,"max":10.0}],
		["powder_clear_at","Reactivate deposits at (-1 = never)",-1.0,{"min":-1.0,"max":86400.0}]
	]
static func fields(d: ActorDefinition) -> void:
	_native_transport().fields(d,FIELDS)

static func release(state: Dictionary,index: int,velocity: Vector3) -> void:
	_native_transport().release(state,index,velocity)

static func before(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float,motions: Dictionary) -> void:
	_native_transport().before(controller,batches,time,motions)

static func after(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	_native_transport().after(controller,batches,time)

static func inventory(state: Dictionary) -> Dictionary:
	return _native_transport().inventory(state)

static func _native_transport() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_transport")
