extends RefCounted
const TYPES={"Noise":["white","smooth","perlin","simplex","fractal","cellular"],"Surfaces":["grain","speckles","paper","fabric","stone","dirt","clouds","scratches","stipple"],"Geometry":["stripes","dots","checkerboard","grid","waves","triangles"]}
static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_procedural_texture")
static func generate(recipe:KiwiImageTextureRecipe,size:Vector2i,cancelled:Callable=Callable())->Image:return _native().generate(recipe,size,cancelled,cancelled.is_valid())
static func _cancelled(callback:Callable)->bool:return bool(callback.call())
