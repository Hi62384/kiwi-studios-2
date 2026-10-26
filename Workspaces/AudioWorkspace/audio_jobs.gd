class_name KiwiAudioJobs
extends Node
## One bounded worker, cancellable jobs and generation tokens. No UI is touched off-thread.
signal completed(kind: String, generation: int, result: Variant)
signal progress_changed(value: float, description: String)
class Work extends RefCounted:
 var mutex := Mutex.new()
 var cancelled := false
 var progress := 0.0
 var description := ""
 func cancel() -> void:
  mutex.lock(); cancelled = true; mutex.unlock()
 func is_cancelled() -> bool:
  mutex.lock(); var value := cancelled; mutex.unlock(); return value
 func update(value: float, message: String = "") -> void:
  mutex.lock(); progress = clampf(value, 0, 1); description = message; mutex.unlock()
 func status() -> Dictionary:
  mutex.lock(); var result := {"progress": progress, "description": description}; mutex.unlock(); return result
var _thread: Thread
var _current: Dictionary = {}
var _queue: Array[Dictionary] = []
func request(kind: String, operation: Callable, generation: int = 0, replace: bool = true) -> void:
 if replace:
  _queue = _queue.filter(func(entry: Dictionary): return str(entry.kind) != kind)
  if str(_current.get("kind", "")) == kind: _current.work.cancel()
 _queue.append({"kind": kind, "operation": operation, "generation": generation, "work": Work.new()})
func busy() -> bool:
 return _thread != null or not _queue.is_empty()
func cancel_all() -> void:
 _queue.clear()
 if not _current.is_empty(): _current.work.cancel()
func _process(_delta: float) -> void:
 if _thread != null:
  var status: Dictionary = _current.work.status()
  progress_changed.emit(status.progress, status.description)
  if _thread.is_alive(): return
  var result: Variant = _thread.wait_to_finish()
  var entry := _current
  _thread = null; _current = {}
  if not entry.work.is_cancelled(): completed.emit(entry.kind, entry.generation, result)
 if _thread == null and not _queue.is_empty():
  _current = _queue.pop_front()
  _thread = Thread.new()
  if _thread.start(_current.operation.bind(_current.work)) != OK:
   completed.emit(_current.kind, _current.generation, {"error": "Could not start audio worker."})
   _thread = null; _current = {}
func _exit_tree() -> void:
 cancel_all()
 if _thread != null: _thread.wait_to_finish()
 _thread = null

func cancel_kind(kind:String)->void:
 _queue = _queue.filter(func(entry:Dictionary):return str(entry.kind)!=kind)
 if str(_current.get("kind",""))==kind:_current.work.cancel()
