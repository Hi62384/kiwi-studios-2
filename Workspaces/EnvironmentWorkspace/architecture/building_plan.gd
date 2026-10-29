extends Control
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
var workspace: Control
var building_id:=""
var current_floor:=0
var tool:="Select"
var zoom:=35.
var pan:=Vector2.ZERO
var snap:=true
var grid_step:=.25
var selected_wall:=-1
var selected_opening:=-1
var cutaway:=false
var view_mode:=1
var _drag: Dictionary={}
var _panning:=false
func _ready() -> void:
	focus_mode=Control.FOCUS_ALL; mouse_filter=Control.MOUSE_FILTER_STOP; custom_minimum_size=Vector2(260,220); size_flags_horizontal=Control.SIZE_EXPAND_FILL; size_flags_vertical=Control.SIZE_EXPAND_FILL
func authored() -> Resource:
	return Buildings.source(workspace.session.document.component(building_id)) if is_instance_valid(workspace) else null
func to_screen(point: Vector2) -> Vector2: return size*.5+pan+point*zoom
func to_plan(point: Vector2) -> Vector2: return (point-size*.5-pan)/zoom
func _snap_point(point: Vector2,control: bool=false) -> Vector2: return point.snapped(Vector2.ONE*grid_step) if snap!=control else point
func _process(_delta: float) -> void:
	if is_instance_valid(workspace) and not workspace.is_visible_in_tree(): return
	if is_instance_valid(workspace):
		grid_step=workspace.canvas.grid_step
		workspace.session.document.workspace_state.architecture_plan={"owner":building_id,"floor":current_floor,"zoom":zoom,"pan":pan,"cutaway":cutaway,"mode":view_mode,"split":get_parent().split_offset if get_parent() is HSplitContainer else -60}
	_apply_cutaway.call_deferred()
	if is_visible_in_tree(): queue_redraw()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_EXIT_TREE] and not _drag.is_empty() and is_instance_valid(workspace): cancel()
func _apply_cutaway() -> void:
	if not is_inside_tree() or not is_instance_valid(workspace): return
	var source:=authored(); var hidden: Dictionary={}
	if source!=null and cutaway:
		current_floor=clampi(current_floor,0,source.floors.size()-1)
		for item in workspace.session.document.components:
			if Buildings.owner(workspace.session,item)==null or Buildings.owner(workspace.session,item).id!=building_id: continue
			var key:=str(item.parameters.get("architecture_key","")); var type:=str(item.parameters.get("architecture_type",""))
			if type=="roof": hidden[item.id]=true
			for index in (source.floors as Array).size():
				if key.begins_with(":"+str(source.floors[index].id)+":") or key==":"+str(source.floors[index].id):
					if index>current_floor or (index==current_floor and type=="ceiling"): hidden[item.id]=true
	var canvas: Control=workspace.canvas
	if canvas.preview_hidden==hidden: return
	canvas.preview_hidden=hidden
	var nodes: Dictionary=canvas.renderer.nodes if canvas is KiwiEnvironmentViewport else canvas.visuals
	if canvas is KiwiEnvironmentViewport: canvas.renderer.preview_hidden=hidden
	for id: String in nodes:
		var item: KiwiModelComponent=workspace.session.document.component(id)
		if item!=null and is_instance_valid(nodes[id]): nodes[id].visible=workspace.session.document.visible_component(item) and not hidden.has(id)
	canvas.request_sync()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101e29")); var source:=authored()
	if source==null or source.floors.is_empty(): return
	var step:=grid_step
	while step*zoom<14.: step*=2.
	var a:=to_plan(Vector2.ZERO); var b:=to_plan(size)
	for x in range(floori(a.x/step),ceili(b.x/step)+1): draw_line(to_screen(Vector2(x*step,a.y)),to_screen(Vector2(x*step,b.y)),Color("203340"),1.)
	for z in range(floori(a.y/step),ceili(b.y/step)+1): draw_line(to_screen(Vector2(a.x,z*step)),to_screen(Vector2(b.x,z*step)),Color("203340"),1.)
	current_floor=clampi(current_floor,0,source.floors.size()-1); var floor: Dictionary=source.floors[current_floor]
	for room: Dictionary in floor.get("rooms",[]):
		var polygon:=PackedVector2Array(); var center:=Vector2.ZERO
		for point: Vector2 in room.get("polygon",source.footprint): polygon.append(to_screen(point)); center+=point
		if polygon.size()>2 and not Geometry2D.triangulate_polygon(polygon).is_empty(): draw_colored_polygon(polygon,Color(.2,.5,.45,.13))
		if not polygon.is_empty(): draw_string(ThemeDB.fallback_font,to_screen(center/polygon.size()),str(room.get("name","Room")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("829aab"))
	for index in (floor.walls as Array).size():
		var wall: Dictionary=floor.walls[index]; var start:=to_screen(wall.a); var end:=to_screen(wall.b); var color:=Color("83e6c8") if index==selected_wall else Color("a8bccb")
		draw_line(start,end,color,maxf(3.,float(source.wall_thickness)*zoom),true); draw_circle(start,3.,color); draw_circle(end,3.,color)
		for opening: Dictionary in wall.get("openings",[]):
			var direction: Vector2=(wall.b-wall.a).normalized(); var center: Vector2=wall.a.lerp(wall.b,float(opening.get("t",.5))); var width:=float(opening.get("width",1.)); var type:=str(opening.get("type","door")); var accent:=Color("76bdff") if type=="window" else (Color("ffc778") if type=="arch" else Color("76ddac"))
			draw_line(to_screen(center-direction*width*.5),to_screen(center+direction*width*.5),Color("101e29"),maxf(5.,float(source.wall_thickness)*zoom+3.),true); draw_line(to_screen(center-direction*width*.5),to_screen(center+direction*width*.5),accent,2.,true); draw_circle(to_screen(center),4.,accent)
		if index==selected_wall:
			draw_circle(start,7.,Color("85f2d4"),false,2.,true); draw_circle(end,7.,Color("85f2d4"),false,2.,true); draw_string(ThemeDB.fallback_font,(start+end)*.5+Vector2(0,-10),"%.2f m"%(wall.a as Vector2).distance_to(wall.b),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
	for stair: Dictionary in source.stairs:
		if str(stair.get("from",""))!=str(floor.id) and str(stair.get("to",""))!=str(floor.id): continue
		var bounds:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")._stair_bounds(stair); draw_rect(Rect2(to_screen(bounds.position),bounds.size*zoom),Color(.9,.67,.3,.15)); draw_rect(Rect2(to_screen(bounds.position),bounds.size*zoom),Color("e6b864"),false,2.)
	if not _drag.is_empty() and _drag.get("kind","") in ["Wall","Room"]:
		var start: Vector2=to_screen(_drag.start); var end: Vector2=to_screen(_drag.point)
		if _drag.kind=="Room": draw_rect(Rect2(start,end-start).abs(),Color(.3,.9,.7,.12)); draw_rect(Rect2(start,end-start).abs(),Color("8df4d2"),false,2.)
		else: draw_line(start,end,Color("8df4d2"),2.,true)
func _pick(point: Vector2,openings: bool=true) -> Dictionary:
	var source:=authored()
	if source==null: return {}
	var floor: Dictionary=source.floors[clampi(current_floor,0,source.floors.size()-1)]; var best: Dictionary={}; var distance:=12.
	for index in (floor.walls as Array).size():
		var wall: Dictionary=floor.walls[index]
		if openings:
			for endpoint: String in ["a","b"]:
				var d:=point.distance_to(to_screen(wall[endpoint]))
				if d<minf(distance,9.): best={"wall":index,"endpoint":endpoint}; distance=d
			for opening in (wall.get("openings",[]) as Array).size():
				var d:=point.distance_to(to_screen((wall.a as Vector2).lerp(wall.b,float(wall.openings[opening].get("t",.5)))))
				if d<minf(distance,9.): best={"wall":index,"opening":opening}; distance=d
		var closest:=Geometry2D.get_closest_point_to_segment(point,to_screen(wall.a),to_screen(wall.b)); var d:=point.distance_to(closest)
		if d<distance and (best.is_empty() or not openings): best={"wall":index}; distance=d
	return best
func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE: cancel(); accept_event(); return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before:=to_plan(event.position); zoom=clampf(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1./1.15),8.,200.); pan=event.position-size*.5-before*zoom; accept_event(); return
		if event.button_index==MOUSE_BUTTON_MIDDLE: _panning=event.pressed; accept_event(); return
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel(); accept_event(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		grab_focus()
		if not event.pressed:
			if not _drag.is_empty():
				if _drag.get("valid",false): workspace.session.commit("Edit floor plan")
				else: workspace.session.cancel()
				_drag={}
			accept_event(); return
		var source:=authored()
		if source==null: return
		var floor: Dictionary=source.floors[current_floor]; var point:=_snap_point(to_plan(event.position),event.ctrl_pressed)
		if tool=="Stairs":
			if current_floor>=source.floors.size()-1: workspace.status.text="Add a level above this one first."; return
			var next:=Source.copy(source); next.stairs.append({"id":ActorData.new_id(),"from":floor.id,"to":source.floors[current_floor+1].id,"type":0,"position":point,"width":1.,"length":4.,"steps":16}); _apply(next,false); accept_event(); return
		if tool in ["Wall","Room"]:
			_drag={"kind":tool,"source":Source.copy(source),"start":point,"point":point,"new_id":ActorData.new_id(),"valid":false}; workspace.session.begin()
		else:
			var hit:=_pick(event.position,tool=="Select")
			if hit.is_empty(): selected_wall=-1; selected_opening=-1; return
			selected_wall=int(hit.wall); selected_opening=int(hit.get("opening",-1))
			if tool=="Select":
				_drag=hit.duplicate(); _drag.kind="Select"; _drag.source=Source.copy(source); _drag.start=point; _drag.point=point; _drag.valid=false; workspace.session.begin()
			elif tool=="Delete":
				var next: Resource=Source.copy(source); next.floors[current_floor].walls.remove_at(selected_wall); _apply(next,false); selected_wall=-1; selected_opening=-1
			else:
				var next: Resource=Source.copy(source); var wall: Dictionary=next.floors[current_floor].walls[selected_wall]; var delta: Vector2=wall.b-wall.a; var t:=clampf((point-wall.a).dot(delta)/maxf(.001,delta.length_squared()),0.,1.)
				wall.openings.append({"id":ActorData.new_id(),"type":tool.to_lower(),"t":t,"width":1.4 if tool=="Window" else 1.,"height":1.2 if tool=="Window" else 2.1,"bottom":1. if tool=="Window" else 0.}); _apply(next,false)
		accept_event()
	elif event is InputEventMouseMotion:
		if _panning: pan+=event.relative; accept_event(); return
		if _drag.is_empty(): return
		var point:=_snap_point(to_plan(event.position),event.ctrl_pressed); _drag.point=point; var next: Resource=Source.copy(_drag.source); var floor: Dictionary=next.floors[current_floor]
		if _drag.kind=="Wall":
			if point.distance_to(_drag.start)<.1: return
			floor.walls.append({"id":_drag.new_id,"a":_drag.start,"b":point,"height":floor.get("height",3.),"openings":[]})
		elif _drag.kind=="Room":
			if not _room(next,floor,Rect2(_drag.start,point-_drag.start).abs(),_drag.new_id): return
		else:
			var wall: Dictionary=floor.walls[_drag.wall]
			if _drag.has("opening"):
				var opening: Dictionary=wall.openings[_drag.opening]; var delta: Vector2=wall.b-wall.a; var half:=float(opening.get("width",1.))*.5/maxf(.001,delta.length()); opening.t=clampf((point-wall.a).dot(delta)/maxf(.001,delta.length_squared()),half,1.-half)
			else:
				var replacements: Dictionary={}
				if _drag.has("endpoint"): replacements[wall[_drag.endpoint]]=point
				else: var offset: Vector2=point-_drag.start; replacements[wall.a]=wall.a+offset; replacements[wall.b]=wall.b+offset
				_replace_points(next,floor,replacements)
		_drag.valid=_apply(next,true); accept_event()
func _apply(source: Resource,preview: bool) -> bool:
	var result:=Buildings.update(workspace.session,building_id,source,"Edit floor plan",preview)
	if not result.errors.is_empty(): workspace.status.text=result.errors[0]; return false
	workspace.status.text=" · ".join(result.warnings) if not result.warnings.is_empty() else "Floor plan updated"; return true
func cancel() -> void:
	if not _drag.is_empty(): workspace.session.cancel(); _drag={}
	queue_redraw()
static func _replace_points(source: Resource,floor: Dictionary,replacements: Dictionary) -> void:
	for wall: Dictionary in floor.walls:
		wall.a=replacements.get(wall.a,wall.a); wall.b=replacements.get(wall.b,wall.b)
	var footprint: PackedVector2Array=floor.get("footprint",source.footprint).duplicate()
	for index in footprint.size(): footprint[index]=replacements.get(footprint[index],footprint[index])
	_set_footprint(source,floor,footprint)
	for room: Dictionary in floor.get("rooms",[]):
		var polygon: PackedVector2Array=room.get("polygon",PackedVector2Array()).duplicate()
		for index in polygon.size(): polygon[index]=replacements.get(polygon[index],polygon[index])
		room.polygon=polygon
func _room(source: Resource,floor: Dictionary,box: Rect2,id: String) -> bool:
	if box.size.x<.2 or box.size.y<.2: return false
	var polygon:=PackedVector2Array([box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]); var merged:=Geometry2D.merge_polygons(floor.get("footprint",source.footprint),polygon)
	if merged.size()!=1: workspace.status.text="The new room must connect to the building footprint."; return false
	_set_footprint(source,floor,merged[0]); var rooms: Array=[]
	for room: Dictionary in floor.get("rooms",[]):
		var contours:=Geometry2D.clip_polygons(room.get("polygon",source.footprint),polygon)
		for part in contours.size():
			if Geometry2D.is_polygon_clockwise(contours[part]): continue
			var retained:=room.duplicate(true); retained.polygon=contours[part]
			if part>0: retained.id=str(room.id)+":part:"+str(part)
			retained.holes=[]
			for previous in room.get("holes",[]):
				for clipped in Geometry2D.intersect_polygons(previous,contours[part]): retained.holes.append(clipped)
			for contour in contours:
				if Geometry2D.is_polygon_clockwise(contour) and Geometry2D.is_point_in_polygon(contour[0],contours[part]): retained.holes.append(contour)
			rooms.append(retained)
	rooms.append({"id":id,"name":"Room "+str(rooms.size()+1),"polygon":polygon}); floor.rooms=rooms
	for index in 4: floor.walls.append({"id":id+":"+str(index),"a":polygon[index],"b":polygon[(index+1)%4],"height":floor.get("height",3.),"openings":[]})
	var result:=partition_walls(floor.walls)
	if not result.error.is_empty(): workspace.status.text=result.error; return false
	floor.walls=result.walls; return true
static func partition_walls(walls: Array) -> Dictionary:
	var result: Array=[]; var seen: Dictionary={}
	for wall: Dictionary in walls:
		var a: Vector2=wall.a; var b: Vector2=wall.b; var delta:=b-a; var ts: Array[float]=[0.,1.]
		for other: Dictionary in walls:
			for point: Vector2 in [other.a,other.b]:
				var t:=clampf((point-a).dot(delta)/maxf(.00001,delta.length_squared()),0.,1.)
				if point.distance_to(a+delta*t)<.0001: ts.append(t)
		ts.sort(); var unique: Array[float]=[]
		for t in ts:
			if unique.is_empty() or absf(unique[-1]-t)>.00001: unique.append(t)
		for index in unique.size()-1:
			var first:=a+delta*unique[index]; var last:=a+delta*unique[index+1]; var key:=str(first)+":"+str(last); var reverse:=str(last)+":"+str(first)
			if seen.has(key) or seen.has(reverse): continue
			var part:=wall.duplicate(true); part.id=str(wall.id) if index==0 else str(wall.id)+":segment:"+str(index); part.a=first; part.b=last; part.openings=[]
			for opening: Dictionary in wall.get("openings",[]):
				var center:=float(opening.get("t",.5))*delta.length(); var half:=float(opening.get("width",1.))*.5; var low:=unique[index]*delta.length(); var high:=unique[index+1]*delta.length()
				if center<low or center>high: continue
				if center-half<low-.00001 or center+half>high+.00001: return {"walls":[],"error":"A room boundary crosses an opening. Move the opening first."}
				var copy:=opening.duplicate(true); copy.t=(center-low)/maxf(.001,high-low); part.openings.append(copy)
			seen[key]=true; result.append(part)
	return {"walls":result,"error":""}
static func _set_footprint(source: Resource,floor: Dictionary,polygon: PackedVector2Array) -> void:
	if str(floor.id)==str(source.floors[0].id):
		for other: Dictionary in source.floors:
			if other.id!=floor.id and not other.has("footprint"): other.footprint=source.footprint.duplicate()
		source.footprint=polygon
	floor.footprint=polygon
