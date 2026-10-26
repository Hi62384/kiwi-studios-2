class_name KiwiTransformationSession
extends RefCounted
signal changed
var document := KiwiTransformationImage2D.blank()
var selected: Array[String]=[]
var edit_states: Dictionary={}
var selected_keys: Array[String]=[]
var playhead := 0.
var dirty := true
var revision := 0
var undo_stack: Array[Dictionary]=[]
var redo_stack: Array[Dictionary]=[]
var pending: Dictionary={}
var clipboard: Array[KiwiTransformationComponent]=[]
var state_clipboard: KiwiTransformationState
var message := ""
var pixel_mask: Image
var pixel_reference: Dictionary={}
func restore_view_state(saved: Dictionary) -> void:
	selected.clear(); edit_states.clear()
	var selection: Variant=saved.get("selected",[])
	if selection is Array or selection is PackedStringArray:
		for id in selection:
			if id is String and document.component(id)!=null and not selected.has(id): selected.append(id)
	var states: Variant=saved.get("states",{})
	if states is Dictionary:
		for component in document.components:
			var id: Variant=states.get(component.id,"")
			if id is String and component.state_for_id(id)!=null: edit_states[component.id]=id
	var time: Variant=saved.get("time",0.)
	playhead=clampf(float(time),0,document.duration) if (time is float or time is int) and is_finite(float(time)) else 0.
	if selected.is_empty() and not document.components.is_empty(): selected.append(document.components[0].id)
func primary() -> KiwiTransformationComponent: return document.component(selected.back()) if not selected.is_empty() else null
func active_state(item: KiwiTransformationComponent=null) -> KiwiTransformationState:
	if item==null: item=primary()
	if item==null: return null
	var state := item.state_for_id(str(edit_states.get(item.id,item.default_state_id)))
	return state if state!=null else item.state_for_id(item.default_state_id)
func snapshot() -> Dictionary: return {"document":document.snapshot(),"selected":selected.duplicate(),"states":edit_states.duplicate(),"keys":selected_keys.duplicate(),"mask":pixel_mask,"pixel_reference":pixel_reference.duplicate()}
func restore(state: Dictionary) -> void:
	document=state.document.snapshot(); selected.assign(state.selected); edit_states=state.states.duplicate(); selected_keys.assign(state.keys); pixel_mask=state.get("mask"); pixel_reference=state.get("pixel_reference",{}).duplicate(); changed.emit()
func begin() -> void:
	if pending.is_empty(): pending=snapshot()
func cancel() -> void:
	if pending.is_empty(): return
	var previous := pending; pending={}; restore(previous)
func commit(label: String) -> void:
	if pending.is_empty(): return
	undo_stack.append({"before":pending,"after":snapshot(),"label":label}); pending={}; redo_stack.clear()
	while undo_stack.size()>40: undo_stack.pop_front()
	# History shares immutable artwork. Bound unique retained raster memory too,
	# rather than treating a 4K stroke as cheap as a tiny component rename.
	while undo_stack.size()>1 and history_bytes()>268435456: undo_stack.pop_front()
	revision+=1; dirty=true; changed.emit()
func history_bytes() -> int:
	var seen := {}; var bytes := 0
	for component in document.components:
		for state in component.states:
			for texture in [state.artwork.texture,state.artwork.paint_base]:
				if texture!=null: seen[texture.get_instance_id()]=true
	if pixel_mask!=null: seen[pixel_mask.get_instance_id()]=true
	for event in document.component_events:
		if event.get("mask") is Texture2D: seen[event.mask.get_instance_id()]=true
	for entry in undo_stack:
		for state in [entry.before,entry.after]:
			for event in state.document.component_events:
				if event.get("mask") is Texture2D and not seen.has(event.mask.get_instance_id()): seen[event.mask.get_instance_id()]=true; bytes+=event.mask.get_width()*event.mask.get_height()*4
			for component in state.document.components:
				for definition in component.states:
					for texture in [definition.artwork.texture,definition.artwork.paint_base]:
						if texture==null or seen.has(texture.get_instance_id()): continue
						seen[texture.get_instance_id()]=true; bytes+=texture.get_width()*texture.get_height()*4
			var mask: Image=state.get("mask")
			if mask!=null and not seen.has(mask.get_instance_id()): seen[mask.get_instance_id()]=true; bytes+=mask.get_width()*mask.get_height()*4
	return bytes
func action(label: String, operation: Callable) -> void: begin(); operation.call(); commit(label)
func undo() -> void:
	if not pending.is_empty(): cancel(); return
	if undo_stack.is_empty(): return
	var entry: Dictionary=undo_stack.pop_back(); redo_stack.append(entry); dirty=true; revision+=1; restore(entry.before)
func redo() -> void:
	if redo_stack.is_empty(): return
	var entry: Dictionary=redo_stack.pop_back(); undo_stack.append(entry); dirty=true; revision+=1; restore(entry.after)
func select(id: String, additive: bool=false) -> void:
	if not additive: selected.clear()
	if not id.is_empty():
		if selected.has(id): selected.erase(id)
		else: selected.append(id)
	changed.emit()
func add_component() -> KiwiTransformationComponent:
	var item := KiwiTransformationImage2D.make_component(document.canvas_size,"Drawing "+str(document.components.size()+1))
	action("Add component",func(): document.components.append(item); selected.assign([item.id])); return item
func delete_components() -> void:
	if selected.is_empty(): return
	action("Delete components",func():
		document.components=document.components.filter(func(item: KiwiTransformationComponent): return not selected.has(item.id) or item.locked)
		document.component_events.assign(document.component_events.filter(func(event: Dictionary): return document.component(event.target)!=null and Array(event.sources).all(func(id: String): return document.component(id)!=null)))
		selected.clear())
func copy_components() -> void:
	clipboard.clear()
	for item in document.components:
		if selected.has(item.id): clipboard.append(item.copy_component())
func paste_components() -> void:
	if clipboard.is_empty(): return
	action("Paste components",func():
		selected.clear()
		for item in clipboard:
			var copy := item.copy_component(true); copy.title+=" copy"; document.components.append(copy); selected.append(copy.id))
func duplicate_components() -> void: copy_components(); paste_components()
func reorder(id: String, target: int) -> void:
	var item := document.component(id)
	if item==null or item.locked: return
	var old := document.components.find(item); target=clampi(target,0,document.components.size()-1)
	if old==target: return
	action("Reorder component",func(): document.components.remove_at(old); document.components.insert(target,item))
func add_state(blank: bool=false) -> KiwiTransformationState:
	var item := primary(); var current := active_state()
	if item==null or item.locked: return null
	var state := current.copy_state(true); state.title="State "+str(item.states.size()+1)
	if blank:
		var art := KiwiImageLayer.create("basic",Vector2i(item.base_size)); art.id=item.id; art.position=current.artwork.position; art.dimensions=current.artwork.dimensions; state.artwork=art; state.title="Empty"
	action("Create state",func(): item.states.append(state); edit_states[item.id]=state.id); return state
func delete_state() -> void:
	var item := primary(); var state := active_state()
	if item==null or item.locked or item.states.size()<2: message="Keep at least one state per component."; return
	# Removing a reusable definition also removes its instances, in one undo.
	action("Delete state and its keys",func():
		item.states.erase(state); item.keys.assign(item.keys.filter(func(key: KiwiTransformationKey): return key.state_id!=state.id)); edit_states[item.id]=item.states[0].id
		if item.default_state_id==state.id: item.default_state_id=item.states[0].id)
func key_at(item: KiwiTransformationComponent, at: float) -> KiwiTransformationKey:
	for key in item.keys:
		if absf(key.time-at)<.00001: return key
	return null
func insert_key() -> void:
	var item := primary(); var state := active_state()
	if item==null or item.locked: return
	action("Insert state key",func():
		var key := key_at(item,playhead)
		if key==null: key=KiwiTransformationKey.new(); key.id=ActorData.new_id(); key.time=playhead; item.keys.append(key)
		key.state_id=state.id; selected_keys.assign([key.id]))
func delete_keys() -> void:
	if selected_keys.is_empty(): return
	action("Delete state keys",func():
		for item in document.components:
			if not item.locked: item.keys.assign(item.keys.filter(func(key: KiwiTransformationKey): return not selected_keys.has(key.id)))
		selected_keys.clear())
func duplicate_keys() -> void:
	if selected_keys.is_empty(): return
	action("Duplicate state keys",func():
		var chosen: Array[String]=[]
		for item in document.components:
			if item.locked: continue
			for key in item.keys.duplicate():
				if not selected_keys.has(key.id): continue
				var time := minf(document.duration,key.time+.1)
				while key_at(item,time)!=null and time<document.duration: time+=.001
				if time>document.duration or key_at(item,time)!=null: continue
				var copy: KiwiTransformationKey=key.copy_key(true); copy.time=time; item.keys.append(copy); chosen.append(copy.id)
		selected_keys.assign(chosen))
func set_duration(value: float) -> void:
	var longest := 0.
	for item in document.components:
		for key in item.keys: longest=maxf(longest,key.time)
	for event in document.component_events: longest=maxf(longest,float(event.time))
	action("Animation duration",func(): document.duration=maxf(maxf(.05,value),longest); playhead=minf(playhead,document.duration))
func sampled(item: KiwiTransformationComponent, time: float) -> Dictionary:
	var keys := item.sorted_keys(); var left: KiwiTransformationKey; var right: KiwiTransformationKey
	if keys.is_empty(): return {"a":item.state_for_id(item.default_state_id),"b":item.state_for_id(item.default_state_id),"t":0.,"key":null}
	left=keys[0]; right=left
	for key in keys:
		if key.time<=time: left=key; right=key
		elif key.time>time: right=key; break
	if time<keys[0].time: left=keys[0]; right=left
	var weight := clampf((time-left.time)/maxf(.000001,right.time-left.time),0,1) if right!=left else 0.
	if left.mode=="Step": weight=0.
	return {"a":item.state_for_id(left.state_id),"b":item.state_for_id(right.state_id),"t":0. if left.mode=="Step" else left.progress(weight),"key":left}
