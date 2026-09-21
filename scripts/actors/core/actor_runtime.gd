class_name ActorRuntime
extends Node3D
## Runtime nodes are disposable views of saved data, never the source of truth.

var actor: ActorData
var active: bool = false


func bind(data: ActorData) -> void:
	actor = data


## Runtime children are attached here. Spatial runtimes override this with an
## always-active transform anchor so a parent's own clip visibility never
## disables independently timed children.
func parenting_node() -> Node:
	return self


## Call after adding this runtime to the scene tree. Overrides are sampled values
## keyed by property ID; future animation tracks can supply them without saving them.
func evaluate_clip(clip: ActorClip, timeline_time: float, overrides: Dictionary = {}) -> void:
	if actor == null or clip.actor_id != actor.id:
		set_active(false)
		return
	actor.animation_time = clip.local_time(timeline_time)
	var evaluated: Dictionary = ActorAnimation.sampled_values(actor, actor.animation_time)
	evaluated.merge(overrides, true)
	# Spatial parenting must remain deterministic even while this actor's own
	# visible/audio clip is inactive. Children can have independent clip timing.
	evaluate_transform(evaluated)
	set_active(clip.contains_time(timeline_time))
	if not active:
		return
	evaluate(clip.local_time(timeline_time), evaluated)
	set_timeline_time(timeline_time)


## Override to hide visuals / mute audio. Called on every sample, including seeks.
func set_active(value: bool) -> void:
	active = value


## Override for transform state that descendants need regardless of activity.
func evaluate_transform(_values: Dictionary) -> void:
	pass


## Override using absolute local time. Treat values and referenced objects as read-only.
func evaluate(_local_time: float, _values: Dictionary) -> void:
	pass


## Set generated shader time after evaluate(), which may replace the material.
func set_timeline_time(_timeline_time: float) -> void:
	pass


## Optional live 3D constraint interface. Runtimes without a spatial transform
## leave this unsupported instead of having their saved values overwritten.
func supports_remote_transform() -> bool:
	return false


func remote_transform() -> Transform3D:
	return Transform3D.IDENTITY


func apply_remote_transform(_source: Transform3D, _position: bool, _rotation: bool, _scale: bool) -> void:
	pass
