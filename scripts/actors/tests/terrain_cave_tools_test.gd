extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Slice=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_slice_view.gd")
func run() -> void:
	root.size=Vector2i(1280,800); var document:=KiwiEnvironmentDocument.new(); var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); var cave:=KiwiTerrainCave.new(); cave.radius_variation=0.; cave.roughness=0.; cave.chambers=PackedVector4Array([Vector4(0,-3,0,2.)]); terrain.caves=[cave]; terrain.prepare_volumes(); var item:=document.add_terrain(terrain); var workspace:=Workspace.new(); root.add_child(workspace); workspace.open_source(document); workspace.session.select(item.id)
	for i in 8: await process_frame
	var canvas:=workspace.canvas; canvas.camera.position=Vector3(0,-3,0); canvas.camera.look_at(Vector3(2,-3,0)); canvas.environment_tool="Cave dig"; canvas.brush_radius=1.; canvas.cave_tool.strength=1.; var screen:=canvas.project(Vector3(2,-3,0)); var history:=workspace.session._undo.size(); var before:=workspace.session.environment().terrain(item.id).signature()
	var down:=InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=screen; canvas._gui_input(down)
	check(not canvas.cave_tool._stroke.is_empty() and workspace.session.environment().terrain(item.id).signature()==before,"Cave brush stroke previews privately without mutating the source before release")
	var up:=down.duplicate(); up.pressed=false; canvas._gui_input(up); await drain(workspace); terrain=workspace.session.environment().terrain(item.id); var current:=terrain.caves[0]; current.prepare()
	check(current.distance(Vector3(2.5,-3,0))<0. and workspace.session._undo.size()==history+1,"Digging in the viewport enlarges the real void as exactly one undoable action")
	for i in 8: await process_frame
	canvas.environment_tool="Cave fill"; canvas._gui_input(down); canvas._gui_input(up); await drain(workspace); current=workspace.session.environment().terrain(item.id).caves[0]; current.prepare()
	check(current.distance(Vector3(2.5,-3,0))>0.,"Viewport Fill restores solid terrain inside the previously excavated region")
	before=workspace.session.environment().terrain(item.id).signature(); canvas._gui_input(down); var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; canvas._gui_input(escape)
	check(canvas.cave_tool._stroke.is_empty() and workspace.session.environment().terrain(item.id).signature()==before and workspace._generation_jobs.is_empty(),"Escape cancels a cave brush stroke without adding history or starting generation")
	var smooth:=current.duplicate(true) as KiwiTerrainCave; smooth.roughness=.5; smooth.prepare(); var near:=smooth.distance(Vector3(2,-3,0)); var far:=smooth.distance(Vector3(-3,-3,0)); smooth.edits.append({"center":Vector3(2,-3,0),"radius":2.,"smooth":true,"strength":1.})
	check(absf(smooth.distance(Vector3(2,-3,0))-near)>.00001 and smooth.distance(Vector3(-3,-3,0))==far,"Local cave smoothing changes the field within its brush region and preserves it outside")
	var weak:=KiwiTerrainCave.new(); weak.roughness=0.; weak.chambers=PackedVector4Array([Vector4(0,0,0,2.)]); weak.prepare(); weak.edits=[{"center":Vector3(2,0,0),"radius":2.,"strength":.25}]; var low:=weak.distance(Vector3(2,0,0)); weak.edits[0].strength=1.; check(weak.distance(Vector3(2,0,0))<low-.5,"Cave strength controls signed-distance influence independently from the brush radius")
	workspace._regenerate_terrain(item.id,{"voxel_cell_budget":1}); await drain(workspace)
	for i in 10: await process_frame
	check(workspace.session.environment().terrain(item.id).voxel_cell_budget!=1 and workspace._generation_jobs.is_empty() and "budget" in workspace.status.text.to_lower(),"A failed voxel budget keeps the old valid terrain and does not enter an automatic retry loop")
	workspace._regenerate_terrain(item.id,{"resolution":129}); workspace._cancel_generation(); await drain(workspace); check(workspace.session.environment().terrain(item.id).resolution==33,"Canceling cave generation preserves the previous completed resolution and geometry")
	var slice:=Slice.new(); slice.source=workspace.session.environment().terrain(item.id); root.add_child(slice); slice._generate(-3.); var deadline:=Time.get_ticks_msec()+10000
	while slice._job!=null and Time.get_ticks_msec()<deadline: await process_frame
	var image: Image=slice.preview.texture.get_image() if slice.preview.texture!=null else null
	check(image!=null and image.get_pixel(48,48).g>image.get_pixel(48,48).r+.2 and image.get_pixel(0,0).r>image.get_pixel(0,0).g,"Density slice displays actual cave air and surrounding solid terrain from a cancelable worker")
	slice.queue_free(); workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("TERRAIN CAVE TOOLS: %d checks, %d failures"%[checks,failures]); quit(failures)
func drain(workspace: Control) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not workspace._generation_jobs.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(workspace._generation_jobs.is_empty(),"Cave brush generation finishes within the bounded test window")
