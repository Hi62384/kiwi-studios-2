class_name KiwiImageCanvas
extends Control
## Canvas navigation and gestures. One gesture produces one history entry.

signal selection_changed
signal gesture_started
signal gesture_changed
signal gesture_finished
signal gesture_cancelled
signal create_requested(kind: String, bounds: Rect2, points: PackedVector2Array)
signal duplicate_requested
signal text_edit_requested
signal files_dropped(paths: PackedStringArray, at: Vector2)
signal color_sampled(color: Color)
signal hint_changed(message: String)
signal brush_size_changed(value: float)
signal correction_scale_changed(value: float)
signal threshold_changed(value: float)
signal polygon_committed(points: PackedVector2Array)

var document: KiwiImageDocument
var preview: Texture2D
var preview_screen_space:=false
var selected: Array[String] = []
var tool := "move"
var zoom := 0.7
var pan := Vector2.ZERO
var snapping := true
var snap_guides_x: Array[float]=[]
var snap_guides_y: Array[float]=[]
var color := Color("62d9bc")
var _value_inverse_key: int=0
var _value_inverse_color:=Color.WHITE
var _value_mask: Image
var _value_mask_mapping:=Transform2D.IDENTITY

func _prepare_source_color() -> void:
 _native_selection().prepare_source_color(self)

func _source_color(point: Vector2) -> Color:
 return _native_selection().source_color(self,point)

var painting_mode:="color"
var material_strength:=1.0
var _material_region: KiwiLivePaintRegion
var _material_template_id:=""
var _material_bake_after:=false
var _material_previous_template:=""
var _material_busy:=false
var _material_flood_source: Image
var _material_stroke_anchor:=Vector2.ZERO
var _material_direction_set:=false
var _material_stamps: RefCounted
var _live_eraser: RefCounted
var brush_size := 28.0
var hardness := 0.8
var brush_opacity := 1.0
var fill_threshold := 0.08
var brush_mode := "freehand"
var brush_type:="normal"
var soften_strength:=.5
var _soften_source: Image
var _soften_opaque:=false
var stroke_correct: bool:
    get: return brush_type=="stroke_correct"
    set(value):
        if value: brush_type="stroke_correct"
        elif brush_type=="stroke_correct": brush_type="normal"
var correction_strength := 0.5
var correction_scale := 1.0
var _erase_modifier:=false
var _corrector: KiwiStrokeCorrector
var _corrected_tail_bounds:=Rect2i()
var _ink_origin:=Vector2i.ZERO
var _corrected_stamp_distance:=0.0
var _corrected_started:=false
var _corrected_all_bounds:=Rect2i()
var paint_new_layer := false
var selection: Image
var selection_transform:=Transform2D.IDENTITY
var selection_inverse:=Transform2D.IDENTITY
var selection_forward_warp: Callable
var selection_inverse_warp: Callable
var _selection_mapping:RefCounted
var selection_preview_origin:=Vector2.ZERO
var _selection_preview_size:=Vector2.ZERO
var selection_texture: ImageTexture
var pixel_selection_bounds := Rect2()
var path_layer_id: String=""
var pixel_mode: String="brush"
var pixel_box_select:=false
var _pixel_area_base: Image
var _pixel_area_previous:=Rect2i()
var pixel_match_all:=false
var edge_magnet:=false
var edge_threshold:=.4
var object_threshold:=.5
var smart_selection:=KiwiPixelSelectionEngine.new()
var _edge_follower:=KiwiPixelEdgeMagnet.new()
var _edge_preview:=Vector2.INF
var _smart_base: Image
var _smart_seed:=Vector2.ZERO
var _object_committed: Dictionary={}
var _pan_previous_drag:=""
var _edge_motion_pending:=false
var _edge_motion_point:=Vector2.ZERO
var _edge_hover_pending:=false
var _smart_request:=-1
var _smart_subtract:=false
var _smart_ready:=false
var _smart_has_proposal:=false
var _smart_apply_when_ready:=false
var paint_selection_only:=false
var _polygon_before:=PackedVector2Array()
var _polygon_index: int=-1
var _selection_overlay:=TextureRect.new()
var warp_tool:=preload("res://Workspaces/ImageWorkspace/image_warp_interaction.gd").new()
var repair_tool:=preload("res://Workspaces/ImageWorkspace/image_repair_interaction.gd").new()
var pixel_source: Image
var selection_alpha:=1.0
var selection_falloff:=0.0
var _pixel_alpha_base: Image
var _pixel_alpha_ink: Image
var _pixel_alpha_stamp: Image
var _pixel_alpha_stamp_key:=""
var pixel_domain:=Rect2i()
var _drag := ""
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _mouse := Vector2.ZERO
var _bounds := Rect2()
var _resize_grab_offset:=Vector2.ZERO
var _resize_proxy_active:=false
var _resize_proxy_screen:=Vector2.ZERO
var _originals: Array[Dictionary] = []
var _points := PackedVector2Array()
var _paint_image: Image
var _paint_data := PackedByteArray()
var _paint_layer: KiwiImageLayer
var _stroke_base: Image
var _stroke_points := PackedVector2Array()
var _paint_created_layer := false
var _selection_operation := 0
var _moved := false
var _vertex_index := -1
var _pending_single := ""
var _active_mode := "freehand"
var _shape_end := Vector2.ZERO
var _shape_control := Vector2.ZERO
var _shape_control_end:=Vector2.ZERO
var _shape_grab_offset:=Vector2.ZERO
var _circle_profiles:=Vector4(2,2,2,2)
var _shape_handle := -1
var _stamp: Image
var _stamp_key := ""
var _stroke_ink: Image
var _stroke_dirty:=Rect2i()


func _ready() -> void:
 _native_selection().ready(self)

func _process(_delta: float) -> void:
 _native_selection().process(self,_delta)

func _sync_selection_overlay() -> void:
 _native_selection().sync_selection_overlay(self)

func origin() -> Vector2:
 return _native_selection().origin(self)

func to_document(point: Vector2) -> Vector2:
 return _native_selection().to_document(self,point)

func fit() -> void:
 _native_selection().fit(self)

func set_zoom(value: float, anchor: Vector2 = Vector2(-1,-1)) -> void:
 _native_selection().set_zoom(self,value,anchor)

func selection_bounds() -> Rect2:
 return _native_selection().selection_bounds(self)

func _draw() -> void:
 _native_selection().draw(self)

func _projected_handles(rect: Rect2) -> Array[Vector2]:
 var result: Array[Vector2]=[]
 result.assign(_native_selection().projected_handles(self,rect))
 return result

func _raw_handles(rect: Rect2) -> Array[Vector2]:
 var result: Array[Vector2]=[]
 result.assign(_native_selection().raw_handles(rect))
 return result

func _handles(rect: Rect2) -> Array[Vector2]:
 var result: Array[Vector2]=[]
 result.assign(_native_selection().handles(self,rect))
 return result

func _rotation_handle(rect: Rect2) -> Vector2:
 return _native_selection().rotation_handle(self,rect)

func hit(point: Vector2) -> KiwiImageLayer:
 return _native_selection().hit(self,point)

func _input_canvas(event: InputEvent) -> void:
 _native_selection().input_canvas(self,event)

func _begin_transform(action: String) -> void:
 _native_selection().begin_transform(self,action)

func _transform(point: Vector2, constrained: bool, control: bool=false) -> void:
 _native_selection().transform(self,point,constrained,control)

func _resize_single(point: Vector2, index: int, constrained: bool, use_snap: bool) -> void:
 _native_selection().resize_single(self,point,index,constrained,use_snap)

func _finish(point: Vector2) -> void:
 var request: Dictionary=_native_selection().prepare_finish(self,point)
 if request.is_empty(): return
 if request.bake:
  await repair_tool.workspace.renderer.bake_live_material(_material_template_id)
 _native_selection().complete_finish(self,request)

func cancel_gesture() -> void:
 _native_selection().cancel_gesture(self)

func finish_path() -> void:
 _native_selection().finish_path(self)

func _begin_paint(point: Vector2) -> void:
 var request: Dictionary=_native_selection().prepare_paint(self,point)
 if request.is_empty(): return
 if request.source:
  var source: Image=await repair_tool.workspace.renderer.source_image(request.item)
  if not _native_selection().accept_paint_source(self,request,source): return
 _native_selection().begin_paint(self,point,request)

func _shape_path() -> PackedVector2Array:
 return _native_selection().shape_path(self)

func _shape_handles() -> Array[Vector2]:
 var result: Array[Vector2]=[]
 result.assign(_native_selection().shape_handles(self))
 return result

func _shape_screen_handle(point: Vector2) -> Vector2:
 return _native_selection().shape_screen_handle(self,point)

func _move_shape_handle(point: Vector2,constrained: bool) -> void:
 _native_selection().move_shape_handle(self,point,constrained)

func _constrain_shape_point(point: Vector2,constrained: bool) -> Vector2:
 return _native_selection().constrain_shape_point(self,point,constrained)

func confirm_stroke() -> void:
 _native_selection().confirm_stroke(self)

func selected_pixel(point: Vector2) -> bool:
 return _native_selection().selected_pixel(self,point,selection_inverse_warp.is_valid())

func selection_coverage(point: Vector2) -> float:
 return _native_selection().selection_coverage(self,point,selection_inverse_warp.is_valid())

func _paint_pixel_allowed(point: Vector2) -> bool:
 return _native_selection().paint_pixel_allowed(self,point,selection_inverse_warp.is_valid())

func _set_erase_modifier(enabled: bool) -> void:
 _native_selection().set_erase_modifier(self,enabled)

func _corrected_path_bounds(path: PackedVector2Array) -> Rect2i:
 return _native_selection().corrected_path_bounds(self,path)

func _paint_corrected_path(path: PackedVector2Array,commit: bool=false) -> void:
 _native_selection().paint_corrected_path(self,path,commit)

func _flush_corrected_stroke() -> void:
 _native_selection().flush_corrected_stroke(self)

func _paint_line(from: Vector2,to: Vector2,upload: bool=true) -> void:
 _native_selection().paint_line(self,from,to,upload)

func _upload_paint() -> void:
 _native_selection().upload_paint(self)

func _upload_native_paint() -> void:
 _native_selection().upload_native_paint(self)

func _replace_paint_texture() -> void:
 _native_selection().replace_paint_texture(self)

func _update_paint_texture() -> void:
 _native_selection().update_paint_texture(self)

func _paint_curve(from: Vector2,control: Vector2,to: Vector2) -> void:
 _native_selection().paint_curve(self,from,control,to)

func _curve_control(from: Vector2,to: Vector2) -> Vector2:
 return _native_selection().curve_control(self,from,to)

func _flood(point: Vector2) -> void:
 _native_selection().flood(self,point)

func canvas_threshold_bytes(value: float) -> float:
 return _native_selection().threshold_bytes(value)

func _make_selection(kind: String,rect: Rect2) -> void:
 _native_selection().make_selection(self,kind,rect)

func clear_selection() -> void:
 _native_selection().clear_selection(self)

func sync_pixel_selection()->void:_native_selection().sync_pixel_selection(self)

func _update_selection_preview() -> void:
 _native_selection().update_selection_preview(self)

func _update_warped_selection_preview() -> void:
 _native_selection().update_warped_selection_preview(self)

static func _selection_projection(corners: PackedVector2Array) -> Array[Vector3]:
 var result: Array[Vector3]=[]
 result.assign(_native_selection().selection_projection(corners))
 return result

func bake_selection_transform() -> void:
 _native_selection().bake_selection_transform(self)

func _begin_pixel_selection(point: Vector2,lasso: bool=false) -> void:
 _native_selection().begin_pixel_selection(self,point,lasso)

func _update_pixel_box(point: Vector2) -> void:
 _native_selection().update_pixel_box(self,point)

func _apply_pixel_lasso(coverage_only: bool=false) -> void:
 _native_selection().apply_pixel_lasso(self,coverage_only)

func _flush_edge_motion() -> void:
 _native_selection().flush_edge_motion(self)

func _pixel_brush_line(from: Vector2,to: Vector2) -> void:
 _native_selection().pixel_brush_line(self,from,to)

func prepare_smart_selection() -> void:
 _native_selection().prepare_smart_selection(self)

func set_object_threshold(value: float) -> void:
 _native_selection().set_object_threshold(self,value)

func commit_object_selection() -> void:
 _native_selection().commit_object_selection(self)

func _smart_proposed(mask: Image,kind: String,request: int) -> void:
 _native_selection().smart_proposed(self,mask,kind,request)

func _request_smart_mask(kind: String,point: Vector2,threshold: float,width: float=1) -> int:
 return _native_selection().request_smart_mask(self,kind,point,threshold,width)

func _pixel_flood(start: Vector2i) -> void:
 _native_selection().pixel_flood(self,start)

func _pixel_alpha_path(path: PackedVector2Array) -> void:
 _native_selection().pixel_alpha_path(self,path)

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
 return _native_selection().can_drop_data(data)

func _snap_polygon_point(at: Vector2, control: bool=false) -> Vector2:
 return _native_selection().snap_polygon_point(self,at,control)

func _polygon_insert(at: Vector2) -> int:
 return _native_selection().polygon_insert(self,at)

func _drop_data(at: Vector2,data: Variant) -> void:
 _native_selection().drop_data(self,at,data)

func _material_flood(point: Vector2) -> void:
 _native_selection().material_flood(self,point)

static func _native_selection()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_canvas_selection")

func _has_selection_warp(inverse: bool=false) -> bool:
 return selection_inverse_warp.is_valid() if inverse else selection_forward_warp.is_valid()

func _map_selection_point(point: Vector2,inverse: bool=false) -> Vector2:
 if inverse: return selection_inverse_warp.call(point) if selection_inverse_warp.is_valid() else selection_inverse*point
 return selection_forward_warp.call(point) if selection_forward_warp.is_valid() else selection_transform*point
