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
func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_waveform_canvas")
func _ready()->void:_native().ready(self)
func open(value:AudioStream,start:float=0,duration:float=-1)->void:_native().open(self,value,start,duration)
func _sample_at(x:float)->int:return _native().sample_at(self,x)
func _draw()->void:_native().draw(self)
func _process(_delta:float)->void:_native().process(self)
func _gui_input(event:InputEvent)->void:_native().gui_input(self,event)
