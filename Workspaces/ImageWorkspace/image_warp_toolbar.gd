extends RefCounted
## Contextual controls and bake operation, separate from canvas gesture logic.
const Number=preload("res://Workspaces/SceneWorkspace/scripts/Timeline/DragNumber.cs")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")

static func build(workspace:KiwiImageWorkspace)->void:_native().warp_build(workspace)

static func setting_slider(workspace:KiwiImageWorkspace,caption:String,value:float,setter:Callable)->void:_native().warp_setting_slider(workspace,caption,value,setter)

static func bake(workspace:KiwiImageWorkspace)->void:_native().warp_bake(workspace)

static func _bake_confirmed(workspace:KiwiImageWorkspace,id:String)->void:
 var request:Dictionary=_native().prepare_warp_bake(workspace,id)
 if request.is_empty():return
 var image:Image=await request.renderer.flattened()
 _native().complete_warp_bake(workspace,request,image)

static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_workspace_ui")
static func _set_slider(callback:Callable,value:float)->void:callback.call(value)
