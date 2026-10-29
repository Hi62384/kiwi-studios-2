extends RefCounted
const Edit=preload("res://Workspaces/ModelWorkspace/natural_edit.gd")
static func open(workspace: Control,id: String) -> void:
	var item: KiwiModelComponent=workspace.session.document.component(id)
	if item==null: return
	var data:={"points":item.parameters.get("growth_path",PackedVector3Array([Vector3.ZERO,Vector3.UP*.5,Vector3.UP])).duplicate(),"selected":0}
	var window:=Window.new(); window.title="Vine path"; window.size=Vector2i(370,430); window.transient=true; workspace.add_child(window)
	var column:=VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); window.add_child(column); var list:=ItemList.new(); list.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(list)
	var fields:=HBoxContainer.new(); column.add_child(fields); var inputs: Array[DragNumber]=[]
	var refresh:=func():
		list.clear()
		for index in data.points.size(): list.add_item("%d   %s"%[index,str(data.points[index])])
		data.selected=clampi(data.selected,0,data.points.size()-1); list.select(data.selected)
		for axis in inputs.size(): inputs[axis].set_value_no_signal(data.points[data.selected][axis])
	for axis in 3:
		var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; fields.add_child(box); var label:=Label.new(); label.text=["X","Y","Z"][axis]; box.add_child(label)
		var number:=DragNumber.new(); number.min_value=-10000.; number.max_value=10000.; number.step=.01; box.add_child(number); inputs.append(number)
		var write:=func(value: float): var points: PackedVector3Array=data.points; var point: Vector3=points[data.selected]; point[axis]=value; points[data.selected]=point; data.points=points; Edit.request(workspace,id,"growth_path",points,true); refresh.call()
		number.value_changed.connect(write); number.drag_committed.connect(write)
	list.item_selected.connect(func(index: int): data.selected=index; refresh.call())
	var row:=HBoxContainer.new(); column.add_child(row)
	for caption in ["＋ Point","− Point"]:
		var button:=Button.new(); button.text=caption; row.add_child(button); button.pressed.connect(func():
			var points: PackedVector3Array=data.points
			if caption=="＋ Point": points.insert(data.selected+1,points[data.selected]+Vector3.UP*.25); data.selected+=1
			elif points.size()>2: points.remove_at(data.selected)
			data.points=points; Edit.request(workspace,id,"growth_path",points,true); refresh.call())
	var attach:=Button.new(); attach.text="Attach to other selected mesh"; column.add_child(attach); attach.pressed.connect(func():
		var current: KiwiModelComponent=workspace.session.document.component(id)
		if current==null: return
		for other_id: String in workspace.session.selected:
			var other: KiwiModelComponent=workspace.session.document.component(other_id)
			if other_id==id or other==null or other.mesh==null: continue
			if workspace.session.document is KiwiEnvironmentDocument and workspace.session.document.terrain(other_id)!=null: workspace.status.text="Bake this terrain to an editable model to use it as an attachment surface."; return
			var source:=KiwiModelModifiers.evaluate(other).copy_mesh(); var pose: Transform3D=workspace.session.document.world_transform(current).affine_inverse()*workspace.session.document.world_transform(other)
			for vertex in source.vertices.size(): source.vertices[vertex]=pose*source.vertices[vertex]
			Edit.request(workspace,id,"growth_surface",source,true); return
		workspace.status.text="Select the vine and a surface mesh together first.")
	var detach:=Button.new(); detach.text="Detach from surface"; column.add_child(detach); detach.pressed.connect(func(): Edit.request(workspace,id,"growth_surface",null,true))
	refresh.call(); window.close_requested.connect(window.queue_free); window.popup_centered()
