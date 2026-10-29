extends RefCounted
static func create(base: ActorDefinition) -> ActorDefinition:
	var definition:=base.duplicate(true) as ActorDefinition; definition.type_id=&"environment_asset"; definition.display_name="Environment Asset"; definition.category="Environment"; definition.description="Linked terrain, placed models and instanced scatter from Environment Creator."; definition.icon=load("res://resources/Images/ActorIcons/EnvironmentAsset.svg"); definition.runtime_scene=load("res://Workspaces/EnvironmentWorkspace/environment_actor.tscn")
	var path:=ActorProperty.create(&"environment_path","Environment document",""); path.options.merge({"file_picker":true,"extensions":["tres","res"],"native_resource_types":["KiwiEnvironmentDocument"],"file_resource_mode":"uneditable","group":"Environment"}); definition.properties.append(path)
	var open:=ActorProperty.create(&"environment_open","Edit environment",false); open.options.merge({"environment_open":true,"group":"Environment","no_keyframes":true}); definition.properties.append(open)
	var physics:=ActorProperty.create(&"physics","Environment collision",{"enabled":true,"body_mode":1,"shape":6,"gravity":0.}); physics.options.inspector_hidden=true; physics.options.group="Physics"; definition.properties.append(physics)
	for row in [["include_lighting","Include authored lights",true],["include_atmosphere","Use authored world / sky",false]]:
		var property:=ActorProperty.create(StringName(row[0]),row[1],row[2]); property.options.group="Environment"; definition.properties.append(property)
	var time:=ActorProperty.create(&"climate_time","Time of day override (-1 = inherit)",-1.,true); time.options.merge({"group":"Climate override","min":-1.,"max":24.,"step":.05,"suffix":" h"}); definition.properties.append(time)
	var weather:=ActorProperty.create(&"climate_weather","Weather override",0,true); weather.options.merge({"group":"Climate override","min":0,"max":7,"step":1,"choices":["Inherit","Clear","Cloudy","Rain","Storm","Snow","Fog","Dust"]}); definition.properties.append(weather)
	for row in [["climate_intensity","Weather intensity override",-1.],["climate_clouds","Cloud coverage override",-1.]]:
		var property:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); property.options.merge({"group":"Climate override","min":-1.,"max":1.,"step":.01}); definition.properties.append(property)
	var temperature:=ActorProperty.create(&"climate_temperature_offset","Temperature offset (°C)",0.,true); temperature.options.merge({"group":"Climate override","min":-100.,"max":100.,"step":.1}); definition.properties.append(temperature)
	var wind:=ActorProperty.create(&"climate_wind_add","Wind velocity addition (m/s)",Vector3.ZERO,true); wind.options.merge({"group":"Climate override","min":-250.,"max":250.,"step":.1}); definition.properties.append(wind)
	return definition
