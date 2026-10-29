extends RefCounted
const Components=preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd")
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	if not Components.accepts(item.generator): return false
	var heading:=Label.new(); heading.text="ARCHITECTURE · "+item.title; parent.add_child(heading)
	var kind:=item.generator.get_slice(" / ",1)
	var fields: Array=["length","height","depth"]
	if kind in ["Door","Window","Arch"]: fields=["width","height","depth","trim"]
	elif kind in ["Column","Pillar"]: fields=["width","height","base","capital"]
	elif kind in ["Floor","Roof section","Foundation","Balcony","Porch","Stairs"]: fields=["width","length","height","depth"]
	if kind in ["Railing","Balcony","Porch"]: fields.append_array(["spacing","rails"])
	if kind=="Stairs": fields.append("steps")
	if kind=="Door": fields.append("angle")
	for field: String in fields:
		var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text=field.capitalize(); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		var number:=DragNumber.new(); number.min_value=-170. if field=="angle" else (0. if field in ["base","capital"] else .01); number.max_value=170. if field=="angle" else (80. if field=="steps" else (6. if field=="rails" else 50.)); number.step=1. if field in ["steps","rails"] else .05; number.custom_minimum_size.x=85; number.set_value_no_signal(float(item.parameters.get(field,0.))); row.add_child(number)
		var setter:=func(value: float): Components.set_parameter(workspace.session,item.id,field,value)
		number.value_changed.connect(setter); number.drag_committed.connect(setter)
	if kind in ["Column","Pillar"]:
		var shape:=OptionButton.new(); parent.add_child(shape)
		for name in ["Round","Square","Octagonal"]: shape.add_item(name)
		shape.select(int(item.parameters.get("shape",0))); shape.item_selected.connect(func(index: int): Components.set_parameter(workspace.session,item.id,"shape",index))
	var editable:=Button.new(); editable.text="Make editable mesh"; parent.add_child(editable); editable.pressed.connect(func():
		var current: KiwiModelComponent=workspace.session.document.component(item.id)
		if current!=null: workspace.session.action("Make architecture editable",func(): current.generator=""))
	return true
