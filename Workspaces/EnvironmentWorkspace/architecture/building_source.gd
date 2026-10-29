extends Resource
## Authored plan only. Native Model components are disposable derived geometry.
@export var source_id:=ActorData.new_id()
@export var title:="Building"
@export var seed:=1
@export var footprint:=PackedVector2Array()
@export var floors: Array[Dictionary]=[]
@export var wall_thickness:=.2
@export var slab_thickness:=.15
@export_enum("Flat","Gable","Shed","Hip") var roof_type:=1
@export var roof_pitch:=30.
@export var roof_overhang:=.25
@export var materials: Array[Material]=[]
@export var stairs: Array[Dictionary]=[]
@export var physics_enabled:=false
@export var foundation_depth:=.4
@export var style:="Custom"
@export_enum("None","Timber frame","Porch","Buttresses","Pilasters","Fins","Cross braces","Spire corners") var facade_detail:=0
@export var detail_width:=.12
@export var baseboard_height:=0.
@export var crown_height:=0.
@export var interior_trim_depth:=.025
static func copy(authored: Resource) -> Resource:
	var result=authored.get_script().new()
	for key in ["source_id","title","seed","footprint","floors","wall_thickness","slab_thickness","roof_type","roof_pitch","roof_overhang","materials","stairs","physics_enabled","foundation_depth","style","facade_detail","detail_width","baseboard_height","crown_height","interior_trim_depth"]:
		var value: Variant=authored.get(key)
		result.set(key,value.duplicate(true) if value is Array or value is Dictionary else value)
	return result
static func rectangular(width: float=6.,depth: float=8.,levels: int=1,with_materials: bool=true) -> Resource:
	var source=load("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").new()
	source.footprint=PackedVector2Array([Vector2(-width/2,-depth/2),Vector2(width/2,-depth/2),Vector2(width/2,depth/2),Vector2(-width/2,depth/2)])
	for level in clampi(levels,1,8):
		var walls: Array=[]
		for edge in 4:
			var openings: Array=[]
			if level==0 and edge==0: openings.append({"id":"door"+str(edge),"type":"door","t":.5,"width":1.,"height":2.1,"bottom":0.,"angle":0.})
			else: openings.append({"id":"window"+str(edge),"type":"window","t":.5,"width":1.4,"height":1.2,"bottom":1.})
			walls.append({"id":"wall"+str(edge),"a":source.footprint[edge],"b":source.footprint[(edge+1)%4],"height":3.,"height_mode":"level","openings":openings})
		source.floors.append({"id":"floor"+str(level),"name":"Level "+str(level+1),"elevation":float(level)*3.,"height":3.,"walls":walls,"rooms":[{"id":"room0","name":"Room","polygon":source.footprint}],"cuts":[]})
	if not with_materials: return source
	var engine=preload("res://scripts/materials/natural_material_engine.gd")
	source.materials.assign([engine.create_spatial_material(engine.defaults("stone/brick")),engine.create_spatial_material(engine.defaults("wood/wood_planks")),engine.create_spatial_material(engine.defaults("stone/slate")),engine.create_spatial_material(engine.defaults("wood/oak"))])
	var glass:=StandardMaterial3D.new(); glass.albedo_color=Color(.65,.85,.9,.28); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness=.12; glass.cull_mode=BaseMaterial3D.CULL_DISABLED; source.materials.append(glass)
	source.materials.append(source.materials[0]); source.materials.append(source.materials[1])
	return source
func validate() -> PackedStringArray:
	var errors:=PackedStringArray(); var ids: Dictionary={}
	for field in ["wall_thickness","slab_thickness","roof_pitch","roof_overhang","foundation_depth","detail_width","baseboard_height","crown_height","interior_trim_depth"]:
		if not is_finite(float(get(field))): errors.append("Building dimensions must be finite."); break
	if roof_type<0 or roof_type>3 or facade_detail<0 or facade_detail>7: errors.append("Choose a supported roof and facade type.")
	if foundation_depth<0. or roof_overhang<0. or roof_pitch<0. or roof_pitch>=85. or detail_width<=0.: errors.append("Foundation, roof and detail dimensions are outside their supported ranges.")
	if baseboard_height<0. or baseboard_height>.5 or crown_height<0. or crown_height>.5 or interior_trim_depth<.005 or interior_trim_depth>.3: errors.append("Interior trim must fit the supported wall profile.")
	if footprint.size()>256: errors.append("A footprint supports up to 256 authored corners.")
	if footprint.size()<3 or Geometry2D.triangulate_polygon(footprint).is_empty(): errors.append("The footprint must be a simple closed polygon.")
	if floors.is_empty() or floors.size()>8: errors.append("A building supports one to eight levels.")
	if stairs.size()>16: errors.append("A building supports up to sixteen staircases.")
	if wall_thickness<.02 or slab_thickness<.02: errors.append("Wall and slab thickness must be at least 0.02 m.")
	for floor: Dictionary in floors:
		var polygon: PackedVector2Array=floor.get("footprint",footprint)
		if not is_finite(float(floor.get("elevation",0.))) or not is_finite(float(floor.get("height",3.))) or float(floor.get("height",3.))<.5: errors.append("Levels require finite elevations and a height of at least 0.5 m.")
		for point in polygon:
			if not point.is_finite(): errors.append("Footprint corners must be finite."); break
		if polygon.size()>256: errors.append("A level footprint supports up to 256 authored corners.")
		if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty(): errors.append("A level footprint must be a simple closed polygon.")
		if (floor.get("rooms",[]) as Array).size()>64 or (floor.get("cuts",[]) as Array).size()>32: errors.append("A level supports up to 64 rooms and 32 floor cuts.")
		var id:=str(floor.get("id",""))
		if id.is_empty() or ids.has(id): errors.append("Levels need unique stable identities.")
		ids[id]=true; var walls: Array=floor.get("walls",[]); var wall_ids: Dictionary={}; var opening_ids: Dictionary={}
		var room_ids: Dictionary={}
		for room: Dictionary in floor.get("rooms",[]):
			var identity:=str(room.get("id","")); var region: PackedVector2Array=room.get("polygon",PackedVector2Array())
			if identity.is_empty() or room_ids.has(identity): errors.append("Rooms need unique stable identities within a level.")
			room_ids[identity]=true
			if region.size()<3 or Geometry2D.triangulate_polygon(region).is_empty(): errors.append("Room regions must be closed simple polygons.")
		if walls.size()>128: errors.append("A level supports up to 128 authored wall segments.")
		for wall: Dictionary in walls:
			if (wall.get("openings",[]) as Array).size()>32: errors.append("A wall supports up to 32 openings.")
			var key:=str(wall.get("id","")); var a: Vector2=wall.get("a",Vector2.ZERO); var b: Vector2=wall.get("b",Vector2.ZERO); var length:=a.distance_to(b); var height:=wall_height(self,floor,wall)
			if key.is_empty() or wall_ids.has(key): errors.append("Wall identities must be unique within a level.")
			wall_ids[key]=true
			if length<.1 or height<.1 or not a.is_finite() or not b.is_finite(): errors.append("Wall segments need finite endpoints and positive dimensions.")
			for opening: Dictionary in wall.get("openings",[]):
				var identity:=str(opening.get("id",""))
				if identity.is_empty() or opening_ids.has(identity): errors.append("Openings need unique stable identities within a level.")
				opening_ids[identity]=true
				var width:=float(opening.get("width",1.)); var center:=float(opening.get("t",.5))*length; var bottom:=float(opening.get("bottom",0.)); var top:=bottom+float(opening.get("height",2.))
				if width<.05 or center-width/2<-.0001 or center+width/2>length+.0001 or bottom<0. or top>height+.0001: errors.append("An opening no longer fits its wall. Resize or move it before rebuilding.")
	return errors
static func wall_height(source: Resource,floor: Dictionary,wall: Dictionary) -> float:
	if wall.get("height_mode","level")!="level": return float(wall.get("height",floor.get("height",3.)))
	var height:=float(floor.get("height",3.))
	for next: Dictionary in source.floors:
		if is_equal_approx(float(next.get("elevation",0.)),float(floor.get("elevation",0.))+height): return maxf(.1,height-float(source.slab_thickness))
	return height
