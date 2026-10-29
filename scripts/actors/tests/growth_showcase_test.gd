extends "res://scripts/actors/tests/surface_growth_test.gd"
func add_component(viewport: SubViewport,session: KiwiModelSession,component: KiwiModelComponent,offset: Vector3,stylized: bool) -> void:
	var visual:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(visual); visual.configure(component,true); visual.data.rendering.automatic_lod=false; visual.data.appearance.mode=1 if stylized else 0; visual.position=offset; visual.update_growth()
func body(viewport: SubViewport,mesh: Mesh,position: Vector3,color: Color) -> void:
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.position=position; var material:=StandardMaterial3D.new(); material.albedo_color=color; material.roughness=.85; node.material_override=material; viewport.add_child(node)
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Showcase requires native rendering."); quit(1); return
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1440,900); viewport.own_world_3d=true; viewport.msaa_3d=Viewport.MSAA_4X; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,2.2,9); camera.look_at(Vector3(0,.2,0)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=7.2; camera.current=true
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.045,.06,.085); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color(.65,.75,1.); environment.environment.ambient_light_energy=.45; viewport.add_child(environment)
	for index in 2:
		var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-35,-35 if index==0 else 125,0); light.light_energy=1.3 if index==0 else .8; light.light_color=Color(1.,.88,.7) if index==0 else Color(.55,.75,1.); light.shadow_enabled=true; viewport.add_child(light)
	var hair_session:=KiwiModelSession.new(); var scalp:=hair_session.add("Sphere",{"radius":.55,"segments":20,"rings":12}); hair_session.mode="Face"; hair_session.elements=PackedInt32Array()
	for face in scalp.mesh.faces.size():
		var center:=Vector3.ZERO
		for vertex in scalp.mesh.faces[face]: center+=scalp.mesh.vertices[vertex]
		if center.y/scalp.mesh.faces[face].size()>.05: hair_session.elements.append(face)
	KiwiSurfaceGrowth.add(hair_session,0); var hair:=hair_session.primary(); hair.growth.settings.merge({"density":1400.,"length":.8,"thickness":.005,"curvature":.05,"variation":.12,"orientation_variation":.02},true); hair_session.document.prepare_growth(); hair.growth.appearance.root_color=Color(.012,.009,.008); hair.growth.appearance.tip_color=Color(.055,.027,.018); hair.growth.appearance.roughness=.36; hair.growth.appearance.specular=.7
	for row: Dictionary in hair.growth.roots:
		var frame:=KiwiSurfaceGrowth.point_frame(hair.growth,row,hair.growth.source_points); var radial:=Vector3(row.position.x,0,row.position.z).normalized(); hair.growth.groom[str(row.id)]={"direction":frame.basis.inverse()*(radial*.8+Vector3.DOWN*.6),"offset":Vector3(0,.4,0)}
	hair.growth.revision+=1
	var fur_session:=KiwiModelSession.new(); var animal:=fur_session.add("Sphere",{"radius":.55,"segments":20,"rings":12}); var error:=KiwiSurfaceGrowth.add_layered_fur(fur_session); check(error.is_empty(),"Layered coat creates independent undercoat and guard-hair components")
	for component: KiwiModelComponent in fur_session.document.components:
		if component.growth==null: continue
		component.growth.settings.density=1100. if component.title=="Undercoat" else 180.; component.growth.settings.thickness=.004 if component.title=="Undercoat" else .005; component.growth.appearance.pattern=1; component.growth.appearance.pattern_scale=3.; component.growth.appearance.pattern_mix=.4; component.growth.appearance.pattern_color=Color(.04,.035,.03)
	fur_session.document.prepare_growth()
	var wing_session:=KiwiModelSession.new(); wing_session.add("Plane",{"size":Vector3(1.15,1,.8)}); KiwiSurfaceGrowth.add(wing_session,2); var wing:=wing_session.primary(); wing.growth.settings.merge({"density":30.,"arrangement":1,"rows":4,"length":.65,"width":.16,"variation":.07,"orientation_variation":0.,"feather_asymmetry":.25},true); wing_session.document.prepare_growth(); wing.growth.appearance.root_color=Color(.5,.27,.1); wing.growth.appearance.tip_color=Color(.16,.08,.035); wing.growth.appearance.feather_pattern=1; wing.growth.appearance.feather_pattern_scale=5.; wing.growth.appearance.feather_pattern_color=Color(.045,.025,.015); wing.growth.appearance.feather_pattern_width=.15
	for row: Dictionary in wing.growth.roots: wing.growth.groom[str(row.id)]={"direction":KiwiSurfaceGrowth.point_frame(wing.growth,row,wing.growth.source_points).basis.inverse()*Vector3(0,.8,-.6)}
	wing.growth.revision+=1
	for style in 2:
		var y:=1.25 if style==0 else -1.05; var sphere:=SphereMesh.new(); sphere.radius=.55; sphere.height=1.1
		body(viewport,sphere,Vector3(-2.25,y,0),Color(.24,.2,.17)); add_component(viewport,hair_session,hair,Vector3(-2.25,y,0),style==1)
		body(viewport,sphere,Vector3(0,y,0),Color(.28,.25,.21))
		for component: KiwiModelComponent in fur_session.document.components:
			if component.growth!=null: add_component(viewport,fur_session,component,Vector3(0,y,0),style==1)
		add_component(viewport,wing_session,wing,Vector3(2.25,y-.25,0),style==1)
	var labels:=CanvasLayer.new(); viewport.add_child(labels)
	for index in 3:
		var label:=Label.new(); label.text=["GROOMED HAIR","LAYERED FUR","MARKED FEATHERS"][index]; label.position=Vector2(85+index*455,20); label.add_theme_font_size_override("font_size",22); labels.add_child(label)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://.godot/verification/growth_showcase.png")==OK,"Realistic and stylized growth showcase captured using identical source grooms")
	viewport.queue_free(); await process_frame; await process_frame; print("GROWTH SHOWCASE: %d checks, %d failures"%[checks,failures]); quit(failures)
