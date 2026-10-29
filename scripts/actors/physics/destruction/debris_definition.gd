class_name KiwiDebris
extends RefCounted
const VISUAL:=["debris_vfx_enabled","debris_intensity","debris_particles","debris_dust","debris_chips","debris_sparks","debris_lifetime","debris_vfx_preset","debris_vfx_mode","debris_copy"]
static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id not in [&"basic_shape",&"basic_mesh"] or d.find_property(&"debris_enabled")!=null: return
	for row in [
		["debris_enabled","Physical debris",true,{}],["debris_collision","Fragment collisions",true,{}],
		["debris_budget","Fragment budget",96,{"min":2,"max":256,"step":1}],
		["debris_impulse","Fracture impulse multiplier",1.0,{"min":0.0,"max":10.0}],
		["debris_secondary","Secondary fragmentation",false,{}],
		["debris_min_size","Minimum secondary piece size (m)",.08,{"min":.005,"max":5.0,"advanced":true}],
		["debris_secondary_energy","Secondary impact threshold (J)",10.0,{"min":.01,"max":100000.0,"advanced":true}],
		["debris_depth","Maximum secondary depth",2,{"min":0,"max":4,"step":1,"advanced":true}],
		["debris_small_size","Small-debris sphere proxy below (m)",.08,{"min":.005,"max":1.0,"advanced":true}],
		["debris_sleep","Sleep settled fragments",true,{"advanced":true}],
		["debris_use_material_contacts","Use material friction / restitution",true,{"advanced":true}],
		["debris_vfx_enabled","Automatic destruction effects",true,{}],
		["debris_intensity","Effect intensity",1.0,{"min":0.0,"max":10.0}],
		["debris_particles","Particles per event",48,{"min":0,"max":512,"step":1}],
		["debris_dust","Dust multiplier",1.0,{"min":0.0,"max":5.0,"advanced":true}],
		["debris_chips","Chips / sparks multiplier",1.0,{"min":0.0,"max":5.0,"advanced":true}],
		["debris_lifetime","Effect lifetime (s)",2.0,{"min":.05,"max":10.0}],
		["debris_vfx_mode","Custom effect mode",0,{"choices":["Replace automatic","Augment automatic"]}],
		["debris_copy","Copy evaluated debris",0,{"debris_copy":true,"no_keyframes":true}]
	]: KiwiPowderDefinition.add(d,row[0],row[1],row[2],"Debris & Effects",row[3],not row[3].get("no_keyframes",false))
	var p:=ActorProperty.create(&"debris_vfx_preset","Custom VFX preset",null); p.object_type=&"debris_vfx"; p.options.group="Debris & Effects"; d.properties.append(p)
static func preset_definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"debris_vfx"; d.display_name="Destruction VFX Preset"
	for row in [["name","Name","Custom effect",{}],["style","Particle style",0,{"choices":["Dust cloud","Reflective chips","Splinters","Sparks"]}],["color","Color",Color(.7,.65,.5,.6),{}],["amount","Amount multiplier",1.0,{"min":0.0,"max":5.0}],["particle_size","Particle size (m)",.08,{"min":.001,"max":2.0}],["velocity","Initial speed",2.0,{"min":0.0,"max":50.0}],["gravity","Gravity",Vector3(0,-2,0),{}],["lifetime","Lifetime multiplier",1.0,{"min":.1,"max":5.0}]]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[3]); d.properties.append(p)
	return d
static func copy_fragments(editor: ActorTimelineEditor,actor: ActorData) -> void:
	var fragments: Array=editor.physics.display_states.get(actor.id,{}).get("destruction_fragments",[]); var scene:=ActorSceneData.new()
	for i in fragments.size():
		var fragment: Dictionary=fragments[i]; var data:=editor.registry.get_definition(&"basic_mesh").create_actor(); data.display_name=actor.display_name+" debris "+str(i+1); data.values.merge(KiwiModelDocument.transform_values(fragment.pose),true)
		var materials: Array[Material]=[]
		if editor.physics.destruction.nodes.has(actor.id) and i<editor.physics.destruction.nodes[actor.id].size():
			var node: MeshInstance3D=editor.physics.destruction.nodes[actor.id][i]
			for surface in node.mesh.get_surface_count(): materials.append(node.get_active_material(surface))
		data.values[&"mesh_path"]=fragment.mesh.render_mesh(materials); data.values[&"physics"]={"enabled":false,"mass":fragment.mass,"velocity":fragment.v,"angular_velocity":fragment.w*180/PI}; scene.actors.append(data); var clip:=ActorClip.create(data,0,5); clip.layer=i; scene.clips.append(clip)
	if not scene.actors.is_empty(): editor.model.instantiate_scene(scene,editor.registry.get_definition(&"point_3d"),editor.canvas.playhead,editor.model.selected_layer,"Debris snapshot","Copy debris as editable actors")
