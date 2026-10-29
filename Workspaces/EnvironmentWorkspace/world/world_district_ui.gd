extends RefCounted
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const UI=preload("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd")
static func properties(workspace: Control,id: String,source: Resource,parent: Node) -> void:
	if source.settlements.is_empty():
		var empty:=Label.new(); empty.text="Add a settlement to edit districts and blocks."; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(empty); return
	var settlements:=OptionButton.new(); parent.add_child(settlements)
	for settlement: Dictionary in source.settlements: settlements.add_item(str(settlement.name))
	var at:=clampi(int(workspace.get_meta("world_settlement_index",0)),0,source.settlements.size()-1); settlements.select(at); settlements.item_selected.connect(func(index: int): workspace.set_meta("world_settlement_index",index); workspace.set_meta("world_district_index",0); workspace._refresh_properties()); var settlement: Dictionary=source.settlements[at]
	var add:=MenuButton.new(); add.text="＋ District"; add.disabled=settlement.get("districts",[]).size()>=32; parent.add_child(add)
	for category in Districts.CATEGORIES: add.get_popup().add_item(category)
	add.get_popup().id_pressed.connect(func(index: int):
		var next: Resource=Edit.source(workspace.session,id).copy(); var owner: Dictionary=next.settlements[at]; var center: Vector3=owner.center; var radius:=float(owner.radius)*.6; var polygon:=PackedVector2Array([Vector2(center.x-radius,center.z-radius),Vector2(center.x+radius,center.z-radius),Vector2(center.x+radius,center.z+radius),Vector2(center.x-radius,center.z+radius)])
		if not owner.has("districts"): owner.districts=[]
		var district:=Districts.create(Districts.CATEGORIES[index],polygon); district.seed=next.seed; owner.districts.append(district); workspace.set_meta("world_district_index",owner.districts.size()-1); UI.apply(workspace,id,next,"Add city district"))
	var districts: Array=settlement.get("districts",[])
	if not districts.is_empty():
		var choices:=OptionButton.new(); choices.fit_to_longest_item=false; choices.clip_text=true; parent.add_child(choices)
		for district: Dictionary in districts: choices.add_item(str(district.name))
		var index:=clampi(int(workspace.get_meta("world_district_index",0)),0,districts.size()-1); choices.select(index); choices.item_selected.connect(func(value: int): workspace.set_meta("world_district_index",value); workspace._refresh_properties()); var district: Dictionary=districts[index]
		workspace.canvas.set_meta("world_district_selection",{"world":id,"district":district.id}); workspace.canvas.overlay.queue_redraw()
		var name:=LineEdit.new(); name.text=str(district.name); name.placeholder_text="District name"; parent.add_child(name); name.text_submitted.connect(func(text: String): _set_district(workspace,id,at,index,"name",text))
		var boundary:=Button.new(); boundary.text="✎ Edit district boundary"; boundary.tooltip_text="Drag points to move them. Click an edge to insert a point; right-click a point to remove it. Escape cancels a drag."; parent.add_child(boundary); boundary.pressed.connect(func(): workspace.canvas.environment_tool="District boundary"; workspace.canvas.grab_focus(); workspace.canvas.overlay.queue_redraw())
		var enabled:=CheckButton.new(); enabled.text="District enabled"; enabled.button_pressed=bool(district.get("enabled",true)); parent.add_child(enabled); enabled.toggled.connect(func(on: bool): _set_district(workspace,id,at,index,"enabled",on))
		var preset:=OptionButton.new(); parent.add_child(preset)
		for category in Districts.CATEGORIES: preset.add_item(category)
		preset.select(Districts.CATEGORIES.find(str(district.category))); preset.item_selected.connect(func(value: int):
			var next: Resource=Edit.source(workspace.session,id).copy(); var previous: Dictionary=next.settlements[at].districts[index]; var replacement:=Districts.create(Districts.CATEGORIES[value],previous.polygon); replacement.id=previous.id; replacement.name=previous.name; next.settlements[at].districts[index]=replacement; UI.apply(workspace,id,next,"Change district preset"))
		for spec in [["Building density","density",0.,1.,.05],["Minimum floors","height_min",1.,8.,1.],["Maximum floors","height_max",1.,8.,1.],["Lot size","lot_size",10.,64.,1.],["Setback","setback",0.,10.,.25]]:
			workspace._value(parent,spec[0],float(district.get(spec[1],spec[2])),spec[2],spec[3],spec[4],func(value: float): _set_district(workspace,id,at,index,spec[1],value))
		var style:=OptionButton.new(); parent.add_child(style); var names: Array=Districts.STYLES.PRESETS.keys()
		for caption in names: style.add_item(str(caption))
		style.select(maxi(0,names.find(str(district.template.style)))); style.item_selected.connect(func(value: int):
			var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[at].districts[index].template=Districts.STYLES.apply(next.settlements[at].districts[index].template,names[value]); UI.apply(workspace,id,next,"Change district architecture"))
		var vary:=Button.new(); vary.text="⟳ Vary district"; parent.add_child(vary); vary.pressed.connect(func(): _set_district(workspace,id,at,index,"seed",int(district.get("seed",1))+1))
		var remove:=Button.new(); remove.text="Remove district"; parent.add_child(remove); remove.pressed.connect(func():
			var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[at].districts.remove_at(index)
			for override: Dictionary in next.settlements[at].get("block_overrides",{}).values():
				if override.get("district_id","")==district.id: override.erase("district_id")
			UI.apply(workspace,id,next,"Remove city district"))
	var heading:=Label.new(); heading.text="BLOCK OVERRIDES"; parent.add_child(heading); var blocks: Array=[]; var root: KiwiModelComponent=workspace.session.document.component(id)
	for block: Dictionary in root.parameters.get("world_blocks",[]):
		if block.settlement==settlement.id: blocks.append(block)
	if blocks.is_empty(): return
	var block_choice:=OptionButton.new(); parent.add_child(block_choice)
	for number in blocks.size(): block_choice.add_item("Block "+str(number+1)+" · "+str(blocks[number].district))
	var selected:=clampi(int(workspace.get_meta("world_block_index",0)),0,blocks.size()-1); block_choice.select(selected); block_choice.item_selected.connect(func(value: int): workspace.set_meta("world_block_index",value); workspace._refresh_properties()); var block: Dictionary=blocks[selected]; var block_id:=str(block.id); var override: Dictionary=settlement.get("block_overrides",{}).get(block_id,{})
	var assigned:=OptionButton.new(); assigned.add_item("District from boundary"); parent.add_child(assigned)
	for district: Dictionary in districts:
		assigned.add_item(str(district.name))
		if override.get("district_id","")==district.id: assigned.select(assigned.item_count-1)
	assigned.item_selected.connect(func(value: int): _block(workspace,id,at,block_id,"district_id",null if value==0 else districts[value-1].id))
	var reserved:=CheckButton.new(); reserved.text="Keep this block open"; reserved.button_pressed=override.has("density") and float(override.density)==0.; parent.add_child(reserved); reserved.toggled.connect(func(on: bool): _block(workspace,id,at,block_id,"density",0. if on else null))
	var reset:=Button.new(); reset.text="↶ Reset block overrides"; reset.disabled=override.is_empty(); parent.add_child(reset); reset.pressed.connect(func(): var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[at].block_overrides.erase(block_id); UI.apply(workspace,id,next,"Reset block overrides"))
static func _set_district(workspace: Control,id: String,settlement: int,district: int,field: String,value: Variant) -> void:
	var next: Resource=Edit.source(workspace.session,id).copy(); next.settlements[settlement].districts[district][field]=value; UI.apply(workspace,id,next,"Edit district "+field)
static func _block(workspace: Control,id: String,settlement: int,block: String,field: String,value: Variant) -> void:
	var next: Resource=Edit.source(workspace.session,id).copy(); var owner: Dictionary=next.settlements[settlement]
	if not owner.has("block_overrides"): owner.block_overrides={}
	if not owner.block_overrides.has(block): owner.block_overrides[block]={}
	if value==null: owner.block_overrides[block].erase(field)
	else: owner.block_overrides[block][field]=value
	if owner.block_overrides[block].is_empty(): owner.block_overrides.erase(block)
	UI.apply(workspace,id,next,"Edit city block")

