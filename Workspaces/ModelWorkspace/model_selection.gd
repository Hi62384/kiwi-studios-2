class_name KiwiModelSelection
extends RefCounted
## Connectivity-based selections use a fixed frontier for each grow/shrink step.
static func expand(mesh: KiwiModelMesh, mode: String, selected: PackedInt32Array, operation: String) -> PackedInt32Array:
	var edges := mesh.edges(); var graph := {}; var count := mesh.vertices.size() if mode=="Vertex" else (edges.size() if mode=="Edge" else mesh.faces.size())
	for i in count: graph[i]={}
	if mode=="Vertex":
		for edge in edges: graph[edge.a][edge.b]=true; graph[edge.b][edge.a]=true
	elif mode=="Face":
		for edge in edges:
			for a in edge.faces:
				for b in edge.faces:
					if a!=b: graph[a][b]=true
	else:
		var incident := {}
		for i in edges.size():
			for vertex in [edges[i].a,edges[i].b]:
				if not incident.has(vertex): incident[vertex]=[]
				incident[vertex].append(i)
		for vertex in incident:
			for a in incident[vertex]:
				for b in incident[vertex]:
					if a!=b: graph[a][b]=true
	var used := {}
	for i in selected:
		if i>=0 and i<count: used[i]=true
	if operation=="Shrink selection":
		var original := used.duplicate()
		for i in selected:
			for neighbor in graph.get(i,{}):
				if not original.has(neighbor): used.erase(i); break
	elif operation=="Select connected":
		var queue := Array(used.keys()); var at := 0
		while at<queue.size():
			var current: int=queue[at]; at+=1
			for neighbor in graph[current]:
				if not used.has(neighbor): used[neighbor]=true; queue.append(neighbor)
	else:
		for i in selected:
			for neighbor in graph.get(i,{}): used[neighbor]=true
	return PackedInt32Array(used.keys())
