extends Window
## Shared searchable library, ordered stack and live GPU preview. Parameters
## reuse the editor's draggable numbers, colors, sliders and undo transactions.
const Math=preload("res://Workspaces/ImageWorkspace/image_values.gd")
const EFFECTS=["mirror","blur","sharpen","shadow","glow","outline","curves","gradient_map","color_replace","grain","pixelate","halftone","chromatic","vignette","wave","twirl","emboss","edge_detect","motion_blur","radial_blur","kaleidoscope","ripple","scanlines"]
const EFFECT_CATEGORIES={
	"Detail & blur":["blur","motion_blur","radial_blur","sharpen","emboss","edge_detect"],
	"Light & outline":["shadow","glow","outline","vignette"],
	"Distortion":["mirror","wave","twirl","ripple","kaleidoscope","chromatic"],
	"Texture & style":["grain","pixelate","halftone","scanlines"],
	"Mapping & custom":["curves","gradient_map","color_replace","shader"]}
const RANGES={"brightness":Vector3(-1,1,0),"contrast":Vector3(0,4,1),"saturation":Vector3(0,4,1),"exposure":Vector3(-6,6,0),"gamma":Vector3(.1,4,1),"hue":Vector3(-PI,PI,0),"temperature":Vector3(-1,1,0),"tint":Vector3(-1,1,0),"red":Vector3(0,4,1),"green":Vector3(0,4,1),"blue":Vector3(0,4,1),"vibrance":Vector3(-1,2,0),"grayscale":Vector3(0,1,1),"sepia":Vector3(0,1,1),"posterize":Vector3(2,32,6),"solarize":Vector3(0,1,.5),"shadows":Vector3(-1,1,0),"highlights":Vector3(-1,1,0),"black_point":Vector3(0,.95,0),"white_point":Vector3(.05,2,1)}
const EXTRA_RANGES={"midtones":Vector3(-1,1,0),"lift":Vector3(-1,1,0),"fade":Vector3(0,1,0),"threshold":Vector3(0,1,.5),"cyan_red":Vector3(-1,1,0),"magenta_green":Vector3(-1,1,0),"yellow_blue":Vector3(-1,1,0),"shadow_warmth":Vector3(-1,1,0),"highlight_warmth":Vector3(-1,1,0),"colorize":Vector3(0,1,.5)}
const CATEGORIES={
	"Light & tone":["brightness","exposure","contrast","gamma","shadows","midtones","highlights","black_point","white_point","lift","fade"],
	"Color & balance":["saturation","vibrance","hue","temperature","tint","cyan_red","magenta_green","yellow_blue","shadow_warmth","highlight_warmth"],
	"Channels":["red","green","blue"],
	"Creative looks":["grayscale","sepia","posterize","solarize","threshold","colorize"],
	"Math":["add","subtract","multiply","divide","power","snap","clamp","lerp","minimum","maximum","absolute","invert","smoothstep"]}
var workspace: KiwiImageWorkspace
var layer_id: String
var adjustments:=false
var search:=LineEdit.new()
var library:=VBoxContainer.new()
var stack:=VBoxContainer.new()
var preview:=preload("res://Workspaces/ImageWorkspace/ImageOperationPreview.cs").new()
var whole:=false
var _signature:=""
var _category_collapsed: Dictionary={}

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_stack_editor")

func adjustment_range(kind: String) -> Vector3:
 return _native().adjustment_range(kind)

func _ready() -> void:
 _native().ready(self)

func layer() -> KiwiImageLayer:
 return _native().layer(self)

func entries() -> Array:
 return _native().entries(self)

func rebuild_library() -> void:
 _native().rebuild_library(self)

func add_entry(kind: String) -> void:
 _native().add_entry(self,kind)

func rebuild_stack() -> void:
 _native().rebuild_stack(self)

func reset_entry(index: int) -> void:
 _native().reset_entry(self,index)

func _simple_math_fields(parent: Node,op: Dictionary) -> void:
 _native().simple_math_fields(self,parent,op)

func move_entry(from: int,to: int) -> void:
 _native().move_entry(self,from,to)

func signature() -> String:
 return _native().signature(self)

func _process(_delta: float) -> void:
 _native().process(self)

func close_editor() -> void:
 _native().close_editor(self)

func _unhandled_key_input(event: InputEvent) -> void:
 _native().key_input(self,event)
