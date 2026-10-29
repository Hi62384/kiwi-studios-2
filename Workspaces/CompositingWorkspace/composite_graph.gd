class_name KiwiCompositeGraph
extends Resource
@export var id:=ActorData.new_id()
@export var name:="Main Graph"
@export var nodes: Array[KiwiCompositeGraphNode]=[]
@export var connections: Array[KiwiCompositeGraphConnection]=[]
@export var output_node:=""
func node(id: String) -> KiwiCompositeGraphNode:
	for item in nodes:
		if item.id==id: return item
	return null
func validate() -> PackedStringArray:
	var errors:=PackedStringArray(); var ids:={}
	for item in nodes:
		if item==null or item.id.is_empty() or ids.has(item.id): errors.append("Graph node IDs must be present and unique."); continue
		ids[item.id]=true
	var edges:={}
	for edge in connections:
		if edge==null or node(edge.from_node)==null or node(edge.to_node)==null: errors.append("A graph connection refers to a missing node."); continue
		var source_node:=node(edge.from_node); var destination_node:=node(edge.to_node); var source:=KiwiCompositeGraphNode.port_type(source_node.kind,edge.from_port); var destination:=KiwiCompositeGraphNode.port_type(destination_node.kind,edge.to_port)
		if not KiwiCompositeGraphNode.has_output(source_node.kind,edge.from_port) or not KiwiCompositeGraphNode.has_input(destination_node.kind,edge.to_port) or source==&"" or destination==&"" or source!=destination: errors.append("A graph connection has incompatible port types."); continue
		if edge.to_port in ["image","foreground","background","mask","depth"] and connections.any(func(other: KiwiCompositeGraphConnection): return other!=edge and other.to_node==edge.to_node and other.to_port==edge.to_port): errors.append("An input port can only have one connection.")
		if not edges.has(edge.from_node): edges[edge.from_node]=[]
		edges[edge.from_node].append(edge.to_node)
	var visiting:={}; var visited:={}
	for item in nodes:
		if _cycle(item.id,edges,visiting,visited): errors.append("Ordinary graph cycles are not supported."); break
	if not output_node.is_empty() and (node(output_node)==null or node(output_node).kind!="Output"): errors.append("Choose a valid Output node.")
	return errors

func compile_errors() -> PackedStringArray:
	var errors:=validate()
	if output_node.is_empty(): errors.append("The graph has no Output node.")
	for item in nodes:
		if item==null: continue
		for port in _required_inputs(item.kind):
			if not connections.any(func(edge: KiwiCompositeGraphConnection): return edge.to_node==item.id and edge.to_port==port): errors.append("Node '%s' is missing its '%s' input."%[item.kind,port])
	return errors

func _required_inputs(kind: String) -> Array[String]:
	match kind:
		"Over","Merge": return ["foreground","background"]
		"Color Grade","Alpha Extract","Blur","Chroma Key","Luma Key","Output": return ["image"]
		"Mask": return ["image","mask"]
		"Depth Compare": return ["image","depth"]
	return []
func _cycle(id: String,edges: Dictionary,visiting: Dictionary,visited: Dictionary) -> bool:
	if visiting.has(id): return true
	if visited.has(id): return false
	visiting[id]=true
	for next: String in edges.get(id,[]):
		if _cycle(next,edges,visiting,visited): return true
	visiting.erase(id); visited[id]=true; return false
