extends RefCounted
## ResourceSaver sorts dictionary keys. Generated-data signatures must describe
## values, not dictionary insertion order, or every reopened cave looks stale.
static func value(data: Variant) -> int: return hash(_ordered(data,{},0))
static func _ordered(data: Variant,seen: Dictionary,depth: int) -> Variant:
	if depth>32: return "depth-limit"
	if data is Dictionary:
		var keys: Array=data.keys(); keys.sort_custom(func(a: Variant,b: Variant): return str(a)<str(b)); var result:=[]
		for key in keys: result.append([str(key),_ordered(data[key],seen,depth+1)])
		return result
	if data is Array:
		var result:=[]
		for item in data: result.append(_ordered(item,seen,depth+1))
		return result
	if data is Script: return ["script",data.resource_path]
	if data is Resource:
		if data is Texture2D and not (data is NoiseTexture2D or data is GradientTexture1D or data is GradientTexture2D): return [data.get_class(),data.get_width(),data.get_height()]
		var identity: int=data.get_instance_id()
		if seen.has(identity): return ["reference",seen[identity]]
		seen[identity]=seen.size(); var properties:=[]; var result: Array=[data.get_class(),data.get_script().resource_path if data.get_script()!=null else ""]
		for property in data.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_STORAGE!=0 and not str(property.name) in ["script","resource_path","resource_local_to_scene","resource_scene_unique_id"]: properties.append(str(property.name))
		properties.sort()
		for name: String in properties: result.append([name,_ordered(data.get(name),seen,depth+1)])
		return result
	return data
