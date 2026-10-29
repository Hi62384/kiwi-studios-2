class_name KiwiTerrainErosion
extends Resource
## Conservative grid transport. Geometry, suspended sediment and derived flow
## are real CPU fields; this operation never substitutes a shader for erosion.
@export var operation_id:=ActorData.new_id()
@export var enabled:=true
@export_enum("Hydraulic","Thermal") var mode:=0
@export var iterations:=40
@export var rainfall:=.02
@export var strength:=.25
@export var sediment_capacity:=4.
@export var deposition_rate:=.25
@export var evaporation:=.08
@export var flow_rate:=.5
@export var minimum_slope:=.01
@export var talus_angle:=35.
@export var mobility:=.5
@export var seed:=1
@export var mask: Dictionary={}
const DIRECTIONS:=[Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]
func signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([operation_id,enabled,mode,iterations,rainfall,strength,sediment_capacity,deposition_rate,evaporation,flow_rate,minimum_slope,talus_angle,mobility,seed,mask])
func apply(source: PackedFloat32Array,n: int,dimensions: Vector2,cancel: Callable=Callable()) -> Dictionary:
	var started:=Time.get_ticks_usec(); var heights:=source.duplicate(); var count:=n*n; var eroded:=PackedFloat32Array(); var deposited:=PackedFloat32Array(); var water:=PackedFloat32Array(); var sediment:=PackedFloat32Array(); var accumulation:=PackedFloat32Array(); var flow:=PackedVector2Array(); var weights:=PackedFloat32Array()
	eroded.resize(count); deposited.resize(count); water.resize(count); sediment.resize(count); accumulation.resize(count); weights.resize(count); flow.resize(count)
	var spacing:=dimensions/maxi(1,n-1); var rng:=RandomNumberGenerator.new(); rng.seed=seed; var rain_pattern:=PackedFloat32Array(); rain_pattern.resize(count)
	for z in n:
		for x in n:
			var index:=x+z*n; weights[index]=KiwiTerrainGenerator.mask((Vector2(x,z)/maxi(1,n-1)-Vector2.ONE*.5)*dimensions,mask); rain_pattern[index]=rng.randf_range(.8,1.2)
	for iteration in clampi(iterations,1,1000):
		if cancel.is_valid() and cancel.call(): return {"cancelled":true,"heights":source}
		if mode==1: _thermal(heights,n,spacing,weights,eroded,deposited); continue
		for index in count: water[index]+=maxf(0.,rainfall)*rain_pattern[index]*weights[index]
		var next_water:=water.duplicate(); var next_sediment:=sediment.duplicate(); var moved_water:=PackedFloat32Array(); moved_water.resize(count)
		for z in n:
			if z%8==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true,"heights":source}
			for x in n:
				var index:=x+z*n
				if water[index]<.000001: continue
				var differences:=PackedFloat32Array([0.,0.,0.,0.]); var total:=0.; var head:=heights[index]+water[index]
				for direction in 4:
					var neighbor: Vector2i=Vector2i(x,z)+DIRECTIONS[direction]
					if neighbor.x<0 or neighbor.y<0 or neighbor.x>=n or neighbor.y>=n: continue
					var other:=neighbor.x+neighbor.y*n; var difference:=maxf(0.,head-heights[other]-water[other]); differences[direction]=difference; total+=difference
				if total<=.000001: continue
				var outgoing:=minf(water[index],total*clampf(flow_rate,0.,1.)*.25); var transferred_sediment:=sediment[index]*(outgoing/water[index]); var vector:=Vector2.ZERO
				for direction in 4:
					if differences[direction]<=0.: continue
					var fraction:=differences[direction]/total; var neighbor: Vector2i=Vector2i(x,z)+DIRECTIONS[direction]; var other:=neighbor.x+neighbor.y*n; next_water[other]+=outgoing*fraction; next_sediment[other]+=transferred_sediment*fraction; vector+=Vector2(DIRECTIONS[direction])*spacing*outgoing*fraction
				next_water[index]-=outgoing; next_sediment[index]-=transferred_sediment; flow[index]=flow[index]+vector; accumulation[index]+=outgoing; moved_water[index]=outgoing
		water=next_water; sediment=next_sediment
		for z in n:
			for x in n:
				var index:=x+z*n; var slope:=0.
				for direction: Vector2i in DIRECTIONS:
					var neighbor:=Vector2i(x,z)+direction
					if neighbor.x<0 or neighbor.y<0 or neighbor.x>=n or neighbor.y>=n: continue
					var distance:=spacing.x if direction.x!=0 else spacing.y; slope=maxf(slope,(heights[index]-heights[neighbor.x+neighbor.y*n])/maxf(.001,distance))
				var capacity:=maxf(minimum_slope,slope)*moved_water[index]*maxf(0.,sediment_capacity)
				if sediment[index]>capacity:
					var amount: float=(sediment[index]-capacity)*clampf(deposition_rate,0.,1.)*weights[index]; sediment[index]-=amount; heights[index]+=amount; deposited[index]+=amount
				else:
					var amount:=minf(.25,(capacity-sediment[index])*clampf(strength,0.,1.))*weights[index]; sediment[index]+=amount; heights[index]-=amount; eroded[index]+=amount
				water[index]*=1.-clampf(evaporation,0.,1.)
				if water[index]<.00001 and weights[index]>0.:
					heights[index]+=sediment[index]; deposited[index]+=sediment[index]; sediment[index]=0.
	return {"heights":heights,"water":water,"sediment":sediment,"erosion":eroded,"deposition":deposited,"flow":flow,"accumulation":accumulation,"milliseconds":float(Time.get_ticks_usec()-started)/1000.,"cancelled":false}
func _thermal(heights: PackedFloat32Array,n: int,spacing: Vector2,weights: PackedFloat32Array,eroded: PackedFloat32Array,deposited: PackedFloat32Array) -> void:
	var delta:=PackedFloat32Array(); delta.resize(n*n); var angle:=tan(deg_to_rad(clampf(talus_angle,0.,85.))); var rate:=clampf(strength*mobility,0.,1.)*.25
	for z in n:
		for x in n:
			var index:=x+z*n
			for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
				var neighbor: Vector2i=Vector2i(x,z)+direction
				if neighbor.x>=n or neighbor.y>=n: continue
				var other:=neighbor.x+neighbor.y*n; var difference:=heights[index]-heights[other]; var threshold:=angle*(spacing.x if direction.x!=0 else spacing.y); var amount:=maxf(0.,absf(difference)-threshold)*rate*minf(weights[index],weights[other])
				if difference>0.: delta[index]-=amount; delta[other]+=amount
				else: delta[index]+=amount; delta[other]-=amount
	for index in delta.size():
		heights[index]+=delta[index]
		if delta[index]>0.: deposited[index]+=delta[index]
		else: eroded[index]-=delta[index]
