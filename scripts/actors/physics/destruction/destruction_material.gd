class_name KiwiDestructionMaterial
extends RefCounted
## Artistic local energy/yield model, not a finite-element stress solver.
const NAMES := ["Glass","Steel","Aluminum","Wood","Stone","Concrete","Plastic","Ceramic","Rubber"]
const VISUAL := ["material_name","material_id","interior","exterior","vfx_family","vfx_preset"]
static func definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"destruction_material"; d.display_name="Destruction Material"
	var family:=ActorProperty.create(&"vfx_family","Debris effect family",0); family.options.merge({"choices":["Automatic","Glass / ceramic","Metal","Wood","Stone / concrete / dirt"],"group":"Debris effects"}); d.properties.append(family)
	var effect:=ActorProperty.create(&"vfx_preset","Default VFX preset",null); effect.object_type=&"debris_vfx"; effect.options.group="Debris effects"; d.properties.append(effect)
	for row in [
		["material_name","Name","Glass",{}],["material_id","Material ID","",{"no_keyframes":true}],
		["strength","Strength (J reference energy)",8.0,{"min":.01,"max":1000.0}],
		["toughness","Toughness (J)",3.0,{"min":.01,"max":1000.0}],
		["bendability","Bendability",.03,{"min":0.0,"max":1.0}],
		["hardness","Indentation resistance (J)",12.0,{"min":.01,"max":1000.0}],
		["brittleness","Brittleness",.98,{"min":0.0,"max":1.0}],
		["density","Density (kg/m³)",2500.0,{"min":1.0,"max":30000.0}],
		["debris_friction","Debris friction",.35,{"min":0.0,"max":1.0}],
		["debris_restitution","Debris restitution",.45,{"min":0.0,"max":1.0}],
		["grain_direction","Preferred direction (local)",Vector3.UP,{}],
		["anisotropy","Directional weakness",0.0,{"min":0.0,"max":1.0}],
		["branching","Fracture branching",.9,{"min":0.0,"max":1.0}],
		["irregularity","Split-plane irregularity",.1,{"min":0.0,"max":1.0}],
		["fragment_size","Fragment size bias",.4,{"min":.1,"max":2.0}],
		["accumulation","Local damage accumulation",.7,{"min":0.0,"max":2.0}],
		["fatigue","Fatigue resistance",.4,{"min":.01,"max":5.0}],
		["rate_sensitivity","Strain-rate sensitivity",.0,{"min":0.0,"max":1.0}],
		["seed","Fracture seed",31,{"no_keyframes":true}],
		["advanced","Explicit yield / failure energies",false,{"refresh_inspector":true}],
		["yield_energy","Yield energy (J)",3.0,{"min":.01,"max":10000.0}],
		["fracture_energy","Fracture energy (J)",14.0,{"min":.01,"max":10000.0}],
		["stiffness","Elastic stiffness",1.0,{"min":.01,"max":20.0}],
		["tensile","Tensile resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["compressive","Compressive resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["shear","Shear resistance multiplier",1.0,{"min":.01,"max":10.0}],
		["plastic_limit","Plastic deformation limit (m)",.3,{"min":.001,"max":5.0}]
	]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],not row[3].get("no_keyframes",false)); p.options.merge(row[3]); p.options.group="Physical material"
		if row[0] in ["yield_energy","fracture_energy","stiffness","tensile","compressive","shear","plastic_limit"]: p.options.group="Advanced"; p.options.visible_when={"property":"advanced","values":[true]}
		d.properties.append(p)
	for key in [&"interior",&"exterior"]:
		var p:=ActorProperty.create(key,"Fracture interior" if key==&"interior" else "Associated exterior",null); p.object_type=&"material"; p.options={"default":null,"group":"Appearance association","accepted_object_types":["material","shader_material","natural_material"]}; d.properties.append(p)
	return d
static func preset(index: int) -> ActorObjectData:
	index=clampi(index,0,NAMES.size()-1); var data:=definition().create_object()
	data.values[&"vfx_family"]=[1,2,2,3,4,4,4,1,4][index]
	data.values[&"debris_friction"]=[.35,.4,.45,.6,.8,.85,.4,.4,.9][index]; data.values[&"debris_restitution"]=[.45,.2,.25,.15,.08,.05,.35,.25,.7][index]
	data.values.merge({&"material_name":NAMES[index],&"material_id":ActorData.new_id(),&"strength":[8.,90.,40.,16.,45.,28.,20.,18.,35.][index],&"toughness":[3.,120.,55.,25.,14.,8.,25.,4.,100.][index],&"bendability":[.03,.45,.65,.15,.02,.03,.65,.015,.98][index],&"hardness":[12.,100.,45.,12.,80.,35.,12.,90.,2.][index],&"brittleness":[.98,.08,.12,.55,.88,.8,.3,.99,.01][index],&"density":[2500.,7850.,2700.,650.,2600.,2400.,1100.,2300.,1000.][index],&"anisotropy":.92 if index==3 else 0.,&"branching":[.95,.1,.2,.15,.4,.7,.2,.8,.05][index],&"irregularity":[.05,.2,.2,.05,.9,.7,.3,.12,.15][index],&"fragment_size":[.3,1.2,1.,1.6,1.2,.7,1.,.45,1.8][index]},true)
	return data
static func resolve(values: Dictionary,point: Vector3=Vector3.ZERO) -> ActorObjectData:
	# Explicit spatial region > component actor material > linked visual material.
	for key in [&"destruction_region",&"destruction_region_2"]:
		var ref: Variant=values.get(key); var region:=ActorAnimation.resolve_reference(ref) if ref is ActorObjectReference else null
		if region!=null and point.distance_to(region.get_value(&"center",Vector3.ZERO))<=float(region.get_value(&"radius",.5)):
			var material: Variant=region.get_value(&"material")
			if material is ActorObjectReference: return ActorAnimation.resolve_reference(material)
	var ref: Variant=values.get(&"destruction_material")
	if ref is ActorObjectReference: return ActorAnimation.resolve_reference(ref)
	var visual: Variant=values.get(&"material"); var object:=ActorAnimation.resolve_reference(visual) if visual is ActorObjectReference else null
	if object!=null and object.get_value(&"damage_material") is ActorObjectReference: return ActorAnimation.resolve_reference(object.get_value(&"damage_material"))
	return null
static func region_definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"destruction_region"; d.display_name="Damage Material Region"
	for row in [["center","Center (actor local)",Vector3.ZERO],["radius","Region radius (m)",.5]]: d.properties.append(ActorProperty.create(StringName(row[0]),row[1],row[2],true))
	var p:=ActorProperty.create(&"material","Physical material",null); p.object_type=&"destruction_material"; d.properties.append(p); return d
static func physical(value: Variant) -> Variant:
	if value is ActorObjectReference: return physical(ActorAnimation.resolve_reference(value))
	if value is ActorObjectData:
		var result:={}
		for key: Variant in value.values:
			if not str(key) in VISUAL: result[str(key)]=physical(value.values[key])
		return result
	return value
static func response(material: ActorObjectData,event: Dictionary,cell: Dictionary,thickness: float) -> Dictionary:
	var v:=material.values; var strength:=maxf(.01,float(v.get(&"strength",8))); var toughness:=maxf(.01,float(v.get(&"toughness",3))); var brittle:=clampf(float(v.get(&"brittleness",.98)),0,1); var bend:=clampf(float(v.get(&"bendability",.03)),0,1)
	var axis: Vector3=(v.get(&"grain_direction",Vector3.UP) as Vector3).normalized(); var normal: Vector3=event.normal; var anisotropy:=clampf(float(v.get(&"anisotropy",0)),0,1)
	var directional:=lerpf(1,.25+absf(normal.dot(axis))*.75,anisotropy)
	var scale:=clampf(thickness,.03,2.)*directional; var energy:=maxf(0,float(event.energy))
	var yield_energy:=float(v.get(&"yield_energy",3)) if v.get(&"advanced",false) else strength*lerpf(.7,.15,bend)
	var failure:=float(v.get(&"fracture_energy",14)) if v.get(&"advanced",false) else strength+toughness*(1+bend*3)
	if v.get(&"advanced",false):
		yield_energy*=maxf(.01,float(v.get(&"compressive",1))); failure*=maxf(.01,float(v.get(&"tensile",1)))
	scale*=1+float(v.get(&"rate_sensitivity",0))*sqrt(energy)*.05
	var damage:=float(cell.get("damage",0))
	if energy>strength*scale*.02: damage+=energy*float(v.get(&"accumulation",.7))/maxf(.01,float(v.get(&"fatigue",.4))*(float(v.get(&"shear",1)) if v.get(&"advanced",false) else 1.0))
	cell.damage=damage; var accumulated:=energy+damage*.3
	var kind:=-1
	if accumulated>=failure*scale: kind=2 if brittle>.4 else 0
	elif accumulated>=strength*scale and brittle>.55: kind=3
	elif energy>=yield_energy*scale*.08: kind=9
	if kind<0:
		if not cell.has("stage"): cell.stage="undamaged"
		return {}
	var op:=KiwiDestructionDefinition.operation(kind); op.position=event.get("local_point",Vector3.ZERO); op.direction=normal
	op.amount=minf(float(v.get(&"plastic_limit",.3)) if v.get(&"advanced",false) else .6,energy/maxf(.01,float(v.get(&"hardness",12)))*maxf(.04,bend)*(1-brittle*.7)/maxf(.1,float(v.get(&"stiffness",1)))/maxf(.1,directional))
	if kind==3: op.amount=maxf(.02,thickness*clampf(accumulated/(failure*scale),.05,.9)); op.radius=maxf(.05,thickness*.6)
	op.elastic=energy<yield_energy*scale or bend>.9; op.seed=int(v.get(&"seed",31)); op.anisotropy=anisotropy; op.grain_direction=axis; op.irregularity=float(v.get(&"irregularity",.1)); op.branching=float(v.get(&"branching",.9))
	op.pieces=clampi(roundi(3+float(op.branching)*10/maxf(.1,float(v.get(&"fragment_size",.4)))),2,16)
	cell.stage="fractured" if kind in [0,2] else ("cracked" if kind==3 else ("elastic" if op.elastic else "plastic"))
	return op
