extends RefCounted
## Color math is shared by preview generation and brush inverse solving.
const TYPES := ["add", "multiply", "subtract", "divide", "power", "snap", "clamp", "lerp", "minimum", "maximum", "absolute", "invert", "smoothstep"]
const BASICS := {"brightness":0.0,"contrast":1.0,"saturation":1.0,"exposure":0.0,"gamma":1.0,"hue":0.0,"temperature":0.0,"tint":0.0}

static func new_operation(kind: String) -> Dictionary:
	var amount:=1.0 if kind in ["multiply","divide","power","minimum"] else (.1 if kind=="snap" else 0.0)
	return {"type":kind,"enabled":true,"preserve_hue":true,"a":{"kind":"pixel"},"b":{"kind":"float","value":amount},"c":{"kind":"float","value":.5 if kind=="lerp" else 1.0}}

static func operand_value(operand: Dictionary, pixel: Vector4) -> Vector4:
	match str(operand.get("kind","pixel")):
		"float": return Vector4.ONE*float(operand.get("value",0))
		"vector":
			var channels: Array=operand.get("channels",[1.0,1.0,1.0,1.0])
			var result:=Vector4.ZERO
			for i in 4:
				result[i]=pixel["rgba".find(str(channels[i]))] if channels[i] is String else float(channels[i])
			return result
	return pixel

static func operand_code(operand: Dictionary) -> String:
	match str(operand.get("kind","pixel")):
		"float": return "vec4(%s)" % str(float(operand.get("value",0)))
		"vector":
			var parts:=PackedStringArray()
			for channel in operand.get("channels",[1.0,1.0,1.0,1.0]): parts.append("v."+str(channel) if channel is String else str(float(channel)))
			return "vec4("+", ".join(parts)+")"
	return "v"

static func operation_code(op: Dictionary) -> String:
	var a:=operand_code(op.a); var b:=operand_code(op.b); var c:=operand_code(op.get("c",{"kind":"float","value":1.0}))
	match str(op.type):
		"add": return a+"+"+b
		"multiply": return a+"*"+b
		"subtract": return a+"-"+b
		"divide": return a+"/safe_denominator("+b+")"
		"power": return "pow(max("+a+",vec4(0.0)),max("+b+",vec4(.0001)))"
		"minimum": return "min("+a+","+b+")"
		"maximum": return "max("+a+","+b+")"
		"clamp": return "clamp("+a+",min("+b+","+c+"),max("+b+","+c+"))"
		"lerp": return "mix("+a+","+b+","+c+")"
		"absolute": return "abs("+a+")"
		"invert": return "vec4(vec3(1.0)-("+a+").rgb,("+a+").a)"
		"smoothstep": return "smoothstep(min("+b+","+c+"),max("+b+","+c+")+vec4(.00001),"+a+")"
		"snap": return ("snap_hue(" if bool(op.get("preserve_hue",true)) else "snap_channels(")+a+","+b+")"
	return a

static func evaluate_operation(pixel: Vector4, op: Dictionary) -> Vector4:
	var a:=operand_value(op.a,pixel); var b:=operand_value(op.b,pixel); var c:=operand_value(op.get("c",{"kind":"float","value":1.0}),pixel)
	var result:=a
	if op.type=="snap" and bool(op.get("preserve_hue",true)):
		var peak:=maxf(a.x,maxf(a.y,a.z)); var step:=maxf(.0001,absf(b.x))
		var ratio:=floorf(peak/step+.5)*step/maxf(.00001,peak)
		return Vector4(a.x*ratio,a.y*ratio,a.z*ratio,a.w)
	for i in 4:
		match str(op.type):
			"add": result[i]=a[i]+b[i]
			"multiply": result[i]=a[i]*b[i]
			"subtract": result[i]=a[i]-b[i]
			"divide": result[i]=a[i]/(maxf(.0001,absf(b[i]))*(-1 if b[i]<0 else 1))
			"power": result[i]=pow(maxf(0,a[i]),maxf(.0001,b[i]))
			"minimum": result[i]=minf(a[i],b[i])
			"maximum": result[i]=maxf(a[i],b[i])
			"clamp": result[i]=clampf(a[i],minf(b[i],c[i]),maxf(b[i],c[i]))
			"lerp": result[i]=lerpf(a[i],b[i],c[i])
			"absolute": result[i]=absf(a[i])
			"invert": result[i]=1-a[i] if i<3 else a[i]
			"smoothstep": result[i]=smoothstep(minf(b[i],c[i]),maxf(b[i],c[i])+.00001,a[i])
			"snap":
				var step:=maxf(.0001,absf(b[i])); result[i]=floorf(a[i]/step+.5)*step
	return result

static func operations(layer: KiwiImageLayer) -> Array:
	var result: Array=layer.properties.get("value_operations",[]).duplicate(true)
	var b: Dictionary=layer.properties.get("value_basics",{})
	for key in BASICS:
		var value: float=float(b.get(key,BASICS[key]))
		if is_equal_approx(value,float(BASICS[key])): continue
		result.append({"type":key,"amount":value})
	return result

static func expression(kind: String, amount: float) -> String:
	var a:=str(amount)
	match kind:
		"multiply": return "c * " + a
		"divide": return "c / " + str(maxf(.001,amount))
		"add", "brightness": return "c + vec3("+a+")"
		"subtract": return "c - vec3("+a+")"
		"power": return "pow(max(c,vec3(0.0)),vec3("+str(maxf(.001,amount))+"))"
		"gamma": return "pow(max(c,vec3(0.0)),vec3("+str(1.0/maxf(.001,amount)) +"))"
		"exposure": return "c * " + str(pow(2,amount))
		"snap": return "floor(c * "+str(maxf(1,amount))+" + .5) / "+str(maxf(1,amount))
		"invert": return "vec3(1.0)-c"
		"contrast": return "(c-vec3(.5))*"+a+"+vec3(.5)"
		"saturation": return "mix(vec3(dot(c,vec3(.2126,.7152,.0722))),c,"+a+")"
		"hue": return "rotate_hue(c,"+a+")"
		"minimum": return "min(c,vec3("+a+"))"
		"maximum": return "max(c,vec3("+a+"))"
		"temperature": return "c+vec3("+a+",0.0,"+str(-amount)+")"
		"tint": return "c+vec3(0.0,"+a+",0.0)"
		"red": return "c*vec3("+a+",1.0,1.0)"
		"green": return "c*vec3(1.0,"+a+",1.0)"
		"blue": return "c*vec3(1.0,1.0,"+a+")"
	return "c"

static func shader_code(layer: KiwiImageLayer) -> String:
	var code: String="""shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D selection_mask;
uniform bool selection_only=false;
uniform bool has_selection=false;
uniform vec2 selection_origin;
uniform vec2 selection_x;
uniform vec2 selection_y;
uniform vec2 document_size;
uniform vec2 content_extent;
vec3 rotate_hue(vec3 c,float a) { vec3 k=vec3(.577350269); return c*cos(a)+cross(k,c)*sin(a)+k*dot(k,c)*(1.0-cos(a)); }
vec4 safe_denominator(vec4 x){ return mix(vec4(1.0),vec4(-1.0),lessThan(x,vec4(0.0)))*max(abs(x),vec4(.0001)); }
vec4 snap_channels(vec4 a,vec4 b){ vec4 step=max(abs(b),vec4(.0001)); return floor(a/step+.5)*step; }
vec4 snap_hue(vec4 a,vec4 b){ float peak=max(a.r,max(a.g,a.b)); float step=max(abs(b.r),.0001); return vec4(a.rgb*(floor(peak/step+.5)*step/max(peak,.00001)),a.a); }
void fragment(){ vec4 original=texture(TEXTURE,UV); vec3 c=original.rgb/max(original.a,.00001); vec4 v=vec4(c,original.a);
"""
	for op in operations(layer):
		if not op.get("enabled",true): continue
		if op.has("a"):
			code+="{vec4 next="+operation_code(op)+"; v="+("next" if op.get("affect_alpha",false) else "vec4(next.rgb,v.a)")+"; c=v.rgb;}\n"
		else: code+="c="+expression(str(op.type),float(op.get("amount",1)))+"; v.rgb=c;\n"
	code+="vec2 p=UV/TEXTURE_PIXEL_SIZE-vec2(48.0); vec2 q=(selection_origin+selection_x*p.x+selection_y*p.y)/document_size; float mask=selection_only ? (has_selection && all(greaterThanEqual(q,vec2(0.0))) && all(lessThanEqual(q,vec2(1.0))) ? texture(selection_mask,q).a : 0.0) : 1.0; v=clamp(v,vec4(0.0),vec4(1.0)); if(original.a==0.0 && (any(lessThan(p,vec2(0.0))) || any(greaterThan(p,content_extent)))) {v.a=0.0;} COLOR=mix(original,vec4(v.rgb*v.a,v.a),mask); }"
	return code

static func evaluate(value: Vector3, ops: Array) -> Vector3:
	var result:=evaluate_rgba(Vector4(value.x,value.y,value.z,1),ops)
	return Vector3(result.x,result.y,result.z)

static func evaluate_rgba(value: Vector4, ops: Array) -> Vector4:
	var result:=value
	for op in ops:
		if not op.get("enabled",true): continue
		if op.has("a"):
			var next:=evaluate_operation(result,op)
			if not bool(op.get("affect_alpha",false)): next.w=result.w
			result=next
		else:
			var rgb:=_legacy_evaluate(Vector3(result.x,result.y,result.z),[op])
			result=Vector4(rgb.x,rgb.y,rgb.z,result.w)
	return result.clamp(Vector4.ZERO,Vector4.ONE)

static func _legacy_evaluate(value: Vector3, ops: Array) -> Vector3:
	var c:=value
	for op in ops:
		if not op.get("enabled",true): continue
		if op.has("a"):
			var next:=evaluate_operation(Vector4(c.x,c.y,c.z,1),op)
			c=Vector3(next.x,next.y,next.z)
			continue
		var a:=float(op.get("amount",1))
		match str(op.type):
			"multiply": c*=a
			"divide": c/=maxf(.001,a)
			"add","brightness": c+=Vector3.ONE*a
			"subtract": c-=Vector3.ONE*a
			"exposure": c*=pow(2,a)
			"power","gamma":
				var exponent:=1.0/maxf(.001,a) if op.type=="gamma" else maxf(.001,a)
				c=Vector3(pow(maxf(0,c.x),exponent),pow(maxf(0,c.y),exponent),pow(maxf(0,c.z),exponent))
			"snap": c=(c*maxf(1,a)+Vector3.ONE*.5).floor()/maxf(1,a)
			"invert": c=Vector3.ONE-c
			"contrast": c=(c-Vector3.ONE*.5)*a+Vector3.ONE*.5
			"saturation": c=Vector3.ONE*c.dot(Vector3(.2126,.7152,.0722))*(1-a)+c*a
			"hue": c=c.rotated(Vector3.ONE.normalized(),a)
			"minimum": c=c.min(Vector3.ONE*a)
			"maximum": c=c.max(Vector3.ONE*a)
			"temperature": c+=Vector3(a,0,-a)
			"tint": c.y+=a
			"red": c.x*=a
			"green": c.y*=a
			"blue": c.z*=a
	return c

static func inverse_color(color: Color, layer: KiwiImageLayer) -> Color:
	var ops:=operations(layer)
	if ops.is_empty(): return color
	var target:=Vector4(color.r,color.g,color.b,color.a)
	var best:=target
	var error:=INF
	# Multistart coordinate descent also supplies a stable nearest reachable color
	# for non-invertible operations (quantization, clipping, zero saturation).
	for seed in [target,Vector4.ZERO,Vector4.ONE,Vector4(.5,.5,.5,.5)]:
		var p: Vector4=seed
		var score:=evaluate_rgba(p,ops).distance_squared_to(target)
		var step:=.5
		for iteration in 36:
			var improved:=false
			for axis in 4:
				for direction in [-1,1]:
					var q:=p; q[axis]=clampf(q[axis]+step*direction,0,1)
					var next:=evaluate_rgba(q,ops).distance_squared_to(target)
					if next<score: p=q; score=next; improved=true
			if not improved: step*=.5
		if score<error: best=p; error=score
	return Color(best.x,best.y,best.z,best.w)
