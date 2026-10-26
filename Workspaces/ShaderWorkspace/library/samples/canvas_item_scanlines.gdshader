// Scanlines
// Traveling scanline modulation for monitors and broadcast effects.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float lines : hint_range(10,400)=90;
uniform float speed : hint_range(0,10)=2;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float stripe=0.7+0.3*sin(UV.y*lines*TAU+TIME*speed);
    COLOR=vec4(c.rgb*stripe,c.a);
}
