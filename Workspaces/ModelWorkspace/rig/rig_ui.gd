class_name KiwiRigUI
extends RefCounted
var workspace: KiwiModelWorkspace
var job: KiwiRigWeightJob
var worker: Thread
var method := "Smooth"
var chain_count := 6
var test_axis := 2
func _init(owner: KiwiModelWorkspace) -> void: workspace=owner
func editor() -> KiwiRigEditor: return workspace.canvas.rig_tool.editor
func refresh() -> void: workspace._refresh_pending=true; workspace.canvas.request_sync()
func button(parent: Node, title: String, action: Callable, hint: String="") -> Button:
	return workspace._button(parent,title,action,hint)
func label(parent: Node, title: String) -> void: workspace._label(parent,title)
func choice(parent: Node, options: Array, current: String, changed: Callable) -> OptionButton:
	var input := OptionButton.new(); input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; input.clip_text=true
	for title: String in options: input.add_item(title)
	input.select(maxi(0,options.find(current))); parent.add_child(input); input.item_selected.connect(func(index: int): changed.call(input.get_item_text(index))); return input
func toggle(parent: Node, title: String, enabled: bool, changed: Callable) -> CheckButton:
	var control := CheckButton.new(); control.text=title; control.button_pressed=enabled; parent.add_child(control); control.toggled.connect(changed); return control
func set_mode(value: String) -> void:
	workspace.canvas.rig_tool.finish(true); editor().mode=value; editor().enabled=true
	if value=="Draw" and editor().rig()==null: editor().empty_rig()
	if value=="Pose": workspace.canvas.tool="Rotate"
	refresh(); workspace.canvas.grab_focus()
func quick_rig() -> void:
	var popup := PopupPanel.new(); popup.name="QuickRig"; workspace.add_child(popup)
	var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(340,180); popup.add_child(column)
	label(column,"QUICK RIG   /   Create → Bind → Pose")
	button(column,"✦ Auto Rig · fitted chain",func(): editor().create("Flexible chain",chain_count); popup.hide(); refresh(),"Fits an editable chain to the longest bounding-box axis. No anatomy recognition is claimed.")
	button(column,"◇ Choose rig template…",func(): popup.hide(); templates())
	button(column,"✎ Draw bones in viewport",func(): popup.hide(); set_mode("Draw"))
	button(column,"↳ Attach existing rig",func(): popup.hide(); editor().enabled=true; refresh(),"Choose the rig in the inspector, then bind the selected meshes.")
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(370,230))
func templates() -> void:
	var popup := PopupPanel.new(); popup.name="RigTemplates"; workspace.add_child(popup)
	var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(350,350); popup.add_child(column)
	label(column,"RIG TEMPLATES · approximate fitting")
	var count := SpinBox.new(); count.min_value=1; count.max_value=64; count.value=chain_count; count.prefix="Chain joints "; column.add_child(count)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y=290; column.add_child(scroll); var list := VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	for category: String in KiwiRigTemplates.CATEGORIES:
		label(list,category.to_upper())
		for kind: String in KiwiRigTemplates.CATEGORIES[category]:
			button(list,kind,func(): chain_count=int(count.value); editor().create(kind,chain_count); popup.hide(); refresh())
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(390,440))
func build_context(parent: HBoxContainer) -> void:
	for mode: String in ["Draw","Edit","Pose","Weight","Envelope"]:
		var control := button(parent,{"Draw":"✎ Draw","Edit":"◇ Edit","Pose":"↻ Pose","Weight":"◉ Weight","Envelope":"◯ Envelope"}[mode],set_mode.bind(mode))
		control.toggle_mode=true; control.button_pressed=editor().mode==mode
	button(parent,"↳ Bind",func(): bind_async(method),"Bind selected mesh components without joining them")
	var methods: Array=["Smooth","Distance","Envelope","Rigid"]
	var binding_method := choice(parent,methods,method,func(value: String): method=value); binding_method.custom_minimum_size.x=110
	button(parent,"⋯",more_menu)
	if editor().busy: button(parent,"Cancel weighting",func(): if job!=null: job.cancel())
func build_properties(parent: VBoxContainer) -> void:
	label(parent,"ARMATURE / RIGGING")
	var rigs: Array[KiwiModelComponent]=[]
	for item in workspace.session.document.components:
		if item.is_skeleton: rigs.append(item)
	var armature := editor().rig()
	var picker := OptionButton.new(); picker.name="RigPicker"; picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL; picker.clip_text=true; parent.add_child(picker)
	for item in rigs: picker.add_item(item.title)
	if armature!=null: picker.select(rigs.find(armature))
	picker.item_selected.connect(func(index: int): editor().rig_id=rigs[index].id; editor().selected_bone=0; refresh())
	if armature==null:
		button(parent,"＋ Quick Rig",quick_rig); button(parent,"Load rig preset…",load_preset); return
	if not armature.bones.is_empty():
		var bones := OptionButton.new(); bones.name="AuthoringBonePicker"; bones.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bones.clip_text=true; parent.add_child(bones)
		for bone in armature.bones: bones.add_item(str(bone.name))
		bones.select(editor().selected_bone); bones.item_selected.connect(func(index: int): editor().selected_bone=index; refresh())
		var bone := armature.bones[editor().selected_bone]
		if editor().mode in ["Edit","Draw","Envelope"]:
			var name_input := LineEdit.new(); name_input.text=str(bone.name); name_input.placeholder_text="Bone name"; parent.add_child(name_input); name_input.text_submitted.connect(func(value: String): editor().rename(value); refresh())
			var names: Array=["No parent"]
			for value in armature.bones: names.append(str(value.name))
			var current := "No parent" if int(bone.parent)<0 else str(armature.bones[int(bone.parent)].name)
			choice(parent,names,current,func(value: String): editor().parent(names.find(value)-1,editor().connected); refresh())
			toggle(parent,"Preserve connected joints",editor().connected,func(value: bool): editor().connected=value)
			toggle(parent,"Mirror edits",editor().symmetry,func(value: bool): editor().symmetry=value; refresh())
			if editor().symmetry:
				choice(parent,["X symmetry","Y symmetry","Z symmetry"],["X symmetry","Y symmetry","Z symmetry"][editor().symmetry_axis],func(value: String): editor().symmetry_axis=["X symmetry","Y symmetry","Z symmetry"].find(value))
				workspace._number(parent,"Mirror plane offset",editor().symmetry_offset,-10000,10000,.01,func(value: float): editor().symmetry_offset=value)
			workspace._number(parent,"Envelope radius",float(bone.radius),.001,1000,.01,func(value: float): editor().rig().bones[editor().selected_bone].radius=value)
			workspace._number(parent,"Roll (degrees)",rad_to_deg(float(bone.roll)),-360,360,.1,func(value: float):
				var rig := editor().rig(); rig.bones[editor().selected_bone].roll=deg_to_rad(value)
				var rest := KiwiRigMath.globals(rig.bones); editor().move_joint(editor().selected_bone,true,KiwiRigMath.tail(rig.bones[editor().selected_bone],rest[editor().selected_bone])))
			var world := KiwiRigMath.globals(armature.bones)
			vector(parent,"Joint head",world[editor().selected_bone].origin,func(value: Vector3): editor().move_joint(editor().selected_bone,false,value))
			vector(parent,"Joint tail",KiwiRigMath.tail(bone,world[editor().selected_bone]),func(value: Vector3): editor().move_joint(editor().selected_bone,true,value))
		else:
			for channel: String in ["position","rotation","scale"]:
				vector(parent,"Pose "+channel,bone[channel],func(value: Vector3):
					if channel=="scale":
						for axis in 3:
							if absf(value[axis])<.001: value[axis]=.001
					editor().rig().bones[editor().selected_bone][channel]=value)
			label(parent,"TEST JOINT BEND")
			choice(parent,["Bend X","Bend Y","Bend Z"],["Bend X","Bend Y","Bend Z"][test_axis],func(value: String): test_axis=["Bend X","Bend Y","Bend Z"].find(value))
			var slider := HSlider.new(); slider.min_value=-150; slider.max_value=150; slider.step=1; parent.add_child(slider)
			slider.drag_started.connect(func(): workspace.session.begin(); workspace._property_gesture=true)
			slider.value_changed.connect(func(value: float):
				var standalone := not workspace._property_gesture
				if standalone: workspace.session.begin()
				var selected: Dictionary=editor().rig().bones[editor().selected_bone]; var rotation: Vector3=(selected.rest as Transform3D).basis.get_rotation_quaternion().get_euler()*180./PI; rotation[test_axis]+=value; selected.rotation=rotation; workspace.session.changed.emit()
				if standalone: workspace.session.commit("Test bone bend"))
			slider.drag_ended.connect(func(_changed: bool): workspace._property_gesture=false; workspace.session.commit("Test bone bend"))
			button(parent,"↺ Reset selected pose",func(): editor().reset_pose(); refresh())
	if editor().mode=="Draw":
		label(parent,"DEPTH PLACEMENT")
		choice(parent,["Inside mesh","Surface","View plane","XY","YZ","XZ"],workspace.canvas.rig_tool.construction,func(value: String): workspace.canvas.rig_tool.construction=value)
		workspace._number(parent,"Plane / depth",workspace.canvas.rig_tool.depth,-10000,10000,.01,func(value: float): workspace.canvas.rig_tool.depth=value)
	if editor().mode=="Weight": weight_controls(parent)
	var row := HBoxContainer.new(); parent.add_child(row)
	button(row,"Save rig…",save_preset); button(row,"Load rig…",load_preset)
	toggle(parent,"Show skeleton",editor().show_bones,func(value: bool): editor().show_bones=value; refresh())
	toggle(parent,"Selected chain only",editor().only_chain,func(value: bool): editor().only_chain=value; refresh())
	toggle(parent,"Compare rest",workspace.canvas.rig_tool.compare_rest,func(value: bool): workspace.canvas.rig_tool.compare_rest=value; refresh())
	var status := Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text=editor().message; status.modulate=Color("a6bfd0"); parent.add_child(status)
func vector(parent: VBoxContainer, title: String, value: Vector3, changed: Callable) -> void:
	label(parent,title.capitalize()); var row := HBoxContainer.new(); parent.add_child(row); var state := {"value":value}
	for axis in 3:
		var control := workspace._number(row,["X","Y","Z"][axis],value[axis],-10000,10000,.01,func(next: float): state.value[axis]=next; changed.call(state.value))
		control.custom_minimum_size.x=55; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
func weight_controls(parent: VBoxContainer) -> void:
	var tool := workspace.canvas.rig_tool
	if editor().rig()==null or editor().rig().bones.is_empty(): label(parent,"Draw or load bones before painting weights."); return
	label(parent,"WEIGHT BRUSH")
	choice(parent,["Brush","Select vertices","Select faces"],tool.weight_tool,func(value: String): tool.weight_tool=value; refresh())
	choice(parent,["Add","Subtract","Replace","Smooth","Clear"],tool.brush_mode,func(value: String): tool.brush_mode=value)
	workspace._number(parent,"Radius · Shift+wheel",tool.brush_radius,.005,100,.01,func(value: float): tool.brush_radius=value)
	workspace._number(parent,"Strength",tool.brush_strength,.001,1,.01,func(value: float): tool.brush_strength=value)
	if tool.brush_mode=="Replace": workspace._number(parent,"Target weight",tool.brush_value,0,1,.01,func(value: float): tool.brush_value=value)
	workspace._number(parent,"Region weight",tool.brush_value,0,1,.01,func(value: float): tool.brush_value=value)
	button(parent,"Assign selected region",func(): tool.fill_region(); refresh())
	button(parent,"Clear region selection",func(): tool.region.clear(); refresh())
	toggle(parent,"Paint selected vertices only",tool.selected_only,func(value: bool): tool.selected_only=value)
	toggle(parent,"Paint hidden / back side",tool.paint_hidden,func(value: bool): tool.paint_hidden=value)
	var locked := false; var armature := editor().rig()
	for item in editor().meshes():
		if item.binding!=null and item.binding.locked_bones.has(str(armature.bones[editor().selected_bone].id)): locked=true
	toggle(parent,"Lock selected influence",locked,func(value: bool):
		var meshes := editor().meshes(); var id := str(editor().rig().bones[editor().selected_bone].id)
		workspace.session.action("Lock bone weights",func():
			for item in meshes:
				if item.binding==null: continue
				if value and not item.binding.locked_bones.has(id): item.binding.locked_bones.append(id)
				elif not value: item.binding.locked_bones=PackedStringArray(Array(item.binding.locked_bones).filter(func(key: String): return key!=id))))
	button(parent,"Adopt imported weights",func(): editor().message=editor().adopt_imported(); refresh())
	for action: String in ["Fix Weights","Normalize","Mirror weights","Clear influence"]:
		button(parent,action,func(): editor().message=editor().cleanup(action); refresh(),"Copy from the selected bone's side to the opposite side; matching mirrored vertices only." if action=="Mirror weights" else "")
	button(parent,"Validate skin weights",func():
		var errors := PackedStringArray()
		for item in editor().meshes():
			if item.binding!=null: errors.append_array(item.binding.validate(editor().rig()))
		editor().message="Weights valid." if errors.is_empty() else "\n".join(errors.slice(0,5)); refresh())
func more_menu() -> void:
	var options: Array=["Extrude connected bone","Select parent bone","Select first child","Disconnect joint","Connect to parent","Insert joint","Duplicate chain","Mirror chain","Unparent bone","Delete bone","Reset entire pose","Save rig preset","Load rig preset","Detach selected meshes","Leave rigging"]
	workspace._choice_menu("RIG OPERATIONS",options,func(value: String):
		match value:
			"Extrude connected bone":
				var armature := editor().rig()
				if armature!=null and not armature.bones.is_empty():
					set_mode("Draw"); var tool := workspace.canvas.rig_tool; tool.chain_parent=editor().selected_bone; tool.chain=KiwiRigMath.tail(armature.bones[tool.chain_parent],tool.world_bones()[tool.chain_parent])
			"Select parent bone":
				var armature := editor().rig()
				if armature!=null and not armature.bones.is_empty(): editor().selected_bone=maxi(0,int(armature.bones[editor().selected_bone].parent))
			"Select first child":
				var armature := editor().rig()
				if armature!=null:
					for i in armature.bones.size():
						if int(armature.bones[i].parent)==editor().selected_bone: editor().selected_bone=i; break
			"Disconnect joint":
				if editor().rig()!=null and not editor().rig().bones.is_empty(): workspace.session.action("Disconnect joint",func(): editor().rig().bones[editor().selected_bone].connected=false)
			"Connect to parent":
				if editor().rig()!=null and not editor().rig().bones.is_empty(): editor().parent(int(editor().rig().bones[editor().selected_bone].parent),true)
			"Insert joint": editor().insert_joint()
			"Duplicate chain": editor().duplicate_chain()
			"Mirror chain": editor().duplicate_chain(true)
			"Unparent bone": editor().parent(-1)
			"Delete bone": editor().delete_bone()
			"Reset entire pose": editor().reset_pose(true)
			"Save rig preset": save_preset()
			"Load rig preset": load_preset()
			"Detach selected meshes": editor().detach()
			"Leave rigging": editor().enabled=false
		refresh())
func bind_async(style: String) -> void:
	if worker!=null: return
	if style=="Rigid": editor().message=editor().bind(style); refresh(); return
	var armature := editor().rig(); var targets := editor().meshes()
	if armature==null or armature.bones.is_empty(): editor().message="Create bones first."; refresh(); return
	if targets.is_empty(): editor().message="Select meshes to bind."; refresh(); return
	var owned_editor := editor(); var owned_session := workspace.session; var revision := owned_session.revision; var id := armature.id; var inverse := owned_session.document.world_transform(armature).affine_inverse()
	var document_signature := owned_session._signature(owned_session.document)
	job=KiwiRigWeightJob.new(); job.method=style
	var budget := 0
	for item in targets:
		var source := KiwiRigEditor.source(item); var count := 0
		for surface in source.get_surface_count():
			if source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: editor().message="Soft binding needs triangular mesh surfaces. Use Rigid for line or point components."; job=null; refresh(); return
			count+=(source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		budget+=count
		if budget>KiwiRigWeighting.MAX_VERTICES or budget*armature.bones.size()>KiwiRigWeighting.MAX_PAIRS: editor().message="Weighting limit: 100,000 source vertices / 3 million vertex-bone pairs. Bind smaller selections or use fewer bones."; job=null; refresh(); return
		job.tasks.append({"id":item.id,"source":source,"bones":armature.bones.duplicate(true),"transform":inverse*owned_session.document.world_transform(item)})
	worker=Thread.new(); var error := worker.start(job.run)
	if error!=OK: editor().message="Could not start weight calculation (%d)."%error; worker=null; job=null; refresh(); return
	editor().busy=true; editor().message="Calculating weights… Cancel is available."; refresh()
	var tree := workspace.get_tree(); var task := job; var started_worker := worker
	while started_worker.is_alive(): await tree.process_frame
	if worker!=started_worker: return # Document switch/close already joined it.
	var bindings: Dictionary=started_worker.wait_to_finish(); worker=null; owned_editor.busy=false
	if task.is_cancelled(): editor().message="Weight calculation canceled. Nothing changed."
	elif workspace.session!=owned_session or owned_session.revision!=revision or not owned_session._gesture.is_empty() or owned_session._signature(owned_session.document)!=document_signature: editor().message="Model changed during calculation; stale weights discarded."
	else: editor().message=editor().install_bindings(id,bindings)
	job=null; refresh()

func cancel_job() -> void:
	if job!=null: job.cancel()
	if worker!=null: worker.wait_to_finish(); worker=null
	job=null
	if is_instance_valid(workspace) and workspace.canvas.rig_tool!=null: editor().busy=false
func save_preset() -> void:
	if editor().rig()==null: return
	var result := await ActorProjectResourceSaveDialog.pick(workspace,"Save reusable armature",editor().rig().title,"tres",false,PackedStringArray(),editor().preset())
	if not result.get("cancelled",true):
		var error := ResourceSaver.save(editor().preset(),str(result.path)); editor().message="Rig preset saved." if error==OK else "Save failed (%d)."%error
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
	refresh()
func load_preset() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["KiwiRigPreset"]}
	var path := await ActorProjectFilePicker.pick(workspace,property,"Load and fit a reusable armature")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var resource := ResourceLoader.load(path) as KiwiRigPreset
	if not editor().load_preset(resource): editor().message="Invalid rig preset."
	refresh()
