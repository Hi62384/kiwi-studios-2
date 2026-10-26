// Posterization
// Quantizes each color channel into a chosen number of bands.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float levels : hint_range(2,16,1)=4;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    COLOR=vec4(floor(c.rgb*(levels-1.0)+0.5)/(levels-1.0),c.a);
}
