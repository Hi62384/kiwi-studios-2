class_name KiwiCompositeGraph
extends Resource
const GraphNodeNative=preload("res://Workspaces/CompositingWorkspace/CompositeGraphNode.cs")
const GraphConnectionNative=preload("res://Workspaces/CompositingWorkspace/CompositeGraphConnection.cs")
@export var id:=ActorData.new_id()
@export var name:="Main Graph"
@export var nodes: Array[Resource]=[]
@export var connections: Array[Resource]=[]
@export var output_node:=""
# Temporary binary-resource behavior bridge; algorithms are implemented in C#.
const GraphNative=preload("res://Workspaces/CompositingWorkspace/CompositeGraph.cs")
func node(id: String) -> Resource:
	return GraphNative.new().node_resource(self,id)
func validate() -> PackedStringArray:
	return GraphNative.new().validate_resource(self)
func compile_errors() -> PackedStringArray:
	return GraphNative.new().compile_errors_resource(self)
