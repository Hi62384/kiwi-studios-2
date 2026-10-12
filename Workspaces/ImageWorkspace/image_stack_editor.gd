extends Window
## Shared searchable library, ordered stack and live GPU preview. Parameters
## reuse the editor's draggable numbers, colors, sliders and undo transactions.
const Math=preload("res://Workspaces/ImageWorkspace/image_values.gd")
const EFFECTS=["mirror","blur","sharpen","shadow","glow","outline","curves","gradient_map","color_replace","grain","pixelate","halftone","chromatic","vignette","wave","twirl","emboss","edge_detect","motion_blur","radial_blur","kaleidoscope","ripple","scanlines"]
const EFFECT_CATEGORIES={
	"Detail & blur":["blur","motion_blur","radial_blur","sharpen","emboss","edge_detect"],
	"Light & outline":["shadow","glow","outline","vignette"],
	"Distortion":["mirror","wave","twirl","ripple","kaleidoscope","chromatic"],
	"Texture & style":["grain","pixelate","halftone","scanlines"],
	"Mapping & custom":["curves","gradient_map","color_replace","shader"]}
const RANGES={"brightness":Vector3(-1,1,0),"contrast":Vector3(0,4,1),"saturation":Vector3(0,4,1),"exposure":Vector3(-6,6,0),"gamma":Vector3(.1,4,1),"hue":Vector3(-PI,PI,0),"temperature":Vector3(-1,1,0),"tint":Vector3(-1,1,0),"red":Vector3(0,4,1),"green":Vector3(0,4,1),"blue":Vector3(0,4,1),"vibrance":Vector3(-1,2,0),"grayscale":Vector3(0,1,1),"sepia":Vector3(0,1,1),"posterize":Vector3(2,32,6),"solarize":Vector3(0,1,.5),"shadows":Vector3(-1,1,0),"highlights":Vector3(-1,1,0),"black_point":Vector3(0,.95,0),"white_point":Vector3(.05,2,1)}
const EXTRA_RANGES={"midtones":Vector3(-1,1,0),"lift":Vector3(-1,1,0),"fade":Vector3(0,1,0),"threshold":Vector3(0,1,.5),"cyan_red":Vector3(-1,1,0),"magenta_green":Vector3(-1,1,0),"yellow_blue":Vector3(-1,1,0),"shadow_warmth":Vector3(-1,1,0),"highlight_warmth":Vector3(-1,1,0),"colorize":Vector3(0,1,.5)}
const CATEGORIES={
	"Light & tone":["brightness","exposure","contrast","gamma","shadows","midtones","highlights","black_point","white_point","lift","fade"],
	"Color & balance":["saturation","vibrance","hue","temperature","tint","cyan_red","magenta_green","yellow_blue","shadow_warmth","highlight_warmth"],
	"Channels":["red","green","blue"],
	"Creative looks":["grayscale","sepia","posterize","solarize","threshold","colorize"],
	"Math":["add","subtract","multiply","divide","power","snap","clamp","lerp","minimum","maximum","absolute","invert","smoothstep"]}
var workspace: KiwiImageWorkspace
var layer_id: String
var adjustments:=false
var search:=LineEdit.new()
var library:=VBoxContainer.new()
var stack:=VBoxContainer.new()
var preview:=preload("res://Workspaces/ImageWorkspace/image_operation_preview.gd").new()
var whole:=false
var _signature:=""
var _category_collapsed: Dictionary={}

func adjustment_range(kind: String) -> Vector3: return EXTRA_RANGES.get(kind,RANGES.get(kind,Vector3(-16,64,1)))

func _ready() -> void:
	title=("Color Adjustments" if adjustments else "Effects & Styles")+" · "+workspace.document.layer_for_id(layer_id).label
	name="AdjustmentStackEditor" if adjustments else "EffectStackEditor"
	transient=true; exclusive=true
	var available:=Vector2i(workspace.get_viewport_rect().size)-Vector2i(48,80)
	size=Vector2i(1250,700).min(available); min_size=Vector2i(680,380).min(available)
	var panel:=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",workspace._box(Color("111b26"),Color("3a5969"),9,12)); add_child(panel)
	var root:=VBoxContainer.new(); root.add_theme_constant_override("separation",10); panel.add_child(root)
	var header:=HBoxContainer.new(); root.add_child(header)
	var heading:=Label.new(); heading.text="COLOR ADJUSTMENTS" if adjustments else "EFFECTS & STYLES"
	heading.add_theme_color_override("font_color",Color("7fe3cd")); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var mode:=OptionButton.new(); mode.add_item("View layer only"); mode.add_item("View whole viewport"); header.add_child(mode)
	mode.item_selected.connect(func(index: int): whole=index==1; preview.pan=Vector2.ZERO; preview.zoom=1)
	workspace._button(header,"Fit",func(): preview.pan=Vector2.ZERO; preview.zoom=1,"Fit preview","fit_layer")
	workspace._button(header,"Done",close_editor,"Keep changes and return to canvas","check")
	var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(split)
	var left:=VBoxContainer.new(); left.custom_minimum_size.x=190; split.add_child(left)
	search.placeholder_text="Search adjustments…" if adjustments else "Search effects…"; search.clear_button_enabled=true; left.add_child(search)
	var browser:=ScrollContainer.new(); browser.size_flags_vertical=Control.SIZE_EXPAND_FILL
	browser.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(browser)
	library.size_flags_horizontal=Control.SIZE_EXPAND_FILL; library.add_theme_constant_override("separation",4); browser.add_child(library)
	search.text_changed.connect(func(_text: String): rebuild_library())
	var right_split:=HSplitContainer.new(); right_split.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(right_split)
	preview.custom_minimum_size=Vector2(180,160); preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL; right_split.add_child(preview)
	var right:=VBoxContainer.new(); right.custom_minimum_size.x=300; right_split.add_child(right)
	var label:=Label.new(); label.text="APPLIED IN ORDER"; label.add_theme_font_size_override("font_size",11); label.add_theme_color_override("font_color",Color("9ab2c1")); right.add_child(label)
	var scroller:=ScrollContainer.new(); scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(scroller)
	stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL; stack.add_theme_constant_override("separation",8); scroller.add_child(stack)
	if not adjustments:
		var styles: Array=[["Copy style",workspace.copy_style],["Paste style",workspace.paste_style],["Save current style…",workspace._save_style]]
		for name: String in workspace._presets:
			var preset:=name; styles.append([name,func(): workspace._apply_style_preset(preset,false)])
		workspace._menu(right,"Style presets",styles)
	close_requested.connect(close_editor)
	if adjustments and entries().any(func(op: Dictionary): return not op.has("a") and op.type in Math.TYPES):
		workspace._action(func():
			var old:=entries()
			for index in old.size():
				var op: Dictionary=old[index]
				if op.has("a") or op.type not in Math.TYPES: continue
				var replacement:=Math.new_operation(op.type); var amount:=float(op.get("amount",1))
				replacement.b.value=1.0/maxf(1,amount) if op.type=="snap" else amount
				replacement.preserve_hue=false; replacement.enabled=op.get("enabled",true); old[index]=replacement)
	if adjustments and not layer().properties.get("value_basics",{}).is_empty():
		# Existing final adjustments keep their ordering when migrated to the
		# new editable stack; rendering and inverse brush-color math stay shared.
		workspace._action(func():
			var basics: Dictionary=layer().properties.value_basics
			for kind in Math.BASICS:
				var amount:=float(basics.get(kind,Math.BASICS[kind]))
				if not is_equal_approx(amount,float(Math.BASICS[kind])): entries().append({"type":kind,"amount":amount,"enabled":true,"id":ActorData.new_id()})
			layer().properties.erase("value_basics"))
	rebuild_library(); rebuild_stack()

func layer() -> KiwiImageLayer: return workspace.document.layer_for_id(layer_id)
func entries() -> Array:
	if adjustments:
		if not layer().properties.has("value_operations"): layer().properties.value_operations=[]
		return layer().properties.value_operations
	return layer().effects

func rebuild_library() -> void:
	workspace._clear(library)
	var groups: Dictionary=CATEGORIES if adjustments else EFFECT_CATEGORIES
	if not groups.is_empty():
		for category: String in groups:
			var matches: Array=[]
			for kind: String in groups[category]:
				if search.text.is_empty() or kind.replace("_"," ").contains(search.text.to_lower()) or category.to_lower().contains(search.text.to_lower()): matches.append(kind)
			if matches.is_empty(): continue
			var section:=VBoxContainer.new(); section.add_theme_constant_override("separation",3); library.add_child(section)
			var header:=workspace._button(section,category,func():
				_category_collapsed[category]=not bool(_category_collapsed.get(category,false)); rebuild_library(),"Expand or collapse "+category)
			header.alignment=HORIZONTAL_ALIGNMENT_LEFT; header.add_theme_color_override("font_color",Color("80d9c4"))
			header.text=("▸ " if _category_collapsed.get(category,false) and search.text.is_empty() else "▾ ")+category
			if _category_collapsed.get(category,false) and search.text.is_empty(): continue
			for kind: String in matches:
				var type:=kind; var caption:="Canvas shader…" if kind=="shader" else kind.replace("_"," ").capitalize()
				var button:=workspace._button(section,caption,func():
					if type=="shader": workspace._choose_shader_effect()
					else: add_entry(type),"Add "+caption,kind)
				button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		return
	var choices: Array=EFFECTS
	for type in choices:
		var kind: String=type; var caption:=kind.replace("_"," ").capitalize()
		if not search.text.is_empty() and not caption.to_lower().contains(search.text.to_lower()): continue
		var button:=workspace._button(library,caption,func(): add_entry(kind),"Add "+caption,kind)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not adjustments and (search.text.is_empty() or "canvas shader".contains(search.text.to_lower())): workspace._button(library,"Canvas shader…",workspace._choose_shader_effect,"Load a canvas shader effect","shader")

func add_entry(kind: String) -> void:
	if adjustments:
		workspace._action(func():
			var op:=Math.new_operation(kind) if kind in Math.TYPES else {"type":kind,"amount":adjustment_range(kind).z,"enabled":true}
			op.id=ActorData.new_id(); entries().append(op))
	else: workspace.add_effect(kind)
	rebuild_stack()

func rebuild_stack() -> void:
	workspace._clear(stack)
	var list:=entries()
	for i in list.size():
		var index:=i; var op: Dictionary=list[i]
		var card:=preload("res://Workspaces/ImageWorkspace/image_operation_row.gd").new()
		card.index=i; card.reorder=func(from: int,to: int): move_entry(from,to)
		card.add_theme_stylebox_override("panel",workspace._box(Color("172735"),Color("355467"),6,7)); stack.add_child(card)
		var fields:=VBoxContainer.new(); fields.mouse_filter=Control.MOUSE_FILTER_PASS; card.add_child(fields)
		var header:=HBoxContainer.new(); fields.add_child(header)
		var enabled:=CheckButton.new(); enabled.text="⠿ %d · %s" % [i+1,str(op.type).replace("_"," ").capitalize()]
		enabled.icon=workspace._icon(op.type); enabled.expand_icon=true; enabled.add_theme_constant_override("icon_max_width",18)
		enabled.add_theme_font_size_override("font_size",12); enabled.button_pressed=op.get("enabled",true); enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(enabled)
		enabled.toggled.connect(func(value: bool): workspace._action(func(): op.enabled=value))
		workspace._button(header,"×",func(): workspace._action(func(): entries().remove_at(index)),"Remove","trash")
		if adjustments:
			if op.has("a"):
				_simple_math_fields(fields,op)
				if op.type=="snap": workspace._check(fields,"Preserve hue",op.get("preserve_hue",true),func(value: bool): op.preserve_hue=value)
			else:
				var limits:=adjustment_range(op.type)
				workspace._slider(fields,"Amount",float(op.get("amount",limits.z)),limits.x,limits.y,func(value: float): op.amount=value)
		else: workspace._effect_fields(fields,op)
		var actions:=HBoxContainer.new(); fields.add_child(actions)
		workspace._button(actions,"↑",func(): move_entry(index,maxi(0,index-1)),"Earlier")
		workspace._button(actions,"↓",func(): move_entry(index,mini(entries().size()-1,index+1)),"Later")
		workspace._button(actions,"Reset",func(): reset_entry(index),"Reset parameters","reset")
		if not adjustments: workspace._button(actions,"Apply",func(): workspace._apply_effect(layer(),index),"Bake effect into pixels","check")
	if list.is_empty():
		var empty:=Label.new(); empty.text="Choose an item from the library."; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; stack.add_child(empty)
	_signature=signature()

func reset_entry(index: int) -> void:
	workspace._action(func():
		var op: Dictionary=entries()[index]
		if adjustments:
			entries()[index]=Math.new_operation(op.type) if op.type in Math.TYPES else {"type":op.type,"amount":adjustment_range(op.type).z,"enabled":true}
		else:
			var replacement:=workspace._new_effect(op.type)
			replacement.id=op.get("id",replacement.id); replacement.enabled=op.get("enabled",true)
			entries()[index]=replacement)
	rebuild_stack()

func _simple_math_fields(parent: Node,op: Dictionary) -> void:
	if op.type in ["absolute","invert"]: return
	var captions: Dictionary={"add":"Amount","subtract":"Amount","multiply":"Factor","divide":"Divisor","power":"Exponent","snap":"Step size","minimum":"Ceiling","maximum":"Floor","clamp":"Minimum","smoothstep":"Lower edge","lerp":"Target value"}
	var limits:=Vector2(-4,4)
	if op.type in ["divide","power"]: limits=Vector2(.01,8)
	elif op.type=="snap": limits=Vector2(.001,1)
	var b: Dictionary=op.get("b",{})
	var value:=float(b.get("value",1)) if b.get("kind","")=="float" else float(Math.operand_value(b,Vector4.ONE).x)
	if op.type=="lerp":
		var rgba:=Math.operand_value(b,Vector4.ONE)
		workspace._color(parent,"Target color",Color(rgba.x,rgba.y,rgba.z,rgba.w),func(next: Color):
			op.a={"kind":"pixel"}; op.b={"kind":"vector","channels":[next.r,next.g,next.b,next.a]})
	else:
		workspace._slider(parent,captions.get(op.type,"Amount"),value,limits.x,limits.y,func(next: float):
			op.a={"kind":"pixel"}; op.b={"kind":"float","value":next})
	if op.type in ["clamp","smoothstep","lerp"]:
		var c: Dictionary=op.get("c",{"kind":"float","value":1.0})
		var second:=float(c.get("value",1)) if c.get("kind","")=="float" else float(Math.operand_value(c,Vector4.ONE).x)
		workspace._slider(parent,"Blend" if op.type=="lerp" else ("Maximum" if op.type=="clamp" else "Upper edge"),second,0 if op.type=="lerp" else -4,1 if op.type=="lerp" else 4,func(next: float):
			op.a={"kind":"pixel"}; op.c={"kind":"float","value":next})

func move_entry(from: int,to: int) -> void:
	if from==to: return
	workspace._action(func(): var item: Dictionary=entries().pop_at(from); entries().insert(to,item))
	rebuild_stack()

func signature() -> String:
	var result:=str(workspace.document.get_instance_id())
	for op in entries(): result+=str(op.get("id",""))+str(op.type)+str(op.has("a"))
	return result

func _process(_delta: float) -> void:
	if layer()==null: close_editor(); return
	if signature()!=_signature: rebuild_stack()
	workspace.renderer.set_composition_preview_enabled(whole)
	if whole: preview.texture=workspace.renderer.composition_texture()
	elif workspace.renderer.views.has(layer_id): preview.texture=workspace.renderer.views[layer_id].output.texture

func close_editor() -> void:
	workspace.renderer.set_composition_preview_enabled(false)
	workspace._finish_pending(); queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode==KEY_Z:
		if event.shift_pressed: workspace.redo()
		else: workspace.undo()
	elif event.ctrl_pressed and event.keycode==KEY_Y: workspace.redo()
	elif event.keycode==KEY_ESCAPE: close_editor()
	else: return
	get_viewport().set_input_as_handled()
