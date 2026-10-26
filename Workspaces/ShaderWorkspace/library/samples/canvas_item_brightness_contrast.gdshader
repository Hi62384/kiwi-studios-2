// Brightness Contrast
// Centered contrast and additive exposure adjustment on a source sprite.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float brightness : hint_range(-1,1)=0.1;
uniform float contrast : hint_range(0,3)=1.3;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    COLOR=vec4(clamp((c.rgb-0.5)*contrast+0.5+brightness,vec3(0),vec3(1)),c.a);
}
