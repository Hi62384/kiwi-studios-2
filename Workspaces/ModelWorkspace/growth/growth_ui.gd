class_name KiwiGrowthUI
extends RefCounted
static var icons: Dictionary={}
static func icon(title: String) -> Texture2D:
	if icons.has(title): return icons[title]
	var paths:={"Hair":"M5 21C2 8 8 3 9 3M10 21C6 9 13 4 14 3M15 21C10 9 18 4 20 3","Fur":"M3 20L6 5 10 20 13 3 17 20 20 7 22 20","Feathers":"M4 21L17 4M7 18C-2 8 14 0 20 3 23 10 19 20 7 18M11 14L20 10M8 17L9 8","Comb":"M4 6H20M5 7V19M9 7V19M13 7V19M17 7V19M20 7V15","Brush":"M5 19L16 3 21 7 9 21ZM4 20L3 23","Cut":"M10 13L21 3M10 11L21 21M10 12L4 5M10 12L4 19M3 3a3 3 0 1 0 1 0M3 17a3 3 0 1 0 1 0","Grow":"M12 21V3M6 9L12 3 18 9M5 16H19","Curl":"M4 19C18 25 25 8 14 4 4 1 4 15 12 15 18 15 16 8 12 9","Clump":"M3 4Q11 6 12 20M8 3L12 20M21 4Q13 6 12 20M16 3L12 20","Density":"M4 4h1M10 4h1M16 4h1M22 4h1M4 10h1M10 10h1M16 10h1M4 16h1M10 16h1M4 22h1","Length":"M4 21V3M2 6L4 3 6 6M2 18L4 21 6 18M11 21V11M16 21V6M21 21V2","Smooth":"M2 14C7 3 17 23 22 10","Relax":"M3 5Q8 21 12 5M12 5L12 18M8 14L12 18 16 14","Part":"M12 2V22M10 7L3 12M14 7L21 12M10 13L3 18M14 13L21 18","Feather width":"M3 12H21M8 7L3 12 8 17M16 7L21 12 16 17","Spread":"M12 21L3 3M12 21V3M12 21L21 3","Protect":"M12 2L3 6V13Q5 19 12 22 19 19 21 13V6ZM8 12L11 15 17 8","Reset region":"M4 10A9 9 0 1 1 5 18M4 3V10H11","Guide":"M3 20C4 4 20 22 21 4M2 19h3v3H2ZM19 2h4v4H19Z"}
	paths["Color paint"]="M4 20L16 3 21 8 9 22ZM3 15H8M14 17a4 4 0 1 0 8 0 4 4 0 1 0 -8 0"
	paths["Select strands"]="M3 2L6 19 10 13 17 12ZM14 3Q20 11 20 22M18 3Q24 11 24 22"
	var image:=Image.new(); image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="'+str(paths.get(title,paths.Hair))+'" fill="none" stroke="#8be4cc" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"/></svg>'); var texture:=ImageTexture.create_from_image(image); icons[title]=texture; return texture
static func add_menu(workspace: KiwiModelWorkspace) -> void:
	var menu:=PopupMenu.new(); workspace.add_child(menu)
	for title: String in KiwiSurfaceGrowth.TYPES: menu.add_icon_item(icon(title),"Generate "+title)
	menu.add_separator(); menu.add_icon_item(icon("Fur"),"Generate layered fur coat",3)
	menu.id_pressed.connect(func(kind: int):
		var error:=KiwiSurfaceGrowth.add_layered_fur(workspace.session) if kind==3 else KiwiSurfaceGrowth.add(workspace.session,kind)
		if not error.is_empty(): workspace.canvas.notice.emit(error)
	)
	menu.position=Vector2i(workspace.get_global_mouse_position()); menu.popup(); menu.popup_hide.connect(menu.queue_free)
static func build(workspace: KiwiModelWorkspace,item: KiwiModelComponent,parent: VBoxContainer) -> void:
	var data:=item.growth; var session:=workspace.session; var tool:=workspace.canvas.groom_tool
	workspace._label(parent,"SURFACE GROWTH · "+KiwiSurfaceGrowth.TYPES[int(data.settings.get("type",0))])
	var source:=OptionButton.new(); source.fit_to_longest_item=false; source.name="GrowthSource"; parent.add_child(source)
	for candidate: KiwiModelComponent in session.document.components:
		if candidate.mesh==null or candidate.growth!=null: continue
		source.add_item(candidate.title); source.set_item_metadata(source.item_count-1,candidate.id)
		if candidate.id==data.source_id: source.select(source.item_count-1)
	source.item_selected.connect(func(index: int): session.action("Change growth source",func(): data.source_id=str(source.get_item_metadata(index)); item.parent_id=data.source_id; item.transform=Transform3D.IDENTITY; data.topology=0; data.generation_key=0; data.groom.clear(); data.groom_layers.clear(); data.guides.clear()))
	var groom:=CheckButton.new(); groom.name="GrowthGroomMode"; groom.text="Groom in viewport"; groom.button_pressed=tool.enabled; parent.add_child(groom); groom.toggled.connect(func(value: bool): tool.enabled=value; workspace.canvas.rig_tool.editor.enabled=false; workspace._refresh_pending=true)
	if tool.enabled:
		var choose:=OptionButton.new(); choose.name="GroomTool"; choose.fit_to_longest_item=false; parent.add_child(choose)
		for title: String in KiwiGroomTool.TOOLS: choose.add_icon_item(icon(title),title)
		choose.select(KiwiGroomTool.TOOLS.find(tool.tool)); choose.item_selected.connect(func(index: int): tool.tool=KiwiGroomTool.TOOLS[index]; workspace._refresh_pending=true)
		build_presets(workspace,parent,data)
		if tool.tool=="Select strands": build_individual(workspace,parent,data)
		workspace._number(parent,"Radius (world)",tool.radius,.005,100,.01,func(value: float): tool.radius=value)
		workspace._number(parent,"Strength",tool.strength,0,1,.01,func(value: float): tool.strength=value)
		workspace._number(parent,"Falloff",tool.falloff,0,1,.01,func(value: float): tool.falloff=value)
		if tool.tool in ["Cut","Grow","Length","Density","Clump","Feather width","Curl"]: workspace._number(parent,"Target / amount",tool.value,0,10,.01,func(value: float): tool.value=value)
		if tool.tool=="Curl": workspace._number(parent,"Curl frequency",tool.frequency,.1,20,.1,func(value: float): tool.frequency=value)
		if tool.tool=="Clump":
			workspace._number(parent,"Clump starts along strand",tool.clump_start,0,.99,.01,func(value: float): tool.clump_start=value)
			workspace._number(parent,"Full clump along strand",tool.clump_end,.01,1,.01,func(value: float): tool.clump_end=value)
			workspace._number(parent,"Clump variation",tool.clump_variation,0,1,.01,func(value: float): tool.clump_variation=value)
		if tool.tool=="Cut":
			workspace._button(parent,"Cut at local height",func(): session.action("Cut groom with plane",func(): KiwiSurfaceGrowth.cut_plane(data,Plane(Vector3.UP,tool.value))))
		if tool.tool=="Guide": build_guides(workspace,parent,data)
		if tool.tool=="Color paint":
			var paint:=ColorPickerButton.new(); paint.color=tool.paint_color; paint.custom_minimum_size.y=24; parent.add_child(paint); paint.color_changed.connect(func(value: Color): tool.paint_color=value)
		var symmetry:=OptionButton.new(); parent.add_child(symmetry)
		for title in ["No symmetry","Mirror X","Mirror Y","Mirror Z"]: symmetry.add_item(title)
		symmetry.select(tool.symmetry+1); symmetry.item_selected.connect(func(index: int): tool.symmetry=index-1)
		var through:=CheckButton.new(); through.text="Through surface"; through.button_pressed=tool.through; parent.add_child(through); through.toggled.connect(func(value: bool): tool.through=value)
		if tool.tool in ["Density","Length","Cut"]:
			var replace:=CheckButton.new(); replace.text="Set target"; replace.button_pressed=tool.target_cut if tool.tool=="Cut" else tool.replace; parent.add_child(replace); replace.toggled.connect(func(value: bool):
				if tool.tool=="Cut": tool.target_cut=value
				else: tool.replace=value)
	else:
		for row in [["density","Density / surface unit²",0.0,10000.0,.1],["length","Length",.001,100.0,.01],["thickness","Thickness",.0001,2.0,.001],["seed","Seed",0.0,1000000.0,1.0],["curvature","Bend",-3.0,3.0,.01],["taper","Taper",0.0,1.0,.01],["variation","Length variation",0.0,1.0,.01],["orientation_variation","Direction variation",0.0,1.0,.01],["spacing","Minimum root spacing",0.0,5.0,.01]]:
			var key: String=row[0]; workspace._number(parent,row[1],float(data.settings.get(key,0)),row[2],row[3],row[4],func(value: float): data.settings[key]=int(value) if key=="seed" else value; data.revision+=1; data.render_cache=null)
		choice(workspace,parent,data,"quality","Detail",["Fast","Balanced","Detailed","Final Render"])
		KiwiGrowthAppearanceUI.styles(workspace,parent,data)
		choice(workspace,parent,data,"direction_mode","Direction",["Surface normal","World direction","Object-local direction","Surface tangent"])
		if int(data.settings.get("direction_mode",0))>0:
			for axis in 3: workspace._number(parent,"Direction "+["X","Y","Z"][axis],data.settings.direction[axis],-1,1,.01,func(value: float): data.settings.direction[axis]=value; data.revision+=1)
			workspace._number(parent,"Direction blend",float(data.settings.get("direction_blend",.4)),0,1,.01,func(value: float): data.settings.direction_blend=value; data.revision+=1)
		if int(data.settings.get("type",0))==2:
			choice(workspace,parent,data,"feather_type","Feathers",["Down","Contour","Flight"]); choice(workspace,parent,data,"arrangement","Arrangement",["Area-random","Ordered surface rows"])
			workspace._number(parent,"Vane width",float(data.settings.get("width",.14)),.001,10,.01,func(value: float): data.settings.width=value; data.revision+=1)
			workspace._number(parent,"Rows",float(data.settings.get("rows",4)),1,32,1,func(value: float): data.settings.rows=int(value))
			workspace._number(parent,"Overlap",float(data.settings.get("overlap",.3)),0,.95,.01,func(value: float): data.settings.overlap=value; data.revision+=1)
		else: choice(workspace,parent,data,"shape","Strands",["Straight","Curved","Wavy","Curly"])
	var actions:=HFlowContainer.new(); parent.add_child(actions)
	workspace._button(actions,"Regenerate",func(): session.action("Regenerate growth",func():
		if not data.source_valid: data.topology=0; data.faces=PackedInt32Array(); data.groom.clear(); data.groom_layers.clear(); data.guides.clear()
		data.generation_key=0; data.render_cache=null; data.revision+=1))
	workspace._button(actions,"Clear face mask",func(): session.action("Clear growth face mask",func(): data.faces=PackedInt32Array(); data.generation_key=0))
	workspace._button(actions,"Convert to mesh",func(): session.action("Make growth editable",func(): item.mesh=KiwiModelMesh.from_mesh(KiwiSurfaceGrowth.render(data)); item.growth=null; item.skeleton_id=""))
	KiwiGrowthAppearanceUI.build(workspace,parent,data)
	preload("res://Workspaces/ModelWorkspace/growth/growth_region_ui.gd").build(workspace,parent,data)
	workspace._label(parent,"%d roots reserved · %d selected faces"%[data.roots.size(),data.faces.size()])
	if not data.error.is_empty(): workspace._label(parent,data.error)
	var enabled:=CheckButton.new(); enabled.text="Groom adjustments"; enabled.button_pressed=data.groom_enabled; parent.add_child(enabled); enabled.toggled.connect(func(value: bool): session.action("Toggle grooming",func(): data.groom_enabled=value; data.revision+=1))
	workspace._button(parent,"Reset groom",func(): session.action("Reset groom",func(): data.groom.clear(); data.groom_layers.clear(); data.guides.clear(); data.revision+=1))
	workspace._button(parent,"Apply groom layers",func(): session.action("Apply groom layers",func():
		if not data.roots.is_empty(): KiwiSurfaceGrowth.style(data,data.roots[0])
		data.groom=data.effective.duplicate(true); data.groom_layers.clear(); data.revision+=1; data.render_cache=null))
	for index in data.groom_layers.size():
		var layer: Dictionary=data.groom_layers[index]; var row:=HBoxContainer.new(); parent.add_child(row); var check:=CheckBox.new(); check.text=str(layer.tool)+" · "+str(layer.changes.size()); check.button_pressed=layer.get("enabled",true); check.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(check)
		check.toggled.connect(func(value: bool): session.action("Toggle grooming layer",func(): data.groom_layers[index].enabled=value; data.revision+=1))
		for direction in [-1,1]:
			var move:=workspace._button(row,"↑" if direction<0 else "↓",func(): session.action("Reorder groom",func(): var copy: Dictionary=data.groom_layers[index]; data.groom_layers.remove_at(index); data.groom_layers.insert(index+direction,copy); data.revision+=1)); move.disabled=index+direction<0 or index+direction>=data.groom_layers.size()
		workspace._button(row,"×",func(): session.action("Remove grooming layer",func(): data.groom_layers.remove_at(index); data.revision+=1))
	for child in parent.get_children():
		if child is Label:
			child.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
static func choice(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData,key: String,title: String,choices: Array) -> void:
	workspace._label(parent,title); var input:=OptionButton.new(); input.fit_to_longest_item=false; parent.add_child(input)
	for label: String in choices: input.add_item(label)
	input.select(clampi(int(data.settings.get(key,0)),0,choices.size()-1)); input.item_selected.connect(func(index: int): workspace.session.action("Growth "+title,func(): data.settings[key]=index; data.revision+=1; data.render_cache=null))
static func build_guides(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	var tool:=workspace.canvas.groom_tool; workspace._label(parent,"Click root → guide · Drag gold handles")
	var choose:=OptionButton.new(); choose.fit_to_longest_item=false; parent.add_child(choose)
	for id: String in data.guides:
		choose.add_item("Guide "+str(choose.item_count+1)); choose.set_item_metadata(choose.item_count-1,id)
		if id==tool.selected_guide: choose.select(choose.item_count-1)
	choose.item_selected.connect(func(index: int): tool.selected_guide=str(choose.get_item_metadata(index)); workspace._refresh_pending=true)
	if not data.guides.has(tool.selected_guide): return
	var id:=tool.selected_guide; var guide: Dictionary=data.guides[id]
	var locked:=CheckButton.new(); locked.text="Lock guide handles"; locked.button_pressed=guide.get("locked",false); parent.add_child(locked); locked.toggled.connect(func(value: bool): workspace.session.action("Lock groom guide",func(): data.guides[id].locked=value))
	workspace._number(parent,"Guide length",float(guide.get("length_scale",1)),.01,10,.01,func(value: float): data.guides[id].length_scale=value; data.revision+=1)
	for axis in 3:
		workspace._number(parent,"Guide rotation "+["X","Y","Z"][axis],rad_to_deg((guide.get("rotation",Vector3.ZERO) as Vector3)[axis]),-360,360,1,func(value: float): var rotation: Vector3=data.guides[id].get("rotation",Vector3.ZERO); rotation[axis]=deg_to_rad(value); data.guides[id].rotation=rotation; data.revision+=1)
	workspace._number(parent,"Guide influence",float(guide.get("influence",1)),0,1,.01,func(value: float): data.guides[id].influence=value; data.revision+=1)
	var row:=HFlowContainer.new(); parent.add_child(row)
	for action: String in ["Add point","Remove tip","Smooth guide","Duplicate guide","Remove guide"]:
		workspace._button(row,action,func(): workspace.session.action(action,func():
			var points: PackedVector3Array=data.guides[id].points
			if action=="Add point": points.append(points[-1]+(points[-1]-points[-2])*.5)
			elif action=="Remove tip" and points.size()>2: points.resize(points.size()-1)
			elif action=="Smooth guide":
				for i in range(1,points.size()-1): points[i]=points[i]*.5+(points[i-1]+points[i+1])*.25
			elif action=="Duplicate guide": data.guides[ActorData.new_id()]=data.guides[id].duplicate(true)
			if action=="Remove guide": data.guides.erase(id)
			else: data.guides[id].points=points
			data.revision+=1; data.render_cache=null))
static func build_presets(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	var tool:=workspace.canvas.groom_tool; var row:=HBoxContainer.new(); parent.add_child(row); var presets:=OptionButton.new(); presets.fit_to_longest_item=false; presets.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(presets); presets.add_item("Brush presets")
	for preset: Dictionary in data.brush_presets: presets.add_icon_item(icon(str(preset.tool)),str(preset.tool)+" · "+str(snappedf(float(preset.radius),.01)))
	if tool.selected_preset>=0 and tool.selected_preset<data.brush_presets.size(): presets.select(tool.selected_preset+1)
	presets.item_selected.connect(func(index: int):
		if index==0: tool.selected_preset=-1; return
		tool.selected_preset=index-1
		for field: String in data.brush_presets[index-1]: tool.set(field,data.brush_presets[index-1][field])
		workspace._refresh_pending=true)
	for fresh in [false,true]:
		workspace._button(row,"+" if fresh else "Save",func():
			var preset:={}
			for field: String in ["tool","radius","strength","falloff","spacing","value","frequency","symmetry","through","replace","target_cut","paint_color","clump_start","clump_end","clump_variation"]: preset[field]=tool.get(field)
			workspace.session.action("Save groom brush preset",func():
				if fresh or tool.selected_preset<0 or tool.selected_preset>=data.brush_presets.size():
					if data.brush_presets.size()<32: data.brush_presets.append(preset); tool.selected_preset=data.brush_presets.size()-1
				else: data.brush_presets[tool.selected_preset]=preset))
	if tool.selected_preset>=0 and tool.selected_preset<data.brush_presets.size(): workspace._button(row,"×",func(): workspace.session.action("Delete groom brush preset",func(): data.brush_presets.remove_at(tool.selected_preset); tool.selected_preset=-1))
static func build_individual(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	var tool:=workspace.canvas.groom_tool; var root: Dictionary={}
	for candidate: Dictionary in data.roots:
		if int(candidate.id)==tool.selected_root: root=candidate; break
	if root.is_empty(): workspace._label(parent,"Click a strand root to edit it."); return
	var id:=str(root.id); workspace._label(parent,"STRAND "+id); var values:=KiwiSurfaceGrowth.style(data,root)
	for row in [["length","Length",values.length,0.,100.],["thickness","Thickness",KiwiSurfaceGrowth.base_settings(data).get("thickness",.01),.0001,2.],["width","Feather width",KiwiSurfaceGrowth.base_settings(data).get("width",.14),.0001,10.],["curl","Curl",0.,-4.,4.],["roll","Roll (degrees)",0.,-180.,180.],["frizz","Frizz",0.,0.,2.]]:
		var field: String=row[0]; workspace._number(parent,row[1],float(values.get(field,row[2])),row[3],row[4],.001,func(value: float):
			if not data.individual.has(id): data.individual[id]={}
			data.individual[id][field]=value; data.revision+=1)
	for field: String in ["direction","offset"]:
		for axis in 3:
			workspace._number(parent,field.capitalize()+" "+["X","Y","Z"][axis],(values.get(field,Vector3.UP if field=="direction" else Vector3.ZERO) as Vector3)[axis],-10,10,.01,func(value: float):
				if not data.individual.has(id): data.individual[id]={}
				var vector: Vector3=data.individual[id].get(field,values.get(field,Vector3.UP if field=="direction" else Vector3.ZERO)); vector[axis]=value; data.individual[id][field]=vector; data.revision+=1)
	workspace._button(parent,"Reset selected strand",func(): workspace.session.action("Reset strand",func(): data.individual.erase(id); data.revision+=1))
