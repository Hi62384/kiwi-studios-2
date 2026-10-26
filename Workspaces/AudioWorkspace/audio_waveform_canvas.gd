class_name KiwiAudioWaveformCanvas
extends Control
signal selection_changed(first_sample: int, last_sample: int)
signal seek_requested(seconds: float)
signal detail_requested(start: float, duration: float)
var stream: AudioStream
var cache: KiwiAudioSourceCache
var rate: int = 44100
var view_start: float = 0
var view_duration: float = 5
var selection := Vector2i.ZERO
var channel: int = -1
var zero_crossing := true
var spectrogram: Texture2D
var spectrogram_start: float = 0
var spectrogram_duration: float = 0
var show_spectrogram := false
var detail: PackedVector2Array = PackedVector2Array()
var detail_start: float = 0
var _drag := false
var _anchor: int = 0
var _last_detail := ""
func _ready()->void:
 custom_minimum_size=Vector2(300,160);focus_mode=Control.FOCUS_ALL;clip_contents=true
func open(value:AudioStream,start:float=0,duration:float=-1)->void:
 stream=value;rate=value.mix_rate if value is AudioStreamWAV else 44100
 view_start=maxf(0,start);view_duration=maxf(1.0/rate,duration if duration>0 else (value.get_length() if value!=null else 1))
 selection=Vector2i(int(round(view_start*rate)),int(round((view_start+view_duration)*rate)))
 detail.clear();_last_detail="";spectrogram=null;queue_redraw()
func _sample_at(x:float)->int:
 var index:=int(round((view_start+clampf(x/maxf(1,size.x),0,1)*view_duration)*rate))
 if zero_crossing and not detail.is_empty():
  var local:=index-int(round(detail_start*rate))
  if local>=0 and local<detail.size():index=int(round(detail_start*rate))+KiwiAudioAnalysis.nearest_zero(detail,local,mini(256,int(view_duration*rate/size.x*8)),channel)
 return clampi(index,0,int(stream.get_length()*rate) if stream!=null else 0)
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("0e1720"))
 if stream==null:return
 if show_spectrogram and spectrogram!=null and spectrogram_duration>0:
  var left:=(view_start-spectrogram_start)/spectrogram_duration*spectrogram.get_width()
  var width:=view_duration/spectrogram_duration*spectrogram.get_width()
  draw_texture_rect_region(spectrogram,Rect2(Vector2.ZERO,size),Rect2(left,0,width,spectrogram.get_height()))
 else:
  var entry:=cache.request(stream) if cache!=null else {}
  var channels:=2 if channel<0 else 1
  for row in channels:
   var source_channel:=row if channel<0 else channel
   var height:=size.y/channels;var center:=height*(row+0.5)
   draw_line(Vector2(0,center),Vector2(size.x,center),Color("3b5160"))
   var color:=Color("74d7bd") if source_channel==0 else Color("80b4ed")
   if view_duration*rate<size.x*2 and not detail.is_empty():
    var previous:=Vector2.ZERO;var found:=false
    var first:=maxi(0,int((view_start-detail_start)*rate))
    var last:=mini(detail.size(),int((view_start+view_duration-detail_start)*rate)+1)
    for i in range(first,last):
     var x:=(detail_start+float(i)/rate-view_start)/view_duration*size.x
     var amplitude:=detail[i].x if source_channel==0 else detail[i].y
     var point:=Vector2(x,center-amplitude*height*0.43)
     if found:draw_line(previous,point,color,1.5)
     if view_duration*rate<size.x/4:draw_circle(point,2.5,color)
     previous=point;found=true
   elif not entry.is_empty():
    var peaks:=KiwiAudioSourceCache.range_peaks(entry,view_start,view_duration,maxi(1,int(size.x)),source_channel)
    for x in peaks.size():draw_line(Vector2(x,center-peaks[x].y*height*0.43),Vector2(x,center-peaks[x].x*height*0.43),color)
   draw_string(ThemeDB.fallback_font,Vector2(5,row*height+16),"L" if source_channel==0 else "R",HORIZONTAL_ALIGNMENT_LEFT,20,11,Color("b4c8d2"))
 var left:=(float(selection.x)/rate-view_start)/view_duration*size.x
 var right:=(float(selection.y)/rate-view_start)/view_duration*size.x
 draw_rect(Rect2(left,0,right-left,size.y),Color(0.6,0.8,1,0.16))
 draw_line(Vector2(left,0),Vector2(left,size.y),Color("e7c672"));draw_line(Vector2(right,0),Vector2(right,size.y),Color("e7c672"))
 draw_string(ThemeDB.fallback_font,Vector2(35,16),"%.6fs  →  %.6fs  |  samples %d–%d" % [view_start,view_start+view_duration,selection.x,selection.y],HORIZONTAL_ALIGNMENT_LEFT,size.x-40,11,Color("c0d1dc"))
func _process(_delta:float)->void:
 if stream==null or not is_visible_in_tree() or view_duration>2:return
 var signature:="%s:%.6f:%.6f" % [stream.get_instance_id(),view_start,view_duration]
 if signature!=_last_detail:
  _last_detail=signature;detail_requested.emit(maxf(0,view_start-0.01),minf(2.02,view_duration+0.02))
func _gui_input(event:InputEvent)->void:
 if stream==null:return
 if event is InputEventMouseButton:
  if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
   var direction:=1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1
   if event.shift_pressed:view_start=clampf(view_start-direction*view_duration*0.2,0,maxf(0,stream.get_length()-view_duration))
   else:
    var anchor:float=view_start+event.position.x/size.x*view_duration
    view_duration=clampf(view_duration*pow(1.3,-direction),4.0/rate,maxf(4.0/rate,stream.get_length()))
    view_start=clampf(anchor-event.position.x/size.x*view_duration,0,maxf(0,stream.get_length()-view_duration))
   queue_redraw();accept_event();return
  if event.button_index==MOUSE_BUTTON_LEFT:
   _drag=event.pressed
   if _drag:_anchor=_sample_at(event.position.x);selection=Vector2i(_anchor,_anchor);grab_focus()
   else:selection_changed.emit(selection.x,selection.y)
   if event.double_click:selection=Vector2i(0,int(stream.get_length()*rate));selection_changed.emit(selection.x,selection.y)
   queue_redraw()
  elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:seek_requested.emit(float(_sample_at(event.position.x))/rate)
 elif event is InputEventMouseMotion and _drag:
  var end:=_sample_at(event.position.x);selection=Vector2i(mini(_anchor,end),maxi(_anchor,end));queue_redraw();selection_changed.emit(selection.x,selection.y)
