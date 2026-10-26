// Transparency Fade
// Uniform transparent fade preserving source RGB and texture alpha.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float opacity : hint_range(0,1)=0.45;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    COLOR=vec4(c.rgb,c.a*opacity);
}
