class_name KiwiPhysicsMeshSnapshot
extends RefCounted
## Explicit, bounded conversion to a normal reusable mesh. Simulation/source data
## is never overwritten. The saved mesh uses world coordinates at this playhead.
const MAX_VERTICES:=150000
static func capture(editor: ActorTimelineEditor,actor: ActorData,deposits_only: bool=false) -> Dictionary:
	return _native_snapshot().capture(editor,actor,deposits_only)

static func prompt(owner: Node,model: ActorTimeline,actor: ActorData,deposits_only: bool=false) -> void:
	var native:=_native_snapshot()
	var result: Dictionary=native.prompt_prepare(owner,model,actor,deposits_only)
	if result.get("missing",false): return
	if str(result.error).is_empty():
		var destination:=await ActorProjectResourceSaveDialog.pick(owner,"Save evaluated mesh",actor.display_name+" Mesh","tres",false,PackedStringArray(["tres"]),result.mesh)
		result=native.prompt_finish(result,destination)
		if result.get("done",false): return
	native.show_error(owner,str(result.error))


static func _native_snapshot() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","physics_mesh_snapshot")
