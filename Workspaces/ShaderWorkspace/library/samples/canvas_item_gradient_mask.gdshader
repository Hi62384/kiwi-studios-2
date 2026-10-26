// Gradient Mask
// Vertical alpha ramp for fades, overlays and atmospheric sprite blending.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float start : hint_range(0,1)=0.05;
uniform float end : hint_range(0.01,1)=0.85;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    COLOR=vec4(c.rgb,c.a*smoothstep(start,end,UV.y));
}
