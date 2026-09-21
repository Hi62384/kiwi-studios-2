class_name ActorClip
extends Resource
## Times are seconds. Active interval includes start, excludes end.

@export var id: String = ""
@export var actor_id: String = ""
@export var start_time: float = 0.0
@export var duration: float = 5.0
@export var source_offset: float = 0.0
@export var playback_speed: float = 1.0
@export var layer: int = 0


static func create(actor: ActorData, start: float = 0.0, length: float = 5.0) -> ActorClip:
	var clip := ActorClip.new()
	clip.id = ActorData.new_id()
	clip.actor_id = actor.id
	clip.start_time = start
	clip.duration = maxf(length, 0.0)
	return clip


func contains_time(timeline_time: float) -> bool:
	return timeline_time >= start_time and timeline_time < start_time + duration


func local_time(timeline_time: float) -> float:
	return source_offset + (timeline_time - start_time) * playback_speed
