class_name KiwiRigWeightJob
extends RefCounted
var tasks: Array[Dictionary]=[]
var method := "Smooth"
var influences := 4
var _mutex := Mutex.new()
var _cancelled := false
func cancel() -> void: _mutex.lock(); _cancelled=true; _mutex.unlock()
func is_cancelled() -> bool:
	_mutex.lock(); var result := _cancelled; _mutex.unlock(); return result
func run() -> Dictionary:
	var result := {}
	for task in tasks:
		if is_cancelled(): return {}
		var data := KiwiRigWeighting.compute(task.source,task.bones,task.transform,method,influences,8,self)
		if data==null: return {}
		result[str(task.id)]=data
	return result
