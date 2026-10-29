extends Resource
## Authored environmental rules. evaluate() is a pure, deterministic query and
## never advances persistent snow/wetness state.
const WEATHER: PackedStringArray=["Clear","Cloudy","Rain","Storm","Snow","Fog","Dust"]
const SEASONS: PackedStringArray=["Spring","Summer","Autumn","Winter"]
@export_enum("Manual","Scene timeline","Automatic") var time_mode:=1
@export_range(0.,24.,.01) var time_of_day:=9.
@export_range(.1,86400.,.1) var day_length_seconds:=600.
@export var time_speed:=1.
@export var start_time:=8.
@export var time_paused:=false
@export var latitude:=45.
@export var date_day:=172
@export_enum("Spring","Summer","Autumn","Winter") var season:=1
@export var temperature:=18.
@export_range(0.,1.,.001) var humidity:=.45
@export_range(0.,1.,.001) var cloud_coverage:=.15
@export_enum("Clear","Cloudy","Rain","Storm","Snow","Fog","Dust") var weather:=0
@export_range(0.,1.,.001) var weather_intensity:=0.
@export var wind_direction:=Vector3(1.,0.,0.)
@export_range(0.,250.,.01) var wind_speed:=2.
@export_range(0.,1.,.001) var gust_strength:=.15
@export_range(.05,3600.,.05) var gust_period:=7.
@export var visibility:=10000.
@export var altitude_temperature_lapse:=.0065
@export var procedural_weather:=false
@export var weather_seed:=1
@export_range(1.,86400.,1.) var weather_interval:=900.
@export_range(0.,3600.,.1) var weather_transition:=120.
@export_range(0.,1.,.001) var storm_probability:=.08
@export_range(0.,1.,.001) var rain_probability:=.3
@export_range(0.,1.,.001) var snow_probability:=.12
@export var schedule: Array[Dictionary]=[]
@export var regions: Array[Dictionary]=[]
@export var version:=1

func copy_climate() -> Resource:
	var result: Resource=duplicate(false)
	result.set("schedule",schedule.duplicate(true)); result.set("regions",regions.duplicate(true))
	return result

func signature() -> int:
	return hash([version,time_mode,time_of_day,day_length_seconds,time_speed,start_time,time_paused,latitude,date_day,season,temperature,humidity,cloud_coverage,weather,weather_intensity,wind_direction,wind_speed,gust_strength,gust_period,visibility,altitude_temperature_lapse,procedural_weather,weather_seed,weather_interval,weather_transition,storm_probability,rain_probability,snow_probability,schedule,regions])

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if version!=1: errors.append("Unsupported climate resource version.")
	for value in [time_of_day,day_length_seconds,time_speed,start_time,latitude,temperature,humidity,cloud_coverage,weather_intensity,wind_speed,gust_strength,gust_period,visibility,altitude_temperature_lapse,weather_interval,weather_transition,storm_probability,rain_probability,snow_probability]:
		if not is_finite(float(value)): errors.append("Climate values must be finite."); break
	if time_mode<0 or time_mode>2 or weather<0 or weather>=WEATHER.size() or season<0 or season>=SEASONS.size(): errors.append("Choose a supported time, weather and seasonal mode.")
	if day_length_seconds<=0. or time_speed<0. or time_of_day<0. or time_of_day>=24. or latitude< -90. or latitude>90. or date_day<1 or date_day>366: errors.append("Time, date and latitude are outside their supported ranges.")
	if humidity<0. or humidity>1. or cloud_coverage<0. or cloud_coverage>1. or weather_intensity<0. or weather_intensity>1. or wind_speed<0. or gust_strength<0. or gust_strength>1. or gust_period<=0. or visibility<1. or altitude_temperature_lapse<0.: errors.append("Humidity, weather, wind and atmosphere values are outside their supported ranges.")
	if procedural_weather and (weather_interval<1. or weather_transition>weather_interval or storm_probability+rain_probability+snow_probability>1.0001): errors.append("Procedural weather probabilities and transition duration must fit within one interval.")
	if schedule.size()>4096 or regions.size()>4096: errors.append("Climate schedules and local regions are limited to 4096 entries.")
	var ids: Dictionary={}
	for region: Dictionary in regions:
		var id:=str(region.get("id","")); var shape:=str(region.get("shape","Sphere")); var size: Vector3=region.get("size",Vector3.ONE); var polygon: PackedVector2Array=region.get("polygon",PackedVector2Array())
		if id.is_empty() or ids.has(id): errors.append("Weather regions need unique stable IDs.")
		ids[id]=true
		if shape not in ["Sphere","Box","Ellipsoid","Polygon"] or not (region.get("center",Vector3.ZERO) as Vector3).is_finite() or not size.is_finite() or size.x<=0. or size.y<=0. or size.z<=0. or float(region.get("blend_distance",0.))<0.: errors.append("A weather region has invalid shape or dimensions.")
		if shape=="Polygon" and (polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty()): errors.append("Polygon weather regions need a closed simple outline.")
	for entry: Dictionary in schedule:
		if not is_finite(float(entry.get("time",0.))) or not is_finite(float(entry.get("duration",0.))) or float(entry.get("duration",0.))<=0. or str(entry.get("weather",WEATHER[0])) not in WEATHER: errors.append("Weather schedule entries need valid times, durations and states.")
	return errors

func evaluate(position: Vector3,scene_time: float,altitude: float=NAN,overrides: Dictionary={}) -> Dictionary:
	var clock:=time_of_day
	if time_mode!=0 and not time_paused: clock=fposmod(start_time+scene_time/maxf(.1,day_length_seconds)*24.*time_speed,24.)
	if time_mode==0: clock=fposmod(time_of_day,24.)
	var time_override:=float(overrides.get("climate_time",-1.)); if time_override>=0.: clock=fposmod(time_override,24.)
	var day_phase:=clock/24.; var sun_angle:=day_phase*TAU-PI*.5; var latitude_radians:=deg_to_rad(latitude); var declination:=sin((float(date_day)-80.)/365.25*TAU)*deg_to_rad(23.44)
	var sun_elevation:=asin(clampf(sin(latitude_radians)*sin(declination)+cos(latitude_radians)*cos(declination)*cos(sun_angle),-1.,1.))
	var height:=position.y if is_nan(altitude) else altitude; var season_temp: float=[4.,10.,-1.,-12.][season]
	var weather_override:=int(overrides.get("climate_weather",0))-1; var selected_weather:=weather_override if weather_override>=0 else weather; var intensity_override:=float(overrides.get("climate_intensity",-1.)); var intensity:=intensity_override if intensity_override>=0. else weather_intensity
	var rain:=_scaled_weather(selected_weather,intensity); var state: Dictionary={"time_of_day":clock,"day_phase":day_phase,"sun_elevation":sun_elevation,"sun_direction":Vector3(cos(sun_angle),sin(sun_elevation),sin(sun_angle)).normalized(),"temperature":temperature+season_temp-height*altitude_temperature_lapse+float(overrides.get("climate_temperature_offset",0.)),"humidity":humidity,"cloud_coverage":cloud_coverage,"weather":rain.weather,"weather_intensity":rain.weather_intensity,"precipitation":rain.precipitation,"rain":rain.rain,"snow":rain.snow,"fog":rain.fog,"dust":rain.dust,"wind_velocity":wind_direction.normalized()*wind_speed+(overrides.get("climate_wind_add",Vector3.ZERO) as Vector3),"gust_strength":gust_strength,"visibility":visibility,"season":SEASONS[season],"sunlight_energy":clampf(sin(sun_elevation)*1.3,0.,1.3)}
	if weather_override>=0: pass
	elif procedural_weather:
		var generated:=_procedural_state(scene_time)
		state=_blend_weather(state,generated)
	elif not schedule.is_empty(): state=_blend_weather(state,_scheduled_state(scene_time))
	var cloud_override:=float(overrides.get("climate_clouds",-1.)); if cloud_override>=0.: state.cloud_coverage=cloud_override
	var gust_phase:=sin(scene_time/maxf(.05,gust_period)*TAU+float(weather_seed%997)*.013)
	state.wind_velocity=(wind_direction.normalized()*wind_speed*(1.+gust_strength*.5*(gust_phase+1.)))+(overrides.get("climate_wind_add",Vector3.ZERO) as Vector3)
	if intensity_override>=0. and weather_override<0:
		var selected_index:=WEATHER.find(str(state.weather)); if selected_index>=0: state=_blend_weather(state,_scaled_weather(selected_index,intensity))
	var ordered:=regions.duplicate(); ordered.sort_custom(func(a: Dictionary,b: Dictionary): var ap:=int(a.get("priority",0)); var bp:=int(b.get("priority",0)); return ap<bp if ap!=bp else str(a.get("id",""))<str(b.get("id","")))
	for region: Dictionary in ordered:
		var weight:=_region_weight(region,position)
		if weight<=0.: continue
		var region_overrides: Dictionary=region.get("overrides",{})
		for key in ["temperature","humidity","cloud_coverage","weather_intensity","visibility","gust_strength"]:
			if region_overrides.has(key): state[key]=lerpf(float(state[key]),float(region_overrides[key]),weight)
		if region_overrides.has("wind_velocity"):
			var velocity: Vector3=state.wind_velocity; state.wind_velocity=velocity.lerp(region_overrides.wind_velocity,weight)
		if region_overrides.has("weather"):
			var local_weather: String=str(region_overrides.weather); var local_index:=WEATHER.find(local_weather)
			if local_index>=0: state=_blend_weather(state,_scaled_weather(local_index,float(region_overrides.get("weather_intensity",1.))),weight)
	return state

func apply_environment(environment: Environment,scene_time: float,position: Vector3=Vector3.ZERO,overrides: Dictionary={}) -> Dictionary:
	if environment==null: return {}
	var state:=evaluate(position,scene_time,NAN,overrides)
	if not environment.has_meta("kiwi_climate_base"):
		var base: Dictionary={"background_mode":environment.background_mode,"fog_enabled":environment.fog_enabled,"fog_density":environment.fog_density,"fog_light_color":environment.fog_light_color,"ambient_light_color":environment.ambient_light_color,"ambient_light_energy":environment.ambient_light_energy}
		if environment.sky!=null and environment.sky.sky_material is ProceduralSkyMaterial:
			var material:=environment.sky.sky_material as ProceduralSkyMaterial
			base.sky_colors=[material.sky_top_color,material.sky_horizon_color,material.ground_bottom_color,material.ground_horizon_color]
		environment.set_meta("kiwi_climate_base",base)
	var authored: Dictionary=environment.get_meta("kiwi_climate_base")
	var night:=clampf(-float(state.sun_elevation)/.8,0.,1.); var clouds:=float(state.cloud_coverage)
	if environment.background_mode==Environment.BG_SKY and environment.sky!=null and environment.sky.sky_material is ProceduralSkyMaterial:
		var material:=environment.sky.sky_material as ProceduralSkyMaterial; var source: Array=authored.get("sky_colors",[Color(.12,.2,.38),Color(.55,.68,.8),Color(.08,.1,.14),Color(.35,.38,.4)]); var twilight:=clampf(1.-absf(float(state.sun_elevation))/.24,0.,1.)
		var top: Color=(source[0] as Color).lerp(Color(.006,.012,.035),night).lerp(Color(.38,.2,.12),twilight*.4); var horizon: Color=(source[1] as Color).lerp(Color(.025,.035,.08),night).lerp(Color(.95,.36,.12),twilight*.65); var overcast:=Color(.43,.48,.53)
		material.sky_top_color=top.lerp(overcast,clouds*.68); material.sky_horizon_color=horizon.lerp(overcast,clouds*.78); material.ground_bottom_color=(source[2] as Color).lerp(Color(.015,.019,.028),night); material.ground_horizon_color=(source[3] as Color).lerp(Color(.17,.19,.21),clouds*.45)
	var fog_amount:=float(state.fog)+float(state.rain)*.12; environment.fog_enabled=bool(authored.get("fog_enabled",false)) or fog_amount>.01; environment.fog_density=maxf(float(authored.get("fog_density",0.)),fog_amount*.035); if environment.fog_enabled: environment.fog_light_color=Color(.48,.54,.62).lerp(Color(.26,.3,.36),night)
	environment.ambient_light_color=(authored.get("ambient_light_color",Color.WHITE) as Color).lerp(Color(.2,.27,.4),night*.65).lerp(Color(.48,.51,.54),clouds*.35); environment.ambient_light_energy=float(authored.get("ambient_light_energy",1.))*lerpf(.32,1.,float(state.sunlight_energy)/1.3 if float(state.sunlight_energy)>0. else .15)
	return state

func make_environment(scene_time: float) -> Environment:
	var result:=Environment.new(); result.background_mode=Environment.BG_SKY; result.sky=Sky.new(); result.sky.sky_material=ProceduralSkyMaterial.new(); result.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; result.ambient_light_color=Color.WHITE; result.ambient_light_energy=1.; apply_environment(result,scene_time); return result

func _procedural_state(scene_time: float) -> Dictionary:
	var interval:=maxf(1.,weather_interval); var slot:=floori(scene_time/interval); var phase:=fposmod(scene_time,interval)
	var previous:=_procedural_pick(slot-1); var current:=_procedural_pick(slot); var blend:=1. if weather_transition<=0. else smoothstep(0.,1.,clampf(phase/weather_transition,0.,1.))
	return _blend_weather(previous,current,blend)

func _procedural_pick(slot: int) -> Dictionary:
	var rng:=RandomNumberGenerator.new(); rng.seed=hash([weather_seed,slot]); var roll:=rng.randf(); var selected: int=3 if roll<storm_probability else (2 if roll<storm_probability+rain_probability else (4 if roll<storm_probability+rain_probability+snow_probability else (1 if roll<.65 else 0)))
	return _scaled_weather(selected,.6+rng.randf()*.4)

func _scheduled_state(scene_time: float) -> Dictionary:
	var entries:=schedule.duplicate(); entries.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.get("time",0.))<float(b.get("time",0.)))
	var previous:=_weather_value(weather); previous["weather_intensity"]=weather_intensity
	for entry: Dictionary in entries:
		var start:=float(entry.time); var duration:=float(entry.get("duration",1.)); var target_index:=WEATHER.find(str(entry.get("weather","Clear"))); if target_index<0: continue
		var target:=_scaled_weather(target_index,float(entry.get("intensity",1.)))
		if scene_time<start: return previous
		if scene_time<start+duration: return _blend_weather(previous,target,smoothstep(0.,1.,(scene_time-start)/duration))
		previous=target
	return previous

func _weather_value(index: int) -> Dictionary:
	var result: Dictionary={"weather":WEATHER[index],"precipitation":0.,"rain":0.,"snow":0.,"fog":0.,"dust":0.,"cloud_coverage":cloud_coverage,"weather_intensity":weather_intensity}
	match index:
		1: result.cloud_coverage=.65
		2: result.merge({"precipitation":1.,"rain":1.,"cloud_coverage":.8},true)
		3: result.merge({"precipitation":1.,"rain":1.,"cloud_coverage":1.,"fog":.2},true)
		4: result.merge({"precipitation":1.,"snow":1.,"cloud_coverage":.82},true)
		5: result.merge({"fog":1.,"cloud_coverage":.9},true)
		6: result.merge({"dust":1.,"cloud_coverage":.55},true)
	return result

func _scaled_weather(index: int,intensity: float) -> Dictionary:
	var result:=_weather_value(index); intensity=clampf(intensity,0.,1.); result.weather_intensity=intensity
	for key in ["precipitation","rain","snow","fog","dust"]: result[key]=float(result.get(key,0.))*intensity
	return result

func _blend_weather(from: Dictionary,to: Dictionary,weight: float=1.) -> Dictionary:
	var result:=from.duplicate(true); weight=clampf(weight,0.,1.)
	for key in ["precipitation","rain","snow","fog","dust","weather_intensity","cloud_coverage"]:
		if to.has(key): result[key]=lerpf(float(result.get(key,0.)),float(to[key]),weight)
	if weight>=.5:
		for key in ["weather","season"]:
			if to.has(key): result[key]=to[key]
	return result

func _region_weight(region: Dictionary,point: Vector3) -> float:
	if not region.get("enabled",true): return 0.
	var center: Vector3=region.get("center",Vector3.ZERO); var delta:=point-center; var size: Vector3=region.get("size",Vector3.ONE); var inside:=false; var edge:=0.
	match str(region.get("shape","Sphere")):
		"Sphere": edge=size.x*.5-delta.length(); inside=edge>=0.
		"Ellipsoid":
			var normalized:=Vector3(delta.x/maxf(.001,size.x*.5),delta.y/maxf(.001,size.y*.5),delta.z/maxf(.001,size.z*.5)); inside=normalized.length()<=1.; edge=(1.-normalized.length())*minf(size.x,minf(size.y,size.z))*.5
		"Box":
			var margin:=size*.5-delta.abs(); inside=margin.x>=0. and margin.y>=0. and margin.z>=0.; edge=minf(margin.x,minf(margin.y,margin.z))
		"Polygon":
			var polygon: PackedVector2Array=region.get("polygon",PackedVector2Array()); inside=Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),polygon)
			if inside:
				edge=INF
				for index in polygon.size(): edge=minf(edge,point_to_segment(Vector2(point.x,point.z),polygon[index],polygon[(index+1)%polygon.size()]))
	if not inside: return 0.
	var blend:=float(region.get("blend_distance",0.)); return 1. if blend<=0. else smoothstep(0.,blend,edge)

static func point_to_segment(point: Vector2,a: Vector2,b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))


