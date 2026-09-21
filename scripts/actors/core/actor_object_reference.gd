class_name ActorObjectReference
extends Resource
## Exactly one source: owned object data or a stable project asset ID.

enum Source { EMBEDDED, ASSET }

@export var source: Source = Source.EMBEDDED
@export var object_type: StringName
@export var embedded: ActorObjectData
@export var asset_id: String = ""


static func from_object(object: ActorObjectData) -> ActorObjectReference:
	var reference := ActorObjectReference.new()
	reference.object_type = object.type_id
	reference.embedded = object
	return reference


static func from_asset(id: String, type: StringName) -> ActorObjectReference:
	var reference := ActorObjectReference.new()
	reference.source = Source.ASSET
	reference.object_type = type
	reference.asset_id = id
	return reference


## Resolver signature: resolve_asset(asset_id: String) -> ActorObjectData.
## Missing assets return null without destroying the stored reference.
func resolve(resolve_asset: Callable = Callable()) -> ActorObjectData:
	var object: ActorObjectData = embedded
	if source == Source.ASSET:
		if asset_id.is_empty() or not resolve_asset.is_valid():
			return null
		var resolved: Variant = resolve_asset.call(asset_id)
		if not resolved is ActorObjectData:
			return null
		object = resolved
	if object == null or object.type_id != object_type:
		return null
	return object


func make_unique(resolve_asset: Callable = Callable()) -> ActorObjectReference:
	var object := resolve(resolve_asset)
	if object == null:
		return null
	return from_object(object.copy_object())


func copy_reference() -> ActorObjectReference:
	if source == Source.ASSET:
		return from_asset(asset_id, object_type)
	if embedded != null:
		return from_object(embedded.copy_object())
	var reference := ActorObjectReference.new()
	reference.object_type = object_type
	return reference
