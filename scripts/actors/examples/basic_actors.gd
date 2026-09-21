class_name BasicActors
extends RefCounted
## Compatibility entry point. Actor data lives in the editable catalog resource.

const CATALOG: ActorCatalog = preload("res://scripts/actors/examples/basic_actor_catalog.tres")

static func register_all(registry: ActorRegistry) -> bool:
	return CATALOG.register_into(registry)
