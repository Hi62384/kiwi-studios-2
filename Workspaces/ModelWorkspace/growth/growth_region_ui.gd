extends RefCounted
static func build(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	var toggle:=CheckButton.new(); toggle.name="GrowthLocalAssignments"; toggle.text="Local styles & materials"; toggle.button_pressed=workspace.get_meta("growth_regions_open",false); parent.add_child(toggle); toggle.toggled.connect(func(value: bool): workspace.set_meta("growth_regions_open",value); workspace._refresh_pending=true)
	if not toggle.button_pressed: return
	var tool:=workspace.canvas.groom_tool; var row:=HBoxContainer.new(); parent.add_child(row); var scope:=OptionButton.new(); scope.fit_to_longest_item=false; scope.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(scope)
	for title in ["Selected strand","Protected strands","Selected guide","Selected clump","Selected strand's face","Whole component"]: scope.add_item(title)
	workspace._button(row,"Assign",func():
		if data.regions.size()>=16: workspace.canvas.notice.emit("A growth component supports 16 local assignments."); return
		var chosen:=PackedInt32Array(); var selected: Dictionary={}
		for root: Dictionary in data.roots:
			if int(root.id)==tool.selected_root: selected=root; break
		var clump:=str(KiwiSurfaceGrowth.style(data,selected).get("clump_id","")) if not selected.is_empty() else ""
		for root: Dictionary in data.roots:
			var edit:=KiwiSurfaceGrowth.style(data,root); var match_root:=false
			match scope.selected:
				0: match_root=int(root.id)==tool.selected_root
				1: match_root=edit.get("locked",false)
				2: match_root=not tool.selected_guide.is_empty() and (str(edit.get("guide",""))==tool.selected_guide or edit.get("guide_weights",{}).has(tool.selected_guide))
				3: match_root=not clump.is_empty() and str(edit.get("clump_id",""))==clump
				4: match_root=not selected.is_empty() and int(root.face)==int(selected.face)
				5: match_root=true
			if match_root: chosen.append(int(root.id))
		if chosen.is_empty(): workspace.canvas.notice.emit("Select a strand/guide or paint a protected region first."); return
		workspace.session.action("Assign local growth material",func(): data.regions.append({"id":ActorData.new_id(),"name":scope.get_item_text(scope.selected),"roots":chosen,"enabled":true,"material":data.appearance.copy_material(),"style":null}); data.revision+=1; workspace.set_meta("growth_region_index",data.regions.size()-1)))
	if data.regions.is_empty(): return
	var choose:=OptionButton.new(); choose.fit_to_longest_item=false; parent.add_child(choose)
	for region: Dictionary in data.regions: choose.add_item(str(region.get("name","Region"))+" · "+str((region.get("roots",PackedInt32Array()) as PackedInt32Array).size()))
	var index:=clampi(int(workspace.get_meta("growth_region_index",0)),0,data.regions.size()-1); choose.select(index); choose.item_selected.connect(func(next: int): workspace.set_meta("growth_region_index",next); workspace._refresh_pending=true)
	var region: Dictionary=data.regions[index]; var controls:=HFlowContainer.new(); parent.add_child(controls); var enabled:=CheckBox.new(); enabled.text="Enabled"; enabled.button_pressed=region.get("enabled",true); controls.add_child(enabled); enabled.toggled.connect(func(value: bool): workspace.session.action("Toggle growth assignment",func(): data.regions[index].enabled=value; data.revision+=1))
	for direction in [-1,1]:
		var move:=workspace._button(controls,"↑" if direction<0 else "↓",func(): workspace.session.action("Reorder growth assignments",func(): var copy: Dictionary=data.regions[index]; data.regions.remove_at(index); data.regions.insert(index+direction,copy); workspace.set_meta("growth_region_index",index+direction); data.revision+=1)); move.disabled=index+direction<0 or index+direction>=data.regions.size()
	workspace._button(controls,"Remove",func(): workspace.session.action("Remove local growth assignment",func(): data.regions.remove_at(index); data.revision+=1))
	workspace._label(parent,"Later assignments win where regions overlap.")
	var material:=region.get("material") as KiwiGrowthMaterial
	if material!=null:
		for field: String in ["root_color","tip_color"]:
			workspace._label(parent,field.replace("_"," ").capitalize()); var color:=ColorPickerButton.new(); color.custom_minimum_size.y=24; color.color=material.get(field); parent.add_child(color); var before:={"value":color.color}
			color.color_changed.connect(func(value: Color): material.set(field,value))
			color.popup_closed.connect(func(): var after:=color.color; material.set(field,before.value); workspace.session.action("Local growth color",func(): material.set(field,after)); before.value=after)
		for field: String in ["roughness","specular","opacity","backlight"]: workspace._number(parent,field.capitalize(),float(material.get(field)),0,1,.01,func(value: float): material.set(field,value))
	var assets:=HFlowContainer.new(); parent.add_child(assets)
	workspace._button(assets,"Load material…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res"]}; var path:=await ActorProjectFilePicker.pick(workspace,property,"Local growth material")
		if path.is_empty(): return
		var loaded: KiwiGrowthMaterial=null if path==ActorProjectFilePicker.EMPTY_RESOURCE else ResourceLoader.load(path) as KiwiGrowthMaterial
		if loaded==null and path!=ActorProjectFilePicker.EMPTY_RESOURCE: workspace.canvas.notice.emit("Choose a Growth Material resource."); return
		workspace.session.action("Load local growth material",func(): data.regions[index].material=loaded.copy_material(true) if loaded!=null else null))
	workspace._button(assets,"Make unique",func(): workspace.session.action("Unique local growth material",func(): data.regions[index].material=(material if material!=null else data.appearance).copy_material(true)))
	workspace._button(assets,"Use component",func(): workspace.session.action("Inherit component material",func(): data.regions[index].material=null))
	if material!=null: workspace._button(assets,"Save material…",func(): var proxy:=KiwiSurfaceGrowthData.new(); proxy.appearance=material; KiwiGrowthAppearanceUI.save(workspace,proxy))
	var styles:=OptionButton.new(); styles.fit_to_longest_item=false; parent.add_child(styles); styles.add_item("Inherit component style")
	for title: String in KiwiGrowthStyle.PRESETS:
		styles.add_icon_item(KiwiGrowthStyle.preset(title).thumbnail(),title)
		if region.get("style") is KiwiGrowthStyle and region.style.title==title: styles.select(styles.item_count-1)
	styles.item_selected.connect(func(next: int): workspace.session.action("Local growth style",func(): data.regions[index].style=KiwiGrowthStyle.preset(styles.get_item_text(next)) if next>0 else null; data.revision+=1))
	if region.get("style") is KiwiGrowthStyle:
		var local_style:=region.style as KiwiGrowthStyle
		for field: String in ["length","thickness","curvature","taper","variation"]:
			var base:=KiwiSurfaceGrowth.base_settings(data); workspace._number(parent,"Local "+field,float(local_style.values.get(field,base.get(field,0))),0,10,.001,func(value: float): local_style.values[field]=value; data.revision+=1)
		workspace._button(parent,"Save local style…",func(): var proxy:=KiwiSurfaceGrowthData.new(); proxy.growth_style=local_style; KiwiGrowthAppearanceUI.save_style(workspace,proxy))
	workspace._button(parent,"Load local style…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res"]}; var path:=await ActorProjectFilePicker.pick(workspace,property,"Local growth style")
		if path.is_empty(): return
		var loaded: KiwiGrowthStyle=null if path==ActorProjectFilePicker.EMPTY_RESOURCE else ResourceLoader.load(path) as KiwiGrowthStyle
		if loaded==null and path!=ActorProjectFilePicker.EMPTY_RESOURCE: workspace.canvas.notice.emit("Choose a Growth Style resource."); return
		workspace.session.action("Load local growth style",func(): data.regions[index].style=loaded.duplicate(true) if loaded!=null else null; data.revision+=1))
