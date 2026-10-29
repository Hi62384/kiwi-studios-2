extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
static func capture(workspace: Control) -> Dictionary:
	var result: Dictionary={}
	for key in ["world_section","world_road_index","world_settlement_index","world_region_index","world_forest_index","world_prop_index","world_connection_index","world_district_index","world_block_index"]: result[key]=int(workspace.get_meta(key,0))
	return result
static func restore(workspace: Control,state: Dictionary) -> void:
	for key in ["world_section","world_road_index","world_settlement_index","world_region_index","world_forest_index","world_prop_index","world_connection_index","world_district_index","world_block_index"]: workspace.set_meta(key,int(state.get(key,0)))
static func apply(workspace: Control,id: String,authored: Resource,label: String="Edit world") -> void:
	var session: KiwiEnvironmentSession=workspace.session; var result:=await Edit.request(session,id,authored,label)
	if not is_instance_valid(workspace) or workspace.session!=session or result.get("cancelled",false): return
	workspace.status.text=result.errors[0] if not result.errors.is_empty() else (" · ".join(result.warnings) if not result.warnings.is_empty() else "World updated")
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	if Worlds.source(item)==null: return false
	var source:=Edit.source(workspace.session,item.id); var heading:=Label.new(); heading.text="WORLD"; parent.add_child(heading)
	var host:=parent
	var common:=HBoxContainer.new(); parent.add_child(common)
	for caption in ["✎ Draw roads","• Edit points"]:
		var button:=Button.new(); button.text=caption; common.add_child(button); button.pressed.connect(func(): workspace.canvas.environment_tool="Draw road" if caption=="✎ Draw roads" else "Road points"; workspace.canvas.grab_focus())
	var creation:=HFlowContainer.new(); parent.add_child(creation)
	var create:=MenuButton.new(); create.text="＋ Settlement ▾"; creation.add_child(create)
	for profile in ["Town","Village","City"]: create.get_popup().add_item(profile)
	create.get_popup().add_separator("Find suitable terrain")
	for index in 3: create.get_popup().add_item("Auto-place "+["Town","Village","City"][index]+"…",100+index)
	create.get_popup().id_pressed.connect(func(index: int):
		if index>=100: preload("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd").request(workspace,item.id,-1,["Town","Village","City"][index-100]); return
		var pose: Transform3D=workspace.session.document.world_transform(workspace.session.document.component(item.id)); var center: Vector3=pose.affine_inverse()*workspace.canvas.target; var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd").create(Edit.source(workspace.session,item.id),center,["Town","Village","City"][index]); workspace.set_meta("world_section",2); workspace.set_meta("world_settlement_index",next.settlements.size()-1); apply(workspace,item.id,next,"Generate settlement"))
	var forest:=MenuButton.new(); forest.text="♧ Add forest ▾"; creation.add_child(forest); forest.disabled=source.terrain_id.is_empty()
	for profile: String in preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").PROFILES: forest.get_popup().add_item(profile)
	forest.get_popup().id_pressed.connect(func(index: int):
		var pose: Transform3D=workspace.session.document.world_transform(workspace.session.document.component(item.id)); var center: Vector3=pose.affine_inverse()*workspace.canvas.target; var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").create(Edit.source(workspace.session,item.id),center,preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").PROFILES[index]); workspace.set_meta("world_section",4); workspace.set_meta("world_forest_index",next.forests.size()-1); apply(workspace,item.id,next,"Generate forest"))
	var props:=MenuButton.new(); props.text="＋ Objects ▾"; creation.add_child(props); props.disabled=source.terrain_id.is_empty()
	for caption in ["Along roads…","Across region…","In clusters…","On grid…"]: props.get_popup().add_item(caption)
	props.get_popup().add_separator("Built-in editable models")
	for index in preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd").NAMES.size(): props.get_popup().add_item(preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd").NAMES[index],100+index)
	props.get_popup().id_pressed.connect(func(index: int):
		if index<100: _add_props(workspace,item.id,["Roadside","Region","Clusters","Grid"][index]); return
		var library:=preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd"); var next: Resource=library.add(Edit.source(workspace.session,item.id),library.NAMES[index-100]); workspace.set_meta("world_section",5); workspace.set_meta("world_prop_index",next.prop_rules.size()-1); apply(workspace,item.id,next,"Populate built-in world props"))
	var sections:=OptionButton.new(); parent.add_child(sections)
	for caption in ["◎ World settings","━ Roads","⌂ Settlements","▦ Regions","♧ Forests","▧ Objects","⇄ Connections","▧ Districts and blocks"]: sections.add_item(caption)
	var panels: Array[VBoxContainer]=[]; var selected:=clampi(int(workspace.get_meta("world_section",0)),0,7)
	for index in 8: var panel:=VBoxContainer.new(); parent.add_child(panel); panel.visible=index==selected; panels.append(panel)
	load("res://Workspaces/EnvironmentWorkspace/world/world_district_ui.gd").properties(workspace,item.id,source,panels[7])
	sections.select(selected); sections.item_selected.connect(func(index: int):
		workspace.set_meta("world_section",index)
		for page in panels.size(): panels[page].visible=page==index
		if index==3: workspace.canvas.environment_tool="World regions"; workspace.canvas.overlay.queue_redraw())
	parent=panels[0]
	var recipes:=MenuButton.new(); recipes.text="Generate world preset…"; recipes.disabled=not preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").empty(source) or str(source.owned_terrain_id).is_empty() or source.owned_terrain_id!=source.terrain_id; recipes.tooltip_text="Start from an empty world with owned terrain. Existing authored worlds and external terrain are preserved."; parent.add_child(recipes)
	for name in preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").NAMES: recipes.get_popup().add_item(name)
	recipes.get_popup().id_pressed.connect(func(index: int): preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").request(workspace,item.id,preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").NAMES[index]))
	workspace._value(parent,"World layout seed",source.seed,-1000000.,1000000.,1.,func(value: float): var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_seed.gd").apply(Edit.source(workspace.session,item.id),int(value)); apply(workspace,item.id,next,"Change world layout seed"))
	workspace._value(parent,"Render distance (0 = all)",source.render_distance,0.,100000.,10.,func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.render_distance=value; apply(workspace,item.id,next,"Change world render distance"))
	for spec in [["Building plot budget","max_building_plots",1.,8192.,1.],["Eager building detail","eager_building_limit",0.,512.,1.],["Building detail distance","building_detail_distance",10.,10000.,10.],["Detailed buildings per view","max_active_buildings",1.,512.,1.],["Building cache (MB)","building_cache_mb",16.,1024.,16.]]:
		workspace._value(parent,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.set(spec[1],value if spec[1]=="building_detail_distance" else int(value)); apply(workspace,item.id,next,"Change building detail budget"))
	var existing:=CheckButton.new(); existing.text="Avoid existing structures"; existing.button_pressed=source.respect_existing_objects; parent.add_child(existing); existing.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.respect_existing_objects=on; apply(workspace,item.id,next,"Change existing-object placement masks"))
	var live:=CheckButton.new(); live.text="Live terrain and object updates"; live.button_pressed=source.auto_update_dependencies; parent.add_child(live); live.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.auto_update_dependencies=on; apply(workspace,item.id,next,"Toggle live world updates"))
	for spec in [["World width",0],["World depth",1]]:
		workspace._value(parent,spec[0],source.dimensions[spec[1]],16.,16384.,16.,func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.dimensions[spec[1]]=value; next.configure_regions(); apply(workspace,item.id,next,"Resize world"))
	workspace._value(parent,"Region size",source.region_size,16.,4096.,16.,func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.region_size=value; next.configure_regions(); apply(workspace,item.id,next,"Resize world regions"))
	var terrain:=OptionButton.new(); terrain.add_item("Terrain · None"); var terrain_ids: Array[String]=[""]; parent.add_child(terrain)
	for component: KiwiModelComponent in workspace.session.document.components:
		if workspace.session.environment().terrain(component.id)!=null: terrain_ids.append(component.id); terrain.add_item(component.title)
	terrain.select(maxi(0,terrain_ids.find(source.terrain_id))); terrain.item_selected.connect(func(index: int): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.terrain_id=terrain_ids[index]; apply(workspace,item.id,next,"Choose world terrain"))
	var grading:=HBoxContainer.new(); parent.add_child(grading)
	for caption in ["Grade roadbeds","Remove grading"]:
		var button:=Button.new(); button.text=caption; grading.add_child(button); button.pressed.connect(func(): _grade(workspace,item.id,caption=="Remove grading"))
	if source.roads.any(func(road: Dictionary): return str(road.get("mode","Ground"))=="Tunnel"):
		var refresh:=Button.new(); refresh.text="↻ Refresh tunnel terrain"; parent.add_child(refresh); refresh.pressed.connect(func(): apply(workspace,item.id,Edit.source(workspace.session,item.id),"Refresh tunnel excavation"))
	parent=panels[3]; var regions:=OptionButton.new(); parent.add_child(regions)
	for region: Dictionary in source.regions: regions.add_item(str(region.name))
	var region_index:=clampi(int(workspace.get_meta("world_region_index",0)),0,maxi(0,source.regions.size()-1)); regions.select(region_index if not source.regions.is_empty() else -1); regions.item_selected.connect(func(index: int): workspace.set_meta("world_region_index",index))
	var region_row:=HBoxContainer.new(); parent.add_child(region_row)
	for field in ["enabled","locked"]:
		var box:=CheckButton.new(); box.text=field.capitalize(); box.disabled=source.regions.is_empty(); box.button_pressed=bool(source.regions[region_index].get(field,false)) if not source.regions.is_empty() else false; region_row.add_child(box); regions.item_selected.connect(func(index: int): box.set_pressed_no_signal(bool(Edit.source(workspace.session,item.id).regions[index].get(field,false))))
		box.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.regions[regions.selected][field]=on; apply(workspace,item.id,next,"Change world region"))
	parent=panels[1]; var choices:=OptionButton.new(); parent.add_child(choices)
	for road: Dictionary in source.roads: choices.add_item(str(road.get("name","Road")))
	var road_index:=clampi(int(workspace.get_meta("world_road_index",0)),0,maxi(0,source.roads.size()-1)); choices.select(road_index if not source.roads.is_empty() else -1); choices.item_selected.connect(func(index: int): workspace.set_meta("world_road_index",index); workspace.canvas.road_tool.road_index=index; workspace.canvas.road_tool.point_index=0; workspace._refresh_properties())
	for index in range(road_index,road_index+1 if not source.roads.is_empty() else road_index):
		var road: Dictionary=source.roads[index]; var label:=Label.new(); label.text="━ "+str(road.get("name","Road")); parent.add_child(label)
		var category:=OptionButton.new(); parent.add_child(category)
		for caption: String in preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES: category.add_item(caption)
		category.select(maxi(0,preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES.find(str(road.get("type","Residential Street"))))); category.item_selected.connect(func(value: int): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index].merge(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").defaults(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES[value]),true); apply(workspace,item.id,next,"Change road type"))
		var mode:=OptionButton.new(); parent.add_child(mode)
		for name in ["Ground","Bridge","Tunnel"]: mode.add_item(name)
		mode.select(maxi(0,["Ground","Bridge","Tunnel"].find(str(road.get("mode","Ground"))))); mode.item_selected.connect(func(choice: int): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index].mode=["Ground","Bridge","Tunnel"][choice]; apply(workspace,item.id,next,"Change road crossing"))
		workspace._value(parent,"Elevation",(road.points as PackedVector3Array)[0].y,-1000.,1000.,.1,func(value: float):
			var next: Resource=Edit.source(workspace.session,item.id).copy(); var points: PackedVector3Array=next.roads[index].points; var offset:=value-points[0].y
			for point in points.size(): points[point]+=Vector3.UP*offset
			next.roads[index].points=points; next.roads[index].follow_terrain=false; next.nodes[next.roads[index].from]=points[0]; next.nodes[next.roads[index].to]=points[-1]; apply(workspace,item.id,next,"Set road elevation"))
		if str(road.get("mode","Ground"))=="Ground":
			var follow:=CheckButton.new(); follow.text="Follow terrain"; follow.button_pressed=bool(road.get("follow_terrain",false)); parent.add_child(follow); follow.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index].follow_terrain=on; apply(workspace,item.id,next,"Change terrain following"))
		if str(road.get("mode","Ground"))=="Bridge": workspace._value(parent,"Pier height",float(road.get("pier_height",8.)),.3,100.,.1,func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index].pier_height=value; apply(workspace,item.id,next,"Change bridge supports"))
		workspace._value(parent,"Width",float(road.width),.5,40.,.25,func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index].width=value; apply(workspace,item.id,next,"Change road width"))
		var details:=CheckButton.new(); details.text="Road section details"; details.button_pressed=bool(road.get("section",false)); parent.add_child(details); details.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); var defaults:=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").defaults(); next.roads[index].merge(defaults,false); next.roads[index].section=on; apply(workspace,item.id,next,"Toggle road section details"))
		if road.get("section",false):
			for spec in [["Thickness","thickness",0.,2.,.01],["Shoulder width","shoulder",0.,8.,.1],["Sidewalk width","sidewalk",0.,8.,.1],["Curb height","curb_height",0.,.5,.01],["Lanes","lanes",1.,12.,1.],["Speed limit","speed_limit",0.,200.,5.]]:
				workspace._value(parent,spec[0],float(road.get(spec[1],0.)),spec[2],spec[3],spec[4],func(value: float): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index][spec[1]]=int(value) if spec[1]=="lanes" else value; apply(workspace,item.id,next,"Change road "+str(spec[1])))
			for field in ["markings","one_way"]:
				var box:=CheckButton.new(); box.text="Lane markings" if field=="markings" else "One way"; box.button_pressed=bool(road.get(field,false)); parent.add_child(box); box.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads[index][field]=on; apply(workspace,item.id,next,"Change road "+field))
		var fitting:=HBoxContainer.new(); parent.add_child(fitting)
		for caption in ["Fit terrain","Route around hills"]:
			var button:=Button.new(); button.text=caption; fitting.add_child(button); button.pressed.connect(func():
				var result:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").fit(workspace.session,item.id,Edit.source(workspace.session,item.id),index,caption=="Route around hills")
				if result.source==null: workspace.status.text=result.error
				else: apply(workspace,item.id,result.source,"Fit road to terrain"))
		var operations:=HFlowContainer.new(); parent.add_child(operations)
		for caption in ["Reverse","Split","Delete point","Extend"]:
			var button:=Button.new(); button.text=caption; operations.add_child(button); button.pressed.connect(func():
				if caption=="Extend":
					workspace.canvas.environment_tool="Draw road"; workspace.canvas.road_tool._world_id=item.id; workspace.canvas.road_tool._first=(Edit.source(workspace.session,item.id).roads[index].points as PackedVector3Array)[-1]; workspace.canvas.road_tool._hover=null; workspace.canvas.grab_focus(); workspace.canvas.overlay.queue_redraw(); return
				var editing:=preload("res://Workspaces/EnvironmentWorkspace/world/road_editing.gd"); var current: Resource=Edit.source(workspace.session,item.id); var point:=int(workspace.canvas.road_tool.point_index) if workspace.canvas.road_tool.road_index==index else -1; var result: Dictionary
				if caption=="Reverse": result=editing.reverse(current,index)
				elif caption=="Split": result=editing.split(current,index,point)
				else: result=editing.remove_point(current,index,point)
				if result.source==null: workspace.status.text=result.error
				else: apply(workspace,item.id,result.source,caption+" road"))
		var joining:=MenuButton.new(); joining.text="Join endpoint to road…"; joining.disabled=source.roads.size()<2; parent.add_child(joining)
		for other in source.roads.size():
			if other!=index: joining.get_popup().add_item(str(source.roads[other].get("name","Road")),other)
		joining.get_popup().id_pressed.connect(func(other: int):
			var result:=preload("res://Workspaces/EnvironmentWorkspace/world/road_editing.gd").join(Edit.source(workspace.session,item.id),index,other)
			if result.source==null: workspace.status.text=result.error
			else: workspace.set_meta("world_road_index",int(result.index)); apply(workspace,item.id,result.source,"Join roads"))
		var remove:=Button.new(); remove.text="Remove road"; parent.add_child(remove); remove.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.roads.remove_at(index); apply(workspace,item.id,next,"Remove road"))
	_settlements(workspace,item.id,source,panels[2]); _forests(workspace,item.id,source,panels[4]); _props(workspace,item.id,source,panels[5]); _connections(workspace,item,source,panels[6]); _compact_choices(host); return true
static func _compact_choices(parent: Node) -> void:
	for child in parent.get_children():
		if child is OptionButton: child.fit_to_longest_item=false; child.clip_text=true; child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_compact_choices(child)
static func _connections(workspace: Control,item: KiwiModelComponent,source: Resource,parent: Node) -> void:
	for field in ["connect_settlements","connection_bridges"]:
		var box:=CheckButton.new(); box.text="Connect settlements" if field=="connect_settlements" else "Allow bridges and approaches"; box.button_pressed=bool(source.get(field)); parent.add_child(box); box.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.set(field,on); apply(workspace,item.id,next,"Change settlement connections"))
	var type:=OptionButton.new(); parent.add_child(type)
	for caption: String in preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES: type.add_item(caption)
	type.select(maxi(0,preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES.find(str(source.connection_road_type)))); type.item_selected.connect(func(index: int): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.connection_road_type=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES[index]; apply(workspace,item.id,next,"Change connecting road type"))
	var records: Array=item.parameters.get("world_connections",[]); var choices:=OptionButton.new(); parent.add_child(choices)
	for connection: Dictionary in records: choices.add_item(str(connection.name))
	if records.is_empty(): return
	var index:=clampi(int(workspace.get_meta("world_connection_index",0)),0,records.size()-1); choices.select(index); choices.item_selected.connect(func(value: int): workspace.set_meta("world_connection_index",value); workspace._refresh_properties()); var record: Dictionary=records[index]
	var summary:=Label.new(); summary.text="%.0f m · %d bridge(s)"%[float(record.length),int(record.bridges)]; parent.add_child(summary)
	var edit:=Button.new(); edit.text="Make connection roads editable"; parent.add_child(edit); edit.pressed.connect(func(): var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_connections.gd").make_editable(Edit.source(workspace.session,item.id),record); workspace.set_meta("world_section",1); workspace.set_meta("world_road_index",next.roads.size()-1); apply(workspace,item.id,next,"Make connecting roads editable"))
	var disable:=Button.new(); disable.text="Disable this connection"; parent.add_child(disable); disable.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,item.id).copy(); next.connection_overrides[record.id]={"disabled":true}; apply(workspace,item.id,next,"Disable settlement connection"))
static func _add_props(workspace: Control,id: String,mode: String) -> void:
	var session: KiwiEnvironmentSession=workspace.session; var property:=ActorProperty.new(); property.options={"extensions":["tres","res","mesh","glb","gltf","obj"],"raw_extensions":["glb","gltf","obj"],"native_resource_types":["KiwiModelDocument","Mesh","PackedScene"]}; var selected:=await ActorProjectFilePicker.pick(workspace,property,"Choose a reusable placement model")
	if not is_instance_valid(workspace) or workspace.session!=session or selected.is_empty() or selected==ActorProjectFilePicker.EMPTY_RESOURCE or session.document.component(id)==null: return
	var checked:=KiwiEnvironmentAssets.load_parts(selected)
	if not str(checked.error).is_empty(): workspace.status.text=str(checked.error); return
	var next: Resource=preload("res://Workspaces/EnvironmentWorkspace/world/world_props.gd").create(Edit.source(session,id),selected,mode); workspace.set_meta("world_section",5); workspace.set_meta("world_prop_index",next.prop_rules.size()-1); apply(workspace,id,next,"Populate world objects")
static func _props(workspace: Control,id: String,source: Resource,parent: Node) -> void:
	var choices:=OptionButton.new(); parent.add_child(choices)
	for rule: Dictionary in source.prop_rules: choices.add_item(str(rule.name))
	if source.prop_rules.is_empty(): return
	var index:=clampi(int(workspace.get_meta("world_prop_index",0)),0,source.prop_rules.size()-1); choices.select(index); choices.item_selected.connect(func(value: int): workspace.set_meta("world_prop_index",value); workspace._refresh_properties()); var rule: Dictionary=source.prop_rules[index]
	var mode:=OptionButton.new(); parent.add_child(mode)
	for caption in ["Along roads","Across region","In clusters","On grid"]: mode.add_item(caption)
	var modes: Array=["Roadside","Region","Clusters","Grid"]; mode.select(maxi(0,modes.find(str(rule.mode)))); mode.item_selected.connect(func(value: int): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index].mode=modes[value]; apply(workspace,id,next,"Change object placement mode"))
	for spec in [["Spacing","spacing",.5,1000.,.5],["Budget","budget",1.,20000.,1.],["Rotation offset","yaw",-180.,180.,1.]]:
		workspace._value(parent,spec[0],float(rule.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index][spec[1]]=value; apply(workspace,id,next,"Change object "+str(spec[1])))
	if str(rule.mode)=="Roadside":
		var sidewalk:=CheckButton.new(); sidewalk.text="Place on sidewalks"; sidewalk.button_pressed=bool(rule.get("sidewalk",false)); parent.add_child(sidewalk); sidewalk.toggled.connect(func(on: bool): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index].sidewalk=on; apply(workspace,id,next,"Change sidewalk placement"))
		workspace._value(parent,"Distance from road",float(rule.get("setback",2.)),.1,100.,.1,func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index].setback=value; apply(workspace,id,next,"Move roadside objects"))
		var side:=OptionButton.new(); parent.add_child(side)
		for caption in ["Both","Left","Right"]: side.add_item(caption)
		side.select(maxi(0,["Both","Left","Right"].find(str(rule.get("sides","Both"))))); side.item_selected.connect(func(value: int): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index].sides=["Both","Left","Right"][value]; apply(workspace,id,next,"Change road placement side"))
	else: workspace._value(parent,"Density",float(rule.get("density",.02)),0.,10.,.01,func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules[index].density=value; apply(workspace,id,next,"Change object density"))
	var edit:=Button.new(); edit.text="Edit layer filters and palette"; parent.add_child(edit); var component_id:=id+":props:"+str(rule.id); edit.disabled=workspace.session.document.component(component_id)==null; edit.pressed.connect(func(): workspace.session.select(component_id))
	var remove:=Button.new(); remove.text="Remove placement rule"; parent.add_child(remove); remove.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.prop_rules.remove_at(index); apply(workspace,id,next,"Remove object placement"))
static func _forests(workspace: Control,id: String,source: Resource,parent: Node) -> void:
	var choice:=OptionButton.new(); parent.add_child(choice)
	for forest: Dictionary in source.forests: choice.add_item(str(forest.name))
	if source.forests.is_empty(): return
	var index:=clampi(int(workspace.get_meta("world_forest_index",0)),0,source.forests.size()-1); choice.select(index); choice.item_selected.connect(func(value: int): workspace.set_meta("world_forest_index",value); workspace._refresh_properties()); var forest: Dictionary=source.forests[index]
	var enabled:=CheckButton.new(); enabled.text="Generate forest"; enabled.button_pressed=bool(forest.get("enabled",true)); parent.add_child(enabled); enabled.toggled.connect(func(value: bool): var next: Resource=Edit.source(workspace.session,id).copy(); next.forests[index].enabled=value; apply(workspace,id,next,"Toggle forest"))
	for spec in [["Density","density",0.,4.,.05],["Clearing size","patch_scale",1.,256.,1.],["Clearing variation","patch_strength",0.,1.,.05],["Instances per layer","budget",1.,20000.,1.]]:
		workspace._value(parent,spec[0],float(forest.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.forests[index][spec[1]]=value; apply(workspace,id,next,"Change forest "+str(spec[1])))
	for spec in [["Center X",0],["Center Z",1],["Width",2],["Depth",3]]:
		var bounds: Rect2=forest.bounds; var value: float=bounds.get_center()[int(spec[1])] if int(spec[1])<2 else bounds.size[int(spec[1])-2]
		workspace._value(parent,spec[0],value,1. if int(spec[1])>=2 else -10000.,16384.,1.,func(changed: float):
			var next: Resource=Edit.source(workspace.session,id).copy(); var rect: Rect2=next.forests[index].bounds; var center:=rect.get_center()
			if int(spec[1])<2: center[int(spec[1])]=changed
			else: rect.size[int(spec[1])-2]=changed
			rect.position=center-rect.size*.5; next.forests[index].bounds=rect; apply(workspace,id,next,"Resize forest region"))
	var layers:=Label.new(); layers.text="Vegetation layers"; parent.add_child(layers)
	for layer: String in preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").LAYERS:
		var button:=Button.new(); button.text="Edit "+layer; parent.add_child(button); var layer_id:=id+":forest:"+str(forest.id)+":"+str(preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").LAYERS.find(layer)); button.disabled=workspace.session.document.component(layer_id)==null; button.pressed.connect(func(): workspace.session.select(layer_id))
	var row:=HBoxContainer.new(); parent.add_child(row)
	var vary:=Button.new(); vary.text="⟳ Vary placement"; row.add_child(vary); vary.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.forests[index].seed=int(next.forests[index].seed)+1; apply(workspace,id,next,"Vary forest placement"))
	var remove:=Button.new(); remove.text="Remove"; row.add_child(remove); remove.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.forests.remove_at(index); apply(workspace,id,next,"Remove forest"))
static func _grade(workspace: Control,id: String,remove: bool) -> void:
	var session: KiwiEnvironmentSession=workspace.session
	if not await Edit.flush(session) or not is_instance_valid(workspace) or workspace.session!=session: return
	var root:=session.document.component(id)
	if root==null: return
	var result:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").grading_plan(session,id,Worlds.source(root),remove)
	if not str(result.error).is_empty(): workspace.status.text=result.error
	else: workspace._regenerate_terrain(str(result.id),result.settings)
static func _settlements(workspace: Control,id: String,source: Resource,parent: Node) -> void:
	var choice:=OptionButton.new(); parent.add_child(choice)
	for settlement: Dictionary in source.settlements: choice.add_item(str(settlement.get("name","Settlement")))
	if source.settlements.is_empty(): return
	var index:=clampi(int(workspace.get_meta("world_settlement_index",source.settlements.size()-1)),0,source.settlements.size()-1); choice.select(index); choice.item_selected.connect(func(next: int): workspace.set_meta("world_settlement_index",next); workspace._refresh_properties()); var settlement: Dictionary=source.settlements[index]
	var find:=Button.new(); find.text="Find suitable site"; find.disabled=str(source.terrain_id).is_empty(); parent.add_child(find); find.pressed.connect(func(): preload("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd").request(workspace,id,index))
	var layout:=OptionButton.new(); parent.add_child(layout); layout.add_item("Generate streets and blocks"); layout.add_item("Use drawn road network"); layout.select(1 if str(settlement.get("layout_mode","Grid"))=="Road network" else 0); layout.item_selected.connect(func(choice: int): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[index].layout_mode="Road network" if choice==1 else "Grid"; apply(workspace,id,next,"Change settlement road layout"))
	if str(settlement.get("layout_mode","Grid"))=="Road network": workspace._value(parent,"Frontage lot size",float(settlement.get("lot_size",18.)),10.,64.,1.,func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[index].lot_size=value; apply(workspace,id,next,"Resize road-frontage lots"))
	for axis in [0,2]:
		workspace._value(parent,"Center "+["X","Y","Z"][axis],(settlement.center as Vector3)[axis],-10000.,10000.,1.,func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); var center: Vector3=next.settlements[index].center; center[axis]=value; next.settlements[index].center=center; apply(workspace,id,next,"Move settlement"))
	for spec in [["Radius","radius",8.,512.,1.],["Blocks per side","blocks",1.,6.,1.],["Minimum floors","height_min",1.,8.,1.],["Maximum floors","height_max",1.,8.,1.],["Setback","setback",1.,10.,.25]]:
		if spec[1]=="blocks" and (settlement.profile=="Village" or str(settlement.get("layout_mode","Grid"))=="Road network"): continue
		workspace._value(parent,spec[0],float(settlement.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[index][spec[1]]=value; apply(workspace,id,next,"Change settlement"))
	var seed:=Button.new(); seed.text="⟳ New settlement variation"; parent.add_child(seed); seed.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[index].seed=int(next.settlements[index].get("seed",1))+1; apply(workspace,id,next,"Vary settlement"))
	var remove:=Button.new(); remove.text="Remove settlement"; parent.add_child(remove); remove.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements.remove_at(index); apply(workspace,id,next,"Remove settlement"))

