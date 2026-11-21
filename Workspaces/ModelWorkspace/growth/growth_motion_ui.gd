extends RefCounted
static func open(editor: ActorTimelineEditor,actor: ActorData,owner: Node) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","growth_physics").call("open",editor,actor,owner)
