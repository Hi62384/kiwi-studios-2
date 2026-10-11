class_name KiwiPixelObjectSegmenter
extends RefCounted
## Lightweight region graph, not seed-color flood fill. Small coherent regions
## merge across internal color changes, bounded by outlines/alpha/background.
## A replacement model only needs to implement propose(seed, threshold).

var field: KiwiPixelEdgeField
var labels:=PackedInt32Array()
var means:=PackedColorArray()
var areas:=PackedInt32Array()
var graph: Array[Dictionary]=[]
var background: Dictionary={}
var distances:=PackedFloat32Array()
var last_seed: int=-1
var border_regions: Dictionary={}
var background_distances:=PackedFloat32Array()

func build(image: Image,domain: Rect2i) -> void:
	labels.clear(); means.clear(); areas.clear(); graph.clear(); background.clear(); border_regions.clear(); last_seed=-1
	field=KiwiPixelEdgeField.new(); field.build(image,domain,256)
	var size:=field.size; var count:=size.x*size.y
	labels.resize(count); labels.fill(-1)
	# Over-segment into connected, locally coherent superpixels. Grid limits
	# prevent a smooth gradient from joining foreground and background at once.
	for start in count:
		if labels[start]>=0: continue
		var id:=means.size(); var queue:=PackedInt32Array([start]); labels[start]=id
		var head:=0; var sum:=Color(0,0,0,0); var tile:=Vector2i(start%size.x,start/size.x)/8
		while head<queue.size():
			var i:=queue[head]; head+=1; var p:=Vector2i(i%size.x,i/size.x); sum+=field.colors[i]
			for next in adjacent(p):
				var q:=Vector2i(next%size.x,next/size.x)
				if labels[next]>=0 or q/8!=tile: continue
				if difference(field.colors[i],field.colors[next])<=.13:
					labels[next]=id; queue.append(next)
		means.append(sum/float(queue.size())); areas.append(queue.size()); graph.append({})
	# Each shared region boundary contributes evidence; interior variation is
	# not compared only to the originally clicked pixel.
	var boundaries: Dictionary={}
	for i in count:
		var p:=Vector2i(i%size.x,i/size.x); var a:=labels[i]
		if p.x==0 or p.y==0 or p.x==size.x-1 or p.y==size.y-1:
			var key:=color_key(field.colors[i]); background[key]=int(background.get(key,0))+1
			border_regions[a]=true
		for q in [p+Vector2i.RIGHT,p+Vector2i.DOWN]:
			if not field.inside(q): continue
			var j: int=q.y*size.x+q.x; var b:=labels[j]
			if a==b: continue
			var key:=Vector2i(mini(a,b),maxi(a,b))
			var value: Vector2=boundaries.get(key,Vector2.ZERO)
			boundaries[key]=value+Vector2(difference(field.colors[i],field.colors[j]),1)
	# A few foreground pixels touching the canvas must not make their entire
	# color a background prior. Keep only well-supported border appearances.
	var border_samples:=0
	for value in background.values(): border_samples+=int(value)
	for key in background.keys():
		if int(background[key])<maxf(3,border_samples*.05): background.erase(key)
	for key: Vector2i in boundaries:
		var boundary: Vector2=boundaries[key]
		var cost:=.12+boundary.x/boundary.y*.28+difference(means[key.x],means[key.y])*.18
		# Dark, connected cartoon outlines are separators, not just another
		# foreground color. Transparent regions never join opaque foreground.
		for id in [key.x,key.y]:
			var c:=means[id]
			if c.a<.01: cost=1.1
			elif maxf(c.r,maxf(c.g,c.b))<.14 and difference(means[key.x],means[key.y])>.15: cost=maxf(cost,.98)
		graph[key.x][key.y]=cost; graph[key.y][key.x]=cost

func background_costs(seed: int) -> void:
	# Background competes for every region. A foreground proposal must be
	# easier to reach from the clicked object than from supported canvas edges.
	background_distances.resize(means.size()); background_distances.fill(INF)
	var heap: Array[Vector2]=[]
	for id: int in border_regions:
		# A clicked subject may touch the canvas. Do not label its own border
		# appearance as background simply because it reaches the image edge.
		if means[id].a>.01 and difference(means[id],means[seed])<.035: continue
		# Textured borders rarely share a dominant quantized color. They still
		# provide background evidence; dropping them leaves the flood unbounded.
		background_distances[id]=0; heap_push(heap,Vector2(0,id))
	while not heap.is_empty():
		var item:=heap_pop(heap); var id:=int(item.y)
		if item.x>background_distances[id]+.00001: continue
		for next: int in graph[id]:
			var distance:=maxf(item.x,float(graph[id][next]))
			if distance<background_distances[next]: background_distances[next]=distance; heap_push(heap,Vector2(distance,next))

func adjacent(p: Vector2i) -> PackedInt32Array:
	var result:=PackedInt32Array()
	for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var q: Vector2i=p+delta
		if field.inside(q): result.append(q.y*field.size.x+q.x)
	return result

static func difference(a: Color,b: Color) -> float:
	return maxf(absf(a.a-b.a),Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()/sqrt(3.0))

static func color_key(c: Color) -> int:
	return clampi(int(c.r*7),0,7)+clampi(int(c.g*7),0,7)*8+clampi(int(c.b*7),0,7)*64

func seed_costs(point: Vector2) -> bool:
	var at:=field.cell(point)
	if not field.inside(at): return false
	var seed:=labels[at.y*field.size.x+at.x]
	if means[seed].a<.01: return false
	if seed==last_seed: return true
	background_costs(seed)
	last_seed=seed; distances.resize(means.size()); distances.fill(INF); distances[seed]=0
	var heap: Array[Vector2]=[Vector2(0,seed)]
	while not heap.is_empty():
		var item:=heap_pop(heap); var id:=int(item.y)
		if item.x>distances[id]+.00001: continue
		for next: int in graph[id]:
			var cost: float=graph[id][next]
			var distance:=maxf(item.x,cost)
			if distance<distances[next]: distances[next]=distance; heap_push(heap,Vector2(distance,next))
	return true

static func heap_push(heap: Array[Vector2],item: Vector2) -> void:
	heap.append(item); var index:=heap.size()-1
	while index>0:
		var parent: int=(index-1)/2
		if heap[parent].x<=item.x: break
		heap[index]=heap[parent]; index=parent
	heap[index]=item

static func heap_pop(heap: Array[Vector2]) -> Vector2:
	var result:=heap[0]; var item: Vector2=heap.pop_back()
	if heap.is_empty(): return result
	var index:=0
	while index*2+1<heap.size():
		var child:=index*2+1
		if child+1<heap.size() and heap[child+1].x<heap[child].x: child+=1
		if heap[child].x>=item.x: break
		heap[index]=heap[child]; index=child
	heap[index]=item; return result

func propose(point: Vector2,threshold: float) -> Image:
	if not seed_costs(point): return null
	var boundary:=background_distances[last_seed]
	if is_inf(boundary): return null
	# Normalize against this object's escape barrier, not a fixed RGB range.
	# The whole slider now explores internal detail up to (but not across)
	# the measured boundary, including low-contrast subjects.
	var amount:=clampf(threshold,0,1)
	var detail_barrier:=.12002
	for id in means.size():
		if distances[id]<boundary and background_distances[id]>distances[id]+.0001:
			detail_barrier=maxf(detail_barrier,distances[id])
	var ceiling:=minf(boundary-.0001,.12+(detail_barrier-.12)*1.6)
	var cutoff:=lerpf(.12001,maxf(.12002,minf(.97,ceiling)),pow(amount,.65))
	var margin:=lerpf(.025,.0001,amount)*maxf(.02,boundary-.12)
	var count:=labels.size()
	var included:=PackedByteArray(); included.resize(count); var total:=0
	for i in count:
		var id:=labels[i]
		# Never cross into a region more strongly connected to the background,
		# even at maximum threshold. This stops broad low-contrast floods.
		var advantage:=background_distances[id]-distances[id]
		if distances[id]<=cutoff and (id==last_seed or advantage>margin) and field.colors[i].a>.01:
			included[i]=1; total+=1
	# Keep only the component reached from the actual clicked pixel. Graph
	# paths through excluded background must not select unrelated islands.
	var seed_cell:=field.cell(point); var seed_index:=seed_cell.y*field.size.x+seed_cell.x
	var connected:=PackedByteArray(); connected.resize(count); connected[seed_index]=1
	var frontier:=PackedInt32Array([seed_index]); var cursor:=0
	while cursor<frontier.size():
		var i:=frontier[cursor]; cursor+=1
		for next in adjacent(Vector2i(i%field.size.x,i/field.size.x)):
			if included[next]!=0 and connected[next]==0: connected[next]=1; frontier.append(next)
	included=connected; total=frontier.size()
	# Refuse ambiguous whole-image expansion rather than pretending to detect
	# an object. No semantics are claimed for this local boundary algorithm.
	if total>count*.85: return null
	# Recover small enclosed details only. Filling every enclosed area could
	# turn a thin foreground ring into a selection of most of the picture.
	if threshold>=.4:
		var exterior:=PackedByteArray(); exterior.resize(count); var queue:=PackedInt32Array()
		for i in count:
			var p:=Vector2i(i%field.size.x,i/field.size.x)
			if included[i]==0 and (p.x==0 or p.y==0 or p.x==field.size.x-1 or p.y==field.size.y-1): exterior[i]=1; queue.append(i)
		var head:=0
		while head<queue.size():
			var i:=queue[head]; head+=1
			for next in adjacent(Vector2i(i%field.size.x,i/field.size.x)):
				if included[next]==0 and exterior[next]==0: exterior[next]=1; queue.append(next)
		var seen:=exterior.duplicate()
		for start in count:
			if included[start]!=0 or seen[start]!=0: continue
			var hole:=PackedInt32Array([start]); seen[start]=1; var index:=0
			while index<hole.size():
				var i:=hole[index]; index+=1
				for next in adjacent(Vector2i(i%field.size.x,i/field.size.x)):
					if included[next]==0 and seen[next]==0: seen[next]=1; hole.append(next)
			if hole.size()>maxf(4,total*lerpf(.02,.15,amount)): continue
			for i in hole:
				if field.colors[i].a>.01: included[i]=1
	var bytes:=PackedByteArray(); bytes.resize(count*4)
	for i in count:
		if included[i]!=0:
			for c in 4: bytes[i*4+c]=255
	var mask:=Image.create_from_data(field.size.x,field.size.y,false,Image.FORMAT_RGBA8,bytes)
	mask.resize(field.domain.size.x,field.domain.size.y,Image.INTERPOLATE_NEAREST)
	# Refine boundary cells at source resolution using the adjacent superpixel
	# appearances; also preserve antialiased/partially transparent source edges.
	var source:=field.source.get_data(); var output:=mask.get_data(); var width:=field.source.get_width()
	for i in count:
		var cell:=Vector2i(i%field.size.x,i/field.size.x)
		var candidates:=adjacent(cell); var at_boundary:=false
		for next in candidates:
			if included[next]!=included[i]: at_boundary=true; break
		if not at_boundary: continue
		var begin:=Vector2i((Vector2(cell)*field.step).ceil())
		var end:=Vector2i((Vector2(cell+Vector2i.ONE)*field.step).ceil()).min(field.domain.size)
		for y in range(begin.y,end.y):
			for x in range(begin.x,end.x):
				var source_index:=((y+field.domain.position.y)*width+x+field.domain.position.x)*4
				var alpha:=source[source_index+3]/255.0; var value:=included[i]!=0
				if alpha>.001:
					var color:=Color(source[source_index]/255.0/alpha,source[source_index+1]/255.0/alpha,source[source_index+2]/255.0/alpha,alpha)
					var best:=difference(color,means[labels[i]])
					for next in candidates:
						var distance:=difference(color,means[labels[next]])
						if distance<best: best=distance; value=included[next]!=0
				var offset: int=(y*field.domain.size.x+x)*4
				for c in 4: output[offset+c]=255 if value and alpha>.001 else 0
	mask=Image.create_from_data(field.domain.size.x,field.domain.size.y,false,Image.FORMAT_RGBA8,output)
	var filtered:=Image.create(field.domain.size.x,field.domain.size.y,false,Image.FORMAT_RGBA8)
	filtered.blit_rect_mask(mask,field.source.get_region(field.domain),Rect2i(Vector2i.ZERO,field.domain.size),Vector2i.ZERO)
	return filtered
