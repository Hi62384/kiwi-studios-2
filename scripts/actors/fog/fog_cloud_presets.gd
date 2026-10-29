extends RefCounted
const TITLES:=["Fair-Weather Cumulus","Thick Cumulus","Stratus","Wispy High Clouds","Storm Clouds","Cartoon Clouds","Anime Clouds","Fantasy Clouds","Morning Mist","Ground Fog","Valley Mist","Forest Mist","Thick Cave Fog","Stylized Mist","Clear Atmospheric Haze","Distant Mountain Haze","Dusty Atmosphere","Humid Tropical Haze","Overcast Atmosphere","Stylized Atmospheric Perspective"]
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
static func configuration(index: int,original: Variant=null) -> Dictionary:
	index=clampi(index,0,TITLES.size()-1); var field:=Field.definition().create_object(); var appearance:=Appearance.definition().create_object()
	var kind: int=[0,0,1,2,3,0,0,0,4,4,4,4,4,4,5,5,5,5,1,5][index]
	field.values.merge({&"mode":8,&"cloud_type":kind,&"resolution":1,&"cloud_coverage":.65,&"cloud_base":.04,&"cloud_thickness":.92,&"seed":31},true)
	appearance.values.merge({&"title":TITLES[index],&"cloud_lighting":kind<4,&"cloud_shadow_strength":1.,&"silver_lining":.5 if kind<4 else 0.,&"cloud_lod":kind<4},true)
	var optical: float=[.18,.4,.12,.045,.65,.2,.18,.15,.03,.08,.06,.045,.25,.05,.002,.008,.018,.012,.1,.007][index]
	if index==0: field.values[&"cloud_coverage"]=.45
	if index==1: field.values[&"cloud_detail"]=.65; field.values[&"cloud_coverage"]=.85
	if kind==1: field.values[&"cloud_base"]=.3; field.values[&"cloud_thickness"]=.4
	if kind==2: field.values[&"cloud_base"]=.35; field.values[&"cloud_thickness"]=.3; field.values[&"cloud_erosion"]=.1; field.values[&"cloud_size"]=.3
	if kind==3: field.values[&"cloud_coverage"]=.85; field.values[&"cloud_detail"]=.7; appearance.values[&"gradient"]=1; appearance.values[&"color"]=Color("374554"); appearance.values[&"secondary"]=Color("c0c8d2")
	if index in [5,6,7,13,19]:
		appearance.values[&"render_style"]={5:1,6:2,7:4,13:3,19:2}[index]; appearance.values[&"gradient"]=1; appearance.values[&"color"]=Color("86a9cd"); appearance.values[&"secondary"]=Color("fff3db"); field.values[&"cloud_erosion"]=.05
	if index==7: appearance.values[&"color"]=Color("9d77d0"); appearance.values[&"secondary"]=Color("e9a0cd"); appearance.values[&"emission"]=Color(.05,.01,.1)
	if kind==4:
		appearance.values[&"color"]=Color("cedde3"); field.values[&"cloud_coverage"]=.85; field.values[&"cloud_ground_falloff"]=[3.,1.,6.,4.,2.,3.][index-8]
	if index==10: field.values[&"cloud_size"]=2.; field.values[&"cloud_detail"]=.1
	if index==11: appearance.values[&"color"]=Color("9aac9c"); field.values[&"cloud_coverage"]=.6
	if index==12: appearance.values[&"color"]=Color("59677c"); appearance.values[&"absorption"]=.8
	if index==16: appearance.values[&"color"]=Color("be9b73")
	if index==17: appearance.values[&"color"]=Color("a2c6c9")
	if kind==5: appearance.values[&"color"]=Color("b6cce1") if index!=16 and index!=17 else appearance.values[&"color"]; field.values[&"cloud_ground_falloff"]=1000.; field.values[&"cloud_base"]=0.; field.values[&"cloud_thickness"]=1.
	# Preserve painted/custom source data as an editable mask; repeated presets
	# replace the cloud generator instead of nesting another cloud every time.
	var previous:=preload("res://scripts/actors/fog/fog_actor.gd").resolve(original)
	if previous!=null:
		field.values[&"mask"]=previous.values.get(&"mask") if int(previous.values.get(&"mode",0))==8 else original
	return {&"field":ActorObjectReference.from_object(field),&"appearance":ActorObjectReference.from_object(appearance),&"density":optical}

static func apply(model: RefCounted,actor: ActorData,index: int) -> void:
	var next:=configuration(index,actor.values.get(&"field")); model.history.create_action("Atmosphere: "+TITLES[clampi(index,0,TITLES.size()-1)])
	for key: StringName in next:
		model.history.add_do_method(model._set_property.bind(actor,key,next[key])); model.history.add_undo_method(model._set_property.bind(actor,key,ActorData.copy_value(actor.values.get(key))))
	model.history.commit_action()
