extends "res://scripts/actors/tests/fog_lighting_render_test.gd"
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
func run() -> void:
	registry=ActorRegistry.new(); BasicActors.register_all(registry); viewport=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(320,240); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.WHITE; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=20.; viewport.find_world_3d().environment=environment
	lens=Camera3D.new(); viewport.add_child(lens); lens.current=true
	var appearance:=Appearance.definition().create_object(); appearance.values[&"scattering"]=0.; var fog:=make_actor(&"fog_volume",{&"position":Vector3(0,0,-4),&"volume_size":Vector3(4,4,4),&"density":.5,&"appearance":ActorObjectReference.from_object(appearance)})
	var full:=await capture(); var field:=Field.definition().create_object(); field.values[&"mode"]=6; field.values[&"shape"]=1; field.values[&"shape_size"]=Vector3.ONE*.8; field.values[&"invert"]=true; fog.actor.values[&"field"]=ActorObjectReference.from_object(field); fog.evaluate(0.,fog.actor.values); var excluded:=await capture(); var point:=Vector2i(160,120)
	check(brightness(excluded,point)>brightness(full,point)+.05,"An authored primitive allowed-space mask removes actual volumetric density")
	var mesh:=BoxMesh.new(); var path:="user://fog-exclusion-box.tres"; ResourceSaver.save(mesh,path); var before:=mesh.surface_get_arrays(0).hash(); field.values[&"mode"]=7; field.values[&"boundary_mesh"]=path; field.values[&"combine"]=4; field.values[&"invert"]=false; fog.evaluate(0.,fog.actor.values); var mesh_hole:=await capture()
	check(brightness(mesh_hole,point)>.9 and mesh.surface_get_arrays(0).hash()==before,"Closed-mesh occupancy excludes fog without altering source geometry")
	var painted:=Field.definition().create_object(); painted.values[&"mode"]=5; painted.values[&"combine"]=4; painted.values[&"paint"]=Field.paint_dab({},Vector3i(16,16,16),15.,1.,0.,2); fog.actor.values[&"field"]=ActorObjectReference.from_object(painted); fog.evaluate(0.,fog.actor.values); var paint_hole:=await capture()
	check(brightness(paint_hole,point)>brightness(full,point)+.05,"Painted three-dimensional masks exclude rendered fog through the same field path")
	mesh_hole.save_png("res://.godot/verification/fog_exclusion.png"); DirAccess.remove_absolute(path); viewport.queue_free(); await process_frame; await process_frame; print("FOG EXCLUSIONS: %d checks, %d failures"%[checks,failures]); quit(failures)
