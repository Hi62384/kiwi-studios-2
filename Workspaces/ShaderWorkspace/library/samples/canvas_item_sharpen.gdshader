// Sharpen
// Four-neighbor unsharp convolution strengthens detail without changing alpha.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float strength : hint_range(0,2)=0.5;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    vec3 n=texture(TEXTURE,UV+vec2(TEXTURE_PIXEL_SIZE.x,0)).rgb+texture(TEXTURE,UV-vec2(TEXTURE_PIXEL_SIZE.x,0)).rgb+texture(TEXTURE,UV+vec2(0,TEXTURE_PIXEL_SIZE.y)).rgb+texture(TEXTURE,UV-vec2(0,TEXTURE_PIXEL_SIZE.y)).rgb;
    COLOR=vec4(clamp(c.rgb+strength*(4.0*c.rgb-n),vec3(0),vec3(1)),c.a);
}
