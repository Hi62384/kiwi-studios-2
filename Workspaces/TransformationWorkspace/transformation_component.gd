class_name KiwiTransformationComponent
extends Resource
@export var id := ""
@export var title := "Component"
@export var visible := true
@export var locked := false
@export var base_size := Vector2(1280,720)
@export var default_state_id := ""
@export var states: Array[KiwiTransformationState]=[]
@export var keys: Array[KiwiTransformationKey]=[]
func state_for_id(value: String) -> KiwiTransformationState:
	for state in states:
		if state.id==value: return state
	return null
func key_for_id(value: String) -> KiwiTransformationKey:
	for key in keys:
		if key.id==value: return key
	return null
func sorted_keys() -> Array[KiwiTransformationKey]:
	var result := keys.duplicate(); result.sort_custom(func(a: KiwiTransformationKey,b: KiwiTransformationKey): return a.time<b.time); return result
func copy_component(new_identity: bool=false) -> KiwiTransformationComponent:
	var result := KiwiTransformationComponent.new(); result.id=ActorData.new_id() if new_identity else id; result.title=title; result.visible=visible; result.locked=locked; result.base_size=base_size
	var mapping := {}
	for state in states:
		var copy := state.copy_state(new_identity); copy.artwork.id=result.id; mapping[state.id]=copy.id; result.states.append(copy)
	result.default_state_id=str(mapping.get(default_state_id,default_state_id))
	for key in keys:
		var copy := key.copy_key(new_identity); copy.state_id=str(mapping.get(key.state_id,key.state_id)); result.keys.append(copy)
	return result
