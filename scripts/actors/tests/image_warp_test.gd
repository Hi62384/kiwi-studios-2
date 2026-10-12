extends SceneTree
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(condition: bool,message: String) -> void:
	if not condition: failures+=1; push_error(message)
func frames(amount: int=10) -> void:
	for i in amount: await process_frame
func data() -> KiwiImageWarpData:
	var result:=KiwiImageWarpData.new(); result.initialize(Vector2(256,256)); return result
func offset(field: KiwiImageWarpData,uv: Vector2) -> Vector2:
	field.rebuild(); return KiwiImageWarpData.sample_grid(field._field,field.grid_size,uv)
func brush_tests() -> void:
	var field:=data()
	check(not KiwiImageWarpBrush.stroke(field,Vector2(256,256),Vector2(.4,.5),Vector2(.6,.5),128,0,.25,"push"),"Zero strength leaves geometry unchanged")
	KiwiImageWarpBrush.stroke(field,Vector2(256,256),Vector2(.4,.5),Vector2(.6,.5),128,.8,.25,"push")
	check(offset(field,Vector2(.5,.5)).x<-.05,"Push follows actual mouse displacement")
	for kind in ["pinch","bulge","twirl_cw","twirl_ccw"]:
		var radial:=data(); KiwiImageWarpBrush.stroke(radial,Vector2(256,256),Vector2(.5,.5),Vector2(.5,.5),128,1,.25,kind)
		var actual:=offset(radial,Vector2(.625,.5))
		check(actual.x>0 if kind=="pinch" else (actual.x<0 if kind=="bulge" else (actual.y<0 if kind=="twirl_cw" else actual.y>0)),kind+" deforms in its expected direction")
	var before:=offset(field,Vector2(.5,.5)).length()
	for i in 25: KiwiImageWarpBrush.stroke(field,Vector2(256,256),Vector2(.5,.5),Vector2(.5,.5),200,1,.25,"restore")
	check(offset(field,Vector2(.5,.5)).length()<before*.15,"Restore reconstructs the original geometry from deformation data")
	var smooth:=data(); var center:=32*65+32; smooth.displacement[center]=Vector2(.1,0); smooth.touch()
	KiwiImageWarpBrush.stroke(smooth,Vector2(256,256),Vector2(.5,.5),Vector2(.5,.5),80,1,.25,"smooth")
	check(smooth.displacement[center].x<.08,"Smooth removes field irregularities without changing source pixels")
	var frozen:=data(); frozen.freeze[center]=1; frozen.capture_baseline()
	KiwiImageWarpBrush.stroke(frozen,Vector2(256,256),Vector2(.4,.5),Vector2(.6,.5),128,1,.25,"push")
	check(offset(frozen,Vector2(.5,.5)).is_zero_approx(),"Frozen areas resist brush deformation")
	var constrained:=data(); constrained.restriction.resize(constrained.displacement.size()); constrained.restriction.fill(0)
	KiwiImageWarpBrush.stroke(constrained,Vector2(256,256),Vector2(.4,.5),Vector2(.6,.5),128,1,.25,"push")
	check(offset(constrained,Vector2(.5,.5)).is_zero_approx(),"Selection constraints preserve unselected geometry")
	var mesh:=data(); mesh.mesh_points[5]+=Vector2(.1,0); mesh.touch()
	var mesh_start:=Time.get_ticks_usec(); mesh.rebuild(); print("4x4 mesh update CPU: %d us" % (Time.get_ticks_usec()-mesh_start))
	check(offset(mesh,Vector2(.4,.34)).x<-.01,"Mesh controls deform actual image geometry")
	for resolution in [4,8,16]:
		mesh.reset_mesh(resolution); check(offset(mesh,Vector2(.4,.34)).length()<.0001,"Reset restores mesh identity at resolution "+str(resolution))
	var pins:=data(); pins.pins=[{"source":Vector2(.5,.5),"target":Vector2(.6,.5),"radius":.5,"locked":false},{"source":Vector2(.2,.5),"target":Vector2(.2,.5),"radius":.5,"locked":true}]; pins.touch()
	var pin_start:=Time.get_ticks_usec(); pins.rebuild(); print("Two-pin update CPU: %d us" % (Time.get_ticks_usec()-pin_start))
	check(offset(pins,Vector2(.6,.5)).x<-.04,"Moving a pin deforms nearby pixels")
	check(offset(pins,Vector2(.2,.5)).length()<.003,"Stationary locked pins anchor nearby geometry")
	var pin_field:=pins._field.duplicate()
	pins.pins.append({"source":Vector2(.55,.45),"target":Vector2(.55,.45),"radius":.5,"locked":false}); pins.touch(); pins.rebuild()
	for i in pin_field.size(): check(pin_field[i].distance_to(pins._field[i])<.000001,"Placing an unmoved pin preserves the existing deformation")
	pins.pins[-1].target+=Vector2(.0001,0); pins.touch(); pins.rebuild()
	check(offset(pins,Vector2(.5,.5)).distance_to(KiwiImageWarpData.sample_grid(pin_field,pins.grid_size,Vector2(.5,.5)))<.001,"A tiny new pin movement does not jump the existing warp")
	var weights:=preload("res://Workspaces/ImageWorkspace/image_warp_interaction.gd").mesh_weights(PackedVector2Array([Vector2.ZERO,Vector2(.1,0),Vector2(.3,0),Vector2(1,1)]),PackedInt32Array([0]),Vector2(256,256),.5,2)
	check(weights[0]==1 and weights[1]>weights[2] and weights[2]>0 and weights[3]==0,"Mesh attenuation moves nearby points by distance and leaves distant points alone")
	var sharper:=preload("res://Workspaces/ImageWorkspace/image_warp_interaction.gd").mesh_weights(PackedVector2Array([Vector2.ZERO,Vector2(.1,0)]),PackedInt32Array([0]),Vector2(256,256),.5,5)
	check(sharper[1]<weights[1],"Increasing mesh attenuation reduces neighboring movement")
	pins.reset_all(); check(offset(pins,Vector2(.6,.5)).length()<.0001,"Reset clears pin displacement")
	var large:=KiwiImageWarpData.new(); large.initialize(Vector2(8192,8192)); var started:=Time.get_ticks_usec()
	KiwiImageWarpBrush.stroke(large,Vector2(8192,8192),Vector2(.4,.5),Vector2(.42,.5),2048,.8,.3,"push"); large.rebuild()
	print("8192px image / 2048px warp brush CPU: %d us; field: %s" % [Time.get_ticks_usec()-started,large.grid_size])
	check(large.displacement.size()<=65*65,"Large images use compact field storage")
	var detail:=data(); detail.refine_for_brush(Vector2(256,256),3)
	check(detail.grid_size.x>65,"Detail brushes refine their field instead of missing small features")
	KiwiImageWarpBrush.stroke(detail,Vector2(256,256),Vector2(.497,.5),Vector2(.505,.5),3,1,.2,"push")
	check(offset(detail,Vector2(.502,.5)).x<-.001,"A small brush creates localized detail deformation")

func run() -> void:
	brush_tests()
	root.size=Vector2i(1440,900)
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256: source.set_pixel(x,y,Color(x/255.0,y/255.0,.3,1 if Vector2(x-128,y-128).length()<110 else 0))
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("warp"); await frames()
	var mode_menu:=studio.find_child("WarpMode",true,false) as MenuButton
	var brush_menu:=studio.find_child("WarpBrushType",true,false) as MenuButton
	check(mode_menu!=null and mode_menu.get_popup().item_count==4,"Warp modes use a styled icon menu instead of radio circles")
	check(brush_menu!=null and brush_menu.get_popup().item_count==10,"Every warp brush has a menu entry")
	if brush_menu!=null:
		var icons: Dictionary={}
		for i in range(1,brush_menu.get_popup().item_count):
			var texture:=brush_menu.get_popup().get_item_icon(i)
			check(texture!=null,"Every brush menu entry has an icon")
			icons[hash(texture.get_image().get_data())]=true
		check(icons.size()==9,"Warp brush icons are all distinct")
		root.gui_embed_subwindows=true
		var popup:=brush_menu.get_popup(); popup.position=Vector2i(brush_menu.global_position+Vector2(0,brush_menu.size.y)); popup.popup()
		await frames(3); root.get_texture().get_image().save_png("res://.godot/warp_brush_menu_ui.png"); popup.hide()
	check(studio.tool_buttons.has("warp") and studio.canvas.tool=="warp","Warp integrates into the editor rail")
	var controller=studio.canvas.warp_tool; controller.diameter=160; controller.strength=.8
	var original:=studio._main_layer().texture
	var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true
	press.position=studio.canvas.origin()+Vector2(110,128)*studio.canvas.zoom
	studio.canvas._input_canvas(press)
	var motion:=InputEventMouseMotion.new(); motion.position=studio.canvas.origin()+Vector2(150,128)*studio.canvas.zoom; motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	studio.canvas._input_canvas(motion); await frames(12)
	var layer:=studio._main_layer()
	check(layer.warp!=null and offset(layer.warp,Vector2(.55,.5)).x<-.02,"Warp updates before mouse release")
	check(layer.texture==original,"Warp keeps the original source texture")
	var live: Image=studio.renderer.views[layer.id].output.texture.get_image()
	check(live.get_pixel(150+48,128+48).r<source.get_pixel(150,128).r-.03,"Live GPU preview visibly moves pixels during the stroke")
	var release:=press.duplicate() as InputEventMouseButton; release.pressed=false; release.position=motion.position; studio.canvas._input_canvas(release)
	check(studio._undo.size()==1,"A complete warp stroke creates exactly one undo entry")
	studio.undo(); check(studio._main_layer().warp==null,"Undo restores original geometry")
	studio.redo(); check(studio._main_layer().warp!=null,"Redo restores deformation")
	var file:="res://.godot/warp_roundtrip.tres"
	check(ResourceSaver.save(studio.document.snapshot(),file)==OK,"Warp saves in native image documents")
	var restored:=ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(restored!=null and restored.layers[0].warp!=null and restored.layers[0].warp.displacement==studio._main_layer().warp.displacement,"Reopened projects retain exact warp fields")
	var previous:=studio._main_layer().warp.displacement.duplicate()
	studio.canvas._input_canvas(press); studio.canvas._input_canvas(motion); await frames(5); studio.canvas.cancel_gesture()
	check(studio._main_layer().warp.displacement==previous,"Cancel restores the uncommitted deformation")
	controller.mode="mesh"; controller.show_grid=true; studio._refresh_context(); await frames()
	studio.canvas._mouse=controller.screen(Vector2(.5,.5),studio._main_layer())
	root.warp_mouse(studio.canvas.global_position+studio.canvas._mouse); studio.canvas.queue_redraw(); await frames(3)
	root.get_texture().get_image().save_png("res://.godot/warp_mesh_ui.png")
	studio.canvas.tool="move"; studio._refresh_context()
	check(studio._main_layer().warp!=null,"Switching tools preserves committed warps")
	var exported: Image=await studio.renderer.flattened()
	check(exported.get_pixel(150,128).r<source.get_pixel(150,128).r-.03,"Export applies the same warp as the preview")
	studio._set_tool("warp"); controller.mode="mesh"; controller.show_grid=true
	studio._action(func(): studio._main_layer().warp.reset_all())
	var item:=studio._main_layer(); var old_history:=studio._undo.size()
	var original_point: Vector2=item.warp.mesh_points[5]
	press.position=controller.screen(original_point,item); press.pressed=true; studio.canvas._input_canvas(press)
	motion.position=controller.screen(original_point+Vector2(.05,0),item); studio.canvas._input_canvas(motion); await frames(6)
	check(studio._main_layer().warp.mesh_points[5].x>original_point.x+.04,"Dragging a mesh handle edits real saved control points")
	check(studio._main_layer().warp.mesh_points[6].x>studio._main_layer().warp.mesh_origin(6).x,"Mesh dragging also moves nearby points with attenuation")
	release.position=motion.position; studio.canvas._input_canvas(release)
	check(studio._undo.size()==old_history+1,"Mesh dragging creates one undo entry")
	studio.undo(); check(studio._main_layer().warp.mesh_points[5].is_equal_approx(original_point),"Mesh dragging is undoable")
	check(studio._main_layer().warp.mesh_points[6].is_equal_approx(studio._main_layer().warp.mesh_origin(6)),"Undo also restores attenuated neighboring mesh points")
	controller.mode="pins"; controller.show_grid=false
	item=studio._main_layer(); old_history=studio._undo.size()
	press.position=controller.screen(Vector2(.5,.5),item); studio.canvas._input_canvas(press)
	motion.position=controller.screen(Vector2(.58,.5),item); studio.canvas._input_canvas(motion); await frames(6)
	release.position=motion.position; studio.canvas._input_canvas(release)
	check(studio._main_layer().warp.pins.size()==1 and Vector2(studio._main_layer().warp.pins[0].target).x>.57,"Place-and-drag pin warps the actual layer")
	check(studio._undo.size()==old_history+1,"Pin placement and movement share one gesture transaction")
	var right:=InputEventMouseButton.new(); right.button_index=MOUSE_BUTTON_RIGHT; right.pressed=true; right.position=motion.position; studio.canvas._input_canvas(right)
	check(studio._main_layer().warp.pins.is_empty(),"Right-click removes an individual pin")
	studio.undo(); check(studio._main_layer().warp.pins.size()==1,"Removing pins is undoable")
	item=studio._main_layer(); item.rotation=.3; item.properties.flip_x=true; item.properties.yaw_left_right=25.0
	var uv:=Vector2(.3,.7); var screen_point: Vector2=controller.screen(uv,item)
	check(controller.local_uv(studio.canvas.to_document(screen_point),item).distance_to(uv)<.0001,"Warp coordinates account for rotation, flips and perspective yaw")
	studio._set_tool("brush")
	var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.shift_pressed=true; wheel.position=studio.canvas.size*.5
	studio.canvas.brush_size=50; studio.canvas._input_canvas(wheel); var small_delta: float=studio.canvas.brush_size-50
	studio.canvas.brush_size=200; studio.canvas._input_canvas(wheel); var large_delta: float=studio.canvas.brush_size-200
	check(large_delta>small_delta*3,"Shift-scroll changes large brushes faster than small brushes")
	studio._set_tool("warp")
	controller.mode="mesh"; controller.mesh_radius=.5; var previous_diameter: float=controller.diameter; var previous_zoom: float=studio.canvas.zoom
	studio.canvas._input_canvas(wheel)
	check(controller.mesh_radius>.5 and controller.diameter==previous_diameter and studio.canvas.zoom==previous_zoom,"Mesh Shift-scroll increases radius without changing brush diameter or zoom")
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; studio.canvas._input_canvas(wheel)
	check(controller.mesh_radius<.56,"Mesh Shift-scroll down decreases radius")
	controller.mesh_radius=0; wheel.button_index=MOUSE_BUTTON_WHEEL_UP; studio.canvas._input_canvas(wheel)
	check(controller.mesh_radius>0,"Shift-scroll can grow a zero mesh radius")
	controller.mesh_radius=2; studio.canvas._input_canvas(wheel); check(controller.mesh_radius==2,"Mesh radius stays within its toolbar range")
	item.rotation=0; item.properties.flip_x=false; item.properties.yaw_left_right=0
	studio.renderer.sync(studio.document)
	var before_bake: Image=await studio.renderer.flattened()
	await preload("res://Workspaces/ImageWorkspace/image_warp_toolbar.gd")._bake_confirmed(studio,item.id)
	check(studio._main_layer().warp==null,"Bake removes editable deformation after applying it to pixels")
	var after_bake: Image=await studio.renderer.flattened()
	check(absf(before_bake.get_pixel(145,128).r-after_bake.get_pixel(145,128).r)<.03,"Bake preserves the warped appearance")
	studio.undo(); check(studio._main_layer().warp!=null,"Bake supports undo")
	studio.queue_free(); await frames(3)
	print("Warp & liquify checks: %d failures" % failures); quit(failures)
