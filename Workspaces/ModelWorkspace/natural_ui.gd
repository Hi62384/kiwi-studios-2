extends RefCounted
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
const Edit=preload("res://Workspaces/ModelWorkspace/natural_edit.gd")
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> void:
	var heading:=Label.new(); heading.text="PROCEDURAL · "+item.generator; parent.add_child(heading)
	var groups: Dictionary={}; var state: Dictionary=workspace.session.document.workspace_state.get("natural_folds",{})
	for name: String in ["Form","Branches & roots","Foliage","Detail"]:
		var heading_button:=Button.new(); heading_button.text=name; heading_button.toggle_mode=true; heading_button.button_pressed=bool(state.get(item.id+name,name=="Form")); parent.add_child(heading_button)
		var content:=VBoxContainer.new(); content.visible=heading_button.button_pressed; parent.add_child(content); groups[name]=content
		heading_button.toggled.connect(func(open: bool): content.visible=open; state[item.id+name]=open; workspace.session.document.workspace_state.natural_folds=state)
	for entry in [["seed",0.,2147483647.,1.],["height",.02,200.,.05],["radius",.005,30.,.01],["branches",1.,16.,1.],["levels",0.,3.,1.],["length",.05,1.5,.01],["angle",.1,2.,.01],["curve",0.,1.,.01],["droop",0.,1.,.01],["lean",-1.,1.,.01],["taper",.1,.98,.01],["foliage",0.,3.,.1],["leaf_size",.01,2.,.01],["roots",0.,16.,1.],["irregularity",0.,.8,.01],["detail",6.,32.,1.]]:
		var key: String=entry[0]
		if item.generator.begins_with("Rock") and key not in ["seed","height","radius","irregularity","detail"]: continue
		if item.generator.begins_with("Plant") and item.generator!="Plant / Bush" and key not in ["seed","height","radius","branches"]: continue
		if item.generator.begins_with("Prop") and key not in ["seed","height","radius","curve","detail"]: continue
		var section: String="Form" if key in ["seed","height","radius"] else ("Foliage" if key in ["foliage","leaf_size"] else ("Detail" if key in ["detail","irregularity"] else "Branches & roots"))
		var row:=HBoxContainer.new(); groups[section].add_child(row); var label:=Label.new(); label.text=key.capitalize(); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		var number:=DragNumber.new(); number.min_value=entry[1]; number.max_value=entry[2]; number.step=entry[3]; number.custom_minimum_size.x=95; number.set_value_no_signal(float(item.parameters.get(key,Generator.defaults(item.generator)[key]))); row.add_child(number)
		if item.generator=="Plant / Cactus" and key=="branches": number.max_value=5
		# Preview uses the same pure generator, and release becomes one shared action.
		number.interaction_started.connect(workspace.session.begin)
		number.preview_changed.connect(func(value: float): Edit.request(workspace,item.id,key,value,false))
		number.drag_committed.connect(func(_value: float): Edit.finish(workspace))
		number.drag_cancelled.connect(func(): Edit.cancel(workspace))
		number.value_changed.connect(func(value: float):
			if number.dragging: return
			Edit.request(workspace,item.id,key,value,true))
	var bake:=Button.new(); bake.text="Make editable mesh"; parent.add_child(bake); bake.pressed.connect(func(): workspace.session.action("Make natural mesh editable",func(): workspace.session.document.component(item.id).generator=""))
	if item.generator=="Plant / Vine":
		var path:=Button.new(); path.text="Edit growth path / attachment…"; parent.add_child(path); path.pressed.connect(preload("res://Workspaces/ModelWorkspace/natural_path_ui.gd").open.bind(workspace,item.id))
	if not item.generator.begins_with("Rock") and item.surface_materials.size()>1 and item.surface_materials[1] is ShaderMaterial:
		var season:=OptionButton.new(); parent.add_child(season)
		for name in ["Summer foliage","Spring foliage","Autumn foliage","Winter foliage"]: season.add_item(name)
		season.select(clampi(int(item.parameters.get("season",0)),0,3)); season.item_selected.connect(func(index: int): appearance(workspace,item.id,"season",index))
		var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text="Wind"; row.add_child(label); var wind:=DragNumber.new(); wind.min_value=0.; wind.max_value=1.; wind.step=.01; wind.set_value_no_signal(float(item.parameters.get("wind_strength",0.))); row.add_child(wind)
		var change_wind:=func(value: float): appearance(workspace,item.id,"wind_strength",value)
		wind.value_changed.connect(change_wind); wind.drag_committed.connect(change_wind)
	if item.generator.begins_with("Tree"):
		var button:=Button.new(); button.text="Edit individual branches…"; parent.add_child(button); button.pressed.connect(branches.bind(workspace,item.id))
		var restore:=Button.new(); restore.text="Reset branch edits"; parent.add_child(restore); restore.pressed.connect(func(): Edit.request(workspace,item.id,"branch_overrides",{},true))

static func appearance(workspace: Control,id: String,key: String,value: Variant) -> void:
	workspace.session.action("Change natural "+key,func():
		var current: KiwiModelComponent=workspace.session.document.component(id)
		if current==null or current.surface_materials.size()<2: return
		current.parameters[key]=value
		var material:=current.surface_materials[1].duplicate(false) as ShaderMaterial
		if material==null: return
		if key=="wind_strength": material.set_shader_parameter("wind_strength",value)
		else: material.set_shader_parameter("leaf_color",[Color(.14,.38,.055),Color(.45,.65,.12),Color(.72,.22,.025),Color(.52,.43,.24)][clampi(int(value),0,3)])
		current.surface_materials[1]=material)

static func branches(workspace: Control,id: String) -> void:
	var item: KiwiModelComponent=workspace.session.document.component(id)
	if item==null: return
	var data:=Generator.generate(item.generator,item.parameters); var popup:=Window.new(); popup.title="Branch structure"; popup.size=Vector2i(340,420); popup.transient=true; workspace.add_child(popup)
	var column:=VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); popup.add_child(column); var picker:=OptionButton.new(); column.add_child(picker)
	var identities: Array=[]
	for branch: Dictionary in data.branches:
		if branch.id=="trunk": continue
		identities.append(branch.id); picker.add_item(branch.id)
	var fields:=VBoxContainer.new(); column.add_child(fields)
	var update:=func():
		for child in fields.get_children(): child.queue_free()
		if picker.selected<0: return
		var identity: String=identities[picker.selected]; var current: KiwiModelComponent=workspace.session.document.component(id)
		var value: Dictionary=current.parameters.get("branch_overrides",{}).get(identity,{})
		for spec in [["Length","length",.05,3.],["Thickness","radius",.1,2.],["Rotate X","rx",-180.,180.],["Rotate Y","ry",-180.,180.],["Rotate Z","rz",-180.,180.]]:
			var row:=HBoxContainer.new(); fields.add_child(row); var label:=Label.new(); label.text=spec[0]; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
			var number:=DragNumber.new(); number.min_value=spec[2]; number.max_value=spec[3]; number.step=.01 if spec[1] in ["length","radius"] else 1.; var key: String=spec[1]
			number.set_value_no_signal(float(value.get(key,1.)) if key in ["length","radius"] else (value.get("rotation",Vector3.ZERO) as Vector3)[["rx","ry","rz"].find(key)]); row.add_child(number)
			var write:=func(next: float): change_branch(workspace,id,identity,key,next)
			number.value_changed.connect(write); number.drag_committed.connect(write)
		var reset:=Button.new(); reset.text="Reset this branch"; fields.add_child(reset); reset.pressed.connect(func(): change_branch(workspace,id,identity,"reset",true))
		var prune:=Button.new(); prune.text="Prune branch and its twigs"; fields.add_child(prune); prune.pressed.connect(func(): change_branch(workspace,id,identity,"pruned",true))
	picker.item_selected.connect(func(_index: int): update.call()); update.call(); popup.close_requested.connect(popup.queue_free); popup.popup_centered()

static func change_branch(workspace: Control,id: String,identity: String,key: String,value: Variant) -> void:
	var target: KiwiModelComponent=workspace.session.document.component(id)
	if target==null: return
	var pending: Dictionary=workspace.get_meta("natural_edit",{}); var parameters: Dictionary=pending.parameters if pending.get("id","")==id else target.parameters
	var overrides: Dictionary=parameters.get("branch_overrides",{}).duplicate(true); var edit: Dictionary=overrides.get(identity,{})
	if key in ["length","radius","pruned"]: edit[key]=value
	elif key!="reset": var rotation: Vector3=edit.get("rotation",Vector3.ZERO); rotation[["rx","ry","rz"].find(key)]=float(value); edit.rotation=rotation
	if key=="reset": overrides.erase(identity)
	else: overrides[identity]=edit
	Edit.request(workspace,id,"branch_overrides",overrides,true)
