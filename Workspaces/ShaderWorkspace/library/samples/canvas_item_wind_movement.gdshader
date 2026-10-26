// Wind Movement
// Sprite vertex bending anchored along its bottom edge for foliage.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float sway : hint_range(0,40)=12;
uniform float speed : hint_range(0,8)=2;
void vertex() {
    VERTEX.x+=sin(TIME*speed+UV.y*2.5)*sway*(1.0-UV.y);
}
void fragment() {
    COLOR=texture(TEXTURE,UV);
}
