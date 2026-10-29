extends "res://scripts/actors/tests/surface_growth_test.gd"
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const Cloud=preload("res://scripts/actors/fog/fog_cloud_field.gd")
const Presets=preload("res://scripts/actors/fog/fog_cloud_presets.gd")
func run() -> void:
	var signatures:=[]; var all_populated:=true; var started:=Time.get_ticks_usec(); var ranges:=[]
	for kind in 6:
		var field:=Field.definition().create_object(); field.values.merge({&"mode":8,&"cloud_type":kind,&"resolution":0},true)
		var texture:=Field.texture(field.values); var descriptor:=Field.prepare_cpu(field.values); var total:=0.; var peak:=0.
		for image: Image in descriptor.images:
			for y in image.get_height():
				for x in image.get_width(): total+=image.get_pixel(x,y).r; peak=maxf(peak,image.get_pixel(x,y).r)
		ranges.append([kind,total,peak]); signatures.append(hash(descriptor.images.map(func(image: Image): return image.get_data()))); all_populated=all_populated and total>1. and peak>.02
		check(texture==Field.texture(field.values),"Formation %d reuses its bounded density texture"%kind)
	print("CLOUD FIELDS six_16cubed_ms=",float(Time.get_ticks_usec()-started)/1000.," ranges=",ranges)
	check(all_populated and signatures.size()==6,"All six atmospheric formations contain actual spatial density")
	var unique:={}
	for signature in signatures: unique[signature]=true
	check(unique.size()==6,"Cumulus, stratus, wisps, storm, mist and haze produce distinct volume structures")
	var field:=Field.definition().create_object(); field.values.merge({&"mode":8,&"resolution":0},true); var a:=Field.prepare_cpu(field.values); field.values[&"seed"]=9; var b:=Field.prepare_cpu(field.values); field.values[&"seed"]=1; var restored:=Field.prepare_cpu(field.values)
	check(a.images[8].get_data()!=b.images[8].get_data() and a.images[8].get_data()==restored.images[8].get_data(),"Cloud seed changes structure and deterministically restores it")
	field.values[&"cloud_type"]=5; var haze:=Field.prepare_cpu(field.values)
	check(Field.sample_prepared(haze,Vector3.ONE*.5,Vector3.ZERO)>Field.sample_prepared(haze,Vector3.ONE*.5,Vector3(0,10,0)),"Atmospheric haze uses real world elevation falloff")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var model:=ActorTimeline.new(); var clip:=model.create_actor(registry.get_definition(&"fog_volume"),0.); var actor:=model.actor_for_id(clip.actor_id)
	var painted:=Field.definition().create_object(); painted.values[&"mode"]=5; painted.values[&"paint"]={Vector3i(15,15,15):.75}; actor.values[&"field"]=ActorObjectReference.from_object(painted)
	Presets.apply(model,actor,0); var cloud:=ActorAnimation.resolve_reference(actor.values[&"field"]); var mask:=ActorAnimation.resolve_reference(cloud.values[&"mask"])
	check(mask.values[&"paint"]==painted.values[&"paint"],"Atmospheric presets preserve authored paint in an editable mask")
	Presets.apply(model,actor,4); cloud=ActorAnimation.resolve_reference(actor.values[&"field"]); mask=ActorAnimation.resolve_reference(cloud.values[&"mask"])
	check(int(mask.values[&"mode"])==5,"Changing presets replaces the generator without stacking old cloud generators")
	model.undo(); check(int(ActorAnimation.resolve_reference(actor.values[&"field"]).values[&"cloud_type"])==0,"A complete atmosphere preset is one undo action")
	var valid:=true
	for i in Presets.TITLES.size():
		var config:=Presets.configuration(i); valid=valid and config[&"density"]>0. and config[&"field"] is ActorObjectReference and config[&"appearance"] is ActorObjectReference
	check(valid and Presets.TITLES.size()==20,"All twenty cloud, mist and atmosphere presets configure editable shared field and appearance objects")
	var path:="user://cloud-field.tres"; ResourceSaver.save(cloud,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(loaded!=null and loaded.values[&"cloud_type"]==cloud.values[&"cloud_type"] and ActorAnimation.resolve_reference(loaded.values[&"mask"]).values[&"paint"]==painted.values[&"paint"],"Cloud generators save and reopen with their authored mask dependencies")
	DirAccess.remove_absolute(path); model.history.clear_history(); print("CLOUD FIELDS: %d checks, %d failures"%[checks,failures]); quit(failures)
