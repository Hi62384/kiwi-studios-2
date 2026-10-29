class_name KiwiPowderDefinition
extends RefCounted
static func create() -> ActorDefinition:
	var d:=ActorDefinition.new(); d.type_id=&"powder"; d.display_name="Powder"; d.category="Simulation"
	d.description="Timeline-controlled granular sources and contact physics: finite volumes, closed mesh interiors and animated emitters."
	d.runtime_scene=load("res://scripts/actors/physics/powder/powder_actor.tscn"); d.icon=load("res://resources/Images/ActorIcons/Powder.svg")
	add(d,"position","Position",Vector3.ZERO,"Transform"); add(d,"rotation","Rotation",Vector3.ZERO,"Transform"); add(d,"scale","Scale",Vector3.ONE,"Transform")
	add(d,"physics","Physics",{"enabled":true,"type":7,"inherit_velocity":false},"Powder",{"inspector_hidden":true},false)
	add(d,"powder_enabled","Enabled",true,"Powder",{"refresh_inspector":true})
	add(d,"powder_source_mode","Source mode",0,"Powder",{"choices":["Finite volume","Emitter","Volume + emitter"],"refresh_inspector":true})
	add(d,"powder_spacing","Grain spacing (m)",.16,"Powder",{"min":.01,"max":5.0,"step":.01})
	add(d,"powder_simulate","Simulate grains",true,"Powder",{"tooltip":"Off previews source creation only. On enables contact-based granular physics."})
	add(d,"powder_jitter","Packing jitter",.06,"Powder",{"min":0.0,"max":.2,"step":.01})
	add(d,"powder_seed","Random seed",1,"Powder",{"min":0,"max":2147483647,"step":1},false)
	var finite:={"property":"powder_source_mode","values":[0,2]}; var emitted:={"property":"powder_source_mode","values":[1,2]}
	add(d,"powder_shape","Volume shape",0,"Source",{"choices":["Box","Sphere / ellipsoid","Cylinder","Closed mesh actor"],"visible_when":finite,"refresh_inspector":true})
	add(d,"powder_dimensions","Dimensions (m)",Vector3.ONE,"Source",{"visible_when":finite})
	add(d,"powder_mesh_actor","Closed mesh actor","","Source",{"actor_reference":true,"visible_when":{"property":"powder_shape","values":[3]}},false)
	add(d,"powder_emit_shape","Emitter shape",1,"Source",{"choices":["Point","Disk","Box","Sphere"],"visible_when":emitted,"refresh_inspector":true})
	add(d,"powder_emit_rate","Grains / source second",40.0,"Source",{"min":0.0,"max":10000.0,"visible_when":emitted})
	add(d,"powder_emit_start","Emission start (s)",0.0,"Source",{"min":0.0,"max":86400.0,"visible_when":emitted})
	add(d,"powder_emit_end","Emission end (-1 = ongoing)",-1.0,"Source",{"min":-1.0,"max":86400.0,"visible_when":emitted})
	add(d,"powder_continuous","Continuous supply",true,"Source",{"visible_when":emitted,"refresh_inspector":true})
	add(d,"powder_supply","Maximum emitted grains",500,"Source",{"min":0,"max":1000000,"step":1,"visible_when":emitted})
	add(d,"powder_emit_radius","Emitter radius (m)",.25,"Source",{"min":.001,"max":100.0,"visible_when":emitted})
	add(d,"powder_emit_dimensions","Emitter dimensions (m)",Vector3(.5,.5,.5),"Source",{"visible_when":emitted})
	add(d,"powder_emit_direction","Direction",Vector3.DOWN,"Source",{"visible_when":emitted})
	add(d,"powder_emit_speed","Speed (m/s)",1.0,"Source",{"min":0.0,"max":1000.0,"visible_when":emitted})
	add(d,"powder_emit_velocity","Initial velocity (m/s)",Vector3.ZERO,"Source")
	add(d,"powder_spread","Direction spread",.08,"Source",{"min":0.0,"max":1.0,"visible_when":emitted})
	add(d,"powder_radius","Grain radius (m)",.055,"Physical Properties",{"min":.001,"max":2.0,"step":.001,"tooltip":"Physical sphere radius, used by collisions, mass and rendering. Source spacing must fit the largest grain."},false)
	add(d,"powder_density","Density (kg/m³)",1600.0,"Physical Properties",{"min":1.0,"max":30000.0,"step":1.0,"tooltip":"Mass = density × spherical grain volume. Does not change gravity in vacuum."})
	add(d,"powder_friction","Friction",.6,"Physical Properties",{"min":0.0,"max":2.0,"tooltip":"Base contact friction in Simple mode; combined geometrically with the other surface."})
	add(d,"powder_cohesion","Cohesion (N/contact)",0.0,"Physical Properties",{"min":0.0,"max":10.0,"step":.001,"tooltip":"Maximum tensile force of breakable grain bonds, not velocity damping."})
	add(d,"powder_flowability","Flowability",.5,"Physical Properties",{"min":0.0,"max":1.0,"tooltip":"Simple mode: more flow lowers derived static/dynamic friction and rolling resistance. Your base friction and cohesion are never overwritten."})
	add(d,"powder_restitution","Bounciness",.05,"Physical Properties",{"min":0.0,"max":1.0,"tooltip":"Fraction of normal impact speed recovered on rebound."})
	add(d,"powder_damping","Damping (1/s)",.08,"Physical Properties",{"min":0.0,"max":20.0,"tooltip":"Exponential free-motion energy loss; contact friction separately stabilizes piles."})
	add(d,"powder_compaction","Compaction resistance",.98,"Physical Properties",{"min":.05,"max":1.0,"tooltip":"Contact stiffness under confinement. Grains rearrange; their radii never shrink."})
	add(d,"powder_wind","Wind influence",1.0,"Physical Properties",{"min":0.0,"max":20.0,"tooltip":"Aerodynamic drag uses the shared Physics wind velocity, grain area and mass. Sheltered grains receive less wind."})
	var advanced:={"advanced":true}
	add(d,"powder_advanced_material","Advanced contact coefficients",false,"Physical Properties",{"advanced":true,"refresh_inspector":true,"tooltip":"Use explicit static/dynamic friction and rolling resistance instead of Simple friction/flowability."},false)
	add(d,"powder_static_friction","Static friction",.66,"Physical Properties",{"advanced":true,"min":0.0,"max":3.0,"visible_when":{"property":"powder_advanced_material","values":[true]},"tooltip":"Tangential motion below this contact limit is cancelled."})
	add(d,"powder_dynamic_friction","Dynamic friction",.495,"Physical Properties",{"advanced":true,"min":0.0,"max":3.0,"visible_when":{"property":"powder_advanced_material","values":[true]},"tooltip":"Sliding friction; solver clamps this to static friction."})
	add(d,"powder_rolling","Rolling / angular-grain resistance",.06,"Physical Properties",{"advanced":true,"min":0.0,"max":1.0,"visible_when":{"property":"powder_advanced_material","values":[true]},"tooltip":"Contact-only tangential resistance approximating rough grains; no independent grain orientation is simulated."})
	add(d,"powder_size_variation","Radius variation",0.0,"Physical Properties",{"advanced":true,"min":0.0,"max":.5,"tooltip":"Seeded radius variation, ± fraction of the average. Structural: regenerates source."},false)
	add(d,"powder_gravity","Gravity influence",1.0,"Physical Properties",{"advanced":true,"min":0.0,"max":10.0,"tooltip":"Multiplier on the shared timeline Physics gravity."})
	add(d,"powder_bond_range","Bond breaking strain",.5,"Physical Properties",{"advanced":true,"min":.05,"max":2.0,"tooltip":"A cohesive connection breaks when stretched beyond this fraction of contact distance."})
	add(d,"powder_contact_damping","Contact damping",.2,"Physical Properties",{"advanced":true,"min":0.0,"max":1.0,"tooltip":"Removes relative closing speed at grain contacts."})
	add(d,"powder_air_drag","Aerodynamic drag coefficient",.47,"Physical Properties",{"advanced":true,"min":0.0,"max":5.0,"tooltip":"Air resistance coefficient used with grain cross-sectional area."})
	add(d,"powder_turbulence","Wind turbulence (m/s)",0.0,"Physical Properties",{"advanced":true,"min":0.0,"max":20.0,"tooltip":"Deterministic time-varying airflow, driven by stable grain identity."})
	add(d,"powder_fluid","Fluid interaction strength",1.0,"Physical Properties",{"advanced":true,"min":0.0,"max":2.0,"tooltip":"Drag, buoyancy and two-way contact exchange with existing Fluid particles."})
	add(d,"powder_quality","Solver quality",1,"Physical Properties",{"advanced":true,"choices":["Fast","Balanced","High"]})
	add(d,"powder_substeps","Base substeps",2,"Physical Properties",{"advanced":true,"min":1,"max":12,"step":1},false)
	add(d,"powder_iterations","Base contact iterations",6,"Physical Properties",{"advanced":true,"min":2,"max":16,"step":1},false)
	add(d,"powder_max_speed","Safety speed limit (m/s)",20.0,"Physical Properties",{"advanced":true,"min":.1,"max":100.0})
	add(d,"powder_sleep_speed","Rest speed threshold (m/s)",.025,"Physical Properties",{"advanced":true,"min":.001,"max":.2})
	add(d,"powder_sleep_delay","Rest delay (s)",.4,"Physical Properties",{"advanced":true,"min":.05,"max":5.0})
	add(d,"powder_characters","Bone collision proxies",true,"Physical Properties",advanced,false)
	add(d,"powder_deformables","Soft / cloth / rope point proxies",true,"Physical Properties",advanced,false)
	for key in ["powder_friction","powder_flowability"]: d.find_property(StringName(key)).options.visible_when={"property":"powder_advanced_material","values":[false]}
	for key in ["powder_spacing","powder_shape","powder_dimensions","powder_source_mode","powder_jitter"]:
		d.find_property(StringName(key)).animatable=false; d.find_property(StringName(key)).options.no_keyframes=true
	add(d,"powder_preset","Material presets",0,"Appearance",{"powder_presets":true},false)
	add(d,"powder_material","Reusable powder material",null,"Appearance",{},false)
	d.find_property(&"powder_material").object_type=&"powder_material"
	add(d,"powder_link_appearance","Use material appearance",false,"Appearance",{"refresh_inspector":true,"tooltip":"Linked appearance edits affect actors using the same saved resource. Physics defaults are adopted only by Apply Physics; the actor's physical controls remain authoritative."},false)
	for p in KiwiPowderMaterial.fields():
		p.options.visible_when={"property":"powder_link_appearance","values":[false]}; p.options.group="Appearance"; d.properties.append(p)
	KiwiPowderTransport.fields(d)
	add(d,"powder_budget","Maximum grains",4096,"Preview",{"min":1,"max":65536,"step":1},false)
	add(d,"powder_show_source","Show source guides when selected",true,"Preview",{},false)
	for key in ["powder_dimensions","powder_mesh_actor","powder_supply","powder_emit_radius","powder_emit_dimensions"]:
		var property:=d.find_property(StringName(key)); var conditions: Array=[property.options.visible_when]
		match key:
			"powder_dimensions": conditions.append({"property":"powder_shape","values":[0,1,2]})
			"powder_mesh_actor": conditions.append(finite)
			"powder_supply": conditions.append({"property":"powder_continuous","values":[false]})
			"powder_emit_radius": conditions.append({"property":"powder_emit_shape","values":[1,3]})
			"powder_emit_dimensions": conditions.append({"property":"powder_emit_shape","values":[2]})
		property.options.erase("visible_when"); property.options.visible_when_all=conditions
	return d
static func add(d: ActorDefinition,key: String,title: String,value: Variant,group: String,hints: Dictionary={},keyed: bool=true) -> void:
	var p:=ActorProperty.create(StringName(key),title,value,keyed); p.options.merge(hints,true); p.options.group=group
	if not keyed: p.options.no_keyframes=true
	d.properties.append(p)
