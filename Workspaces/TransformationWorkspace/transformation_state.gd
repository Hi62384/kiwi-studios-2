class_name KiwiTransformationState
extends Resource
@export var id := ""
@export var title := "State"
@export var artwork: KiwiImageLayer
@export var pivot := Vector2(.5,.5)
@export var revision := 0
func copy_state(new_identity: bool=false) -> KiwiTransformationState:
	var result := KiwiTransformationState.new(); result.id=ActorData.new_id() if new_identity else id; result.title=title; result.pivot=pivot; result.revision=revision
	result.artwork=artwork.copy_layer() if artwork!=null else null
	return result
func anchor() -> Vector2: return artwork.local_transform()*(artwork.dimensions*pivot)
