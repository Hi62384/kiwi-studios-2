class_name ActorInspector
extends VBoxContainer
## Inspector fields are generated from the selected actor's definition.

const IMAGE_FILE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "hdr", "exr"]

signal ui_state_changed

var model: ActorTimeline
var registry: ActorRegistry
var fields := VBoxContainer.new()
var _actor: ActorData
var _syncing: bool = false
var _updaters: Array[Callable] = []
var hints: RefCounted
var ui_state: ActorInspectorState
var _restoring_scroll: bool = false
var _rebuild_queued: bool = false
var _animation_layout_signature: String = ""
var property_batch := ActorPropertyBatch.new()
var _inspecting_file := false
var _file_selection := ""
var content_scroll := ScrollContainer.new()
var main_tabs := HBoxContainer.new()
var section_scroll := ScrollContainer.new()
var section_tabs := VBoxContainer.new()
var identity_fields := VBoxContainer.new()
var _sections: Dictionary = {}
var _main_buttons: Dictionary = {}
var _main_tab := "Properties"
var _section := ""
var _navigation_revision := 0
var _resource_depth:=0
var _empty_section: Label

# Preserve the inspector's existing scrolling interface for scene integrations.
var scroll_vertical: int:
	get: return content_scroll.scroll_vertical
	set(value): content_scroll.scroll_vertical = value

func get_v_scroll_bar() -> VScrollBar: return content_scroll.get_v_scroll_bar()
func get_h_scroll_bar() -> HScrollBar: return content_scroll.get_h_scroll_bar()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Some file validators use an inspector without mounting its UI.
		for control in [fields, content_scroll, main_tabs, section_scroll, section_tabs, identity_fields]:
			if is_instance_valid(control) and control.get_parent() == null: control.free()


func setup(document: ActorTimeline, types: ActorRegistry, state: ActorInspectorState = null) -> void:
	_native_inspector().setup(self,document,types,state)

func _build_navigation() -> void:
	_native_inspector().build_navigation(self)

func _style_navigation_button(button: Button, side: bool) -> void:
	_native_inspector().style_navigation_button(button,side)

func _clear_fields() -> void:
	_native_inspector().clear_fields(self)

func _section_page(title: String, main_tab: String) -> VBoxContainer:
	return _native_inspector().section_page(self,title,main_tab)

func _save_page_scroll() -> void:
	_native_inspector().save_page_scroll(self)

func select_main_tab(title: String) -> void:
	_native_inspector().select_main_tab(self,title)

func select_section(title: String) -> void:
	_native_inspector().select_section(self,title)

func _apply_navigation() -> void:
	_native_inspector().apply_navigation(self)

static func _property_main_tab(property: ActorProperty) -> String:
	return _native_inspector().property_main_tab(property)

func _edit_property(actor: ActorData, _definition: ActorDefinition, key: StringName, value: Variant) -> void:
	property_batch.edit(actor, key, value)

func _preview_property(actor: ActorData, _definition: ActorDefinition, key: StringName, value: Variant) -> void:
	property_batch.preview(actor, key, value)

func _commit_property_preview(actor: ActorData, _definition: ActorDefinition, key: StringName, original: Variant, value: Variant) -> void:
	property_batch.finish(actor, key, original, value)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and get_global_rect().has_point(event.position):
		FocusableKeyInput.set_focused_instance(null)


func _inspect_media(path: String) -> bool:
	return _native_inspector().inspect_media(self,path)

func inspect_file_resource(path: String) -> void:
	_native_inspector().inspect_file_resource(self,path)

func _add_file_object_value(object: ActorObjectData, definition: ActorObjectDefinition,
		property: ActorProperty, parent: VBoxContainer, save_owner: ActorObjectData = null) -> void:
	_native_inspector().add_file_object_value(self,object,definition,property,parent,save_owner)

func _assign_file_object_value(object: ActorObjectData,key: StringName,value: Variant,root: ActorObjectData) -> void:
	_native_inspector().assign_file_object_value(self,object,key,value,root)

func _add_file_object_reference(object: ActorObjectData,property: ActorProperty,parent: VBoxContainer,root: ActorObjectData) -> void:
	_native_inspector().add_file_object_reference(self,object,property,parent,root)

func _add_file_shader_uniforms(object: ActorObjectData, parent: VBoxContainer) -> void:
	_native_inspector().add_file_shader_uniforms(self,object,parent)

func _add_file_shader_uniform_value(object: ActorObjectData, parent: VBoxContainer,
		uniform_name: StringName, value: Variant, default_value: Variant, info: Dictionary) -> void:
	_native_inspector().add_file_shader_uniform_value(self,object,parent,uniform_name,value,default_value,info)

func refresh() -> void:
	_native_inspector().refresh(self)

func _add_transformation_editor(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> void:
	_native_inspector().add_transformation_editor(self,property,definition,parent)

func _add_skeleton_editor(actor: ActorData) -> void:
	_native_inspector().add_skeleton_editor(self,actor)

func _prepare_buttons() -> void:
	_native_inspector().prepare_buttons(self)

func _font_editor(parent: Control, value: String, commit: Callable) -> Button:
	return _native_inspector().font_editor(self,parent,value,commit)

func _label(text: String) -> void:
	_add_label(fields, text)


func _add_label(parent: Control, text: String) -> void:
	_native_inspector().add_label(parent,text)

func _category(text: String, _actor_data: ActorData, main_tab: String = "Properties") -> VBoxContainer:
	return _section_page(text, main_tab)


func _stateful_category(text: String, state_id: String, parent: VBoxContainer,
		state_key: String = "") -> VBoxContainer:
	return _native_inspector().stateful_category(self,text,state_id,parent,state_key)

func _scroll_changed(value: float) -> void:
	_native_inspector().scroll_changed(self,value)

func _restore_scroll(actor_id: String, revision: int = -1) -> void:
	await get_tree().process_frame
	_native_inspector().restore_scroll(self,actor_id,revision)

func _number(value: float, step: float) -> SpinBox:
	return _native_inspector().number(self,value,step)

func _number_editor(parent: Control, value: float, property: ActorProperty) -> DragNumber:
	return _native_inspector().number_editor(self,parent,value,property)

func _set_number_silent(input: DragNumber, value: float) -> void:
	_native_inspector().set_number_silent(input,value)

func _choice_editor(parent: Control, property: ActorProperty, selected: int) -> OptionButton:
	return _native_inspector().choice_editor(parent,property,selected)

func _add_property(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> void:
	_native_inspector().add_property(self,property,definition,parent)

func _add_object_reference(property: ActorProperty, actor_definition: ActorDefinition,
		parent: VBoxContainer) -> void:
	_native_inspector().add_object_reference(self,property,actor_definition,parent)

func _add_image_object_preview(object: ActorObjectData, parent: VBoxContainer) -> void:
	_native_inspector().add_image_object_preview(self,object,parent)

func _add_image_editor_button(parent: VBoxContainer, object: ActorObjectData) -> void:
	_native_inspector().add_image_editor_button(self,parent,object)

func _open_image_workspace(value: Variant) -> void:
	_native_inspector().open_image_workspace(self,value)

func _object_menu_action(id: int, actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition,
		creatable_definitions: Array[ActorObjectDefinition]) -> void:
	_native_inspector().object_menu_action(self,id,actor,null,actor_definition,property,object_definition,creatable_definitions)

func _choose_object_resource(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition,from_clipboard: bool=false) -> void:
	var path := await ActorProjectFilePicker.pick(self, _object_picker_property(property),
		"Choose " + object_definition.display_name,from_clipboard)
	if path==ActorProjectFilePicker.EMPTY_RESOURCE:
		_edit_property(actor,actor_definition,property.id,null); _rebuild_selected(); return
	if path.is_empty():
		return
	_assign_object_resource_path(actor, actor_definition, property, path)


func _file_path_allowed(path: String, property: ActorProperty) -> bool:
	return _native_inspector().file_path_allowed(self,path,property)

func _add_actor_reference(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> void:
	_native_inspector().add_actor_reference(self,property,definition,parent)

func _actor_reference_candidate(property: ActorProperty, candidate: ActorData) -> bool:
	return _native_inspector().actor_reference_candidate(self,property,candidate)

func _add_file_resource_slot(parent: Control, property: ActorProperty,
		get_value: Callable, set_value: Callable, expand_action: Callable = Callable(),
		workspace_parameters: Callable = Callable()) -> void:
	_native_inspector().add_file_resource_slot(self,parent,property,get_value,set_value,expand_action,workspace_parameters)

func _shader_texture_options() -> Dictionary:
	return _native_inspector().shader_texture_options()

func _noise_object_from_value(value: Variant) -> ActorObjectData:
	return _native_inspector().noise_object_from_value(self,value)

func _add_shader_texture_uniform(parent: VBoxContainer, property: ActorProperty,
		get_value: Callable, set_value: Callable, actor: ActorData = null,
		file_owner: ActorObjectData = null) -> void:
	_native_inspector().add_shader_texture_uniform(self,parent,property,get_value,set_value,actor,file_owner)

func _file_resource_menu_action(id: int, property: ActorProperty, get_value: Callable,
		set_value: Callable, update_slot: Callable) -> void:
	if id in [1,7]:
		var path:=await ActorProjectFilePicker.pick(self,property,"Choose "+property.label,id==7)
		if path==ActorProjectFilePicker.EMPTY_RESOURCE: set_value.call(null)
		else: _native_inspector().picked_file_resource(self,property,set_value,path)
	elif id==3: await _save_file_resource(property,get_value.call(),set_value)
	else: _native_inspector().file_resource_menu_action(self,id,property,get_value,set_value)
	update_slot.call()

func _file_resource_type_name(property: ActorProperty) -> String:
	return _native_inspector().file_resource_type_name(property)

func _is_shader_property(property: ActorProperty) -> bool:
	return _native_inspector().is_shader_property(property)

func _is_mesh_property(property: ActorProperty) -> bool:
	return _native_inspector().is_mesh_property(property)

func _file_resource_display_name(value: Variant) -> String:
	return _native_inspector().file_resource_display_name(value)

func _file_resource_tooltip(value: Variant) -> String:
	return _native_inspector().file_resource_tooltip(value)

func _file_resource_to_embedded(value: Variant, property: ActorProperty) -> Resource:
	return _native_inspector().file_resource_to_embedded(value,property)

func _save_file_resource(property: ActorProperty, value: Variant, set_value: Callable) -> void:
	var plan: Dictionary=_native_inspector().prepare_file_save(property,value)
	if plan.is_empty(): return
	var result:=await ActorProjectResourceSaveDialog.pick(self,plan.title,plan.suggested,plan.extension,plan.embed,plan.formats,value)
	var request: Dictionary=_native_inspector().begin_file_save(self,property,value,set_value,result)
	if request.is_empty(): return
	var success: bool=await ActorMediaExport.write_async(self,request.value,request.path,property) if request.media else _write_file_resource(request.value,request.path)
	_native_inspector().finish_file_save(self,property,set_value,request,success)

func _write_file_resource(value: Variant, path: String) -> bool:
	return _native_inspector().write_file_resource(value,path)

func _open_shader_resource(value: Variant, full_workspace: bool = false, parameters: Variant = null) -> void:
	_native_inspector().open_shader_resource(self,value,full_workspace,parameters)

func _shader_code_changed(_source: Variant) -> void:
	# Shader code can change both the rendered program and the list/defaults of
	# uniforms, so refresh the runtime and reconstruct the nested inspector.
	model.changed.emit()
	call_deferred("_rebuild_selected")


func _same_value(left: Variant, right: Variant) -> bool:
	return _native_inspector().same_value(left,right)

func _add_keyframe_button(parent: Control, actor: ActorData, property: ActorProperty,
		path: PackedStringArray, fallback: Variant = null) -> void:
	_native_inspector().add_keyframe_button(self,parent,actor,property,path,fallback)

func _object_resource_path_allowed(path: String, property: ActorProperty) -> bool:
	return _native_inspector().object_resource_path_allowed(self,path,property)

func _property_accepts_image(property: ActorProperty) -> bool:
	return _native_inspector().property_accepts_image(property)

func _is_raw_image_path(path: String) -> bool:
	return _native_inspector().is_raw_image_path(path)

func _object_picker_property(property: ActorProperty) -> ActorProperty:
	return _native_inspector().object_picker_property(property)

func _assign_object_resource_path(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, path: String) -> void:
	_native_inspector().assign_object_resource_path(self,actor,actor_definition,property,path)

func _save_object_resource(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition, object: ActorObjectData) -> void:
	await _save_actor_object_driver(actor,null,actor_definition,property,object_definition,object)

func _create_project_file(property: ActorProperty, title: String) -> String:
	var plan: Dictionary=_native_inspector().prepare_project_file(property)
	if plan.is_empty(): return ""
	var result:=await ActorProjectResourceSaveDialog.pick(self,title,plan.suggested,plan.extension,false)
	return _native_inspector().finish_project_file(property,result)

func _resolve_object(reference: ActorObjectReference) -> ActorObjectData:
	return _native_inspector().resolve_object(reference)

func _rebuild_selected() -> void:
	_actor = null
	refresh()


func _queue_rebuild_selected() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_finish_queued_rebuild")


func _finish_queued_rebuild() -> void:
	_rebuild_queued = false
	_rebuild_selected()


func refresh_shader_source(_source: Variant) -> void:
	# Shader code can add/remove uniforms and linked tabs can alter their values.
	# Rebuild the selected actor while retaining its inspector viewport state.
	_rebuild_selected()


func _resource_box() -> StyleBoxFlat:
	return _native_inspector().resource_box()

func _property_is_visible(property: ActorProperty, owner: Object) -> bool:
	return _native_inspector().property_is_visible(self,property,owner)

func _animated_layout_signature(actor: ActorData) -> String:
	return _native_inspector().animated_layout_signature(self,actor)

func _add_nested_object_reference(actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		parent: VBoxContainer) -> void:
	_native_inspector().add_nested_object_reference(self,actor,owner,owner_definition,property,parent)

func _nested_object_menu_action(id: int, actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		object_definition: ActorObjectDefinition,
		creatable_definitions: Array[ActorObjectDefinition]) -> void:
	_native_inspector().object_menu_action(self,id,actor,owner,owner_definition,property,object_definition,creatable_definitions)

func _assign_nested_object_resource_path(path: String, actor: ActorData,
		owner: ActorObjectData, owner_definition: ActorObjectDefinition,
		property: ActorProperty) -> void:
	_native_inspector().assign_nested_object_resource_path(self,path,actor,owner,owner_definition,property)

func _save_nested_object_resource(actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		object_definition: ActorObjectDefinition, object: ActorObjectData) -> void:
	await _save_actor_object_driver(actor,owner,owner_definition,property,object_definition,object)

func _animated_object_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty) -> Variant:
	return _native_inspector().animated_object_value(self,actor,object,definition,property)

func shader_workspace_parameter_binding(actor_id: String, object_path: PackedStringArray,
		origin_actor: ActorData = null) -> Dictionary:
	var origin_history: UndoRedo = model.history
	var reader:=func() -> Dictionary: return _native_inspector().read_shader_binding(self,actor_id,object_path,origin_actor)
	var writer:=func(name: StringName,value: Variant,mode: String,original: Variant): _native_inspector().write_shader_binding(self,actor_id,object_path,origin_actor,origin_history,name,value,mode,original)
	return {"values":reader.call(),"reader":reader,"writer":writer}

func _edit_detached_shader_uniform(object: ActorObjectData, definition: ActorObjectDefinition,
		history: UndoRedo, name: StringName, value: Variant, mode: String, original: Variant) -> void:
	_native_inspector().edit_detached_shader_uniform(self,object,definition,history,name,value,mode,original)

func _set_detached_object_property(object: ActorObjectData, key: StringName, value: Variant) -> void:
	_native_inspector().set_detached_object_property(object,key,value)

func _add_natural_material_editor(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer,
		save_owner: ActorObjectData = null) -> void:
	_native_inspector().add_natural_material_editor(self,actor,object,definition,property,parent,save_owner)

func _add_object_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer) -> void:
	_native_inspector().add_object_value(self,actor,object,definition,property,parent)

func _add_shader_uniforms(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, parent: VBoxContainer) -> void:
	_native_inspector().add_shader_uniforms(self,actor,object,definition,parent)

func _shader_uniform_layout(shader: Shader, parent: VBoxContainer, state_id: String, scope: String) -> Array[Dictionary]:
	return _native_inspector().shader_uniform_layout(self,shader,parent,state_id,scope)

func _shader_from_value(value: Variant) -> Shader:
	return _native_inspector().shader_from_value(value)

func _shader_uniform_default(shader: Shader, uniform_name: StringName, value_type: int) -> Variant:
	return _native_inspector().shader_uniform_default(shader,uniform_name,value_type)

func _add_shader_uniform_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, parent: VBoxContainer, uniform_name: StringName,
		value: Variant, default_value: Variant, info: Dictionary) -> void:
	_native_inspector().add_shader_uniform_value(self,actor,object,definition,parent,uniform_name,value,default_value,info)

static func _native_inspector() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("actor_inspector")

func _run_inspector_updaters() -> void:
	for update in _updaters:
		update.call()

func _add_special_property(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> bool:
	return _native_inspector().add_special_property(self,property,definition,parent)

func _add_property_file_slot(parent: Control, property: ActorProperty, actor: ActorData, definition: ActorDefinition) -> void:
	_native_inspector().add_property_file_slot(self,parent,property,actor,definition)

func _add_powder_preset_browser(parent: VBoxContainer, actor: ActorData) -> void:
	var browser:=preload("res://scripts/actors/physics/powder/PowderMaterialControl.cs").new()
	parent.add_child(browser)
	browser.setup(model,actor,_queue_rebuild_selected)

func _invoke_font_commit(callback: Callable, family: String) -> void:
	callback.call(family)

func _configure_object_slot(slot: ActorResourceSlot, property: ActorProperty) -> void:
	slot.accepts_file=_object_resource_path_allowed.bind(property)

func _dispatch_object_menu(id: int, actor: ActorData, owner: ActorObjectData, owner_definition: Resource, property: ActorProperty, definition: ActorObjectDefinition, choices: Array) -> void:
	_native_inspector().object_menu_action(self,id,actor,owner,owner_definition,property,definition,choices)

func _add_special_object_value(actor: ActorData, object: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer) -> bool:
	return _native_inspector().add_special_object_value(self,actor,object,definition,property,parent)

func _add_object_file_slot(actor: ActorData, object: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer) -> void:
	_native_inspector().add_object_file_slot(self,actor,object,definition,property,parent)

func _add_object_font(actor: ActorData, object: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer) -> void:
	_native_inspector().add_object_font(self,actor,object,definition,property,parent)

func _add_uniform_texture_slot(actor: ActorData, object: ActorObjectData, definition: ActorObjectDefinition, parent: VBoxContainer, uniform_name: StringName, title: String) -> void:
	_native_inspector().add_uniform_texture_slot(self,actor,object,definition,parent,uniform_name,title)

func _add_special_file_value(object: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer, save_owner: ActorObjectData) -> bool:
	return _native_inspector().add_special_file_value(self,object,definition,property,parent,save_owner)

func _add_saved_object_file_slot(object: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer, save_owner: ActorObjectData) -> void:
	_native_inspector().add_saved_object_file_slot(self,object,definition,property,parent,save_owner)

func _add_file_uniform_texture(object: ActorObjectData, parent: VBoxContainer, uniform_name: StringName, title: String) -> void:
	_native_inspector().add_file_uniform_texture(self,object,parent,uniform_name,title)

func _configure_file_slot_validation(slot: ActorResourceSlot, property: ActorProperty) -> void:
	slot.accepts_file=_file_path_allowed.bind(property)

func _pick_transformation_asset(actor: ActorData, property: ActorProperty) -> void:
	var path:=await ActorProjectFilePicker.pick(self,property,"Choose Transformation Image 2D")
	if path==ActorProjectFilePicker.EMPTY_RESOURCE: _native_inspector().assign_transformation_asset(self,actor,property,"")
	elif not path.is_empty(): _native_inspector().assign_transformation_asset(self,actor,property,path)

func _selection_requested() -> void:
	_native_inspector().selection_requested(self)

func _emit_ui_state_changed() -> void:
	ui_state_changed.emit()

func _invoke_inspector_callback(callback: Callable, args: Array) -> Variant:
	return callback.callv(args) if callback.is_valid() else null

func _make_model_unique(get_value: Callable, set_value: Callable) -> void:
	var plan: Dictionary=_native_inspector().prepare_model_unique(self,get_value)
	if plan.is_empty(): return
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Make model unique",plan.suggested,"tres",false)
	_native_inspector().finish_model_unique(self,set_value,plan,result)

func _pick_file_reference(object: ActorObjectData, property: ActorProperty, root: ActorObjectData, clipboard: bool) -> void:
	var path:=await ActorProjectFilePicker.pick(self,_object_picker_property(property),"Choose "+property.label,clipboard)
	_native_inspector().load_file_reference(self,object,property,root,path)

func _pick_actor_object_resource(actor: ActorData, owner: ActorObjectData, definition: Resource, property: ActorProperty, object_definition: ActorObjectDefinition, clipboard: bool) -> void:
	var path:=await ActorProjectFilePicker.pick(self,_object_picker_property(property),"Choose "+object_definition.display_name,clipboard)
	_native_inspector().actor_object_resource_chosen(self,actor,owner,definition,property,path)

func _save_actor_object_driver(actor: ActorData, owner: ActorObjectData, definition: Resource, property: ActorProperty, object_definition: ActorObjectDefinition, object: ActorObjectData) -> void:
	var plan: Dictionary=_native_inspector().prepare_object_save(actor,property,object_definition,object)
	var result:=await ActorProjectResourceSaveDialog.pick(self,plan.title,plan.suggested,"tres",true,plan.formats,object)
	var request: Dictionary=_native_inspector().begin_object_save(self,actor,owner,definition,property,object,result)
	if request.is_empty(): return
	var success:=await ActorMediaExport.write_async(self,request.value,request.path,property)
	_native_inspector().finish_object_save(self,actor,owner,definition,property,request,success)
