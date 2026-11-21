extends TextEdit
## Native keyboard/IME editing with the same aligned paragraph layout as the layer.
## Native TextEdit glyphs are hidden; only the shaped text, selection, and caret draw.

signal navigation_requested(event: InputEventMouseButton)
var layer: KiwiImageLayer
var canvas: KiwiImageCanvas
var paragraph:=TextParagraph.new()
var settings: Dictionary
var font: Font
var font_size:=16
var detail:=1.0
var _signature:=0
var _blink:=0.0
var _drag_anchor: int=-1


func _ready()->void:_native().ready(self)

func _process(delta:float)->void:_native().process(self,delta)

func sync_layout()->void:_native().sync_layout(self)

func _absolute(line:int,column:int)->int:return _native().absolute(self,line,column)

func _line_column(offset:int)->Vector2i:return _native().line_column(self,offset)

func _place_caret(offset:int,select_from:int=-1)->void:_native().place_caret(self,offset,select_from)

func hit_text(at:Vector2)->int:return _native().hit_text(self,at)

func _gui_input(event:InputEvent)->void:_native().gui_input(self,event)

func caret_rect_for_line(line:int,offset:int)->Rect2:return _native().caret_rect_for_line(self,line,offset)

func _draw()->void:_native().draw(self)


static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_inline_text")
