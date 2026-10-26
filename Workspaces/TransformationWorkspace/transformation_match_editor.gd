class_name KiwiTransformationMatchEditor
extends PopupPanel
var workspace: KiwiTransformationWorkspace
var component_id := ""
var key_id := ""
var next_state_id := ""
var surface: MatchSurface
var overlays := true
class MatchSurface extends Control:
	var host: KiwiTransformationMatchEditor
	var pending: Variant=null
	var drag := -1
	var side := 0
	var selected_pair := -1
	func rect(index: int) -> Rect2: return Rect2(Vector2(index*size.x*.5+12,30),Vector2(size.x*.5-24,size.y-45))
	func _draw() -> void:
		var key := host.key(); var item := host.workspace.session.document.component(host.component_id)
		if key==null or item==null: return
		if host.overlays:
			for i in key.points_a.size(): draw_line(rect(0).position+key.points_a[i]*rect(0).size,rect(1).position+key.points_b[i]*rect(1).size,Color(.5,1,.85,.22),1.,true)
		for index in 2:
			var state := item.state_for_id(key.state_id if index==0 else host.next_state_id); var box := rect(index)
			draw_rect(box,Color("24323e")); draw_texture_rect(state.artwork.texture,box,false)
			draw_string(ThemeDB.fallback_font,box.position-Vector2(0,8),state.title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("79e0c5"))
			var points := key.points_a if index==0 else key.points_b
			if not host.overlays: continue
			for i in points.size():
				var p := box.position+points[i]*box.size; draw_circle(p,7,Color("10202b")); draw_circle(p,5,Color("7fe6ce") if selected_pair==i else Color("ffd18b")); draw_string(ThemeDB.fallback_font,p+Vector2(8,-4),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		if pending is Vector2 and host.overlays: draw_circle(rect(0).position+pending*rect(0).size,6,Color("7fe6ce"))
	func _gui_input(event: InputEvent) -> void:
		var key := host.key()
		if key==null or not host.overlays: return
		if event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and drag>=0:
				drag=-1
				var errors := host.workspace.session.document.validate()
				if errors.is_empty(): host.workspace.session.commit("Move morph correspondence")
				else: host.workspace.session.cancel(); host.workspace.status.text=errors[0]
				queue_redraw(); accept_event(); return
			var index := 0 if event.position.x<size.x*.5 else 1; var box := rect(index); var uv: Vector2=((event.position-box.position)/box.size).clamp(Vector2.ZERO,Vector2.ONE)
			if not box.has_point(event.position): return
			var points := key.points_a if index==0 else key.points_b; var nearest := -1
			for i in points.size():
				if (points[i]*box.size+box.position).distance_to(event.position)<10: nearest=i; break
			if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
				pending=null
				if nearest>=0: host.workspace.session.action("Delete morph correspondence",func(): key.points_a.remove_at(nearest); key.points_b.remove_at(nearest))
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:
					if nearest>=0: drag=nearest; selected_pair=nearest; side=index; host.workspace.session.begin()
					elif index==0: pending=uv
					elif pending is Vector2 and key.points_a.size()<24:
						host.workspace.session.action("Add morph correspondence",func(): key.points_a.append(pending); key.points_b.append(uv)); pending=null; selected_pair=key.points_a.size()-1
			queue_redraw(); accept_event()
		elif event is InputEventMouseMotion and drag>=0:
			var uv: Vector2=((event.position-rect(side).position)/rect(side).size).clamp(Vector2.ZERO,Vector2.ONE)
			if side==0: key.points_a[drag]=uv
			else: key.points_b[drag]=uv
			host.workspace._render_pending=true; queue_redraw(); accept_event()
func key() -> KiwiTransformationKey:
	var item := workspace.session.document.component(component_id)
	return item.key_for_id(key_id) if item!=null else null
func open() -> void:
	workspace.style_popup(self)
	var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(760,520); add_child(column)
	workspace.label(column,"MATCH POINTS · click a feature on the left, then its partner on the right")
	surface=MatchSurface.new(); surface.host=self; surface.custom_minimum_size=Vector2(740,300); column.add_child(surface)
	workspace.label(column,"INTERMEDIATE · live canvas composite")
	var preview := TextureRect.new(); preview.custom_minimum_size=Vector2(400,150); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture=workspace.animation_renderer.texture(); column.add_child(preview)
	var row := HBoxContainer.new(); column.add_child(row); workspace.label(row,"Preview")
	var slider := HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=.001; slider.value=.5; slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(slider)
	var keys := workspace.session.document.component(component_id).sorted_keys(); var index := keys.find(key())
	slider.value_changed.connect(func(value: float): workspace.seek(lerpf(keys[index].time,keys[index+1].time,value)))
	workspace.button(row,"Reset automatic",func(): workspace.session.action("Reset automatic morph",func(): key().points_a=PackedVector2Array(); key().points_b=PackedVector2Array(); key().mode="Auto Morph"); surface.pending=null; surface.selected_pair=-1; surface.queue_redraw())
	workspace.button(row,"Unpair",func():
		var current := key(); var selected := surface.selected_pair
		if current!=null and selected>=0 and selected<current.points_a.size():
			surface.pending=current.points_a[selected]; workspace.session.action("Unpair correction point",func(): current.points_a.remove_at(selected); current.points_b.remove_at(selected)); surface.selected_pair=-1; surface.queue_redraw())
	var overlay_toggle := CheckButton.new(); overlay_toggle.text="Overlays"; overlay_toggle.button_pressed=true; row.add_child(overlay_toggle); overlay_toggle.toggled.connect(func(value: bool): overlays=value; surface.queue_redraw())
	workspace.button(row,"Done",hide)
	popup_hide.connect(func():
		if surface.drag>=0: workspace.session.cancel()
		queue_free())
	workspace.seek(lerpf(keys[index].time,keys[index+1].time,.5)); popup_centered(Vector2i(790,560))
