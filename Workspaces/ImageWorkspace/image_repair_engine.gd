extends Node
## Background-only image processing. Main thread owns scene nodes and textures;
## generations reject results after cancellation, undo or document changes.
signal preview(result: Dictionary)
signal idle
var _thread: Thread
var _pending: Dictionary={}
var _job: Dictionary={}
var _generation:=0
var _sequence:=0

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_repair_engine")

func cancel() -> void:
 _native().cancel(self)

func submit(job: Dictionary) -> int:
 return _native().submit(self,job)

func busy() -> bool:
 return _native().busy(self)

func _process(_delta: float) -> void:
 _native().process(self)

func _work(job: Dictionary) -> Dictionary:
 return _native().work(self,job)

func _cancellation(job: Dictionary) -> Callable:
 return func(): return job.generation!=_generation

func _exit_tree() -> void:
 _native().exit_tree(self)
