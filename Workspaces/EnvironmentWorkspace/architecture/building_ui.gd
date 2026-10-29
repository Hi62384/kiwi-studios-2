extends RefCounted
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
static func create(workspace: Control,levels: int=1) -> void:
	if not await preload("res://Workspaces/ModelWorkspace/natural_edit.gd").flush(workspace): return
	Buildings.add(workspace.session,workspace.canvas.target,levels); workspace.canvas.request_sync(); workspace.canvas.frame()
static func show_plan(workspace: Control,root: KiwiModelComponent,mode: int=1,fit_first: bool=true) -> Control:
	if not await preload("res://Workspaces/ModelWorkspace/natural_edit.gd").flush(workspace): return null
	var plan: Control=workspace.get_meta("building_plan") if workspace.has_meta("building_plan") else null; var first_open:=not is_instance_valid(plan)
	if not is_instance_valid(plan):
		plan=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_plan.gd").new(); plan.workspace=workspace
		var canvas: Control=workspace.canvas; var parent:=canvas.get_parent(); var index:=canvas.get_index(); var wrapper:=VBoxContainer.new(); wrapper.size_flags_horizontal=Control.SIZE_EXPAND_FILL; wrapper.size_flags_vertical=Control.SIZE_EXPAND_FILL; parent.remove_child(canvas); parent.add_child(wrapper); parent.move_child(wrapper,index)
		var tools:=HFlowContainer.new(); tools.add_theme_constant_override("h_separation",3); wrapper.add_child(tools)
		for entry in [["Select","↖ Select"],["Wall","╱ Wall"],["Room","▱ Room"],["Door","▯ Door"],["Window","▦ Window"],["Arch","∩ Arch"],["Stairs","↗ Stairs"],["Delete","⌫"]]:
			var button:=Button.new(); button.text=entry[1]; button.tooltip_text=entry[0]; tools.add_child(button); button.pressed.connect(func(): plan.cancel(); plan.tool=entry[0]; plan.grab_focus())
		var snap:=CheckButton.new(); snap.text="Snap"; snap.button_pressed=true; tools.add_child(snap); snap.toggled.connect(func(on: bool): plan.snap=on)
		var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.size_flags_horizontal=Control.SIZE_EXPAND_FILL; wrapper.add_child(split); split.add_child(plan); split.add_child(canvas); split.split_offset=-60; workspace.set_meta("building_plan",plan); workspace.set_meta("building_plan_tools",tools)
		_button(tools,"⌖ Fit",func(): _frame(workspace))
	if plan.building_id!=root.id: plan.cancel(); plan.selected_wall=-1; plan.selected_opening=-1
	plan.building_id=root.id; var state: Dictionary=workspace.session.document.workspace_state.get("architecture_plan",{})
	if state.get("owner","")==root.id: plan.current_floor=int(state.get("floor",0)); plan.zoom=float(state.get("zoom",35.)); plan.pan=state.get("pan",Vector2.ZERO); plan.cutaway=bool(state.get("cutaway",false))
	if plan.get_parent() is HSplitContainer: plan.get_parent().split_offset=int(state.get("split",-60))
	plan.view_mode=mode
	plan.visible=mode!=2; workspace.canvas.visible=mode!=0; (workspace.get_meta("building_plan_tools") as Control).visible=mode!=2
	if first_open and mode!=0 and fit_first: await workspace.get_tree().process_frame; _frame(workspace)
	return plan
static func cancel(workspace: Control) -> void:
	if workspace.has_meta("building_plan"):
		var plan: Control=workspace.get_meta("building_plan")
		if is_instance_valid(plan): plan.cancel()
static func restore(workspace: Control) -> void:
	var state: Dictionary=workspace.session.document.workspace_state.get("architecture_plan",{}).duplicate(true); var document: KiwiModelDocument=workspace.session.document
	await workspace.get_tree().process_frame
	if not is_instance_valid(workspace) or not workspace.is_inside_tree() or workspace.session.document!=document: return
	var root:=document.component(str(state.get("owner","")))
	if Buildings.source(root)!=null:
		document.workspace_state.architecture_plan=state; await show_plan(workspace,root,int(state.get("mode",1)),false)
	elif workspace.has_meta("building_plan"):
		var plan: Control=workspace.get_meta("building_plan"); plan.building_id=""; plan.cutaway=false; plan.hide(); (workspace.get_meta("building_plan_tools") as Control).hide(); workspace.canvas.show(); workspace.canvas.preview_hidden={}
		if workspace.canvas is KiwiEnvironmentViewport: workspace.canvas.renderer.preview_hidden={}
		workspace.canvas.request_sync()
static func _frame(workspace: Control) -> void:
	workspace.canvas.frame(); var aspect: float=workspace.canvas.size.x/maxf(1.,workspace.canvas.size.y)
	if aspect<1.: workspace.canvas.distance/=maxf(.2,aspect); workspace.canvas.update_camera()
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	if preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component_ui.gd").properties(workspace,item,parent): return true
	var module_properties:=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links_ui.gd").properties(workspace,item,parent)
	var root:=Buildings.owner(workspace.session,item)
	if root==null: return module_properties
	var source:=_source(workspace,root.id); var plan: Control=workspace.get_meta("building_plan") if workspace.has_meta("building_plan") else null; var level:=clampi(int(plan.current_floor) if is_instance_valid(plan) and plan.building_id==root.id else 0,0,source.floors.size()-1)
	var heading:=Label.new(); heading.text="ARCHITECTURE · "+root.title; heading.add_theme_color_override("font_color",Color("8be1ca")); parent.add_child(heading); var modes:=HBoxContainer.new(); parent.add_child(modes)
	if workspace.session.document is KiwiEnvironmentDocument and (workspace.session.document as KiwiEnvironmentDocument).component_kind(root.id)=="building":
		_button(parent,"Make building detail editable",func(): _apply(workspace,root.id,_source(workspace,root.id),"Make building detail editable"))
	if workspace.session is KiwiEnvironmentSession and root.parameters.has("world_owner") and root.parameters.has("world_plot"):
		_button(parent,"Keep building independent",func(): var error:=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd").keep_independent(workspace.session,root.id); workspace.status.text=error if not error.is_empty() else "Building kept independent of settlement regeneration")
	var styles:=OptionButton.new(); styles.add_item("Style · "+source.style); parent.add_child(styles)
	for name: String in preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").PRESETS: styles.add_item(name)
	styles.item_selected.connect(func(index: int):
		if index==0: return
		var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").apply(_source(workspace,root.id),styles.get_item_text(index)); _apply(workspace,root.id,next,"Apply building style"))
	var detail:=OptionButton.new(); parent.add_child(detail)
	for name in ["No facade details","Timber frame","Porch","Buttresses","Pilasters","Fins","Cross braces","Spire corners"]: detail.add_item(name)
	detail.select(source.facade_detail); detail.item_selected.connect(func(index: int): var next:=Source.copy(_source(workspace,root.id)); next.facade_detail=index; _apply(workspace,root.id,next,"Change facade details"))
	_number(parent,"Detail width",source.detail_width,.04,.5,.01,func(value: float): var next:=Source.copy(_source(workspace,root.id)); next.detail_width=value; _apply(workspace,root.id,next,"Change facade width"))
	if item.id!=root.id: _button(parent,"Reset procedural overrides on this component",func(): var result:=Buildings.reset_overrides(workspace.session,root.id,item.id); workspace.status.text=result.errors[0] if not result.errors.is_empty() else "Component reset")
	for entry in [["▦ 2D",0],["◫ Split",1],["◇ 3D",2]]: _button(modes,entry[0],func(): await show_plan(workspace,root,entry[1]))
	var cut:=CheckButton.new(); cut.text="Interior cutaway"; cut.button_pressed=is_instance_valid(plan) and plan.cutaway; parent.add_child(cut); cut.toggled.connect(func(on: bool):
		var editor: Control=await show_plan(workspace,root,1)
		if editor==null: return
		editor.cutaway=on; editor._apply_cutaway(); await workspace.get_tree().process_frame; _frame(workspace))
	var floors:=OptionButton.new(); parent.add_child(floors)
	for floor: Dictionary in source.floors: floors.add_item(str(floor.get("name","Level")))
	floors.select(level); floors.item_selected.connect(func(index: int): var editor: Control=await show_plan(workspace,root,1); if editor!=null: editor.current_floor=index; editor.selected_wall=-1; editor.selected_opening=-1)
	_button(parent,"＋ Level",func():
		var next:=Source.copy(_source(workspace,root.id))
		if next.floors.size()>=8: workspace.status.text="This building already has eight levels."; return
		var floor: Dictionary=next.floors[-1].duplicate(true); floor.id=ActorData.new_id(); floor.name="Level "+str(next.floors.size()+1); floor.elevation=float(floor.elevation)+float(floor.get("height",3.)); next.floors.append(floor); _apply(workspace,root.id,next,"Add building level"))
	_number(parent,"Level height",float(source.floors[level].get("height",3.)),1.,20.,.05,func(value: float):
		var next:=Source.copy(_source(workspace,root.id)); var floor: Dictionary=next.floors[level]; var previous:=float(floor.get("height",3.)); floor.height=value
		for wall: Dictionary in floor.walls:
			if is_equal_approx(float(wall.get("height",previous)),previous): wall.height=value
		for index in range(level+1,next.floors.size()): next.floors[index].elevation=float(next.floors[index].elevation)+value-previous
		_apply(workspace,root.id,next,"Change level height"))
	for spec in [["Wall thickness","wall_thickness",.02,2.],["Slab thickness","slab_thickness",.02,1.],["Foundation depth","foundation_depth",.05,5.],["Roof pitch","roof_pitch",1.,75.],["Roof overhang","roof_overhang",0.,2.],["Baseboard height","baseboard_height",0.,.5],["Crown height","crown_height",0.,.5],["Interior trim depth","interior_trim_depth",.005,.3]]:
		_number(parent,spec[0],float(source.get(spec[1])),spec[2],spec[3],.01,func(value: float): var next:=Source.copy(_source(workspace,root.id)); next.set(spec[1],value); _apply(workspace,root.id,next,"Change "+str(spec[0]).to_lower()))
	var simulation:=CheckButton.new(); simulation.text="Structural physics"; simulation.tooltip_text="Simulate generated walls, floors, doors and supports through the scene timeline. The foundation remains fixed."; simulation.button_pressed=source.physics_enabled; parent.add_child(simulation)
	simulation.toggled.connect(func(on: bool): var next:=Source.copy(_source(workspace,root.id)); next.physics_enabled=on; _apply(workspace,root.id,next,"Change building physics"))
	var roof:=OptionButton.new(); parent.add_child(roof)
	for name in ["Flat roof","Gable roof","Shed roof","Hip roof"]: roof.add_item(name)
	roof.select(source.roof_type); roof.item_selected.connect(func(index: int): var next:=Source.copy(_source(workspace,root.id)); next.roof_type=index; _apply(workspace,root.id,next,"Change roof"))
	if level<source.floors.size()-1:
		_button(parent,"＋ Staircase to next level",func():
			var next:=Source.copy(_source(workspace,root.id)); next.stairs.append({"id":ActorData.new_id(),"from":next.floors[level].id,"to":next.floors[level+1].id,"type":0,"position":Vector2(-1,-2),"width":1.,"length":4.,"steps":16}); _apply(workspace,root.id,next,"Add staircase"))
	for index in (source.stairs as Array).size(): _stair_properties(workspace,root.id,source,index,parent)
	if is_instance_valid(plan) and plan.building_id==root.id and plan.selected_wall>=0 and plan.selected_wall<(source.floors[level].walls as Array).size(): _wall_properties(workspace,root.id,source,level,plan.selected_wall,plan.selected_opening,parent)
	for entry in [["Exterior wall material",0],["Interior wall material",5],["Floor material",1],["Ceiling material",6],["Roof material",2],["Trim / door material",3],["Glass material",4]]: _button(parent,entry[0]+"…",choose_material.bind(workspace,root.id,entry[1]))
	_button(parent,"＋ Insert model / furniture…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res","glb","gltf","tscn","scn","obj"],"native_resource_types":["KiwiModelDocument","Mesh","PackedScene"]}; var path:=await ActorProjectFilePicker.pick(workspace,property,"Choose reusable model")
		if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
		var target: KiwiModelComponent=workspace.session.document.component(item.id)
		if target==null: return
		var pose: Transform3D=workspace.session.document.world_transform(target).affine_inverse()*Transform3D(Basis.IDENTITY,workspace.canvas.target)
		var result:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_modules.gd").insert(workspace.session,target.id,path,pose,workspace.path); workspace.status.text=result.error if not result.error.is_empty() else "Model inserted" )
	_button(parent,"⌖ Align component anchors…",_anchors.bind(workspace,item.id))
	if workspace.session is KiwiEnvironmentSession:
		var terrain_ids: Array[String]=[]; var terrains:=OptionButton.new(); parent.add_child(terrains)
		for component: KiwiModelComponent in workspace.session.document.components:
			if workspace.session.environment().terrain(component.id)!=null: terrain_ids.append(component.id); terrains.add_item("Foundation terrain · "+component.title)
		if terrain_ids.is_empty(): terrains.add_item("Add terrain to enable foundation shaping"); terrains.disabled=true
		var blend:=DragNumber.new(); blend.min_value=0.; blend.max_value=20.; blend.step=.1; blend.set_value_no_signal(1.); blend.custom_minimum_size.x=90; var blend_row:=HBoxContainer.new(); parent.add_child(blend_row); var blend_label:=Label.new(); blend_label.text="Foundation blend distance"; blend_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; blend_row.add_child(blend_label); blend_row.add_child(blend)
		var restore_blend:=func(index: int):
			if index<0 or index>=terrain_ids.size(): return
			var current: KiwiEnvironmentTerrain=workspace.session.environment().terrain(terrain_ids[index]); blend.set_value_no_signal(1.)
			if current==null or current.generation==null: return
			for layer: Dictionary in current.generation.layers:
				if layer.get("foundation_owner","")==root.id: blend.set_value_no_signal(float(layer.get("feather",1.))); break
		terrains.item_selected.connect(restore_blend); restore_blend.call(0)
		var foundation_actions:=HBoxContainer.new(); parent.add_child(foundation_actions)
		for choice in [["Update foundation",false],["Remove",true]]:
			_button(foundation_actions,choice[0],func():
				if terrains.selected<0 or terrains.selected>=terrain_ids.size(): return
				var error: String=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd").set_modifier(workspace.session,root.id,terrain_ids[terrains.selected],blend.value,choice[1]); workspace.status.text=error if not error.is_empty() else "Foundation terrain modifier updated; sculpt edits are preserved")
	var layout:=VBoxContainer.new(); parent.add_child(layout); var layout_heading:=Label.new(); layout_heading.text="RECTANGULAR ROOM LAYOUT"; layout.add_child(layout_heading)
	var rooms:=DragNumber.new(); rooms.min_value=2; rooms.max_value=12; rooms.step=1; rooms.set_value_no_signal(5); var room_row:=HBoxContainer.new(); layout.add_child(room_row); var room_label:=Label.new(); room_label.text="Rooms per level"; room_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; room_row.add_child(room_label); room_row.add_child(rooms)
	var corridor:=DragNumber.new(); corridor.min_value=.9; corridor.max_value=3.; corridor.step=.05; corridor.set_value_no_signal(1.2); var corridor_row:=HBoxContainer.new(); layout.add_child(corridor_row); var corridor_label:=Label.new(); corridor_label.text="Hallway width"; corridor_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; corridor_row.add_child(corridor_label); corridor_row.add_child(corridor)
	_number(layout,"Layout seed",source.seed,0.,100000.,1.,func(value: float): var next:=Source.copy(_source(workspace,root.id)); next.seed=int(value); _apply(workspace,root.id,next,"Change layout seed"))
	_button(layout,"▦ Generate rooms and doors",func():
		var result:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd").generate(_source(workspace,root.id),int(rooms.value),corridor.value)
		if not result.errors.is_empty(): workspace.status.text=result.errors[0]; return
		_apply(workspace,root.id,result.source,"Generate room layout"))
	return true
static func _anchors(workspace: Control,id: String) -> void:
	var item: KiwiModelComponent=workspace.session.document.component(id)
	if item==null: return
	var modules=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_modules.gd"); var window:=Window.new(); window.title="Align component anchors"; window.size=Vector2i(430,240); window.transient=true; workspace.add_child(window); window.close_requested.connect(window.queue_free)
	var panel:=VBoxContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_constant_override("separation",8); window.add_child(panel)
	var source_anchors: Array[Dictionary]=modules.anchors(item); var from:=OptionButton.new(); panel.add_child(from)
	for anchor in source_anchors: from.add_item("Moving anchor · "+str(anchor.name))
	var target:=OptionButton.new(); panel.add_child(target); var ids: Array[String]=[]
	for other in workspace.session.document.components:
		if other.id==id or workspace.session.document.is_descendant(other.id,id): continue
		ids.append(other.id); target.add_item(other.title)
	var to:=OptionButton.new(); panel.add_child(to); var target_anchors: Array[Dictionary]=[]
	var refresh:=func(index: int):
		to.clear(); target_anchors.clear()
		if index<0 or index>=ids.size(): return
		var other: KiwiModelComponent=workspace.session.document.component(ids[index])
		if other==null: return
		target_anchors.assign(modules.anchors(other))
		for anchor in target_anchors: to.add_item("Target anchor · "+str(anchor.name))
	target.item_selected.connect(refresh); refresh.call(0)
	var mate:=CheckButton.new(); mate.text="Face anchors toward each other"; mate.button_pressed=true; panel.add_child(mate)
	var apply:=Button.new(); apply.text="Align"; apply.disabled=ids.is_empty(); panel.add_child(apply); apply.pressed.connect(func():
		if target.selected<0 or target.selected>=ids.size() or to.selected<0 or to.selected>=target_anchors.size(): return
		var error: String=modules.snap(workspace.session,id,source_anchors[from.selected].pose,ids[target.selected],target_anchors[to.selected].pose,mate.button_pressed); workspace.status.text=error if not error.is_empty() else "Component aligned"
		if error.is_empty(): window.queue_free())
	window.popup_centered()
static func _wall_properties(workspace: Control,id: String,source: Resource,level: int,index: int,selected: int,parent: Node) -> void:
	var wall: Dictionary=source.floors[level].walls[index]; var heading:=Label.new(); heading.text="SELECTED WALL"; parent.add_child(heading)
	_number(parent,"Wall height",Source.wall_height(source,source.floors[level],wall),.1,20.,.05,func(value: float): var next:=Source.copy(_source(workspace,id)); next.floors[level].walls[index].height=value; next.floors[level].walls[index].height_mode="custom"; _apply(workspace,id,next,"Change wall height"))
	if selected<0 or selected>=(wall.get("openings",[]) as Array).size(): return
	var opening: Dictionary=wall.openings[selected]; var title:=Label.new(); title.text=str(opening.get("type","Opening")).capitalize(); parent.add_child(title)
	var types: Array=["door","slider","window","arch"]; var type:=OptionButton.new(); parent.add_child(type)
	for name in ["Hinged door","Sliding door","Window","Arch"]: type.add_item(name)
	type.select(maxi(0,types.find(str(opening.get("type","door"))))); type.item_selected.connect(func(choice: int):
		var next:=Source.copy(_source(workspace,id)); var entry: Dictionary=next.floors[level].walls[index].openings[selected]; entry.type=types[choice]; entry.bottom=1. if choice==2 else 0.; entry.height=1.2 if choice==2 else maxf(2.1,float(entry.get("height",2.1))); _apply(workspace,id,next,"Change opening type"))
	for spec in [["Width","width",.1,10.],["Height","height",.1,10.],["Sill height","bottom",0.,10.],["Position along wall","t",0.,1.],["Door angle","angle",-170.,170.],["Slide amount","slide",0.,1.]]:
		if spec[1]=="angle" and opening.get("type","")!="door": continue
		if spec[1]=="slide" and opening.get("type","")!="slider": continue
		_number(parent,spec[0],float(opening.get(spec[1],0.)),spec[2],spec[3],.01,func(value: float): var next:=Source.copy(_source(workspace,id)); next.floors[level].walls[index].openings[selected][spec[1]]=value; _apply(workspace,id,next,"Edit opening"))
	_button(parent,"Remove opening",func(): var next:=Source.copy(_source(workspace,id)); next.floors[level].walls[index].openings.remove_at(selected); _apply(workspace,id,next,"Remove opening"))
static func _stair_properties(workspace: Control,id: String,source: Resource,index: int,parent: Node) -> void:
	var stair: Dictionary=source.stairs[index]; var kind:=OptionButton.new(); parent.add_child(kind)
	for name in ["Straight staircase","L staircase","U staircase","Spiral staircase"]: kind.add_item(name)
	kind.select(int(stair.get("type",0))); kind.item_selected.connect(func(value: int): var next:=Source.copy(_source(workspace,id)); next.stairs[index].type=value; _apply(workspace,id,next,"Change staircase"))
	for spec in [["Width","width",.3,5.],["Run","length",.5,20.],["Steps","steps",2.,80.],["Rotation","yaw",-180.,180.]]:
		_number(parent,spec[0],float(stair.get(spec[1],16 if spec[1]=="steps" else 0.)),spec[2],spec[3],1. if spec[1]=="steps" else .05,func(value: float): var next:=Source.copy(_source(workspace,id)); next.stairs[index][spec[1]]=value; _apply(workspace,id,next,"Edit staircase"))
	for axis in 2:
		_number(parent,"Stair "+["X","Z"][axis],(stair.get("position",Vector2.ZERO) as Vector2)[axis],-100.,100.,.1,func(value: float): var next:=Source.copy(_source(workspace,id)); var point: Vector2=next.stairs[index].get("position",Vector2.ZERO); point[axis]=value; next.stairs[index].position=point; _apply(workspace,id,next,"Move staircase"))
	_button(parent,"Remove staircase",func(): var next:=Source.copy(_source(workspace,id)); next.stairs.remove_at(index); _apply(workspace,id,next,"Remove staircase"))
static func choose_material(workspace: Control,id: String,index: int) -> void:
	if not await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").flush(workspace.session): return
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res","material"],"native_resource_types":["Material"],"accepted_object_types":["material","natural_material","shader_material"]}; var path:=await ActorProjectFilePicker.pick(workspace,property,"Choose building material")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var material:=KiwiEnvironmentAssets.material(path)
	if material==null: return
	var source:=_source(workspace,id)
	if source==null: return
	Buildings.set_material(workspace.session,id,index,material)
static func _apply(workspace: Control,id: String,source: Resource,label: String) -> void:
	var session: KiwiModelSession=workspace.session; workspace.status.text="Updating building…"
	var result: Dictionary=await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").request(session,id,source,label)
	if not is_instance_valid(workspace) or workspace.session!=session or result.get("cancelled",false): return
	workspace.status.text=result.errors[0] if not result.errors.is_empty() else (" · ".join(result.warnings) if not result.warnings.is_empty() else "Building updated")
static func _source(workspace: Control,id: String) -> Resource:
	return preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").source(workspace.session,id)
static func _number(parent: Node,title: String,value: float,low: float,high: float,step: float,setter: Callable) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text=title; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label); var number:=DragNumber.new(); number.min_value=low; number.max_value=high; number.step=step; number.custom_minimum_size.x=85; number.set_value_no_signal(value); row.add_child(number); number.value_changed.connect(setter); number.drag_committed.connect(setter)
static func _button(parent: Node,title: String,callback: Callable) -> void:
	var button:=Button.new(); button.text=title; parent.add_child(button); button.pressed.connect(callback)
