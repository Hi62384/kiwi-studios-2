class_name KiwiTerrainGenerator
extends Resource
## Pure terrain-coordinate sampling. Authored landforms are ordered independently
## of sculpt edits; derived erosion, drainage and biome fields consume this base.
const PROFILES:=["Flat","Rolling Hills","Mountainous","Island","Archipelago","Desert","Canyon","Plateau","Coastal","Custom"]
const LANDFORMS:=["Mountain range","Mountain","Ridge","Valley","Canyon","Cliff","Plateau","Mesa","Hill","Basin","Crater","Dunes"]
@export var profile:=1
@export_enum("Simplex","Perlin","Ridged","Cellular","Domain warped") var noise_type:=0
@export var octaves:=4
@export var lacunarity:=2.
@export var gain:=.5
@export var medium_weight:=.3
@export var fine_weight:=.06
@export var warp_strength:=0.
@export var sharpness:=2.
@export var direction:=0.
@export var island_radius:=.8
@export var transition:=.25
@export var layers: Array[Dictionary]=[]
@export var foundation_edits:=PackedFloat32Array()
var _noise: Array[FastNoiseLite]=[]
var _warp: FastNoiseLite
var _key:=0
func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	for field in ["lacunarity","gain","medium_weight","fine_weight","warp_strength","sharpness","direction","island_radius","transition"]:
		if not is_finite(float(get(field))): errors.append("Terrain generator values must be finite."); break
	for layer in layers:
		if layer.get("type","")=="Foundation":
			var polygon: PackedVector2Array=layer.get("polygon",PackedVector2Array()); var plane: Plane=layer.get("plane",Plane(Vector3.UP,0.))
			if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty() or not plane.normal.is_finite() or not is_finite(plane.d) or absf(plane.normal.y)<.2: errors.append("Foundation modifiers need a valid footprint and a near-horizontal finite plane.")
			if not is_finite(float(layer.get("feather",1.))) or float(layer.get("feather",1.))<0.: errors.append("Foundation blending distance must be finite and nonnegative.")
		for field in ["width","length","height","direction","sharpness"]:
			if not is_finite(float(layer.get(field,1.))): errors.append("Landform values must be finite."); break
		if not (layer.get("center",Vector2.ZERO) as Vector2).is_finite(): errors.append("Landform positions must be finite.")
	return errors
func signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([profile,noise_type,octaves,lacunarity,gain,medium_weight,fine_weight,warp_strength,sharpness,direction,island_radius,transition,layers,foundation_edits])
func prepare(seed: int,frequency: float) -> void:
	var key:=hash([signature(),seed,frequency])
	if key==_key and _noise.size()==3: return
	_key=key; _noise.clear()
	for scale in 3:
		var noise:=FastNoiseLite.new(); noise.seed=seed+scale*173; noise.frequency=maxf(.000001,frequency*pow(3.,scale)); noise.noise_type=FastNoiseLite.TYPE_PERLIN if noise_type==1 else (FastNoiseLite.TYPE_CELLULAR if noise_type==3 else FastNoiseLite.TYPE_SIMPLEX_SMOOTH); noise.fractal_type=FastNoiseLite.FRACTAL_FBM; noise.fractal_octaves=clampi(octaves,1,10); noise.fractal_lacunarity=clampf(lacunarity,1.,5.); noise.fractal_gain=clampf(gain,.01,1.); _noise.append(noise)
	_warp=FastNoiseLite.new(); _warp.seed=seed+971; _warp.frequency=maxf(.000001,frequency*.7)
func value(point: Vector2,dimensions: Vector2,amplitude: float,base_height: float) -> float:
	var p:=point
	if warp_strength>0. or noise_type==4: p+=Vector2(_warp.get_noise_2dv(point),_warp.get_noise_2dv(point+Vector2(74,193)))*maxf(warp_strength,1. if noise_type==4 else 0.)
	var macro:=_noise[0].get_noise_2dv(p); var medium:=_noise[1].get_noise_2dv(p)*medium_weight; var fine:=_noise[2].get_noise_2dv(p)*fine_weight; var result:=macro+medium+fine; var rotated:=p.rotated(-deg_to_rad(direction)); var unit:=point/dimensions*2.
	if noise_type==2: result=pow(maxf(0.,1.-absf(macro)),maxf(.1,sharpness))-.5+medium+fine
	match profile:
		0: result=0.
		2: result=pow(maxf(0.,1.-absf(macro)),maxf(.1,sharpness))-.4+medium+fine
		3: result=(result+.7)*(1.-smoothstep(maxf(.01,island_radius-transition),maxf(.02,island_radius),unit.length()))-.4
		4: result=pow(clampf(result+.6,0.,1.),1.8)*1.8-.5
		5: result=pow((sin(rotated.x*.7+macro*3.)+1.)*.5,2.5)*.7+medium*.3+fine*.2
		6: result=.5+medium-1.2*exp(-pow((rotated.x-sin(rotated.y*.12)*dimensions.x*.12)/maxf(.1,dimensions.x*.07),2.))
		7: result=lerpf(result,snappedf(result,.25),.85)
		8: result=unit.x*.7+medium+fine
	var elevation:=base_height+result*amplitude
	for layer in layers:
		if not bool(layer.get("enabled",true)): continue
		if layer.get("type","")=="Foundation": continue
		var contribution:=_landform(point,layer); var weight:=mask(point,layer.get("mask",{}))
		match str(layer.get("blend","add")):
			"maximum": elevation=lerpf(elevation,maxf(elevation,base_height+contribution),weight)
			"minimum": elevation=lerpf(elevation,minf(elevation,base_height+contribution),weight)
			"replace": elevation=lerpf(elevation,base_height+contribution,weight)
			_: elevation+=contribution*weight
	return elevation
func apply_foundations(heights: PackedFloat32Array,resolution: int,dimensions: Vector2,cancel: Callable=Callable()) -> PackedFloat32Array:
	var result:=heights; var edit_resolution:=floori(sqrt(float(foundation_edits.size())))
	for layer in layers:
		if layer.get("type","")!="Foundation" or not layer.get("enabled",true): continue
		var polygon: PackedVector2Array=layer.get("polygon",PackedVector2Array()); var plane: Plane=layer.get("plane",Plane(Vector3.UP,0.)); var feather:=maxf(0.,float(layer.get("feather",1.)))
		if polygon.size()<3 or absf(plane.normal.y)<.2: continue
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: bounds=bounds.expand(point)
		bounds=bounds.grow(feather); var start:=Vector2i(((bounds.position/dimensions+Vector2.ONE*.5)*(resolution-1)).floor()).max(Vector2i.ZERO); var end:=Vector2i(((bounds.end/dimensions+Vector2.ONE*.5)*(resolution-1)).ceil()).min(Vector2i.ONE*(resolution-1))
		for z in range(start.y,end.y+1):
			if cancel.is_valid() and cancel.call(): return PackedFloat32Array()
			for x in range(start.x,end.x+1):
				var point:=Vector2(float(x)/(resolution-1)-.5,float(z)/(resolution-1)-.5)*dimensions; var inside:=Geometry2D.is_point_in_polygon(point,polygon); var distance:=INF
				if not inside:
					for edge in polygon.size(): distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[edge],polygon[(edge+1)%polygon.size()])))
				var weight:=1. if inside else (1.-smoothstep(0.,feather,distance) if feather>.0001 else 0.)
				if weight<=0.: continue
				var index:=x+z*resolution; var target:=(plane.d-plane.normal.x*point.x-plane.normal.z*point.y)/plane.normal.y
				if layer.get("surface_target",false) and edit_resolution>1 and edit_resolution*edit_resolution==foundation_edits.size():
					var p:=Vector2(x,z)/float(resolution-1)*(edit_resolution-1); var cell:=Vector2i(p.floor()).min(Vector2i.ONE*(edit_resolution-2)); var f:=p-Vector2(cell); target-=lerpf(lerpf(foundation_edits[cell.x+cell.y*edit_resolution],foundation_edits[cell.x+1+cell.y*edit_resolution],f.x),lerpf(foundation_edits[cell.x+(cell.y+1)*edit_resolution],foundation_edits[cell.x+1+(cell.y+1)*edit_resolution],f.x),f.y)
				result[index]=lerpf(result[index],target,weight)
	return result
static func mask(point: Vector2,settings: Dictionary) -> float:
	if settings.is_empty(): return 1.
	var radius:=maxf(.001,float(settings.get("radius",1.))); var distance:=point.distance_to(settings.get("center",Vector2.ZERO))/radius; var weight:=1.-smoothstep(clampf(1.-float(settings.get("falloff",.25)),0.,.999),1.,distance)
	return 1.-weight if bool(settings.get("invert",false)) else weight
static func _landform(point: Vector2,settings: Dictionary) -> float:
	var p: Vector2=(point-(settings.get("center",Vector2.ZERO) as Vector2)).rotated(-deg_to_rad(float(settings.get("direction",0.)))); var width:=maxf(.01,float(settings.get("width",5.))); var length:=maxf(.01,float(settings.get("length",20.))); var height:=float(settings.get("height",5.)); var sharp:=maxf(.1,float(settings.get("sharpness",2.))); var radial:=Vector2(p.x/width,p.y/length).length(); var axial:=p.x/width; var winding:=sin(p.y/maxf(1.,length)*TAU)*width*.35
	match str(settings.get("type","Hill")):
		"Mountain range":
			var ridge:=pow(maxf(0.,1.-absf((p.x-winding)/width)),sharp); var fork:=pow(maxf(0.,1.-absf((p.x+p.y*.4+winding*.5)/(width*.7))),sharp)*.6
			return height*maxf(ridge,fork)*(1.-smoothstep(.65,1.,absf(p.y)/length))
		"Mountain": return height*pow(maxf(0.,1.-radial),sharp)
		"Ridge": return height*pow(maxf(0.,1.-absf(axial)),sharp)*(1.-smoothstep(.7,1.,absf(p.y)/length))
		"Valley": return -height*exp(-pow((p.x-winding)/width,2.))*(1.-smoothstep(.7,1.,absf(p.y)/length))
		"Canyon": return -height*(1.-smoothstep(.55,1.,absf((p.x-winding)/width)))*(1.-smoothstep(.7,1.,absf(p.y)/length))
		"Cliff": return height*smoothstep(-.05,.05,axial)*(1.-smoothstep(.7,1.,radial))
		"Plateau","Mesa": return height*(1.-smoothstep(.65,1.,radial))
		"Basin": return -height*pow(maxf(0.,1.-radial*radial),2.)
		"Crater": return height*(exp(-pow((radial-.7)*8.,2.))*.6-exp(-pow(radial*2.,2.)))
		"Dunes": return height*pow((sin(axial*TAU)+1.)*.5,sharp)*(1.-smoothstep(.7,1.,absf(p.y)/length))
	return height*exp(-radial*radial*3.)
static func preset(index: int) -> KiwiTerrainGenerator:
	var result:=KiwiTerrainGenerator.new(); result.profile=clampi(index,0,PROFILES.size()-1)
	if index in [2,3,4]: result.warp_strength=2.
	if index==2: result.noise_type=2; result.sharpness=2.5
	if index==5: result.direction=30.; result.fine_weight=.02
	return result
