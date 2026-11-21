extends RefCounted
# Static typed compatibility surface; controls and source edits are native.
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_ui").properties(workspace,item,parent)
static func appearance(workspace: Control,id: String,key: String,value: Variant) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_ui").appearance(workspace,id,key,value)
static func branches(workspace: Control,id: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_ui").branches(workspace,id)
static func change_branch(workspace: Control,id: String,identity: String,key: String,value: Variant) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_ui").change_branch(workspace,id,identity,key,value)
