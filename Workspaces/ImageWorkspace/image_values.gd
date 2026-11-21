extends RefCounted
## Color math is shared by preview generation and brush inverse solving.
const TYPES := ["add", "multiply", "subtract", "divide", "power", "snap", "clamp", "lerp", "minimum", "maximum", "absolute", "invert", "smoothstep"]
const BASICS := {"brightness":0.0,"contrast":1.0,"saturation":1.0,"exposure":0.0,"gamma":1.0,"hue":0.0,"temperature":0.0,"tint":0.0}

static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_values")
static func new_operation(kind:String)->Dictionary:return _native().new_operation(kind)
static func operand_value(operand:Dictionary,pixel:Vector4)->Vector4:return _native().operand_value(operand,pixel)
static func operand_code(operand:Dictionary)->String:return _native().operand_code(operand)
static func operation_code(op:Dictionary)->String:return _native().operation_code(op)
static func evaluate_operation(pixel:Vector4,op:Dictionary)->Vector4:return _native().evaluate_operation(pixel,op)
static func operations(layer:KiwiImageLayer)->Array:return _native().operations(layer)
static func expression(kind:String,amount:float)->String:return _native().expression(kind,amount)
static func shader_code(layer:KiwiImageLayer)->String:return _native().shader_code(layer)
static func evaluate(value:Vector3,ops:Array)->Vector3:return _native().evaluate(value,ops)
static func evaluate_rgba(value:Vector4,ops:Array)->Vector4:return _native().evaluate_rgba(value,ops)
static func _legacy_evaluate(value:Vector3,ops:Array)->Vector3:return _native().legacy_evaluate(value,ops)
static func inverse_color(color:Color,layer:KiwiImageLayer)->Color:return _native().inverse_color(color,layer)
