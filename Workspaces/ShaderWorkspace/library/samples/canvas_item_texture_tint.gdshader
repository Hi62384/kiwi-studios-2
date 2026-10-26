// Texture Tint
// Multiply a sprite by a tint while preserving its alpha.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.7,1.0,0.8,1);
void fragment() {
    COLOR = texture(TEXTURE,UV) * tint;
}
