// Inner Shadow
// Directional inset shadow restricted to existing opaque pixels.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 offset=vec2(6,8);
uniform float strength : hint_range(0,1)=0.7;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float exposed=1.0-texture(TEXTURE,UV-offset*TEXTURE_PIXEL_SIZE).a;
    COLOR=vec4(c.rgb*(1.0-exposed*strength),c.a);
}
