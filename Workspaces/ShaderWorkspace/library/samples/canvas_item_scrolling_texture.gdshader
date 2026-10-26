// Scrolling Texture
// Repeating UV translation for conveyor belts, clouds and background layers.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 velocity=vec2(0.1,0.03);
void fragment() {
    COLOR=texture(TEXTURE,fract(UV+velocity*TIME));
}
