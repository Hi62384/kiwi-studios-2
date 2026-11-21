extends RefCounted
signal settings_changed
var canvas: Control
var engine:=preload("res://Workspaces/ImageWorkspace/image_repair_engine.gd").new()
var workspace: Control
var mode:="spot"
var main_mode:="repair"
var repair_source:="nearby"
var repair_method:="natural"
var texture_source:="procedural"
var material: KiwiTextureMaterial
var material_instances: Dictionary={}
var custom_materials: Dictionary={}
var mode_settings: Dictionary={}
var favorites:=PackedStringArray()
var recent:=PackedStringArray()
var _material_generation:=0
var _editable_texture:=false
var _coverage_base: Image
var _fill_bounds:=Rect2i()
var _fill_mask: Image
var config: Dictionary={"size":40.0,"hardness":.3,"strength":1.0,"opacity":1.0,"selection_only":true,"aligned":true,"sample_mode":"current","source_mode":"nearby","sample_shape":"rectangle","sample_size":64.0,"healing_blend":"texture","texture_preservation":1.0,"patch_size":16,"quality":1,"search_radius":3,"variation":.3,"scale":1.0,"rotation":0.0,"offset":Vector2.ZERO,"spacing":0.0,"density":1.0,"random_rotation":15.0,"random_scale":.15,"color_variation":.1,"seed":0,"layout":"tiled","behavior":"exact","new_layer":false,"clip_alpha":false}
var recipe:=KiwiImageTextureRecipe.new()
var active:=false
var ending:=false
var sampling:=false
var source_area:=Rect2i()
var source_point:=Vector2.ZERO
var sample_document_point:=Vector2.ZERO
var source_image: Image
var source_points:=PackedVector2Array()
var pattern_path:=""
var _owner: KiwiImageLayer
var _document: KiwiImageDocument
var _original: Image
var _editing: Image
var _points:=PackedVector2Array()
var _last:=Vector2.ZERO
var _anchor:=Vector2.ZERO
var _aligned_offset:=Vector2.ZERO
var _has_alignment:=false
var _area:=Rect2i()
var _latest:=0
var _completed:=0
var _changed:=false
var _pending:=false
var _sample_start:=Vector2.ZERO
var _generation_target:=""
var _generation_document: KiwiImageDocument
var _generation_sequence:=0
var _sample_down:=false
var _cached_procedural: Image
var _procedural_key:=0
var _selection: Image
var _pressures:=PackedFloat32Array()
var _layer_mask: Image
var selection_preview:=false
var _patch_drag:=false
var _patch_rect:=Rect2i()
var _repair_new_layer:=false
var _stroke_source_anchor:=Vector2.ZERO
var _selected_before: Array[String]=[]
var pick_source:=false
var _sample_region_dragged:=false

func initialize(studio: Control) -> void:
 _native().initialize(self,studio)

func settings() -> Dictionary:
 return _native().settings(self)

func restore_settings(state: Dictionary) -> void:
 _native().restore_settings(self,state)

func layer() -> KiwiImageLayer:
 return _native().layer(self)

func to_pixel(document_point: Vector2,item: KiwiImageLayer) -> Vector2:
 return _native().to_pixel(self,document_point,item)

func to_screen(pixel: Vector2,item: KiwiImageLayer) -> Vector2:
 return _native().to_screen(self,pixel,item)

func sample_source(document_point: Vector2) -> void:
 if not _native().prepare_sample(self,document_point): return
 var item:=layer()
 var document: KiwiImageDocument=workspace.document
 workspace.renderer.sync(document)
 if config.sample_mode=="group" and not item.parent_id.is_empty(): source_image=await workspace._render_layers([item.parent_id])
 else: source_image=await workspace.renderer.flattened()
 if workspace.document!=document: return
 source_point=document_point
 _native().complete_sample(self,document_point)

func handle(event: InputEvent) -> bool:
 return _native().handle(self,event)

func begin(item: KiwiImageLayer,point: Vector2,fill: bool=false) -> void:
 _native().begin(self,item,point,fill)

func process() -> void:
 _native().process(self)

func _queue(fill: bool=false,final: bool=false) -> void:
 _native().queue(self,fill,final)

func finish() -> void:
 _native().finish(self)

func cancel() -> void:
 _native().cancel(self)

func _on_preview(result: Dictionary) -> void:
 _native().on_preview(self,result)

func _on_idle() -> void:
 _native().on_idle(self)

func fill_selection() -> void:
 var item: KiwiImageLayer=_native().prepare_fill(self)
 if item==null: return
 var document: KiwiImageDocument=canvas.document
 var local_mask: Texture2D=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(workspace,item)
 if not _native().accept_fill_mask(self,item,document,local_mask): return
 if main_mode=="texture" and source_image==null: await refresh_material()
 _native().complete_fill(self,item)

func refresh_selection_preview() -> void:
 _native().refresh_selection_preview(self)

func configure(key: String,value: Variant) -> void:
 _native().configure(self,key,value)

func choose_material(id: String) -> void:
 _native().choose_material(self,id)

func switch_mode(next: String) -> void:
 _native().switch_mode(self,next)

func apply_material_settings(live: bool=false) -> void:
 _native().apply_material_settings(self,live)

func refresh_material() -> void:
 var request: Dictionary=_native().prepare_material(self)
 if request.is_empty(): return
 var result: Image=await preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").preview(canvas,request.value,request.size,request.extent,request.frame)
 _native().complete_material(self,request,result)

func begin_patch_source(at: Vector2,item: KiwiImageLayer) -> void:
 _native().begin_patch_source(self,at,item)

func generate(target_id: String="") -> void:
 _native().generate(self,target_id)

func draw() -> void:
 _native().draw(self)

static func NAMES_MODE_LABEL(kind: String) -> String: return kind.replace("_"," ").capitalize()

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_repair_interaction")

func _has_selection_inverse() -> bool:
 return canvas.selection_inverse_warp.is_valid()

func _selection_forward_point(point: Vector2) -> Vector2:
 return canvas.selection_forward_warp.call(point) if canvas.selection_forward_warp.is_valid() else canvas.selection_transform*point
