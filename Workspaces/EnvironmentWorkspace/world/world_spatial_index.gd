extends RefCounted
## Bounded broad phase. Large footprints use a separate list, never huge bin maps.
var cell_size:=64.
var entries: Array[Dictionary]=[]
var bins: Dictionary={}
var large: Array[int]=[]
func add(bounds: Rect2,value: Variant) -> void:
	var index:=entries.size(); bounds=bounds.abs(); entries.append({"bounds":bounds,"value":value}); var low:=Vector2i((bounds.position/cell_size).floor()); var high:=Vector2i((bounds.end/cell_size).floor())
	if float(high.x-low.x+1)*float(high.y-low.y+1)>256.: large.append(index); return
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell:=Vector2i(x,z)
			if not bins.has(cell): bins[cell]=[]
			bins[cell].append(index)
func query(bounds: Rect2) -> Array:
	bounds=bounds.abs(); var found: Dictionary={}; var result: Array=[]; var low:=Vector2i((bounds.position/cell_size).floor()); var high:=Vector2i((bounds.end/cell_size).floor()); var candidates: Array=large.duplicate()
	if float(high.x-low.x+1)*float(high.y-low.y+1)>maxi(256,bins.size()*2):
		for index in entries.size(): candidates.append(index)
	else:
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1): candidates.append_array(bins.get(Vector2i(x,z),[]))
	for index: int in candidates:
		if found.has(index): continue
		found[index]=true
		if (entries[index].bounds as Rect2).intersects(bounds,true): result.append(entries[index].value)
	return result
static func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: bounds=bounds.expand(point)
	return bounds
