extends RefCounted
## Native PBR blending and editable material-mask upload.
static func material(owner: Node3D,terrain: KiwiEnvironmentTerrain,ground: Material,paint: Material) -> Material:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_paint_render").call("material",owner,terrain,ground,paint,KiwiEnvironmentAssets.revisions)
