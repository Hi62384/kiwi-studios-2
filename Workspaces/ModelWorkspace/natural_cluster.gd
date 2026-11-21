extends RefCounted
## Editable ordinary component groups; generated children retain stable IDs and
## manually edited child geometry/poses across procedural regeneration.
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
const PRESETS={"Boulder field":"Rock / Granite","River stones":"Rock / River stone","Rockfall":"Rock / Slate","Forest grove":"Tree / Oak","Grass patch":"Plant / Grass","Deadwood":"Prop / Driftwood"}
static func kinds() -> Array: return Engine.get_singleton("KiwiNativeServices").call("service","natural_cluster").kinds()
static func accepts(item: Resource) -> bool: return Engine.get_singleton("KiwiNativeServices").call("service","natural_cluster").accepts(item)
static func add(session: KiwiModelSession,kind: String,parameters: Dictionary,position: Vector3) -> KiwiModelComponent: return Engine.get_singleton("KiwiNativeServices").call("service","natural_cluster").add(session,kind,parameters,position)
static func regenerate(session: KiwiModelSession,root: KiwiModelComponent) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_cluster").regenerate(session,root)
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_cluster").properties(workspace,item,parent)
