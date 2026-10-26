// Alpha Mask
// Soft elliptical procedural alpha mask with independent center and radii.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 center=vec2(0.5);
uniform vec2 radius=vec2(0.42,0.35);
uniform float feather : hint_range(0.001,1)=0.08;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float d=length((UV-center)/radius);
    COLOR=vec4(c.rgb,c.a*(1.0-smoothstep(1.0-feather,1.0,d)));
}
