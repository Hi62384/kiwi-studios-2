// Pixelation
// Samples source-aligned pixel blocks with a stable grid.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float pixel_size : hint_range(1,32)=12;
void fragment() {
    vec2 cells=max(vec2(1),1.0/(TEXTURE_PIXEL_SIZE*pixel_size));
    COLOR=texture(TEXTURE,(floor(UV*cells)+0.5)/cells);
}
