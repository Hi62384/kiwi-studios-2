class_name KiwiEnvironmentSession
extends KiwiModelSession
## Legacy state and typed/default API retained during schema/caller migration.
var _terrain_stroke: Dictionary={}
var _scatter_stroke: Dictionary={}
func _native_environment() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_session")
func _init() -> void: document=KiwiEnvironmentDocument.new()
func environment() -> KiwiEnvironmentDocument: return _native_environment().call("environment",self)
func commit(label: String) -> void: _native_environment().call("commit",self,label)
func _signature(data: KiwiModelDocument) -> int: return _native_environment().call("signature",data)
func add_terrain() -> KiwiModelComponent: return _native_environment().call("add_terrain",self)
func add_group(name: String="Group") -> KiwiModelComponent: return _native_environment().call("add_group",self,name)
func selected_environment() -> KiwiEnvironmentDocument: return _native_environment().call("selected_environment",self)
func insert_environment(source: KiwiEnvironmentDocument,origin: Vector3=Vector3.ZERO) -> String: return _native_environment().call("insert_environment",self,source,origin)
func place_asset(path: String,point: Vector3,normal: Vector3=Vector3.UP,align: bool=false) -> String: return _native_environment().call("place_asset",self,path,point,normal,align)
func add_scatter(terrain_id: String,asset: String) -> String: return _native_environment().call("add_scatter",self,terrain_id,asset)
func promote_scatter(layer_id: String,identity: String,placement: Dictionary) -> String: return _native_environment().call("promote_scatter",self,layer_id,identity,placement)
func duplicate_selected(preview: bool=false) -> void: _native_environment().call("duplicate_selected",self,preview)
func begin_scatter(id: String) -> bool: return _native_environment().call("begin_scatter",self,id)
func paint_scatter(point: Vector2,radius: float,erase: bool) -> void: _native_environment().call("paint_scatter",self,point,radius,erase)
func _apply_scatter_regions(id: String,paint: Array[Vector3],erase: Array[Vector3]) -> void: _native_environment().call("apply_scatter_regions",self,id,paint,erase)
func finish_scatter(cancelled: bool=false) -> void: _native_environment().call("finish_scatter",self,cancelled)
func begin_terrain(id: String,material: bool=false) -> bool: return _native_environment().call("begin_terrain",self,id,material)
func sculpt(center: Vector2,radius: float,amount: float,falloff: float,operation: int,flatten: float=0.,options: Dictionary={}) -> void: _native_environment().call("sculpt",self,center,radius,amount,falloff,operation,flatten,options)
func patch_editable(id: String,samples: Dictionary) -> void: _native_environment().call("patch_editable",self,id,samples)
func apply_terrain(id: String,samples: Dictionary,material: bool=false) -> void: _native_environment().call("apply_terrain",self,id,samples,material)
func finish_terrain(cancelled: bool=false) -> void: _native_environment().call("finish_terrain",self,cancelled)
func regenerate_terrain(id: String,settings: Dictionary,reset_edits: bool=false) -> void: _native_environment().call("regenerate_terrain",self,id,settings,reset_edits)
func delete_selected() -> String: return _native_environment().call("delete_selected",self)
