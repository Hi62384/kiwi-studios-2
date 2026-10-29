extends RefCounted
## Authored districts classify whole road blocks; later entries take priority.
const CATEGORIES=["Residential","Commercial","Industrial","Downtown","Suburban","Mixed Use","Civic","Park/Green Space","Agricultural","Custom"]
const STYLES=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd")
static func create(category: String,polygon: PackedVector2Array) -> Dictionary:
	var minimum:=1; var maximum:=2; var lot:=18.; var density:=1.; var style:="Modern"; var setback:=2.
	match category:
		"Commercial": minimum=2; maximum=4; lot=24.
		"Industrial": maximum=1; lot=30.; style="Industrial"; setback=3.
		"Downtown": minimum=3; maximum=8; lot=16.; setback=1.
		"Suburban": maximum=2; lot=22.; density=.7; style="Traditional"; setback=3.
		"Mixed Use": minimum=2; maximum=5
		"Civic": minimum=2; maximum=3; lot=28.; style="Classical-Inspired"; setback=4.
		"Park/Green Space": density=0.
		"Agricultural": maximum=1; lot=32.; density=.35; style="Cabin"; setback=4.
	var template: Resource=STYLES.apply(preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").rectangular(),style)
	return {"id":ActorData.new_id(),"name":category,"category":category,"polygon":polygon.duplicate(),"enabled":true,"density":density,"height_min":minimum,"height_max":maximum,"lot_size":lot,"setback":setback,"seed":1,"template":template}
static func validate(settlement: Dictionary) -> PackedStringArray:
	var errors:=PackedStringArray(); var seen: Dictionary={}; var districts: Array=settlement.get("districts",[])
	if districts.size()>32: errors.append("A settlement supports at most 32 editable districts.")
	for district: Dictionary in districts:
		var id:=str(district.get("id","")); var polygon: PackedVector2Array=district.get("polygon",PackedVector2Array())
		if id.is_empty() or seen.has(id): errors.append("District IDs must be unique within their settlement.")
		seen[id]=true
		if district.get("category","") not in CATEGORIES: errors.append("Choose a supported district category.")
		var finite:=true
		for point in polygon: finite=finite and point.is_finite()
		if not finite or polygon.size()<3 or polygon.size()>512 or absf(_area(polygon))<.01 or Geometry2D.triangulate_polygon(polygon).is_empty() or not _simple(polygon): errors.append("District boundaries need a simple polygon with 3 to 512 finite points.")
		errors.append_array(_validate_rules(district))
	var overrides: Dictionary=settlement.get("block_overrides",{})
	if overrides.size()>4096: errors.append("This settlement exceeds its editable block-override budget.")
	for settings: Dictionary in overrides.values():
		errors.append_array(_validate_rules(settings))
		if settings.has("district_id") and not seen.has(str(settings.district_id)): errors.append("Block overrides must reference an existing district.")
	return errors
static func _validate_rules(settings: Dictionary) -> PackedStringArray:
	var errors:=PackedStringArray()
	for spec in [["density",0.,1.],["lot_size",10.,64.],["setback",0.,10.],["height_min",1.,8.],["height_max",1.,8.]]:
		if not settings.has(spec[0]): continue
		var value:=float(settings[spec[0]])
		if not is_finite(value) or value<float(spec[1]) or value>float(spec[2]): errors.append("District or block "+str(spec[0])+" is outside its supported range.")
	if int(settings.get("height_min",1))>int(settings.get("height_max",8)): errors.append("Minimum building height cannot exceed maximum height.")
	return errors
static func rules(block: Dictionary,settlement: Dictionary) -> Dictionary:
	var result: Dictionary={}; var polygon: PackedVector2Array=block.polygon; var area:=absf(_area(polygon))
	for district: Dictionary in settlement.get("districts",[]):
		if not district.get("enabled",true): continue
		var covered:=0.
		for intersection: PackedVector2Array in Geometry2D.intersect_polygons(polygon,district.polygon): covered+=absf(_area(intersection))
		if covered<area*.5: continue
		result=district.duplicate(); result.erase("polygon"); result.district_id=district.id
	var override: Dictionary=settlement.get("block_overrides",{}).get(str(block.id),{})
	if override.has("district_id"):
		for district: Dictionary in settlement.get("districts",[]):
			if district.id==override.district_id and district.get("enabled",true): result=district.duplicate(); result.erase("polygon"); result.district_id=district.id; break
	result.merge(override,true)
	if result.is_empty(): return result
	if str(result.get("category",""))=="Park/Green Space": result.density=0.
	block.district=result.get("category",block.get("district","Residential")); block.district_id=result.get("district_id","")
	return result
static func effective(settlement: Dictionary,settings: Dictionary) -> Dictionary:
	var result:=settlement.duplicate(); result.erase("districts"); result.erase("block_overrides"); result.merge(settings,true); result.id=settlement.id
	return result
static func accept(plot: Dictionary,settings: Dictionary) -> bool:
	if settings.is_empty(): return true
	var seed:=int(settings.get("seed",1)); var value:=float(hash([plot.id,seed])&0x7fffffff)/2147483647.
	return value<float(settings.get("density",1.))
static func _area(polygon: PackedVector2Array) -> float:
	var area:=0.
	for index in polygon.size(): area+=polygon[index].cross(polygon[(index+1)%polygon.size()])
	return area*.5
static func _simple(polygon: PackedVector2Array) -> bool:
	for index in polygon.size():
		if polygon[index].distance_squared_to(polygon[(index+1)%polygon.size()])<.000001: return false
		for other in range(index+2,polygon.size()):
			if (other+1)%polygon.size()==index: continue
			if Geometry2D.segment_intersects_segment(polygon[index],polygon[(index+1)%polygon.size()],polygon[other],polygon[(other+1)%polygon.size()])!=null: return false
	return true
