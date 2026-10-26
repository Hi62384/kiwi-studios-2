// Drop Shadow
// Offset silhouette shadow with correct straight-alpha compositing; requires sprite padding.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 offset=vec2(10,10);
uniform vec4 shadow : source_color=vec4(0.02,0.01,0.05,0.75);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float a=texture(TEXTURE,UV-offset*TEXTURE_PIXEL_SIZE).a*shadow.a;
    float out_a=c.a+a*(1.0-c.a);
    COLOR=vec4((c.rgb*c.a+shadow.rgb*a*(1.0-c.a))/max(out_a,0.0001),out_a);
}
