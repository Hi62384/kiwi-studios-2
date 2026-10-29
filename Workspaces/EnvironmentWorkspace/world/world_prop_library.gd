extends RefCounted
## Editable multi-part native models, shared by ordinary scatter palettes.
const NAMES=["Park bench","Street lamp","Bollard","Direction sign","Wood fence","Stone boundary","Supply crates","Rock cluster"]
static func model(kind: String) -> KiwiModelDocument:
	var document:=KiwiModelDocument.new(); var wood:=_material(Color("72523b")); var metal:=_material(Color("3b454a")); var stone:=_material(Color("858980")); var light:=_material(Color("fff0bd")); light.emission_enabled=true; light.emission=Color("ffda85"); light.emission_energy_multiplier=2.
	match kind:
		"Park bench":
			for x: float in [-.65,.65]: _part(document,"Leg","Box",{"size":Vector3(.1,.5,.6)},Vector3(x,.25,0),metal)
			for z in 3: _part(document,"Seat slat","Box",{"size":Vector3(1.65,.07,.17)},Vector3(0,.52,(z-1)*.2),wood)
			for y in 2: _part(document,"Back slat","Box",{"size":Vector3(1.65,.16,.07)},Vector3(0,.8+y*.2,.3),wood)
		"Street lamp":
			_part(document,"Foot","Cylinder",{"radius":.18,"height":.15,"segments":12},Vector3(0,.075,0),metal); _part(document,"Post","Cylinder",{"radius":.055,"height":3.6,"segments":10},Vector3(0,1.9,0),metal); _part(document,"Arm","Box",{"size":Vector3(.1,.1,.8)},Vector3(0,3.65,-.35),metal); _part(document,"Lamp housing","Box",{"size":Vector3(.4,.15,.65)},Vector3(0,3.58,-.65),metal); _part(document,"Lamp lens","Box",{"size":Vector3(.32,.025,.55)},Vector3(0,3.49,-.65),light)
		"Bollard": _part(document,"Base","Cylinder",{"radius":.14,"height":.1,"segments":12},Vector3(0,.05,0),metal); _part(document,"Post","Cylinder",{"radius":.075,"height":.85,"segments":12},Vector3(0,.525,0),metal); _part(document,"Reflector","Cylinder",{"radius":.078,"height":.07,"segments":12},Vector3(0,.8,0),light)
		"Direction sign":
			_part(document,"Post","Cylinder",{"radius":.05,"height":2.,"segments":10},Vector3(0,1.,0),metal); _part(document,"Sign board","Box",{"size":Vector3(1.2,.35,.09)},Vector3(0,1.75,0),wood); _part(document,"Arrow","Prism",{"size":Vector3(.3,.35,.09)},Vector3(.72,1.75,0),wood)
		"Wood fence":
			for x: float in [-1.,1.]: _part(document,"Post","Box",{"size":Vector3(.12,1.2,.12)},Vector3(x,.6,0),wood)
			for y: float in [.35,.9]: _part(document,"Rail","Box",{"size":Vector3(2.1,.13,.09)},Vector3(0,y,0),wood)
		"Stone boundary":
			for row in 3:
				for block in 4: _part(document,"Stone","Box",{"size":Vector3(.5,.22,.35)},Vector3((block-1.5)*.51+(row%2)*.1,.11+row*.23,0),stone)
		"Supply crates":
			for spec: Vector3 in [Vector3(-.3,.35,0),Vector3(.45,.25,.2),Vector3(-.3,.95,0)]: _part(document,"Crate","Box",{"size":Vector3(.65,.6,.65)},spec,wood)
		"Rock cluster":
			for spec: Vector3 in [Vector3(-.4,.25,0),Vector3(.35,.4,.2),Vector3(.15,.16,-.45)]: _part(document,"Rock","Sphere",{"radius":.45,"segments":10},spec,stone)
	if not document.components.is_empty(): document.components[0].title=kind
	return document
static func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new(); material.albedo_color=color; material.roughness=.85; return material
static func _part(document: KiwiModelDocument,title: String,shape: String,settings: Dictionary,position: Vector3,material: Material) -> void:
	var part:=KiwiModelComponent.new(); part.id="part:"+str(document.components.size()); part.title=title; part.generator=shape; part.parameters=KiwiModelPrimitives.defaults(shape); part.parameters.merge(settings,true); part.mesh=KiwiModelPrimitives.create(shape,settings); part.transform.origin=position; part.surface_materials.append(material); document.components.append(part)
static func add(source: Resource,kind: String) -> Resource:
	var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_props.gd").create(source,model(kind),"Roadside" if kind not in ["Supply crates","Rock cluster"] else "Clusters"); var rule: Dictionary=next.prop_rules[-1]; rule.name=kind; rule.spacing=20. if kind=="Street lamp" else (2.1 if kind in ["Wood fence","Stone boundary"] else 12.); rule.sidewalk=kind in ["Park bench","Street lamp","Bollard"]; rule.setback=1.; rule.budget=500; return next
