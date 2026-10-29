extends RefCounted
## Froxel sampling is renderer-wide, never a fake per-volume quality slider.
const PRESETS:=[Vector2i(64,32),Vector2i(128,64),Vector2i(192,96),Vector2i(256,128)]
const NAMES:=["Fast","Balanced","Detailed","Final render"]
static func apply(values: Dictionary) -> void:
	RenderingServer.environment_set_volumetric_fog_volume_size(clampi(int(values.get("size",ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size",64))),32,256),clampi(int(values.get("depth",ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth",64))),16,128))
	RenderingServer.environment_set_volumetric_fog_filter_active(bool(values.get("filter",true)))
static func attach(tabs: Node) -> void:
	var button:=tabs.get_node_or_null("../HBoxContainer/EditorButton") as Button
	if button==null: return
	apply(StaticData.loaded_project.fog_rendering if StaticData.loaded_project!=null else {})
	button.pressed.connect(func(): show_menu(button,tabs))
static func assign(project: Project,values: Dictionary) -> void:
	project.fog_rendering=values.duplicate(); apply(values)
	var tree:=Engine.get_main_loop() as SceneTree
	if tree!=null:
		for tabs in tree.get_nodes_in_group("actor_scene_tabs"): apply_scene_shadow(tabs)
	if not project.resource_path.is_empty(): ResourceSaver.save(project,project.resource_path)
static func apply_scene_shadow(tabs: Node) -> void:
	if tabs.timeline==null or not is_instance_valid(tabs.timeline.runtime_holder): return
	var viewport: Viewport=tabs.timeline.runtime_holder.get_viewport()
	if not viewport.has_meta("kiwi_original_shadow_atlas"): viewport.set_meta("kiwi_original_shadow_atlas",viewport.positional_shadow_atlas_size)
	var project:=StaticData.loaded_project
	if project!=null: viewport.positional_shadow_atlas_size=int(project.fog_rendering.get("shadow_atlas",viewport.get_meta("kiwi_original_shadow_atlas")))
static func edit(tabs: Node,values: Dictionary) -> void:
	var project:=StaticData.loaded_project
	if project==null or tabs.timeline==null: return
	var before:=project.fog_rendering.duplicate(); var model: ActorTimeline=tabs.timeline.model
	model.history.create_action("Project volumetric rendering quality"); model.history.add_do_method(assign.bind(project,values.duplicate())); model.history.add_undo_method(assign.bind(project,before)); model.history.commit_action()
static func show_menu(button: Button,tabs: Node) -> void:
	var project:=StaticData.loaded_project
	if project==null: return
	var popup:=PopupPanel.new(); popup.name="FogRenderingSettings"; button.add_child(popup); popup.popup_hide.connect(popup.queue_free)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",8); popup.add_child(column)
	var title:=Label.new(); title.text="Volumetric rendering · Project"; column.add_child(title)
	var caption:=Label.new(); caption.text="Sampling applies to every viewport. Light and environment\nproperties remain in their actor inspectors."; caption.add_theme_font_size_override("font_size",12); column.add_child(caption)
	var row:=HBoxContainer.new(); column.add_child(row)
	for index in NAMES.size():
		var preset:=Button.new(); preset.text=NAMES[index]; row.add_child(preset)
		preset.pressed.connect(func(): var v:=project.fog_rendering.duplicate(); v.merge({"size":PRESETS[index].x,"depth":PRESETS[index].y,"filter":true},true); edit(tabs,v); popup.hide())
	for key in ["size","depth"]:
		var line:=HBoxContainer.new(); column.add_child(line); var label:=Label.new(); label.text="Fog resolution" if key=="size" else "Depth resolution"; label.tooltip_text="Higher sampling detail improves light shafts and uses more GPU time and memory. Applies renderer-wide."; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; line.add_child(label)
		var input:=DragNumber.new(); input.min_value=32 if key=="size" else 16; input.max_value=256 if key=="size" else 128; input.step=1.; input.value=float(project.fog_rendering.get(key,ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_"+key,64))); line.add_child(input)
		var preview:=func(value: float): var v:=project.fog_rendering.duplicate(); v[key]=int(value); apply(v)
		var commit:=func(value: float): var v:=project.fog_rendering.duplicate(); v[key]=int(value); edit(tabs,v)
		input.value_changed.connect(commit); input.preview_changed.connect(preview); input.drag_committed.connect(commit); input.drag_cancelled.connect(func(): apply(project.fog_rendering))
	var filter:=CheckButton.new(); filter.text="Filter volumetric samples"; filter.button_pressed=project.fog_rendering.get("filter",true); column.add_child(filter); filter.toggled.connect(func(enabled: bool): var v:=project.fog_rendering.duplicate(); v.filter=enabled; edit(tabs,v))
	var shadow_row:=HBoxContainer.new(); column.add_child(shadow_row); var shadow_label:=Label.new(); shadow_label.text="Scene shadow maps"; shadow_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; shadow_row.add_child(shadow_label)
	var atlas:=OptionButton.new(); shadow_row.add_child(atlas); var sizes:=[1024,2048,4096,8192]
	for value: int in sizes: atlas.add_item(str(value))
	var current:=int(project.fog_rendering.get("shadow_atlas",2048)); atlas.select(maxi(0,sizes.find(current))); atlas.tooltip_text="Omni/spot shadow atlas for the scene viewport and camera previews. Higher resolution uses more GPU memory."
	atlas.item_selected.connect(func(index: int): var v:=project.fog_rendering.duplicate(); v.shadow_atlas=sizes[index]; edit(tabs,v))
	popup.position=Vector2i(button.get_screen_position()+Vector2(0,button.size.y)); popup.popup()
